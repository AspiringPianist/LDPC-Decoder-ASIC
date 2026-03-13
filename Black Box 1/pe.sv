// pe.sv
// Single PE implementing piecewise time-distributed CN + VN update for one row of a column.
// Implements OFFSET_BETA, saturating arithmetic, bypass support.
`timescale 1ns/1ps
import defs_pkg::*;

module pe #(
  parameter integer QV_W = QV_W,
  parameter integer LVC_MAG = LVC_MAG,
  parameter integer LVC_W = LVC_W,
  parameter integer MIN_W = MIN_W,
  parameter integer OFFSET_BETA = OFFSET_BETA,
  parameter integer MSG_W = MSG_W
)(
  input  logic clk,
  input  logic rst_n,
  // control
  input  logic phase_cn,   // 1 => CN phase, 0 => VN phase
  input  logic [$clog2(NUM_LAYERS)-1:0] layer_id,  // current layer
  input  logic en,         // enable this PE this cycle
  // inbound layer message (packed: [pc|sc|min1|min2])
  input  logic [MSG_W-1:0] msg_in,
  // stored local messages (read ports)
  input  logic [LVC_W-1:0] lvc_in,      // sign-magnitude format [sign|mag]
  input  logic signed [QV_W-1:0] qv_in,
  // outputs to next column (layer message, packed)
  output logic [MSG_W-1:0] msg_out,
  // memory writebacks
  output logic [LVC_W-1:0] lvc_wdata,
  output logic lvc_wen,
  output logic signed [QV_W-1:0] qv_wdata,
  output logic qv_wen,
  // hard-decision bit
  output logic c_hat_out
);

  // Unpack input message
  logic in_pc, in_sc;
  logic [MIN_W-1:0] in_min1, in_min2;
  always_comb begin
    in_pc = msg_in[MSG_W-1];
    in_sc = msg_in[MSG_W-2];
    in_min1 = msg_in[MSG_W-3 -: MIN_W];
    in_min2 = msg_in[MIN_W-1 : 0];
  end

  // Unpack stored Lvc
  logic lvc_sign;
  logic [LVC_MAG-1:0] lvc_mag;
  always_comb begin
    lvc_sign = lvc_in[LVC_W-1];
    lvc_mag = lvc_in[LVC_MAG-1:0];
  end

  // CN accumulation combinational (applies when phase_cn)
  logic sc_after;
  logic [MIN_W-1:0] new_min1, new_min2;
  
  always_comb begin
    sc_after = in_sc ^ lvc_sign;
    if (lvc_mag <= in_min1) begin
      new_min1 = lvc_mag;
      new_min2 = in_min1;
    end else if (lvc_mag < in_min2) begin
      new_min1 = in_min1;
      new_min2 = lvc_mag;
    end else begin
      new_min1 = in_min1;
      new_min2 = in_min2;
    end
  end

  // MCV selection (for VN update) with OFFSET_BETA and sign selection
  logic [MIN_W-1:0] chosen_mag;
  logic [MIN_W-1:0] chosen_mag_off;
  logic chosen_sign;
  
  always_comb begin
    chosen_mag = (lvc_mag == in_min1) ? in_min2 : in_min1;
    chosen_mag_off = (chosen_mag > OFFSET_BETA) ? (chosen_mag - OFFSET_BETA) : {MIN_W{1'b0}};
    chosen_sign = sc_after;
  end

  // Represent mcv as signed integer with width MIN_W+1
  logic signed [MIN_W:0] mcv_signed;
  always_comb begin
    mcv_signed = chosen_sign ? -$signed({1'b0, chosen_mag_off}) : $signed({1'b0, chosen_mag_off});
  end

  // Saturation helpers
  localparam signed [QV_W-1:0] QV_MAX = (1 << (QV_W-1)) - 1;
  localparam signed [QV_W-1:0] QV_MIN = - (1 << (QV_W-1));

  // Compute LV and LVC_new during VN phase (combinational)
  logic signed [QV_W+MIN_W:0] lv_tmp;
  logic signed [QV_W-1:0] lv_clamped;
  logic c_hat;
  
  always_comb begin
    lv_tmp = $signed(qv_in) + $signed(mcv_signed);
    if (lv_tmp > QV_MAX) lv_clamped = QV_MAX;
    else if (lv_tmp < QV_MIN) lv_clamped = QV_MIN;
    else lv_clamped = lv_tmp[QV_W-1:0];
    c_hat = lv_clamped[QV_W-1];
  end

  // lvc_new = lv_clamped - mcv_signed
  logic signed [QV_W+MIN_W:0] lvc_tmp;
  always_comb begin
    lvc_tmp = $signed(lv_clamped) - $signed(mcv_signed);
  end

  // Convert lvc_tmp to sign-magnitude and clamp to LVC_MAG
  logic [LVC_W-1:0] lvc_next_sm;
  always_comb begin
    integer imax = (1<<LVC_MAG) - 1;
    logic [QV_W+MIN_W:0] abs_val;
    if (lvc_tmp < 0) begin
      abs_val = -lvc_tmp;
      if (abs_val > imax) lvc_next_sm = {1'b1, imax[LVC_MAG-1:0]};
      else lvc_next_sm = {1'b1, abs_val[LVC_MAG-1:0]};
    end else begin
      abs_val = lvc_tmp;
      if (abs_val > imax) lvc_next_sm = {1'b0, imax[LVC_MAG-1:0]};
      else lvc_next_sm = {1'b0, abs_val[LVC_MAG-1:0]};
    end
  end

  // Output message registers (will be packed below)
  logic out_pc, out_sc;
  logic [MIN_W-1:0] out_min1, out_min2;

  // Registered outputs & write enable logic
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      out_pc <= 1'b0;
      out_sc <= 1'b0;
      out_min1 <= {MIN_W{1'b1}};
      out_min2 <= {MIN_W{1'b1}};
      lvc_wdata <= 0;
      lvc_wen <= 1'b0;
      qv_wdata <= 0;
      qv_wen <= 1'b0;
      c_hat_out <= 1'b0;
    end else begin
      // Default: hold enables low
      lvc_wen <= 1'b0;
      qv_wen <= 1'b0;

      if (en) begin
        // ALWAYS update output message (goes to next column pipeline)
        // This maintains proper pipelined data flow through columns
        out_pc <= in_pc;
        out_sc <= sc_after;
        out_min1 <= new_min1;
        out_min2 <= new_min2;
        
        // Compute hard decision every cycle
        c_hat_out <= c_hat;
        
        // Memory writes ONLY during VN phase (update stored values)
        if (!phase_cn) begin
          // VN phase: write updated LVC and QV to memory
          lvc_wdata <= lvc_next_sm;
          lvc_wen <= 1'b1;
          qv_wdata <= lv_clamped;
          qv_wen <= 1'b1;
        end
      end else begin
        // Not enabled - hold output values
        c_hat_out <= c_hat;  // compute hard decision regardless
      end
    end
  end

  // Pack output message: [pc|sc|min1|min2]
  always_comb begin
    msg_out[MSG_W-1] = out_pc;
    msg_out[MSG_W-2] = out_sc;
    msg_out[MSG_W-3 -: MIN_W] = out_min1;
    msg_out[MIN_W-1 : 0] = out_min2;
  end

endmodule
