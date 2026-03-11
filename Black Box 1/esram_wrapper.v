// esram_wrapper.v
// Template for ASIC eSRAM macro. Replace internal content with your macro instance.
// For RTL simulation this falls back to a small inferable RAM.
module esram_wrapper #(
  parameter integer WIDTH = 5,
  parameter integer DEPTH = 42,
  parameter integer ADDR_W = 6
)(
  input  wire                  clk,
  input  wire [ADDR_W-1:0]     raddr,
  output wire [WIDTH-1:0]      rdata,
  input  wire                  wen,
  input  wire [ADDR_W-1:0]     waddr,
  input  wire [WIDTH-1:0]      wdata
);
  // TODO: Replace the following simulation fallback with ASIC eSRAM macro instantiation
  reg [WIDTH-1:0] mem_sim [0:DEPTH-1];
  assign rdata = mem_sim[raddr];
  always @(posedge clk) if (wen) mem_sim[waddr] <= wdata;
endmodule