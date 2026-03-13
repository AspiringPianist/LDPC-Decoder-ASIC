// top_decoder_synth.sv
`timescale 1ns/1ps
import defs_pkg::*;
module top_decoder_synth #(
  parameter int RATE_SELECT = 0
)(
  input  wire clk,
  input  wire rst_n,
  input  wire start,
  output wire done_all
);
  // control
  wire [$clog2(NUM_LAYERS*2)-1:0] cycle_idx;
  wire [$clog2(NUM_LAYERS)-1:0] current_layer;
  wire phase_cn;
  wire [NUM_COLS*4-1:0] faddr_bus_unmasked;
  wire [NUM_COLS-1:0] en_slice_bus_masked;
  wire check_now;
  wire [1:0] rate_select;

  // instantiate controller
  global_control #(.NUM_COLS_p(NUM_COLS), .Z_p(Z), .NUM_LAYERS_p(NUM_LAYERS), .NUM_FRAMES_p(NUM_FRAMES)) gctrl (
    .clk(clk), .rst_n(rst_n), .start(start), .rate_select_in(RATE_SELECT),
    .cycle_idx(cycle_idx), .current_layer(current_layer), .phase_cn(phase_cn),
    .faddr_bus(faddr_bus_unmasked), .en_slice_bus(), .check_now(check_now), .rate_select(rate_select)
  );

  // frame_done (from parity checker) will gate slice enables
  wire [NUM_FRAMES-1:0] frame_done;
  // en_slice final per-col = base_enable & ~frame_done[faddr]
  genvar c;
  wire [NUM_COLS-1:0] en_slice_bus;
  generate
    for (c = 0; c < NUM_COLS; c = c + 1) begin : gen_en
      wire [3:0] faddr = faddr_bus_unmasked[c*4 +: 4];
      assign en_slice_bus[c] = (frame_done[faddr] == 1'b1) ? 1'b0 : 1'b1;
    end
  endgenerate

  // per-column flattened layer buses
  wire [Z*MSG_W-1:0] layer_bus_out_flat [NUM_COLS-1:0];
  wire [Z*MSG_W-1:0] layer_bus_in_flat  [NUM_COLS-1:0];

  // router arrays: to_row, active, inactive
  logic [$clog2(Z)-1:0] router_to_row [NUM_COLS-1:0][Z-1:0];
  logic router_active   [NUM_COLS-1:0][Z-1:0];
  logic router_inactive [NUM_COLS-1:0][Z-1:0];

  genvar gc, gr;
  generate
    for (gc = 0; gc < NUM_COLS; gc = gc + 1) begin : gen_rcol
      localparam int col_id = gc;
      for (gr = 0; gr < Z; gr = gr + 1) begin : gen_rrow
        localparam int row_id = gr;
        router #(.NUM_COLS(NUM_COLS), .Z(Z), .NUM_LAYERS(NUM_LAYERS), .RATE_SELECT(RATE_SELECT)) r_inst (
          .from_col(col_id[$clog2(NUM_COLS)-1:0]),
          .from_row(row_id[$clog2(Z)-1:0]),
          .from_layer(current_layer),
          .to_row(router_to_row[col_id][row_id]),
          .active(router_active[col_id][row_id]),
          .inactive_layer(router_inactive[col_id][row_id])
        );
      end
    end
  endgenerate

  // Build per-column packed vectors for router flags and pass to column slices
  generate
    for (c = 0; c < NUM_COLS; c = c + 1) begin : gen_cols
      // build router_active_vec and router_inactive_vec per column
      wire [Z-1:0] router_active_vec;
      wire [Z-1:0] router_inactive_vec;
      // flatten from router_active array
      genvar rr;
      for (rr = 0; rr < Z; rr = rr + 1) begin : flatten_flags
        assign router_active_vec[rr]   = router_active[c][rr];
        assign router_inactive_vec[rr] = router_inactive[c][rr];
      end

      // instantiate column slice
      column_slice #(
        .COL_ID(c),
        .Z_local(Z),
        .QV_W_local(QV_W),
        .LVC_MAG_local(LVC_MAG),
        .LVC_W_local(LVC_W),
        .NFRAMES(NUM_FRAMES)
      ) cs (
        .clk(clk),
        .rst_n(rst_n),
        .cycle_idx(cycle_idx),
        .faddr_read(faddr_bus_unmasked[c*4 +: 4]),
        .en_slice(en_slice_bus[c]),
        .in_layer_bus(layer_bus_in_flat[c]),
        .out_layer_bus(layer_bus_out_flat[c]),
        .router_active_vec(router_active_vec),
        .router_inactive_vec(router_inactive_vec),
        .parity_bits_out() // will be connected below for start column
      );
    end
  endgenerate

  // Combinational routing: map each (col, row) out -> (col+1).to_row per router
  integer i,j;
  always_comb begin
    for (i = 0; i < NUM_COLS; i = i + 1) layer_bus_in_flat[i] = {Z*MSG_W{1'b0}};
    for (i = 0; i < NUM_COLS; i = i + 1) begin
      int next_col = (i + 1) % NUM_COLS;
      for (j = 0; j < Z; j = j + 1) begin
        int sidx = j * MSG_W;
        if (router_inactive[i][j]) begin
          // inactive: no message forwarded for this row
        end else if (!router_active[i][j]) begin
          // bypass: same-row forward
          layer_bus_in_flat[next_col][sidx +: MSG_W] = layer_bus_out_flat[i][sidx +: MSG_W];
        end else begin
          // active: route to shifted destination
          int dest = router_to_row[i][j];
          int didx = dest * MSG_W;
          layer_bus_in_flat[next_col][didx +: MSG_W] = layer_bus_out_flat[i][sidx +: MSG_W];
        end
      end
    end
  end

  // Parity checker hookup: choose START_COL (paper denotes start col; we choose 0)
  localparam int START_COL = 0;
  // tie to the parity_bits_out of the instantiated slice: generated block name is gen_cols[START_COL].cs
  wire [Z-1:0] start_parity_bits;
  assign start_parity_bits = gen_cols[START_COL].cs.parity_bits_out;

  parity_checker #(.Z_p(Z), .NUM_FRAMES_p(NUM_FRAMES)) pchk (
    .clk(clk),
    .rst_n(rst_n),
    .parity_in(start_parity_bits),
    .frame_id(faddr_bus_unmasked[START_COL*4 +: 4]),
    .check_now(check_now),
    .frame_done(frame_done)
  );

  // done_all when all frames have terminated (paper semantics)
  assign done_all = &frame_done;

endmodule