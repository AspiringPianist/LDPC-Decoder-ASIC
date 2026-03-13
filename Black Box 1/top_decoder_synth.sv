// top_decoder_synth.sv
`timescale 1ns/1ps
import defs_pkg::*;
module top_decoder_synth #(
  parameter int RATE_SELECT = 0
)(
  input  wire clk,
  input  wire rst_n,
  input  wire start,
  input  wire [1:0] rate_select_in,  // Runtime rate selection (optional, defaults to RATE_SELECT parameter)
  output wire done_all
);
  // control
  wire [$clog2(NUM_LAYERS)-1:0] current_layer;
  wire [$clog2(NUM_LAYERS)*2-1:0] cycle_idx UNUSED; // kept for debugging if desired
  wire phase_cn;
  wire [NUM_COLS*4-1:0] faddr_bus;
  wire [NUM_COLS-1:0] en_slice_bus;
  wire check_now;
  wire [1:0] rate_select;
  global_control gctrl (
    .clk(clk), .rst_n(rst_n), .start(start), .rate_select_in(rate_select_in),
    .cycle_idx(cycle_idx), .current_layer(current_layer), .phase_cn(phase_cn),
    .faddr_bus(faddr_bus), .en_slice_bus(en_slice_bus), .check_now(check_now),
    .rate_select(rate_select)
  );

  // per-column flat buses
  wire [Z*MSG_W-1:0] layer_bus_out_flat [NUM_COLS-1:0];
  wire [Z*MSG_W-1:0] layer_bus_in_flat  [NUM_COLS-1:0];
  // parity bits from each column
  wire [Z-1:0] parity_bits_from_col [NUM_COLS-1:0];

  // instantiate column slices
  genvar c;
  generate
    for (c = 0; c < NUM_COLS; c = c + 1) begin : gen_cols
      wire [3:0] faddr = faddr_bus[c*4 +: 4];
      wire en_slice = en_slice_bus[c];
      column_slice #(
        .COL_ID(c),
        .Z(Z),
        .QV_W(QV_W),
        .LVC_MAG(LVC_MAG),
        .LVC_W(LVC_W),
        .NFRAMES(NUM_FRAMES),
        .MEM_TYPE("ESRAM") // you choose "BRAM" or "ESRAM"
      ) cs (
        .clk(clk), .rst_n(rst_n),
        .cycle_idx(cycle_idx),
        .faddr_read(faddr),
        .en_slice(en_slice),
        .in_layer_bus(layer_bus_in_flat[c]),
        .out_layer_bus(layer_bus_out_flat[c]),
        .parity_bits_out(parity_bits_from_col[c]) // capture parity bits from each column
      );
    end
  endgenerate

  // router arrays and instantiation per (col,row)
  logic [$clog2(Z)-1:0] router_to_row [NUM_COLS-1:0][Z-1:0];
  logic router_active [NUM_COLS-1:0][Z-1:0];
  logic router_inactive [NUM_COLS-1:0][Z-1:0];

  genvar gc, gr;
  generate
    for (gc = 0; gc < NUM_COLS; gc = gc + 1) begin : gen_router_col
      localparam int col_id = gc;
      for (gr = 0; gr < Z; gr = gr + 1) begin : gen_router_row
        localparam int row_id = gr;
        router #(.NUM_COLS(NUM_COLS), .Z(Z), .NUM_LAYERS(NUM_LAYERS), .RATE_SELECT(RATE_SELECT)) router_inst (
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

  // combinational routing: current_layer only (map out->in of next column)
  integer i, j;
  always_comb begin
    for (i = 0; i < NUM_COLS; i = i + 1) layer_bus_in_flat[i] = {Z*MSG_W{1'b0}};
    for (i = 0; i < NUM_COLS; i = i + 1) begin
      int next_col = (i + 1) % NUM_COLS;
      for (j = 0; j < Z; j = j + 1) begin
        int sidx = j * MSG_W;
        if (router_inactive[i][j]) begin
          // no connection (inactive)
        end else if (!router_active[i][j]) begin
          // bypass: copy same row
          layer_bus_in_flat[next_col][sidx +: MSG_W] = layer_bus_out_flat[i][sidx +: MSG_W];
        end else begin
          // active: route to to_row
          int dest = router_to_row[i][j];
          int didx = dest * MSG_W;
          layer_bus_in_flat[next_col][didx +: MSG_W] = layer_bus_out_flat[i][sidx +: MSG_W];
        end
      end
    end
  end

  // parity checker instance (connect parity bits from designated start column)
  // paper uses one designated start col (typically column 0)
  localparam int START_COL = 0;
  wire [Z-1:0] start_parity_bits = parity_bits_from_col[START_COL];
  wire [$clog2(NUM_FRAMES)-1:0] start_frame = faddr_bus[START_COL*4 +: 4];
  wire [NUM_FRAMES-1:0] frame_done;
  parity_checker #(.Z(Z), .NUM_FRAMES(NUM_FRAMES)) pchk (
    .clk(clk), .rst_n(rst_n),
    .parity_in(start_parity_bits),
    .frame_id(start_frame),
    .check_now(check_now),
    .frame_done(frame_done)
  );

  // done_all when all frame_done bits are set (early termination may set some)
  assign done_all = &frame_done;

endmodule