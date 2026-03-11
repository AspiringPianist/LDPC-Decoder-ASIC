// column_slice.v
`include "defs.v"
module column_slice #(
  parameter integer COL_ID = 0,
  parameter integer Z = 42,
  parameter integer QV_W = 5,
  parameter integer LVC_MAG = 4,
  parameter integer LVC_W = 1 + LVC_MAG,
  parameter integer NFRAMES = 16
)(
  input  wire                 clk,
  input  wire                 rst_n,
  // scheduling interface: current global cycle index (0..NUM_COLS-1)
  input  wire [$clog2(NUM_COLS)-1:0] cycle_idx,
  // control: frame-select pointer for this slice - controller supplies faddr to read
  input  wire [3:0]           faddr_read,  // which frame this slice processes this cycle
  input  wire                 en_slice,    // enable this slice in this cycle (frame not terminated)
  // layer message buses to/from neighbor slices (z-wide packed)
  input  wire [Z*(1+1+LVC_MAG+LVC_MAG)-1:0] in_layer_bus,  // pack: pc, sc, min1, min2
  output wire [Z*(1+1+LVC_MAG+LVC_MAG)-1:0] out_layer_bus,
  // local memory buses (external wires to higher level aggregator)
  // read port for Qv/Lvc are per-PE via mem modules built internally here
  // parity reduction outputs (one bit per PE) to be used by top-level parity checker
  output wire [Z-1:0] parity_bits_out
);

  // local memories for Qv and Lvc (multi-frame)
  // instantiate mem_frame for Qv (signed 2's comp) and for Lvc (sign-magnitude stored raw)
  // Qv width QV_W, LVC width LVC_W
  genvar i;
  // create arrays of wires to connect instances
  wire [QV_W-1:0] qv_rdata [0:Z-1];
  wire [LVC_W-1:0] lvc_rdata [0:Z-1];
  // writeback wires
  reg [QV_W-1:0] qv_wdata [0:Z-1];
  reg qv_wen [0:Z-1];
  reg [LVC_W-1:0] lvc_wdata_reg [0:Z-1];
  reg lvc_wen_reg [0:Z-1];

  // instantiate per-PE memories: we create Z instances of memory; for area optimize share multi-port memory but here one-per-row for clarity
  // Note: for synthesis you'll likely want a single multiported SRAM per column with linearized addressing. This behavioral memory is for simulation/verification.
  generate
    for (i=0;i<Z;i=i+1) begin : mems
      // Qv mem
      mem_frame #(.WIDTH(QV_W), .DEPTH(Z), .NFRAMES(NFRAMES)) qv_mem (
        .clk(clk),
        .faddr_a(faddr_read),
        .addr_a(i[$clog2(Z)-1:0]),
        .rdata_a(qv_rdata[i]),
        .wen_b(qv_wen[i]),
        .faddr_b(faddr_read),
        .addr_b(i[$clog2(Z)-1:0]),
        .wdata_b(qv_wdata[i])
      );
      // Lvc mem
      mem_frame #(.WIDTH(LVC_W), .DEPTH(Z), .NFRAMES(NFRAMES)) lvc_mem (
        .clk(clk),
        .faddr_a(faddr_read),
        .addr_a(i[$clog2(Z)-1:0]),
        .rdata_a(lvc_rdata[i]),
        .wen_b(lvc_wen_reg[i]),
        .faddr_b(faddr_read),
        .addr_b(i[$clog2(Z)-1:0]),
        .wdata_b(lvc_wdata_reg[i])
      );
    end
  endgenerate

  // instantiate PEs
  generate
    for (i=0;i<Z;i=i+1) begin : pes
      // extract input layer fields
      wire in_pc  = in_layer_bus[i*(1+1+LVC_MAG+LVC_MAG) +: 1];
      wire in_sc  = in_layer_bus[i*(1+1+LVC_MAG+LVC_MAG) + 1 +: 1];
      wire [LVC_MAG-1:0] in_min1 = in_layer_bus[i*(1+1+LVC_MAG+LVC_MAG) + 2 +: LVC_MAG];
      wire [LVC_MAG-1:0] in_min2 = in_layer_bus[i*(1+1+LVC_MAG+LVC_MAG) + 2 + LVC_MAG +: LVC_MAG];

      wire [LVC_W-1:0] stored_lvc = lvc_rdata[i];
      wire signed [QV_W-1:0] stored_qv = $signed(qv_rdata[i]);

      // scheduler: in our simplified mapping, this slice schedules PE i when en_slice==1 (controller already ensures faddr_read is correct)
      wire pe_en = en_slice;

      // routing for active flag: we query router per (COL_ID, row)
      // Use a simple active = 1 for now; top-level can mute particular edges via mask array
      wire active_edge = 1'b1;

      wire out_pc; wire out_sc;
      wire [LVC_MAG-1:0] out_min1; wire [LVC_MAG-1:0] out_min2;
      wire [LVC_W-1:0] lvc_wr; wire lvc_we;
      wire signed [QV_W-1:0] qv_wr; wire qv_we;
      wire c_hat;

      pe #(.QV_W(QV_W), .LVC_MAG(LVC_MAG), .LVC_W(LVC_W), .MIN_W(LVC_MAG)) pe_inst (
        .clk(clk), .rst_n(rst_n), .active(active_edge), .en_cycle(pe_en),
        .in_pc(in_pc), .in_sc(in_sc), .in_min1(in_min1), .in_min2(in_min2),
        .stored_lvc_sm(stored_lvc), .stored_qv(stored_qv),
        .out_pc(out_pc), .out_sc(out_sc), .out_min1(out_min1), .out_min2(out_min2),
        .lvc_wdata(lvc_wr), .lvc_wen(lvc_we), .qv_wdata(qv_wr), .qv_wen(qv_we),
        .c_hat_out(c_hat)
      );

      // connect outputs into bus
      assign out_layer_bus[i*(1+1+LVC_MAG+LVC_MAG) +: 1] = out_pc;
      assign out_layer_bus[i*(1+1+LVC_MAG+LVC_MAG) + 1 +: 1] = out_sc;
      assign out_layer_bus[i*(1+1+LVC_MAG+LVC_MAG) + 2 +: LVC_MAG] = out_min1;
      assign out_layer_bus[i*(1+1+LVC_MAG+LVC_MAG) + 2 + LVC_MAG +: LVC_MAG] = out_min2;

      // hook writebacks into memories (registered to meet single-cycle semantics)
      always @(posedge clk) begin
        qv_wdata[i] <= qv_wr;
        qv_wen[i] <= qv_we;
        lvc_wdata_reg[i] <= lvc_wr;
        lvc_wen_reg[i] <= lvc_we;
      end

      assign parity_bits_out[i] = c_hat;
    end
  endgenerate

endmodule