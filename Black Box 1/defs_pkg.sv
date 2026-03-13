// defs_pkg.sv
// Central constants used throughout the project.
// Import with: import defs_pkg::*;
package defs_pkg;
  // architecture sizing (paper defaults)
  parameter int NUM_COLS   = 16;  // macrocolumns / column slices
  parameter int Z          = 42;  // QC submatrix size
  parameter int NUM_LAYERS = 8;   // base layers
  parameter int NUM_FRAMES = 16;  // pipelined frames (paper uses 16)
  // widths (tune as needed for your quantization)
  parameter int MIN_W      = 4;   // min1/min2 width (bits)
  parameter int LVC_MAG    = MIN_W;
  parameter int LVC_W      = 1 + LVC_MAG;       // sign + magnitude
  parameter int QV_W       = 6;                 // soft LLR width (signed)
  parameter int MSG_W      = 1 + 1 + MIN_W + MIN_W; // pc + sc + min1 + min2
  parameter int OFFSET_BETA = 1; // offset for offset-min-sum
  parameter int MAX_ITER   = 10;
endpackage : defs_pkg