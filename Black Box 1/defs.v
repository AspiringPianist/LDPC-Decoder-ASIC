// defs.v
`timescale 1ns/1ps
module defs();
  // Paper defaults (tune if needed)
  parameter integer QV_W       = 5;   // channel LLR width (signed 2's complement)
  parameter integer LVC_MAG    = 4;   // magnitude bits for stored Lvc (sign-magnitude)
  parameter integer LVC_W      = 1 + LVC_MAG;
  parameter integer MIN_W      = LVC_MAG; // width for min1/min2
  parameter integer NUM_COLS   = 16;  // macrocolumns
  parameter integer Z_ROWS     = 42;  // subblock rows
  parameter integer NUM_LAYERS = 8;   // logical layers
  parameter integer NUM_FRAMES = 16;  // pipelined frame interleave depth
  parameter integer MAX_ITER   = 10;  // algorithm iterations
  parameter integer OFFSET_BETA = 1;  // offset for offset-min-sum
endmodule