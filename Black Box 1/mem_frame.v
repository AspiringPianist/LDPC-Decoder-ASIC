// mem_frame.v
// Simple multi-frame dual-ported synchronous RAMs (one cycle read, write on same cycle allowed).
// For FPGA use, replace with BRAM/array primitive; for ASIC, replace with eSRAM wrappers.

module mem_frame #(
  parameter integer WIDTH = 5,
  parameter integer DEPTH = 42,         // number of PEs per column
  parameter integer NFRAMES = 16
)(
  input  wire                     clk,
  // port A: read for frame faddr_a, row idx addr_a
  input  wire [3:0]               faddr_a,   // log2(NFRAMES) bits (assume <=16)
  input  wire [$clog2(DEPTH)-1:0] addr_a,
  output reg  [WIDTH-1:0]         rdata_a,
  // port B: write for frame faddr_b, row idx addr_b
  input  wire                     wen_b,
  input  wire [3:0]               faddr_b,
  input  wire [$clog2(DEPTH)-1:0] addr_b,
  input  wire [WIDTH-1:0]         wdata_b
);
  localparam integer TOTAL = DEPTH * NFRAMES;
  reg [WIDTH-1:0] mem [0:TOTAL-1];

  // Address linearization: idx = faddr * DEPTH + addr
  wire [$clog2(TOTAL)-1:0] idx_a = (faddr_a * DEPTH) + addr_a;
  wire [$clog2(TOTAL)-1:0] idx_b = (faddr_b * DEPTH) + addr_b;

  always @(posedge clk) begin
    rdata_a <= mem[idx_a];
    if (wen_b) mem[idx_b] <= wdata_b;
  end
endmodule