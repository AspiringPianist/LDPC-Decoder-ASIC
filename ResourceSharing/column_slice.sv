// column_slice.sv
// Multi-layer column slice using flat packed buses (icarus compatible).
`timescale 1ns/1ps
import defs_pkg::*;

module column_slice #(
  parameter int COL_ID     = 0,
  parameter int Z_L        = Z,
  parameter int N_LAYERS   = MAX_LAYERS_PER_COL,
  parameter int QV_W_L     = QV_W,
  parameter int LVC_W_L    = LVC_W,
  parameter int LVC_MAG_L  = LVC_MAG,
  parameter int MSG_W_L    = MSG_W,
  parameter int NUM_QV_FR  = NUM_QV_FRAMES,
  parameter int NUM_LVC_FR = NUM_LVC_FRAMES,
  parameter int REGISTERED = 1
)(
  input  logic clk,
  input  logic rst_n,
  input  logic phase_cn,
  input  logic [3:0] faddr_read,
  input  logic en_slice,

  // Flat bus: Z rows × N_LAYERS layers × MSG_W bits
  input  logic [Z_L*N_LAYERS*MSG_W_L-1:0] in_layer_bus,
  output logic [Z_L*N_LAYERS*MSG_W_L-1:0] out_layer_bus,

  // Per-row router flags (packed: N_LAYERS bits per row, Z rows)
  input  logic [Z_L*N_LAYERS-1:0] router_active_flat,
  input  logic [Z_L*N_LAYERS-1:0] router_inactive_flat,

  output logic [Z_L-1:0] parity_bits_out
);

  localparam int PE_MSG_BUS_W = N_LAYERS * MSG_W_L;
  localparam int PE_LVC_BUS_W = N_LAYERS * LVC_W_L;
  localparam int LVC_ADDR_W   = $clog2(NUM_LVC_FR);
  localparam int QV_ADDR_W    = $clog2(NUM_QV_FR);

  genvar r, lay;
  generate
    for (r = 0; r < Z_L; r = r + 1) begin : gen_row

      // ---- QV memory bank (one per row, shared across layers) ----
      wire [QV_W_L-1:0] qv_rdata;
      wire               qv_we;
      wire [QV_W_L-1:0]  qv_wd;
      esram_bram_sim #(.DEPTH(NUM_QV_FR), .DATA_W(QV_W_L)) qv_bank (
        .clk(clk), .ren(1'b1),
        .raddr(faddr_read[QV_ADDR_W-1:0]),
        .rdata(qv_rdata),
        .wen(qv_we),
        .waddr(faddr_read[QV_ADDR_W-1:0]),
        .wdata(qv_wd)
      );

      // ---- Per-layer LVC memory banks ----
      wire [PE_LVC_BUS_W-1:0] lvc_rdata_bus; // flat: layer0 in LSBs
      wire [PE_LVC_BUS_W-1:0] pe_lvc_wdata_bus;
      wire [N_LAYERS-1:0]     pe_lvc_wen;

      for (lay = 0; lay < N_LAYERS; lay = lay + 1) begin : gen_lvc
        wire [LVC_W_L-1:0] lvc_rd;
        wire [LVC_W_L-1:0] lvc_wdata_single = pe_lvc_wdata_bus[lay*LVC_W_L +: LVC_W_L];
        wire                lvc_we_single    = pe_lvc_wen[lay] & en_slice;

        esram_bram_sim #(.DEPTH(NUM_LVC_FR), .DATA_W(LVC_W_L)) lvc_bank (
          .clk(clk), .ren(1'b1),
          .raddr(faddr_read[LVC_ADDR_W-1:0]),
          .rdata(lvc_rd),
          .wen(lvc_we_single),
          .waddr(faddr_read[LVC_ADDR_W-1:0]),
          .wdata(lvc_wdata_single)
        );
        assign lvc_rdata_bus[lay*LVC_W_L +: LVC_W_L] = lvc_rd;
      end

      // ---- Extract this row's message slice from flat bus ----
      wire [PE_MSG_BUS_W-1:0] row_msg_in = in_layer_bus[r*PE_MSG_BUS_W +: PE_MSG_BUS_W];
      wire [N_LAYERS-1:0] row_active     = router_active_flat[r*N_LAYERS +: N_LAYERS];
      wire [N_LAYERS-1:0] row_inactive   = router_inactive_flat[r*N_LAYERS +: N_LAYERS];

      // ---- PE instance ----
      wire [PE_MSG_BUS_W-1:0] pe_msg_out_bus;
      wire                    pe_qv_wen;
      wire [QV_W_L-1:0]      pe_qv_wdata;
      wire                    pe_c_hat;

      pe #(
        .N_LAYERS(N_LAYERS), .QV_W_p(QV_W_L), .LVC_MAG_p(LVC_MAG_L),
        .LVC_W_p(LVC_W_L), .MIN_W_p(MIN_W), .OFFSET_BETA_p(OFFSET_BETA),
        .MSG_W_p(MSG_W_L), .REGISTERED(REGISTERED)
      ) pe_inst (
        .clk(clk), .rst_n(rst_n),
        .phase_cn(phase_cn), .en(en_slice),
        .layer_active(row_active),
        .msg_in_flat(row_msg_in),
        .lvc_in_flat(lvc_rdata_bus),
        .qv_in(qv_rdata),
        .msg_out_flat(pe_msg_out_bus),
        .lvc_wdata_flat(pe_lvc_wdata_bus),
        .lvc_wen(pe_lvc_wen),
        .qv_wdata(pe_qv_wdata),
        .qv_wen(pe_qv_wen),
        .c_hat_out(pe_c_hat)
      );

      assign qv_we = pe_qv_wen & en_slice;
      assign qv_wd = pe_qv_wdata;
      assign parity_bits_out[r] = pe_c_hat;

      // ---- Per-layer output muxing: active/bypass/inactive ----
      for (lay = 0; lay < N_LAYERS; lay = lay + 1) begin : gen_out_mux
        wire [MSG_W_L-1:0] pe_out_this = pe_msg_out_bus[lay*MSG_W_L +: MSG_W_L];
        wire [MSG_W_L-1:0] in_this     = row_msg_in[lay*MSG_W_L +: MSG_W_L];
        wire is_inactive = row_inactive[lay];
        wire is_active   = row_active[lay];

        localparam int OUT_BASE = (r*N_LAYERS + lay) * MSG_W_L;
        assign out_layer_bus[OUT_BASE +: MSG_W_L] =
          is_inactive ? {MSG_W_L{1'b0}} :
          is_active   ? pe_out_this     : in_this; // bypass if neither
      end

    end // gen_row
  endgenerate

endmodule