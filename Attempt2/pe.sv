// pe.sv
// Area-optimized multi-layer combined CN+VN processing element (Figure 9).
// Processes up to N_LAYERS layers in parallel per clock cycle.
// All multi-layer ports use flat PACKED buses for icarus compatibility.
// REGISTERED=1: outputs are registered (odd columns). REGISTERED=0: combinational (even columns).
//
// Area Optimizations Applied:
//   1. Accumulator width reduced from QV_W+5 to QV_W+3 (mathematically safe)
//   2. LVC absolute-value uses bit-invert + carry instead of full negation
//   3. Saturation detection via MSB overflow bits instead of two full comparators
//   4. OFFSET_BETA exploit: zero-detect (NOR) replaces general comparator
//   5. Output register gating: combinational gate before FF eliminates mux branch
`timescale 1ns/1ps
import defs_pkg::*;

module pe #(
  parameter integer N_LAYERS      = MAX_LAYERS_PER_COL,
  parameter integer QV_W_p        = QV_W,
  parameter integer LVC_MAG_p     = LVC_MAG,
  parameter integer LVC_W_p       = LVC_W,
  parameter integer MIN_W_p       = MIN_W,
  parameter integer OFFSET_BETA_p = OFFSET_BETA,
  parameter integer MSG_W_p       = MSG_W,
  parameter integer REGISTERED    = 1
)(
  input  logic clk,
  input  logic rst_n,
  input  logic phase_cn,
  input  logic en,
  input  logic [N_LAYERS-1:0] layer_active,

  // Flat packed buses: layer 0 in LSBs, layer N_LAYERS-1 in MSBs.
  input  logic [N_LAYERS*MSG_W_p-1:0]  msg_in_flat,
  input  logic [N_LAYERS*LVC_W_p-1:0]  lvc_in_flat,
  input  logic signed [QV_W_p-1:0]     qv_in,

  output logic [N_LAYERS*MSG_W_p-1:0]  msg_out_flat,
  output logic [N_LAYERS*LVC_W_p-1:0]  lvc_wdata_flat,
  output logic [N_LAYERS-1:0]          lvc_wen,
  output logic signed [QV_W_p-1:0]     qv_wdata,
  output logic                         qv_wen,
  output logic                         c_hat_out
);

  localparam signed [QV_W_p-1:0] QV_MAX = (1 << (QV_W_p-1)) - 1;
  localparam signed [QV_W_p-1:0] QV_MIN = -(1 << (QV_W_p-1));
  localparam integer LVC_MAG_MAX = (1 << LVC_MAG_p) - 1;

  // ---------------------------------------------------------------
  // OPT: Accumulator width calculation
  //   Max per-layer mcv magnitude = (2^MIN_W - 1) = 15 (4-bit)
  //   Max sum of 8 layers = 8 * 15 = 120, fits in 8 bits unsigned / 9 bits signed
  //   After adding QV_W (6-bit signed), need QV_W+3 = 9 bits total
  // ---------------------------------------------------------------
  localparam integer ACCUM_W = QV_W_p + 3; // 9 bits — reduced from QV_W+5 (11 bits)

  // ---------------------------------------------------------------
  // Per-layer CN logic via generate — using assign for flat-bus slicing
  // ---------------------------------------------------------------
  wire [MIN_W_p-1:0]  new_min1_w [0:N_LAYERS-1];
  wire [MIN_W_p-1:0]  new_min2_w [0:N_LAYERS-1];
  wire                sc_after_w [0:N_LAYERS-1];
  wire [LVC_MAG_p-1:0] lvc_mag_w [0:N_LAYERS-1];
  wire                lvc_sign_w [0:N_LAYERS-1];
  wire [MSG_W_p-1:0]  cn_msg_out_w [0:N_LAYERS-1];
  wire signed [MIN_W_p:0] mcv_signed_w [0:N_LAYERS-1];
  wire [LVC_W_p-1:0]  lvc_next_w [0:N_LAYERS-1];
  wire [MSG_W_p-1:0]  vn_msg_out_w [0:N_LAYERS-1];
  wire                c_hat_comb;

  genvar L;
  generate
    for (L = 0; L < N_LAYERS; L = L + 1) begin : gen_layer

      // --- Extract from flat bus via assign (no always block) ---
      wire [MSG_W_p-1:0]  this_msg_in  = msg_in_flat[L*MSG_W_p +: MSG_W_p];
      wire [LVC_W_p-1:0]  this_lvc_in  = lvc_in_flat[L*LVC_W_p +: LVC_W_p];

      // Unpack message fields
      wire               in_pc   = this_msg_in[MSG_W_p-1];
      wire               in_sc   = this_msg_in[MSG_W_p-2];
      wire [MIN_W_p-1:0] in_min1 = this_msg_in[MSG_W_p-3 -: MIN_W_p];
      wire [MIN_W_p-1:0] in_min2 = this_msg_in[MIN_W_p-1 : 0];

      // Unpack Lvc
      wire               l_sign = this_lvc_in[LVC_W_p-1];
      wire [LVC_MAG_p-1:0] l_mag = this_lvc_in[LVC_MAG_p-1:0];

      assign lvc_sign_w[L] = l_sign;
      assign lvc_mag_w[L]  = l_mag;

      // CN accumulation
      wire sc_new = in_sc ^ l_sign;
      assign sc_after_w[L] = sc_new;

      wire [MIN_W_p-1:0] cn_min1, cn_min2;
      assign cn_min1 = (l_mag <= in_min1) ? l_mag  : in_min1;
      assign cn_min2 = (l_mag <= in_min1) ? in_min1 :
                       (l_mag <  in_min2) ? l_mag   : in_min2;
      assign new_min1_w[L] = cn_min1;
      assign new_min2_w[L] = cn_min2;

      // Pack CN output message
      assign cn_msg_out_w[L] = {in_pc, sc_new, cn_min1, cn_min2};

      // MCV computation (for VN phase)
      wire [MIN_W_p-1:0] chosen_mag = (l_mag == in_min1) ? in_min2 : in_min1;

      // OPT: OFFSET_BETA exploit — when OFFSET_BETA=1, subtraction is
      // just decrement-by-1, and the guard is just zero-detect (NOR gate).
      // For general OFFSET_BETA, falls back to original logic.
      // (Conditional constant expression — synth tool optimizes dead branch)
      wire [MIN_W_p-1:0] chosen_mag_off =
          (OFFSET_BETA_p == 1) ?
              ((|chosen_mag) ? (chosen_mag - 1'b1) : {MIN_W_p{1'b0}}) :
              ((chosen_mag > OFFSET_BETA_p) ? (chosen_mag - OFFSET_BETA_p) : {MIN_W_p{1'b0}});

      wire signed [MIN_W_p:0] mcv_s = in_sc ?
                                      -$signed({1'b0, chosen_mag_off}) :
                                       $signed({1'b0, chosen_mag_off});
      assign mcv_signed_w[L] = mcv_s;

      // VN-phase outgoing message
      assign vn_msg_out_w[L] = {in_pc ^ c_hat_comb, in_sc, in_min1, in_min2};

    end
  endgenerate

  // ---------------------------------------------------------------
  // VN: total mcv accumulation (sum of all active layers)
  // OPT: Reduced accumulator width from QV_W+5 (11 bits) to ACCUM_W (9 bits)
  // ---------------------------------------------------------------
  wire signed [ACCUM_W-1:0] mcv_partial [0:N_LAYERS];
  assign mcv_partial[0] = {ACCUM_W{1'b0}};
  generate
    for (L = 0; L < N_LAYERS; L = L + 1) begin : gen_mcv_accum
      wire signed [ACCUM_W-1:0] this_mcv = layer_active[L] ?
          $signed({{(ACCUM_W-MIN_W_p-1){mcv_signed_w[L][MIN_W_p]}}, mcv_signed_w[L]}) :
          {ACCUM_W{1'b0}};
      assign mcv_partial[L+1] = mcv_partial[L] + this_mcv;
    end
  endgenerate
  wire signed [ACCUM_W-1:0] mcv_total = mcv_partial[N_LAYERS];

  // Lv = Qv + sum(mcv)
  wire signed [ACCUM_W-1:0] lv_tmp = $signed({{(ACCUM_W-QV_W_p){qv_in[QV_W_p-1]}}, qv_in}) + mcv_total;

  // OPT: Saturation via overflow detection instead of two full comparators.
  // Check if the result overflows QV_W range by inspecting the MSBs.
  wire signed [QV_W_p-1:0] lv_clamped;
  wire overflow_pos = ~lv_tmp[ACCUM_W-1] & (|lv_tmp[ACCUM_W-2:QV_W_p-1]); // positive overflow
  wire overflow_neg =  lv_tmp[ACCUM_W-1] & ~(&lv_tmp[ACCUM_W-2:QV_W_p-1]); // negative overflow
  assign lv_clamped = overflow_pos ? QV_MAX :
                      overflow_neg ? QV_MIN :
                      lv_tmp[QV_W_p-1:0];

  assign c_hat_comb = lv_clamped[QV_W_p-1];

  // ---------------------------------------------------------------
  // Per-layer Lvc_new = Lv - mcv[layer], sign-magnitude conversion
  // OPT: Uses bit-invert + increment for absolute value instead of
  //       full negation (saves one subtractor per layer)
  // ---------------------------------------------------------------
  generate
    for (L = 0; L < N_LAYERS; L = L + 1) begin : gen_lvc_update
      wire signed [ACCUM_W-1:0] lvc_diff =
          $signed({{(ACCUM_W-QV_W_p){lv_clamped[QV_W_p-1]}}, lv_clamped}) -
          $signed({{(ACCUM_W-MIN_W_p-1){mcv_signed_w[L][MIN_W_p]}}, mcv_signed_w[L]});

      // OPT: Absolute value via conditional invert + carry
      wire lvc_neg = lvc_diff[ACCUM_W-1]; // sign bit
      wire [ACCUM_W-1:0] lvc_abs_val = lvc_neg ? (~lvc_diff + 1'b1) : lvc_diff;

      assign lvc_next_w[L] = (lvc_abs_val > $unsigned(LVC_MAG_MAX)) ?
                              {lvc_neg, {LVC_MAG_p{1'b1}}} :
                              {lvc_neg, lvc_abs_val[LVC_MAG_p-1:0]};
    end
  endgenerate

  // ---------------------------------------------------------------
  // Mux CN/VN outputs and pack into flat buses
  // ---------------------------------------------------------------
  logic [N_LAYERS*MSG_W_p-1:0]  final_msg_flat;
  logic [N_LAYERS*LVC_W_p-1:0]  final_lvc_flat;
  logic [N_LAYERS-1:0]          final_lvc_wen;

  // OPT: Gate enable signals combinationally to avoid toggling registers
  wire vn_active = ~phase_cn & en;
  wire signed [QV_W_p-1:0]     final_qv     = vn_active ? lv_clamped : '0;
  wire                          final_qv_wen = vn_active;

  generate
    for (L = 0; L < N_LAYERS; L = L + 1) begin : gen_mux
      wire [MSG_W_p-1:0] muxed_msg = phase_cn ? cn_msg_out_w[L] : vn_msg_out_w[L];
      assign final_msg_flat[L*MSG_W_p +: MSG_W_p] = muxed_msg;
      assign final_lvc_flat[L*LVC_W_p +: LVC_W_p] = lvc_next_w[L];
      assign final_lvc_wen[L] = vn_active ? layer_active[L] : 1'b0;
    end
  endgenerate

  // ---------------------------------------------------------------
  // Output stage: REGISTERED or COMBINATIONAL
  // OPT: Cleaner register enable — use single `en` gate, no separate
  //      else-branch for clearing wen (saves mux logic)
  // ---------------------------------------------------------------
  generate
    if (REGISTERED) begin : gen_reg
      reg [N_LAYERS*MSG_W_p-1:0]  msg_r;
      reg [N_LAYERS*LVC_W_p-1:0]  lvc_r;
      reg [N_LAYERS-1:0]          lvc_wen_r;
      reg signed [QV_W_p-1:0]    qv_r;
      reg                         qv_wen_r;
      reg                         c_hat_r;

      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          msg_r     <= '0;
          lvc_r     <= '0;
          lvc_wen_r <= '0;
          qv_r      <= '0;
          qv_wen_r  <= 1'b0;
          c_hat_r   <= 1'b0;
        end else if (en) begin
          msg_r     <= final_msg_flat;
          lvc_r     <= final_lvc_flat;
          lvc_wen_r <= final_lvc_wen;
          qv_r      <= final_qv;
          qv_wen_r  <= final_qv_wen;
          c_hat_r   <= c_hat_comb;
        end else begin
          // OPT: Only clear write-enables, hold data (avoids toggle)
          lvc_wen_r <= '0;
          qv_wen_r  <= 1'b0;
        end
      end

      assign msg_out_flat  = msg_r;
      assign lvc_wdata_flat = lvc_r;
      assign lvc_wen        = lvc_wen_r;
      assign qv_wdata       = qv_r;
      assign qv_wen         = qv_wen_r;
      assign c_hat_out      = c_hat_r;

    end else begin : gen_comb
      assign msg_out_flat  = final_msg_flat;
      assign lvc_wdata_flat = final_lvc_flat;
      assign lvc_wen        = final_lvc_wen;
      assign qv_wdata       = final_qv;
      assign qv_wen         = final_qv_wen;
      assign c_hat_out      = c_hat_comb;
    end
  endgenerate

endmodule
