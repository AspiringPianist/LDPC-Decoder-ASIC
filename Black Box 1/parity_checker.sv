// parity_checker.sv
`timescale 1ns/1ps
import defs_pkg::*;
module parity_checker #(
  parameter int NUM_COLS = NUM_COLS,
  parameter int Z = Z,
  parameter int NUM_FRAMES = NUM_FRAMES
)(
  input  logic clk,
  input  logic rst_n,
  // parity bits arriving from start column for current frame (z bits)
  input  logic [Z-1:0] parity_in,
  // frame id associated with this parity vector
  input  logic [$clog2(NUM_FRAMES)-1:0] frame_id,
  // pulse: sample parity_in this cycle and update frame_done
  input  logic check_now,
  output logic [NUM_FRAMES-1:0] frame_done
);

  // frame_done latch array
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) frame_done <= '0;
    else begin
      if (check_now) begin
        // if any parity bit == 1 => parity failure => frame not done
        if (|parity_in) frame_done[frame_id] <= 1'b0;
        else frame_done[frame_id] <= 1'b1;
      end
    end
  end
endmodule