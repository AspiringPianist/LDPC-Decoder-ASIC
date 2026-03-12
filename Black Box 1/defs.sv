// defs.sv
package defs;
  parameter int QV_W       = 5;
  parameter int LVC_MAG    = 4;
  parameter int LVC_W      = 1 + LVC_MAG;
  parameter int MIN_W      = LVC_MAG;
  parameter int NUM_COLS   = 16;
  parameter int Z          = 42;
  parameter int NUM_LAYERS = 8;
  parameter int NUM_FRAMES = 16;
  parameter int MAX_ITER   = 10;
  parameter int OFFSET_BETA = 1;
endpackage : defs