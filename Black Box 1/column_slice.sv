// column_slice.v
import defs::*;
module column_slice #(
  parameter integer COL_ID = 0,
  parameter integer Z = 42,
  parameter integer QV_W = 5,
  parameter integer LVC_MAG = 4,
  parameter integer LVC_W = 1 + LVC_MAG,
  parameter integer NFRAMES = 16,
  parameter string MEM_TYPE = "ESRAM" // "BRAM" or "ESRAM"
)(
  input  wire                 clk,
  input  wire                 rst_n,
  input  wire [$clog2(NUM_COLS)-1:0] cycle_idx, // global cycle counter (controller)
  input  wire [3:0]           faddr_read,      // frame index selected by controller for this slice
  input  wire                 en_slice,        // enable processing when frame active
  // layer bus in/out (flattened): per-row {pc, sc, min1, min2}
  input  wire [Z*(1+1+LVC_MAG+LVC_MAG)-1:0] in_layer_bus,
  output wire [Z*(1+1+LVC_MAG+LVC_MAG)-1:0] out_layer_bus,
  // parity bits output (for parity reduction / early termination)
  output wire [Z-1:0] parity_bits_out
);

  // internal widths
  localparam integer ADDR_W = $clog2(Z * NFRAMES);
  // instantiate memory wrappers for each row (linearized layout)
  // We'll instantiate one shared memory per column with linearized addressing for area (for simplicity we instantiate Z independent small BRAMs here).

  genvar r;
  generate
    for (r=0; r<Z; r=r+1) begin : rows
      // linearized address = faddr_read * Z + r
      wire [ADDR_W-1:0] raddr = faddr_read * Z + r;
      wire [ADDR_W-1:0] waddr = faddr_read * Z + r;
      // Qv memory
      if (MEM_TYPE == "BRAM") begin
        bram_wrapper #(.WIDTH(QV_W), .DEPTH(Z*NFRAMES), .ADDR_W(ADDR_W)) qv_mem (
          .clk(clk), .raddr(raddr), .rdata(), .wen(), .waddr(waddr), .wdata()
        );
      end else begin
        esram_wrapper #(.WIDTH(QV_W), .DEPTH(Z*NFRAMES), .ADDR_W(ADDR_W)) qv_mem (
          .clk(clk), .raddr(raddr), .rdata(), .wen(), .waddr(waddr), .wdata()
        );
      end
      // Lvc memory (LVC_W bits)
      if (MEM_TYPE == "BRAM") begin
        bram_wrapper #(.WIDTH(LVC_W), .DEPTH(Z*NFRAMES), .ADDR_W(ADDR_W)) lvc_mem (
          .clk(clk), .raddr(raddr), .rdata(), .wen(), .waddr(waddr), .wdata()
        );
      end else begin
        esram_wrapper #(.WIDTH(LVC_W), .DEPTH(Z*NFRAMES), .ADDR_W(ADDR_W)) lvc_mem (
          .clk(clk), .raddr(raddr), .rdata(), .wen(), .waddr(waddr), .wdata()
        );
      end
      // NOTE: For clarity and synthesis you should replace these per-row instances with a single multiported SRAM / BRAM per column.
    end
  endgenerate

  // instantiate PEs for each row and route bus through router logic externally
  // For routing between columns the top-level connects out_layer_bus of this slice to in_layer_bus of the next column using router mapping.
  // Here the column slice simply consumes in_layer_bus (assumed already permuted by top-level wiring).

  generate
    for (r=0; r<Z; r=r+1) begin : pes
      wire in_pc  = in_layer_bus[r*(1+1+LVC_MAG+LVC_MAG) +: 1];
      wire in_sc  = in_layer_bus[r*(1+1+LVC_MAG+LVC_MAG) + 1 +: 1];
      wire [LVC_MAG-1:0] in_min1 = in_layer_bus[r*(1+1+LVC_MAG+LVC_MAG) + 2 +: LVC_MAG];
      wire [LVC_MAG-1:0] in_min2 = in_layer_bus[r*(1+1+LVC_MAG+LVC_MAG) + 2 + LVC_MAG +: LVC_MAG];

      // read stored mem values (combinational read registers would be needed; simplify here: assume mem read ports filled into regs before scheduling)
      // For simulation you must hook the actual read data to the stored inputs. For synthesizable design the read addresses must be applied one cycle prior to PE usage.
      wire [LVC_W-1:0] stored_lvc_sm = {LVC_W{1'b0}}; // placeholder: tie-in to lvc_mem.rdata
      wire signed [QV_W-1:0] stored_qv = {QV_W{1'b0}}; // placeholder: tie-in to qv_mem.rdata

      wire pe_active = 1'b1; // top-level router will determine bypass; for now assume active. Replace with routed active flag.

      // Determine whether this row is scheduled this cycle: en_slice indicates frame not finished
      wire do_cycle = en_slice;

      // instantiate PE
      pe #(.QV_W(QV_W), .LVC_MAG(LVC_MAG), .LVC_W(LVC_W), .MIN_W(MIN_W), .OFFSET_BETA(OFFSET_BETA)) pe_i (
        .clk(clk), .rst_n(rst_n),
        .active(pe_active),
        .do_cycle(do_cycle),
        .phase_cn((cycle_idx % 16) < 8),
        .in_pc(in_pc), .in_sc(in_sc), .in_min1(in_min1), .in_min2(in_min2),
        .stored_lvc_sm(stored_lvc_sm),
        .stored_qv(stored_qv),
        .out_pc(out_layer_bus[r*(1+1+LVC_MAG+LVC_MAG) +: 1]),
        .out_sc(out_layer_bus[r*(1+1+LVC_MAG+LVC_MAG) + 1 +: 1]),
        .out_min1(out_layer_bus[r*(1+1+LVC_MAG+LVC_MAG) + 2 +: LVC_MAG]),
        .out_min2(out_layer_bus[r*(1+1+LVC_MAG+LVC_MAG) + 2 + LVC_MAG +: LVC_MAG]),
        .lvc_wdata(), .lvc_wen(), .qv_wdata(), .qv_wen(),
        .c_hat_out(parity_bits_out[r])
      );
    end
  endgenerate
endmodule