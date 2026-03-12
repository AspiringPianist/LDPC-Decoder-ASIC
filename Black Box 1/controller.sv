// controller.v
import defs::*;
module controller #(
  parameter integer NUM_COLS = 16,
  parameter integer NUM_FRAMES = 16
)(
  input  wire clk,
  input  wire rst_n,
  // outputs: frame index per slice (packed bus) and enable per slice (packed)
  output reg [NUM_COLS*4-1:0] faddr_bus,    // each slice faddr in 4 bits
  output reg [NUM_COLS-1:0]   en_slice_bus, // 1 = slice enabled this cycle
  // input: frame_done flags per frame (1=terminated)
  input  wire [NUM_FRAMES-1:0] frame_done,
  output reg [$clog2(NUM_COLS)-1:0] cycle_idx
);
  integer i;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cycle_idx <= 0;
      faddr_bus <= {NUM_COLS*4{1'b0}};
      en_slice_bus <= {NUM_COLS{1'b1}};
    end else begin
      cycle_idx <= cycle_idx + 1;
      // compute frame index for each column slice:
      for (i=0;i<NUM_COLS;i=i+1) begin
        integer tmp;
        integer f;
        tmp = i - (cycle_idx % NUM_FRAMES);
        if (tmp < 0) f = tmp + NUM_FRAMES;
        else f = tmp % NUM_FRAMES;
        faddr_bus[i*4 +: 4] <= f[3:0];
        en_slice_bus[i] <= (frame_done[f] ? 1'b0 : 1'b1);
      end
    end
  end
endmodule