// esram_macro_stub.sv
`timescale 1ns/1ps
module esram_macro_stub #(
  parameter int DEPTH = 42*16,
  parameter int DATA_W = 8
)(
  input  wire clk,
  input  wire ren,
  input  wire [$clog2(DEPTH)-1:0] raddr,
  output wire [DATA_W-1:0] rdata,
  input  wire wen,
  input  wire [$clog2(DEPTH)-1:0] waddr,
  input  wire [DATA_W-1:0] wdata
);
  // Synthesis flow: replace body with actual macro instantiation.
  // For simulation fallback, instantiate behavioral memory.
  // NOTE: keep the same interface as esram_bram_sim for easy swapping.
  `ifdef SIM
    // Behavioral fallback for simulation
    import defs_pkg::*;
    esram_bram_sim #(.DEPTH(DEPTH), .DATA_W(DATA_W)) beh (
      .clk(clk), .ren(ren), .raddr(raddr), .rdata(rdata),
      .wen(wen), .waddr(waddr), .wdata(wdata)
    );
  `else
    // Place-holder blackbox for synthesis/PNR - replace with real macro cell
    // synthesis translate_off
    import defs_pkg::*;
    esram_bram_sim #(.DEPTH(DEPTH), .DATA_W(DATA_W)) beh2 (
      .clk(clk), .ren(ren), .raddr(raddr), .rdata(rdata),
      .wen(wen), .waddr(waddr), .wdata(wdata)
    );
    // synthesis translate_on
  `endif
endmodule