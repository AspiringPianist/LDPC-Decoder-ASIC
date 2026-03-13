// column_slice.sv
`timescale 1ns/1ps
import defs_pkg::*;
module column_slice #(
  parameter int COL_ID = 0,
  parameter int Z_local = Z,
  parameter int QV_W_local = QV_W,
  parameter int LVC_MAG_local = LVC_MAG,
  parameter int LVC_W_local = LVC_W,
  parameter int NUM_QV_FRAMES_local = NUM_QV_FRAMES,
  parameter int NUM_LVC_FRAMES_local = NUM_LVC_FRAMES
)(
  input  logic clk,
  input  logic rst_n,
  input  logic [$clog2(NUM_LAYERS*2)-1:0] cycle_idx, // 0..(2*NUM_LAYERS-1)
  input  logic [3:0] faddr_read, // frame pointer for this slice (0..NUM_FRAMES-1)
  input  logic en_slice,
  input  logic [Z_local*MSG_W-1:0] in_layer_bus,  // input from previous column (flattened)
  output logic [Z_local*MSG_W-1:0] out_layer_bus, // output to next column (flattened)
  input  logic [Z_local-1:0] router_active_vec,   // per-row active flags from router (1=active)
  input  logic [Z_local-1:0] router_inactive_vec, // per-row inactive flags from router (1=inactive wired)
  output logic [Z_local-1:0] parity_bits_out      // per-row hard decisions (for parity check)
);

  // derive phase: CN when cycle_idx < NUM_LAYERS
  logic phase_cn_local;
  assign phase_cn_local = (cycle_idx < NUM_LAYERS) ? 1'b1 : 1'b0;
  logic [$clog2(NUM_LAYERS)-1:0] layer_id;
  assign layer_id = phase_cn_local ? cycle_idx[$clog2(NUM_LAYERS)-1:0] : (cycle_idx - NUM_LAYERS)[$clog2(NUM_LAYERS)-1:0];

  // Per-row banked memories: QV depth = NUM_QV_FRAMES (16), LVC depth = NUM_LVC_FRAMES (8)
  // NOTE: faddr_read is currently shared address for both banks. Per paper architecture,
  // QV and LVC use different frame indices. This simplified version uses same faddr for both;
  // a full implementation would provide separate address buses (faddr_qv and faddr_lvc).
  logic [QV_W_local-1:0] qv_rdata_row [0:Z_local-1];
  logic [LVC_W_local-1:0] lvc_rdata_row [0:Z_local-1];
  logic qv_wen_row  [0:Z_local-1];
  logic lvc_wen_row [0:Z_local-1];
  logic [QV_W_local-1:0] qv_wdata_row [0:Z_local-1];
  logic [LVC_W_local-1:0] lvc_wdata_row [0:Z_local-1];

  genvar r;
  generate
    for (r = 0; r < Z_local; r = r + 1) begin : per_row_bank
      // instantiate QV memory bank with depth = NUM_QV_FRAMES
      esram_bram_sim #(.DEPTH(NUM_QV_FRAMES_local), .DATA_W(QV_W_local)) qv_bank (
        .clk(clk),
        .ren(1'b1),                 // always enabled read; rdata will reflect raddr which is frame index
        .raddr(faddr_read),
        .rdata(qv_rdata_row[r]),
        .wen(qv_wen_row[r]),
        .waddr(faddr_read),
        .wdata(qv_wdata_row[r])
      );

      // instantiate LVC memory bank with depth = NUM_LVC_FRAMES
      esram_bram_sim #(.DEPTH(NUM_LVC_FRAMES_local), .DATA_W(LVC_W_local)) lvc_bank (
        .clk(clk),
        .ren(1'b1),
        .raddr(faddr_read),
        .rdata(lvc_rdata_row[r]),
        .wen(lvc_wen_row[r]),
        .waddr(faddr_read),
        .wdata(lvc_wdata_row[r])
      );
    end
  endgenerate

  // Unpack inbound layer bus into per-row messages
  logic [MSG_W-1:0] in_msg [0:Z_local-1];
  logic [MSG_W-1:0] out_msg [0:Z_local-1];

  generate
    for (r = 0; r < Z_local; r = r + 1) begin : unpack_in
      assign in_msg[r] = in_layer_bus[r*MSG_W +: MSG_W];
    end
  endgenerate

  // Instantiate PEs and wire them to bank rdata / write strobes
  generate
    for (r = 0; r < Z_local; r = r + 1) begin : gen_pe
      // local wires for PE write control
      logic pe_lvc_we; logic [LVC_W_local-1:0] pe_lvc_wdata;
      logic pe_qv_we;  logic [QV_W_local-1:0]  pe_qv_wdata;
      logic [MSG_W-1:0] pe_msg_out;
      logic pe_parity_out;

      // Determine mode for this row from router flags
      logic is_active = router_active_vec[r];
      logic is_inactive = router_inactive_vec[r];
      logic do_bypass = (!is_active && !is_inactive); // -1 means bypass (all-zero submatrix)
      // NOTE: in the paper, bypass means forward same-row message; inactive means layer absent (no routing).

      // instantiate PE
      logic en_pe;
      assign en_pe = en_slice && is_active;  // only enable PE when slice enabled and router says row is active
      
      pe pe_inst (
        .clk(clk),
        .rst_n(rst_n),
        .phase_cn(phase_cn_local),
        .layer_id(layer_id),
        .en(en_pe),
        .msg_in(in_msg[r]),
        .lvc_in(lvc_rdata_row[r]),
        .qv_in(qv_rdata_row[r]),
        .msg_out(pe_msg_out),
        .lvc_wdata(pe_lvc_wdata),
        .lvc_wen(pe_lvc_we),
        .qv_wdata(pe_qv_wdata),
        .qv_wen(pe_qv_we),
        .c_hat_out(pe_parity_out)
      );

      // Decide final msg_out depending on bypass / inactive / active
      always_comb begin
        if (is_inactive) begin
          // inactive wired layer: no routing / no message produced for this layer
          out_msg[r] = {MSG_W{1'b0}};
        end else if (do_bypass) begin
          // bypass (all-zero submatrix): forward same-row message to next column unchanged
          out_msg[r] = in_msg[r];
        end else begin
          // active: use PE computed outgoing message
          out_msg[r] = pe_msg_out;
        end
      end

      // Connect parity output
      assign parity_bits_out[r] = pe_parity_out;

      // Hook PE write strobes to per-row bank write ports (do writes only when slice enabled and during VN update)
      // Only perform writes when slice is enabled and we are in VN pass (PE produced updates).
      always_comb begin
        if (en_slice && (!phase_cn_local)) begin
          // VN pass: forward writes from PE to row banks
          qv_wen_row[r]  = pe_qv_we;
          qv_wdata_row[r]= pe_qv_wdata;
          lvc_wen_row[r] = pe_lvc_we;
          lvc_wdata_row[r]= pe_lvc_wdata;
        end else begin
          qv_wen_row[r]  = 1'b0;
          lvc_wen_row[r] = 1'b0;
          qv_wdata_row[r] = '0;
          lvc_wdata_row[r] = '0;
        end
      end

    end
  endgenerate

  // Pack out_layer_bus from out_msg array; note routing in top-level may shift rows
  generate
    for (r = 0; r < Z_local; r = r + 1) begin : pack_out
      assign out_layer_bus[r*MSG_W +: MSG_W] = out_msg[r];
    end
  endgenerate

endmodule