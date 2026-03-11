// controller.v
`include "defs.v"
module controller (
  input  wire clk,
  input  wire rst_n,
  // simple interface: global cycle counter increments every clock
  output reg [$clog2(NUM_COLS)-1:0] cycle_idx, // 0..NUM_COLS-1
  // for each slice, produce the frame pointer faddr to use this cycle
  output reg [3:0] faddr_for_slice [0:NUM_COLS-1],
  // per-slice enable (1 = the frame scheduled for this slice is active)
  output reg en_slice [0:NUM_COLS-1],
  // simple API to mark a frame as finished (external: top-level parity reduction determines done)
  input  wire frame_done [0:NUM_FRAMES-1]
);
  integer i,j;
  initial begin
    cycle_idx = 0;
    for (i=0;i<NUM_COLS;i=i=i+1) begin
      faddr_for_slice[i] = 0;
      en_slice[i] = 1'b1;
    end
  end

  // schedule rule: slice s processes frame f = (cycle_idx - s) mod NUM_FRAMES
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cycle_idx <= 0;
      for (i=0;i<NUM_COLS;i=i=i+1) begin
        faddr_for_slice[i] <= 0;
        en_slice[i] <= 1'b1;
      end
    end else begin
      cycle_idx <= cycle_idx + 1;
      for (i=0;i<NUM_COLS;i=i+1) begin
        // compute frame index (signed)
        integer tmp = cycle_idx - i;
        integer f;
        if (tmp < 0) f = tmp + NUM_FRAMES;
        else f = tmp % NUM_FRAMES;
        faddr_for_slice[i] <= f;
        // if that frame is marked done, disable the slice for that frame (clock-gate behavior)
        if (frame_done[f]) en_slice[i] <= 1'b0;
        else en_slice[i] <= 1'b1;
      end
    end
  end
endmodule