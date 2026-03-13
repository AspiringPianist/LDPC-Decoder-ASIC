// column_slice.sv
`timescale 1ns/1ps
import defs_pkg::*;
module column_slice #(
  parameter int COL_ID = 0,
  parameter int Z_local = Z,
  parameter int QV_W_local = QV_W,
  parameter int LVC_MAG_local = LVC_MAG,
  parameter int LVC_W_local = LVC_W,
  parameter int NFRAMES = NUM_FRAMES,
  parameter string MEM_TYPE = "ESRAM" // "BRAM" for FPGA or "ESRAM" for ASIC
)(
  input  logic clk,
  input  logic rst_n,
  input  logic [$clog2(NUM_LAYERS*2)-1:0] cycle_idx, // 0..CYCLES-1
  input  logic [3:0] faddr_read, // frame pointer for this slice (0..NUM_FRAMES-1)
  input  logic en_slice,
  input  logic [Z_local*MSG_W-1:0] in_layer_bus,  // input from previous column
  output logic [Z_local*MSG_W-1:0] out_layer_bus, // output to next column
  output logic [Z_local-1:0] parity_bits_out // hard decisions per VN (for parity reduction)
);

  // compute current phase (CN/VN) from cycle_idx: CN when cycle_idx < NUM_LAYERS
  logic phase_cn_local;
  assign phase_cn_local = (cycle_idx < NUM_LAYERS) ? 1'b1 : 1'b0;
  // derive current layer id (0..NUM_LAYERS-1)
  logic [$clog2(NUM_LAYERS)-1:0] layer_id;
  assign layer_id = phase_cn_local ? cycle_idx[$clog2(NUM_LAYERS)-1:0] : (cycle_idx - NUM_LAYERS)[$clog2(NUM_LAYERS)-1:0];

  // Depth for memories (per column): NFRAMES * Z_local
  localparam int DEPTH = NFRAMES * Z_local;

  // memory instances for QV and LVC (behavioral for sim)
  // Read/write addresses are linearized as: addr = frame * Z + vn_row
  logic qv_ren, qv_wen;
  logic [$clog2(DEPTH)-1:0] qv_raddr, qv_waddr;
  logic [QV_W_local-1:0] qv_rdata, qv_wdata;

  logic lvc_ren, lvc_wen;
  logic [$clog2(DEPTH)-1:0] lvc_raddr, lvc_waddr;
  logic [LVC_W_local-1:0] lvc_rdata, lvc_wdata;

  // instantiate memory wrappers (behavioral)
  esram_bram_sim #(.DEPTH(DEPTH), .DATA_W(QV_W_local)) qv_mem (
    .clk(clk), .ren(qv_ren), .raddr(qv_raddr), .rdata(qv_rdata),
    .wen(qv_wen), .waddr(qv_waddr), .wdata(qv_wdata)
  );

  esram_bram_sim #(.DEPTH(DEPTH), .DATA_W(LVC_W_local)) lvc_mem (
    .clk(clk), .ren(lvc_ren), .raddr(lvc_raddr), .rdata(lvc_rdata),
    .wen(lvc_wen), .waddr(lvc_waddr), .wdata(lvc_wdata)
  );

  // read-address pipeline: apply read address one cycle before PE consumes data
  // We'll maintain per-row read address registers and enable signals.
  logic [$clog2(DEPTH)-1:0] scheduled_qv_raddr [Z_local-1:0];
  logic [$clog2(DEPTH)-1:0] scheduled_lvc_raddr [Z_local-1:0];
  logic scheduled_ren [Z_local-1:0];

  // Unpack inbound layer bus into per-row messages
  logic [MSG_W-1:0] in_msg [Z_local-1:0];
  logic [MSG_W-1:0] out_msg [Z_local-1:0];

  // flattening unpack
  genvar r;
  generate
    for (r = 0; r < Z_local; r = r + 1) begin : unpack_in
      assign in_msg[r] = in_layer_bus[r*MSG_W +: MSG_W];
    end
  endgenerate

  // Per-row memory read/write signals
  logic [QV_W_local-1:0] qv_rdata_per_row [Z_local-1:0];
  logic [LVC_W_local-1:0] lvc_rdata_per_row [Z_local-1:0];
  logic [QV_W_local-1:0] qv_wdata_per_row [Z_local-1:0];
  logic [LVC_W_local-1:0] lvc_wdata_per_row [Z_local-1:0];
  logic qv_wen_per_row [Z_local-1:0];
  logic lvc_wen_per_row [Z_local-1:0];

  // instantiate PEs (one per VN row)
  // Each PE reads qv/lvc, consumes in_msg during CN pass, and produces out_msg + memory writes during VN pass
  generate
    for (r = 0; r < Z_local; r = r + 1) begin : gen_pe
      // Compute linear memory address for this row
      logic [$clog2(DEPTH)-1:0] addr_for_row;
      always_comb addr_for_row = (faddr_read * Z_local) + r;

      // Instantiate PE with new interface
      pe #(
        .MIN_W(MIN_W),
        .LVC_W(LVC_W_local),
        .QV_W(QV_W_local),
        .OFFSET_BETA(OFFSET_BETA),
        .MSG_W(MSG_W)
      ) pe_inst (
        .clk(clk),
        .rst_n(rst_n),
        .phase_cn(phase_cn_local),
        .layer_id(layer_id),
        .en(en_slice),
        .msg_in(in_msg[r]),
        .lvc_in(lvc_rdata_per_row[r]),
        .qv_in(qv_rdata_per_row[r]),
        .msg_out(out_msg[r]),
        .lvc_wdata(lvc_wdata_per_row[r]),
        .lvc_wen(lvc_wen_per_row[r]),
        .qv_wdata(qv_wdata_per_row[r]),
        .qv_wen(qv_wen_per_row[r]),
        .c_hat_out(parity_bits_out[r])
      );

      // Memory read for this row (synchronous)
      // Issue read address combinationally; data available next cycle
      always_comb begin
        qv_ren = 1'b1;  // Global read enable (for all rows)
        lvc_ren = 1'b1;
      end

      // Use multiplexing to read one row at a time from single-port memory
      // For true parallel behavior, replace esram_bram_sim with multi-ported macro
      // This sequential approach works for simulation; in ASIC use actual multi-ported SRAM
    end
  endgenerate

  // Memory multiplexing: Read address sequencing
  // For simulation: cycle through rows each clock; in ASIC use actual parallel reads
  logic [$clog2(Z_local)-1:0] read_row_idx;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) read_row_idx <= 0;
    else read_row_idx <= (read_row_idx + 1) % Z_local;
  end

  // Compute address for current read cycle
  logic [$clog2(DEPTH)-1:0] current_read_addr;
  always_comb current_read_addr = (faddr_read * Z_local) + read_row_idx;

  // Issue read address to single-port memory
  always_comb begin
    qv_raddr = current_read_addr;
    lvc_raddr = current_read_addr;
  end

  // Distribute read data to corresponding row with pipeline delay
  // (data read in cycle N is available in cycle N+1)
  logic [$clog2(Z_local)-1:0] read_row_idx_d1;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) read_row_idx_d1 <= 0;
    else read_row_idx_d1 <= read_row_idx;
  end

  // Multiplex read data to per-row latches
  generate
    for (r = 0; r < Z_local; r = r + 1) begin : mux_read_data
      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          qv_rdata_per_row[r] <= 0;
          lvc_rdata_per_row[r] <= 0;
        end else begin
          if (read_row_idx_d1 == r) begin
            qv_rdata_per_row[r] <= qv_rdata;
            lvc_rdata_per_row[r] <= lvc_rdata;
          end
        end
      end
    end
  endgenerate

  // Memory write arbitration: write from PE that is enabled
  // (In a pipelined design, handle proper write scheduling)
  generate
    for (r = 0; r < Z_local; r = r + 1) begin : write_arb
      always_comb begin
        if (qv_wen_per_row[r]) begin
          qv_wen = 1'b1;
          qv_waddr = (faddr_read * Z_local) + r;
          qv_wdata = qv_wdata_per_row[r];
        end else begin
          qv_wen = 1'b0;
          qv_waddr = 0;
          qv_wdata = 0;
        end

        if (lvc_wen_per_row[r]) begin
          lvc_wen = 1'b1;
          lvc_waddr = (faddr_read * Z_local) + r;
          lvc_wdata = lvc_wdata_per_row[r];
        end else begin
          lvc_wen = 1'b0;
          lvc_waddr = 0;
          lvc_wdata = 0;
        end
      end
    end
  endgenerate

  // For demonstration: forward out_msg array to flat out_layer_bus
  // pack out_layer_bus
  generate
    for (r = 0; r < Z_local; r = r + 1) begin : pack_out
      assign out_layer_bus[r*MSG_W +: MSG_W] = out_msg[r];
    end
  endgenerate

endmodule