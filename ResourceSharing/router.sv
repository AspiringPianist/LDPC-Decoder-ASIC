// router.sv — QC shift table lookup for all layers simultaneously.
// Given (from_col, from_row) and rate_select, returns per-layer
// to_row, active, and inactive_layer for ALL 8 LAYERS at once.
`timescale 1ns/1ps
import defs_pkg::*;

module router #(
  parameter integer NUM_COLS   = 16,
  parameter integer Z          = 42,
  parameter integer NUM_LAYERS = 8
)(
  input  logic [1:0]                    rate_select,
  input  logic [$clog2(NUM_COLS)-1:0]   from_col,
  input  logic [$clog2(Z)-1:0]          from_row,
  // Flat packed buses for Icarus compatibility
  output logic [NUM_LAYERS*$clog2(Z)-1:0] to_row_flat,
  output logic [NUM_LAYERS-1:0]           active_flat,
  output logic [NUM_LAYERS-1:0]           inactive_flat
);

  localparam int TR_W = $clog2(Z);

  // QC shift table lookup function
  function integer get_qc_shift;
    input integer rate, col, lay;
    integer val;
    begin
      val = -2; // default inactive
      case (rate)
        // ---- Rate 1/2 ----
        0: case (col)
          0:  case(lay) 0:val=40; 1:val=34; 2:val=-1; 3:val=-1; 4:val=35; 5:val=29; 6:val=-1; 7:val=-1; endcase
          1:  case(lay) 0:val=-1; 1:val=-1; 2:val=36; 3:val=27; 4:val=-1; 5:val=-1; 6:val=31; 7:val=22; endcase
          2:  case(lay) 0:val=38; 1:val=35; 2:val=-1; 3:val=-1; 4:val=41; 5:val= 0; 6:val=-1; 7:val=-1; endcase
          3:  case(lay) 0:val=-1; 1:val=-1; 2:val=31; 3:val=18; 4:val=-1; 5:val=-1; 6:val=23; 7:val=34; endcase
          4:  case(lay) 0:val=13; 1:val=27; 2:val=-1; 3:val=-1; 4:val=40; 5:val=-1; 6:val=-1; 7:val=31; endcase
          5:  case(lay) 0:val=-1; 1:val=-1; 2:val= 7; 3:val=12; 4:val=-1; 5:val=22; 6:val=21; 7:val=-1; endcase
          6:  case(lay) 0:val= 5; 1:val=-1; 2:val=-1; 3:val=20; 4:val=39; 5:val=-1; 6:val=-1; 7:val=14; endcase
          7:  case(lay) 0:val=-1; 1:val=30; 2:val=34; 3:val=-1; 4:val=-1; 5:val= 4; 6:val=20; 7:val=-1; endcase
          8:  case(lay) 0:val=18; 1:val= 2; 2:val=-1; 3:val=-1; 4:val=28; 5:val=-1; 6:val=-1; 7:val= 4; endcase
          9:  case(lay) 0:val=-1; 1:val= 1; 2:val=10; 3:val=-1; 4:val=-1; 5:val=28; 6:val=-1; 7:val=-1; endcase
          10: case(lay) 0:val=-1; 1:val=-1; 2:val=41; 3:val=15; 4:val=-1; 5:val=-1; 6:val=12; 7:val=-1; endcase
          11: case(lay) 0:val=-1; 1:val=-1; 2:val=-1; 3:val= 6; 4:val= 3; 5:val=27; 6:val=-1; 7:val=-1; endcase
          12: case(lay) 0:val=-1; 1:val=-1; 2:val=-1; 3:val=-1; 4:val=28; 5:val=-1; 6:val=-1; 7:val=13; endcase
          13: case(lay) 0:val=-1; 1:val=-1; 2:val=-1; 3:val=-1; 4:val=-1; 5:val=23; 6:val= 0; 7:val=-1; endcase
          14: case(lay) 0:val=-1; 1:val=-1; 2:val=-1; 3:val=-1; 4:val=-1; 5:val=-1; 6:val=13; 7:val=22; endcase
          15: case(lay) 0:val=-1; 1:val=-1; 2:val=-1; 3:val=-1; 4:val=-1; 5:val=-1; 6:val=-1; 7:val=24; endcase
        endcase
        // ---- Rate 5/8 ----
        1: case (col)
          0:  case(lay) 0:val=-2; 1:val=-2; 2:val=20; 3:val=30; 4:val=35; 5:val=29; 6:val=-1; 7:val=-1; endcase
          1:  case(lay) 0:val=-2; 1:val=-2; 2:val=36; 3:val=27; 4:val=-1; 5:val=-1; 6:val=31; 7:val=22; endcase
          2:  case(lay) 0:val=-2; 1:val=-2; 2:val=34; 3:val=-1; 4:val=41; 5:val= 0; 6:val=-1; 7:val=-1; endcase
          3:  case(lay) 0:val=-2; 1:val=-2; 2:val=31; 3:val=18; 4:val=-1; 5:val=-1; 6:val=23; 7:val=34; endcase
          4:  case(lay) 0:val=-2; 1:val=-2; 2:val=20; 3:val=-1; 4:val=40; 5:val=-1; 6:val=-1; 7:val=31; endcase
          5:  case(lay) 0:val=-2; 1:val=-2; 2:val= 7; 3:val=12; 4:val=-1; 5:val=22; 6:val=21; 7:val=-1; endcase
          6:  case(lay) 0:val=-2; 1:val=-2; 2:val=41; 3:val=20; 4:val=39; 5:val=-1; 6:val=-1; 7:val=14; endcase
          7:  case(lay) 0:val=-2; 1:val=-2; 2:val=34; 3:val=14; 4:val=-1; 5:val= 4; 6:val=20; 7:val=-1; endcase
          8:  case(lay) 0:val=-2; 1:val=-2; 2:val=-1; 3:val= 2; 4:val=28; 5:val=-1; 6:val=-1; 7:val= 4; endcase
          9:  case(lay) 0:val=-2; 1:val=-2; 2:val=10; 3:val=25; 4:val=-1; 5:val=28; 6:val= 9; 7:val=-1; endcase
          10: case(lay) 0:val=-2; 1:val=-2; 2:val=41; 3:val=15; 4:val=-1; 5:val=-1; 6:val=12; 7:val=-1; endcase
          11: case(lay) 0:val=-2; 1:val=-2; 2:val=-1; 3:val= 6; 4:val= 3; 5:val=27; 6:val=-1; 7:val=-1; endcase
          12: case(lay) 0:val=-2; 1:val=-2; 2:val=-1; 3:val=-1; 4:val=28; 5:val=24; 6:val=-1; 7:val=-1; endcase
          13: case(lay) 0:val=-2; 1:val=-2; 2:val=-1; 3:val=-1; 4:val=-1; 5:val=23; 6:val= 0; 7:val=-1; endcase
          14: case(lay) 0:val=-2; 1:val=-2; 2:val=-1; 3:val=-1; 4:val=-1; 5:val=-1; 6:val=13; 7:val=22; endcase
          15: case(lay) 0:val=-2; 1:val=-2; 2:val=-1; 3:val=-1; 4:val=-1; 5:val=-1; 6:val=-1; 7:val=24; endcase
        endcase
        // ---- Rate 3/4 ----
        2: case (col)
          0:  case(lay) 0:val=-2; 1:val=-2; 2:val=-2; 3:val=-2; 4:val=35; 5:val=29; 6:val=37; 7:val=25; endcase
          1:  case(lay) 0:val=-2; 1:val=-2; 2:val=-2; 3:val=-2; 4:val=19; 5:val=30; 6:val=31; 7:val=22; endcase
          2:  case(lay) 0:val=-2; 1:val=-2; 2:val=-2; 3:val=-2; 4:val=41; 5:val= 0; 6:val=18; 7:val= 4; endcase
          3:  case(lay) 0:val=-2; 1:val=-2; 2:val=-2; 3:val=-2; 4:val=22; 5:val= 8; 6:val=23; 7:val=34; endcase
          4:  case(lay) 0:val=-2; 1:val=-2; 2:val=-2; 3:val=-2; 4:val=40; 5:val=33; 6:val=11; 7:val=31; endcase
          5:  case(lay) 0:val=-2; 1:val=-2; 2:val=-2; 3:val=-2; 4:val=41; 5:val=22; 6:val=21; 7:val= 3; endcase
          6:  case(lay) 0:val=-2; 1:val=-2; 2:val=-2; 3:val=-2; 4:val=39; 5:val=17; 6:val= 6; 7:val=14; endcase
          7:  case(lay) 0:val=-2; 1:val=-2; 2:val=-2; 3:val=-2; 4:val= 6; 5:val= 4; 6:val=20; 7:val=15; endcase
          8:  case(lay) 0:val=-2; 1:val=-2; 2:val=-2; 3:val=-2; 4:val=28; 5:val=27; 6:val=32; 7:val= 4; endcase
          9:  case(lay) 0:val=-2; 1:val=-2; 2:val=-2; 3:val=-2; 4:val=18; 5:val=28; 6:val= 9; 7:val=-1; endcase
          10: case(lay) 0:val=-2; 1:val=-2; 2:val=-2; 3:val=-2; 4:val=17; 5:val=20; 6:val=12; 7:val=14; endcase
          11: case(lay) 0:val=-2; 1:val=-2; 2:val=-2; 3:val=-2; 4:val= 3; 5:val=27; 6:val=29; 7:val=18; endcase
          12: case(lay) 0:val=-2; 1:val=-2; 2:val=-2; 3:val=-2; 4:val=28; 5:val=24; 6:val=-1; 7:val=13; endcase
          13: case(lay) 0:val=-2; 1:val=-2; 2:val=-2; 3:val=-2; 4:val=-1; 5:val=23; 6:val= 0; 7:val=22; endcase
          14: case(lay) 0:val=-2; 1:val=-2; 2:val=-2; 3:val=-2; 4:val=-1; 5:val=-1; 6:val=13; 7:val=22; endcase
          15: case(lay) 0:val=-2; 1:val=-2; 2:val=-2; 3:val=-2; 4:val=-1; 5:val=-1; 6:val=-1; 7:val=24; endcase
        endcase
        // ---- Rate 13/16 ----
        3: case (col)
          0:  case(lay) 0:val=-2; 1:val=-2; 2:val=-2; 3:val=-2; 4:val=-2; 5:val=29; 6:val=37; 7:val=25; endcase
          1:  case(lay) 0:val=-2; 1:val=-2; 2:val=-2; 3:val=-2; 4:val=-2; 5:val=30; 6:val=31; 7:val=22; endcase
          2:  case(lay) 0:val=-2; 1:val=-2; 2:val=-2; 3:val=-2; 4:val=-2; 5:val= 0; 6:val=18; 7:val= 4; endcase
          3:  case(lay) 0:val=-2; 1:val=-2; 2:val=-2; 3:val=-2; 4:val=-2; 5:val= 8; 6:val=23; 7:val=34; endcase
          4:  case(lay) 0:val=-2; 1:val=-2; 2:val=-2; 3:val=-2; 4:val=-2; 5:val=33; 6:val=11; 7:val=31; endcase
          5:  case(lay) 0:val=-2; 1:val=-2; 2:val=-2; 3:val=-2; 4:val=-2; 5:val=22; 6:val=21; 7:val= 3; endcase
          6:  case(lay) 0:val=-2; 1:val=-2; 2:val=-2; 3:val=-2; 4:val=-2; 5:val=17; 6:val= 6; 7:val=14; endcase
          7:  case(lay) 0:val=-2; 1:val=-2; 2:val=-2; 3:val=-2; 4:val=-2; 5:val= 4; 6:val=20; 7:val=15; endcase
          8:  case(lay) 0:val=-2; 1:val=-2; 2:val=-2; 3:val=-2; 4:val=-2; 5:val=27; 6:val=32; 7:val= 4; endcase
          9:  case(lay) 0:val=-2; 1:val=-2; 2:val=-2; 3:val=-2; 4:val=-2; 5:val=28; 6:val= 9; 7:val= 2; endcase
          10: case(lay) 0:val=-2; 1:val=-2; 2:val=-2; 3:val=-2; 4:val=-2; 5:val=20; 6:val=12; 7:val=14; endcase
          11: case(lay) 0:val=-2; 1:val=-2; 2:val=-2; 3:val=-2; 4:val=-2; 5:val=27; 6:val=29; 7:val=18; endcase
          12: case(lay) 0:val=-2; 1:val=-2; 2:val=-2; 3:val=-2; 4:val=-2; 5:val=24; 6:val=10; 7:val=13; endcase
          13: case(lay) 0:val=-2; 1:val=-2; 2:val=-2; 3:val=-2; 4:val=-2; 5:val=23; 6:val= 0; 7:val=22; endcase
          14: case(lay) 0:val=-2; 1:val=-2; 2:val=-2; 3:val=-2; 4:val=-2; 5:val=-1; 6:val=13; 7:val=22; endcase
          15: case(lay) 0:val=-2; 1:val=-2; 2:val=-2; 3:val=-2; 4:val=-2; 5:val=-1; 6:val=-1; 7:val=24; endcase
        endcase
        default: val = -2;
      endcase
      get_qc_shift = val;
    end
  endfunction

  // All-layer combinational lookup + packing
  always_comb begin
    for (int lay = 0; lay < NUM_LAYERS; lay++) begin
      integer s_val;
      logic [TR_W-1:0] tr;
      logic act, inact;

      s_val = get_qc_shift(rate_select, from_col, lay);

      if (s_val == -2) begin
        inact = 1'b1;
        act   = 1'b0;
        tr    = from_row;
      end else if (s_val == -1) begin
        inact = 1'b0;
        act   = 1'b0;
        tr    = from_row;
      end else begin
        inact = 1'b0;
        act   = 1'b1;
        tr    = (from_row + s_val) % Z;
      end
      
      to_row_flat[lay*TR_W +: TR_W] = tr;
      active_flat[lay]              = act;
      inactive_flat[lay]            = inact;
    end
  end
endmodule