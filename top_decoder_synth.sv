// top_decoder_synth.sv
// Top-level LDPC decoder: multi-layer parallel, pipeline pairs, clock gating.
// All routing uses generate+assign for icarus compatibility where possible.
`timescale 1ns/1ps
import defs_pkg::*;

module top_decoder_synth (
  input  wire clk,
  input  wire rst_n,
  input  wire start,
  input  wire [1:0] rate_select_in,
  output wire done_all
);

  localparam int NL = NUM_LAYERS;
  localparam int MW = MSG_W;
  localparam int COL_BUS_W = Z * NL * MW;
  localparam int TR_W = $clog2(Z);
  localparam int COL_W = $clog2(NUM_COLS);
  localparam int FR_W = $clog2(NUM_FRAMES);

  // ---------------------------------------------------------------
  // Global controller
  // ---------------------------------------------------------------
  wire [COL_W-1:0] cycle_idx;
  wire phase_cn;
  wire [NUM_COLS*4-1:0] faddr_bus_raw;
  wire [1:0] rate_select;
  wire iter_done;

  wire check_now;
  global_control #(
    .NUM_COLS_p(NUM_COLS), .Z_p(Z), .NUM_LAYERS_p(NL), .NUM_FRAMES_p(NUM_FRAMES), .MAX_ITER_p(MAX_ITER)
  ) gctrl (
    .clk(clk), .rst_n(rst_n), .start(start),
    .rate_select_in(rate_select_in),
    .cycle_idx(cycle_idx), .phase_cn(phase_cn),
    .faddr_bus(faddr_bus_raw), .en_slice_bus(),
    .check_now(check_now), .rate_select(rate_select),
    .iter_done(iter_done)
  );

  // ---------------------------------------------------------------
  // Frame done / enable gating
  // ---------------------------------------------------------------
  wire [NUM_FRAMES-1:0] frame_done;
  wire [NUM_COLS-1:0] en_slice_bus;

  genvar gc;
  generate
    for (gc = 0; gc < NUM_COLS; gc = gc + 1) begin : gen_en
      wire [3:0] fa = faddr_bus_raw[gc*4 +: 4];
      assign en_slice_bus[gc] = ~frame_done[fa[FR_W-1:0]];
    end
  endgenerate

  // ---------------------------------------------------------------
  // Router: all layers for all (col, row) — combinational
  // ---------------------------------------------------------------
  // Per-(col,row): packed router flags [NL-1:0]
  wire [Z*NL-1:0] col_active_flat  [0:NUM_COLS-1];
  wire [Z*NL-1:0] col_inactive_flat [0:NUM_COLS-1];
  // Per-(col,row,layer): destination row
  wire [TR_W-1:0] col_to_row [0:NUM_COLS-1][0:Z-1][0:NL-1];

  genvar gr;
  generate
    for (gc = 0; gc < NUM_COLS; gc = gc + 1) begin : gen_rcol
      for (gr = 0; gr < Z; gr = gr + 1) begin : gen_rrow
        wire [TR_W-1:0] r_to_row   [0:NUM_LAYERS-1];
        wire             r_active   [0:NUM_LAYERS-1];
        wire             r_inactive [0:NUM_LAYERS-1];

        wire [NUM_LAYERS*TR_W-1:0] r_to_row_f;
        wire [NUM_LAYERS-1:0]      r_active_f;
        wire [NUM_LAYERS-1:0]      r_inactive_f;

        router #(
          .NUM_COLS(NUM_COLS), .Z(Z), .NUM_LAYERS(NUM_LAYERS)
        ) rtr (
          .rate_select(rate_select),
          .from_col(gc[COL_W-1:0]),
          .from_row(gr[TR_W-1:0]),
          .to_row_flat(r_to_row_f),
          .active_flat(r_active_f),
          .inactive_flat(r_inactive_f)
        );

        // Unpack for indexing
        for (genvar ll = 0; ll < NUM_LAYERS; ll = ll + 1) begin : unpack_r
          assign r_to_row[ll]   = r_to_row_f[ll*TR_W +: TR_W];
          assign r_active[ll]   = r_active_f[ll];
          assign r_inactive[ll] = r_inactive_f[ll];
        end

        // Pack first NL layers
        for (genvar ll = 0; ll < NL; ll = ll + 1) begin : pack_f
          assign col_active_flat[gc][gr*NL + ll]  = r_active[ll];
          assign col_inactive_flat[gc][gr*NL + ll] = r_inactive[ll];
          assign col_to_row[gc][gr][ll] = r_to_row[ll];
        end
      end
    end
  endgenerate

  // ---------------------------------------------------------------
  // Column slices with clock gating
  // ---------------------------------------------------------------
  wire [COL_BUS_W-1:0] layer_bus_out [0:NUM_COLS-1];
  wire [COL_BUS_W-1:0] layer_bus_in  [0:NUM_COLS-1];
  wire [Z-1:0]         parity_from_col [0:NUM_COLS-1];

  generate
    for (gc = 0; gc < NUM_COLS; gc = gc + 1) begin : gen_cols
      wire gated_clk;
      clock_gate_stub cg_inst (
        .clk_in(clk), .enable(en_slice_bus[gc]), .clk_out(gated_clk)
      );

      column_slice #(
        .COL_ID(gc), .Z_L(Z), .N_LAYERS(NL),
        .QV_W_L(QV_W), .LVC_W_L(LVC_W), .LVC_MAG_L(LVC_MAG),
        .MSG_W_L(MW), .NUM_QV_FR(NUM_QV_FRAMES), .NUM_LVC_FR(NUM_LVC_FRAMES),
        .REGISTERED(gc % 2)
      ) cs (
        .clk(gated_clk), .rst_n(rst_n), .phase_cn(phase_cn),
        .faddr_read(faddr_bus_raw[gc*4 +: 4]),
        .en_slice(en_slice_bus[gc]),
        .in_layer_bus(layer_bus_in[gc]),
        .out_layer_bus(layer_bus_out[gc]),
        .router_active_flat(col_active_flat[gc]),
        .router_inactive_flat(col_inactive_flat[gc]),
        .parity_bits_out(parity_from_col[gc])
      );
    end
  endgenerate

  // ---------------------------------------------------------------
  // Inter-column routing via always_comb with logic array
  // ---------------------------------------------------------------
  logic [COL_BUS_W-1:0] layer_bus_in_logic [0:NUM_COLS-1];

  generate
    for (gc = 0; gc < NUM_COLS; gc = gc + 1) begin : gen_connect
      assign layer_bus_in[gc] = layer_bus_in_logic[gc];
    end
  endgenerate

  integer ir, jr, lr;
  always_comb begin
    for (ir = 0; ir < NUM_COLS; ir = ir + 1)
      layer_bus_in_logic[ir] = '0;

    for (ir = 0; ir < NUM_COLS; ir = ir + 1) begin
      integer next_col;
      next_col = (ir + 1) % NUM_COLS;
      for (jr = 0; jr < Z; jr = jr + 1) begin
        for (lr = 0; lr < NL; lr = lr + 1) begin
          integer src_bit;
          src_bit = (jr * NL + lr) * MW;
          if (col_inactive_flat[ir][jr*NL + lr]) begin
            // inactive: already zero
          end else if (!col_active_flat[ir][jr*NL + lr]) begin
            // bypass: same row
            layer_bus_in_logic[next_col][src_bit +: MW] = layer_bus_out[ir][src_bit +: MW];
          end else begin
            // active: use to_row
            integer d_row, dst_bit;
            d_row   = col_to_row[ir][jr][lr];
            dst_bit = (d_row * NL + lr) * MW;
            layer_bus_in_logic[next_col][dst_bit +: MW] = layer_bus_out[ir][src_bit +: MW];
          end
        end
      end
    end
  end

  // ---------------------------------------------------------------
  // Parity checker: Connected to the LAST column (15) to detect completion
  // ---------------------------------------------------------------
  localparam int CHECK_COL = 15;
  parity_checker #(.NUM_COLS(NUM_COLS), .Z(Z), .NUM_FRAMES(NUM_FRAMES)) pchk (
    .clk(clk), .rst_n(rst_n),
    .parity_in(parity_from_col[CHECK_COL]),
    .frame_id(faddr_bus_raw[CHECK_COL*4 +: FR_W]),
    .check_now(check_now),
    .frame_done(frame_done)
  );

  // done_all is only valid when start is active and we have either 
  // converged on all frames or reached the iteration limit.
  assign done_all = start && (iter_done || (frame_done == {NUM_FRAMES{1'b1}}));

endmodule