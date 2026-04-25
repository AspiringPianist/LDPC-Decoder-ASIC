// defs_pkg.sv
package defs_pkg;
  // Architecture sizing (set to match Figure 7: 8 frames interleave)
  parameter int NUM_COLS   = 16;  // macrocolumns / column slices
  parameter int Z          = 42;  // QC submatrix size (rows per column slice)
  parameter int NUM_LAYERS = 8;   // base layers
  parameter int NUM_FRAMES = 8;   // frame interleave depth (Fig. 7)

  // Max active processing layers per PE per clock cycle (Fig. 5a, Fig. 9)
  parameter int MAX_LAYERS_PER_COL = 8; // Match 8 connection layers

  // Separate memory depths to match paper architecture
  parameter int NUM_QV_FRAMES   = 16; // Qv (channel LLR input buffer) depth = 16 frames
  parameter int NUM_LVC_FRAMES  = 8;  // Lvc (stored VN->CN messages) depth = 8 frames

  // Widths / quantization (tune to paper's numeric choices as required)
  parameter int MIN_W      = 4;   // bits for min magnitudes
  parameter int LVC_MAG    = MIN_W;
  parameter int LVC_W      = 1 + LVC_MAG;       // sign + magnitude
  parameter int QV_W       = 6;                 // soft LLR width (signed)
  parameter int MSG_W      = 1 + 1 + MIN_W + MIN_W; // pc + sc + min1 + min2

  // Multi-layer message bus width per row
  parameter int LAYER_MSG_W = MSG_W * MAX_LAYERS_PER_COL;

  // Algorithmic parameters
  parameter int OFFSET_BETA = 1; // default min-sum offset
  parameter int MAX_ITER   = 10;
endpackage : defs_pkg