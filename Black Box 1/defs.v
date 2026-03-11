// defs.v
`timescale 1ns/1ps
module defs ();
  // default architecture params (paper values)
  parameter integer QV_W       = 5;   // channel LLR width (signed 2's complement)
  parameter integer LVC_MAG    = 4;   // magnitude bits for stored Lvc (sign-magnitude)
  parameter integer LVC_W      = 1 + LVC_MAG;
  parameter integer MIN_W      = LVC_MAG; // width for min1/min2
  parameter integer NUM_COLS   = 16;  // macrocolumns (paper)
  parameter integer Z_ROWS     = 42;  // sub-block rows per column (paper)
  parameter integer NUM_LAYERS = 8;   // base-matrix rows (paper)
  parameter integer NUM_FRAMES = 16;  // frame interleaving depth (paper)
  parameter integer MAX_ITER   = 10;  // algorithm max iterations
endmodule