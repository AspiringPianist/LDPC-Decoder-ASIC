// clock_gate_stub.sv
module clock_gate_stub (
  input  wire clk_in,
  input  wire enable,
  output wire clk_out
);
  // simulation: simple AND. Replace by latch-based clock-gate cell during synthesis.
  assign clk_out = clk_in & enable;
endmodule