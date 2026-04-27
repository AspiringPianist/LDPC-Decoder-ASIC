// esram_bram_sim.sv
`timescale 1ns/1ps
import defs_pkg::*;
module esram_bram_sim #(
  parameter int DEPTH = Z*NUM_FRAMES,
  parameter int DATA_W = 8
)(
  input  logic clk,
  input  logic ren,                // read enable (synchronous)
  input  logic [$clog2(DEPTH)-1:0] raddr,
  output logic [DATA_W-1:0] rdata,

  input  logic wen,                // write enable (synchronous)
  input  logic [$clog2(DEPTH)-1:0] waddr,
  input  logic [DATA_W-1:0] wdata
);
  localparam int AW = $clog2(DEPTH);
  logic [DATA_W-1:0] mem [0:DEPTH-1];
  logic [AW-1:0] raddr_reg;
  always_ff @(posedge clk) begin
    raddr_reg <= raddr;
    if (wen) mem[waddr] <= wdata;
    if (ren) rdata <= mem[raddr_reg];
    else rdata <= {DATA_W{1'b0}};
  end
endmodule