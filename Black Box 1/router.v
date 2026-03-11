// router.v  -- use this file to hold the QC shift table(s) for each rate.
// The tables are qc_shift_rate_xxx[col][layer] with col=0..15 and layer=0..7.
// -1 means B (all-zero submatrix) => bypass routing (active=0).
// After pasting, the router is combinational: given from_col, from_row, from_layer and RATE_SELECT,
// it returns to_row and active.

module router #(
  parameter integer NUM_COLS = 16,
  parameter integer Z = 42,
  parameter integer NUM_LAYERS = 8,
  parameter integer RATE_SELECT = 0
)(
  input  wire [$clog2(NUM_COLS)-1:0]   from_col,
  input  wire [$clog2(Z)-1:0]          from_row,
  input  wire [$clog2(NUM_LAYERS)-1:0] from_layer,
  output reg  [$clog2(Z)-1:0]          to_row,
  output reg                           active,
  output reg                           inactive_layer
);

  // --------------------------
  // localparam tables (16 cols × 8 layers)
  // column-major: qc_shift[col][layer]
  // -1 indicates an all-zero submatrix (bypass).
  // --------------------------
  
  // Rate 1/2 (No inactive wired layers)
  localparam integer qc_shift_rate_1_2 [0:15][0:7] = '{
    '{  40,  34,  -1,  -1,  35,  29,  -1,  -1 }, // col 0
    '{  -1,  -1,  36,  27,  -1,  -1,  31,  22 }, // col 1
    '{  38,  35,  -1,  -1,  41,   0,  -1,  -1 }, // col 2
    '{  -1,  -1,  31,  18,  -1,  -1,  23,  34 }, // col 3
    '{  13,  27,  -1,  -1,  40,  -1,  -1,  31 }, // col 4
    '{  -1,  -1,   7,  12,  -1,  22,  21,  -1 }, // col 5
    '{   5,  -1,  -1,  20,  39,  -1,  -1,  14 }, // col 6
    '{  -1,  30,  34,  -1,  -1,   4,  20,  -1 }, // col 7
    '{  18,   2,  -1,  -1,  28,  -1,  -1,   4 }, // col 8
    '{  -1,   1,  10,  -1,  -1,  28,  -1,  -1 }, // col 9
    '{  -1,  -1,  41,  15,  -1,  -1,  12,  -1 }, // col 10
    '{  -1,  -1,  -1,   6,   3,  27,  -1,  -1 }, // col 11
    '{  -1,  -1,  -1,  -1,  28,  -1,  -1,  13 }, // col 12
    '{  -1,  -1,  -1,  -1,  -1,  23,   0,  -1 }, // col 13
    '{  -1,  -1,  -1,  -1,  -1,  -1,  13,  22 }, // col 14
    '{  -1,  -1,  -1,  -1,  -1,  -1,  -1,  24 }  // col 15
  };

  // Rate 5/8 (First 2 layers are inactive)
  localparam integer qc_shift_rate_5_8 [0:15][0:7] = '{
    '{  -2,  -2,  20,  30,  35,  29,  -1,  -1 }, // col 0
    '{  -2,  -2,  36,  27,  -1,  -1,  31,  22 }, // col 1
    '{  -2,  -2,  34,  -1,  41,   0,  -1,  -1 }, // col 2
    '{  -2,  -2,  31,  18,  -1,  -1,  23,  34 }, // col 3
    '{  -2,  -2,  20,  -1,  40,  -1,  -1,  31 }, // col 4
    '{  -2,  -2,   7,  12,  -1,  22,  21,  -1 }, // col 5
    '{  -2,  -2,  41,  20,  39,  -1,  -1,  14 }, // col 6
    '{  -2,  -2,  34,  14,  -1,   4,  20,  -1 }, // col 7
    '{  -2,  -2,  -1,   2,  28,  -1,  -1,   4 }, // col 8
    '{  -2,  -2,  10,  25,  -1,  28,   9,  -1 }, // col 9
    '{  -2,  -2,  41,  15,  -1,  -1,  12,  -1 }, // col 10
    '{  -2,  -2,  -1,   6,   3,  27,  -1,  -1 }, // col 11
    '{  -2,  -2,  -1,  -1,  28,  24,  -1,  -1 }, // col 12
    '{  -2,  -2,  -1,  -1,  -1,  23,   0,  -1 }, // col 13
    '{  -2,  -2,  -1,  -1,  -1,  -1,  13,  22 }, // col 14
    '{  -2,  -2,  -1,  -1,  -1,  -1,  -1,  24 }  // col 15
  };

  // Rate 3/4 (First 4 layers are inactive)
  localparam integer qc_shift_rate_3_4 [0:15][0:7] = '{
    '{  -2,  -2,  -2,  -2,  35,  29,  37,  25 }, // col 0
    '{  -2,  -2,  -2,  -2,  19,  30,  31,  22 }, // col 1
    '{  -2,  -2,  -2,  -2,  41,   0,  18,   4 }, // col 2
    '{  -2,  -2,  -2,  -2,  22,   8,  23,  34 }, // col 3
    '{  -2,  -2,  -2,  -2,  40,  33,  11,  31 }, // col 4
    '{  -2,  -2,  -2,  -2,  41,  22,  21,   3 }, // col 5
    '{  -2,  -2,  -2,  -2,  39,  17,   6,  14 }, // col 6
    '{  -2,  -2,  -2,  -2,   6,   4,  20,  15 }, // col 7
    '{  -2,  -2,  -2,  -2,  28,  27,  32,   4 }, // col 8
    '{  -2,  -2,  -2,  -2,  18,  28,   9,  -1 }, // col 9
    '{  -2,  -2,  -2,  -2,  17,  20,  12,  14 }, // col 10
    '{  -2,  -2,  -2,  -2,   3,  27,  29,  18 }, // col 11
    '{  -2,  -2,  -2,  -2,  28,  24,  -1,  13 }, // col 12
    '{  -2,  -2,  -2,  -2,  -1,  23,   0,  22 }, // col 13
    '{  -2,  -2,  -2,  -2,  -1,  -1,  13,  22 }, // col 14
    '{  -2,  -2,  -2,  -2,  -1,  -1,  -1,  24 }  // col 15
  };

  // Rate 13/16 (First 5 layers are inactive)
  localparam integer qc_shift_rate_13_16 [0:15][0:7] = '{
    '{  -2,  -2,  -2,  -2,  -2,  29,  37,  25 }, // col 0
    '{  -2,  -2,  -2,  -2,  -2,  30,  31,  22 }, // col 1
    '{  -2,  -2,  -2,  -2,  -2,   0,  18,   4 }, // col 2
    '{  -2,  -2,  -2,  -2,  -2,   8,  23,  34 }, // col 3
    '{  -2,  -2,  -2,  -2,  -2,  33,  11,  31 }, // col 4
    '{  -2,  -2,  -2,  -2,  -2,  22,  21,   3 }, // col 5
    '{  -2,  -2,  -2,  -2,  -2,  17,   6,  14 }, // col 6
    '{  -2,  -2,  -2,  -2,  -2,   4,  20,  15 }, // col 7
    '{  -2,  -2,  -2,  -2,  -2,  27,  32,   4 }, // col 8
    '{  -2,  -2,  -2,  -2,  -2,  28,   9,   2 }, // col 9
    '{  -2,  -2,  -2,  -2,  -2,  20,  12,  14 }, // col 10
    '{  -2,  -2,  -2,  -2,  -2,  27,  29,  18 }, // col 11
    '{  -2,  -2,  -2,  -2,  -2,  24,  10,  13 }, // col 12
    '{  -2,  -2,  -2,  -2,  -2,  23,   0,  22 }, // col 13
    '{  -2,  -2,  -2,  -2,  -2,  -1,  13,  22 }, // col 14
    '{  -2,  -2,  -2,  -2,  -2,  -1,  -1,  24 }  // col 15
  };

  // Select the proper table and compute mapping
  integer s;
  always @(*) begin
    inactive_layer = 1'b0;
    active = 1'b0;
    to_row = from_row;

    case (RATE_SELECT)
      0: s = qc_shift_rate_1_2[from_col][from_layer];
      1: s = qc_shift_rate_5_8[from_col][from_layer];
      2: s = qc_shift_rate_3_4[from_col][from_layer];
      3: s = qc_shift_rate_13_16[from_col][from_layer];
      default: s = -2;
    endcase

    if (s == -2) begin
      // inactive wired layer: treat as absent (no wiring for this layer)
      inactive_layer = 1'b1;
      active = 1'b0;
      to_row = from_row; // keep unchanged
    end else if (s == -1) begin
      // bypass (all-zero submatrix): layer exists, but no CN update; forward same-row
      inactive_layer = 1'b0;
      active = 1'b0;
      to_row = from_row; // forward on same row
    end else begin
      // active cyclic-shift mapping
      inactive_layer = 1'b0;
      active = 1'b1;
      to_row = (from_row + s) % Z;
    end
  end
endmodule