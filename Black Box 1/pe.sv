// pe.v
// Single PE implementing piecewise time-distributed CN + VN update for one row of a column.
// Implements OFFSET_BETA, saturating arithmetic, bypass support.
`include "defs.v"
module pe #(
  parameter integer QV_W = 5,
  parameter integer LVC_MAG = 4,
  parameter integer LVC_W = 1 + LVC_MAG,
  parameter integer MIN_W = LVC_MAG,
  parameter integer OFFSET_BETA = 1
)(
  input  wire                    clk,
  input  wire                    rst_n,
  // control
  input  wire                    active,     // active edge (non-zero subblock)
  input  wire                    do_cycle,   // scheduled this cycle (controller)
  input  wire                    phase_cn,   // 1 => CN phase (accumulate), 0 => VN phase (update)
  // inbound layer message (from previous column)
  input  wire                    in_pc,
  input  wire                    in_sc,
  input  wire [MIN_W-1:0]        in_min1,
  input  wire [MIN_W-1:0]        in_min2,
  // stored local messages (read ports)
  input  wire [LVC_W-1:0]        stored_lvc_sm, // sign-magnitude format [sign|mag]
  input  wire signed [QV_W-1:0]  stored_qv,
  // outputs to next column (layer message)
  output reg                     out_pc,
  output reg                     out_sc,
  output reg [MIN_W-1:0]         out_min1,
  output reg [MIN_W-1:0]         out_min2,
  // memory writebacks
  output reg [LVC_W-1:0]         lvc_wdata,
  output reg                     lvc_wen,
  output reg signed [QV_W-1:0]   qv_wdata,
  output reg                     qv_wen,
  // hard-decision bit
  output reg                     c_hat_out
);

  // Unpack stored Lvc
  wire lvc_sign = stored_lvc_sm[LVC_MAG];
  wire [LVC_MAG-1:0] lvc_mag = stored_lvc_sm[LVC_MAG-1:0];

  // CN accumulation combinational (applies when active && do_cycle && phase_cn)
  wire sc_after = in_sc ^ lvc_sign;
  wire [MIN_W-1:0] new_min1;
  wire [MIN_W-1:0] new_min2;
  assign {new_min1, new_min2} =
    (lvc_mag <= in_min1) ? {lvc_mag, in_min1} :
    (lvc_mag <  in_min2) ? {in_min1, lvc_mag} :
                           {in_min1, in_min2};

  // MCV selection (for VN update) with OFFSET_BETA and sign selection
  wire [MIN_W-1:0] chosen_mag = (lvc_mag == in_min1) ? in_min2 : in_min1;
  wire [MIN_W-1:0] chosen_mag_off = (chosen_mag > OFFSET_BETA) ? (chosen_mag - OFFSET_BETA) : {MIN_W{1'b0}};
  wire chosen_sign = sc_after; // as discussed in the paper (sc XOR sgn(Lvc) done earlier)

  // Represent mcv as signed integer with width MIN_W+1
  wire signed [MIN_W:0] mcv_signed = chosen_sign ? -$signed({1'b0, chosen_mag_off}) : $signed({1'b0, chosen_mag_off});

  // Saturation helpers
  localparam signed [QV_W-1:0] QV_MAX = (1 << (QV_W-1)) - 1;
  localparam signed [QV_W-1:0] QV_MIN = - (1 << (QV_W-1));

  // Compute LV and LVC_new during VN phase (combinational)
  wire signed [QV_W+MIN_W:0] lv_tmp = $signed(stored_qv) + $signed(mcv_signed);
  reg signed [QV_W-1:0] lv_clamped;
  always @(*) begin
    if (lv_tmp > QV_MAX) lv_clamped = QV_MAX;
    else if (lv_tmp < QV_MIN) lv_clamped = QV_MIN;
    else lv_clamped = lv_tmp[QV_W-1:0];
  end

  wire c_hat = lv_clamped[QV_W-1]; // MSB = sign

  // lvc_new = lv_clamped - mcv_signed
  wire signed [QV_W+MIN_W:0] lvc_tmp = $signed(lv_clamped) - $signed(mcv_signed);

  // Convert lvc_tmp to sign-magnitude and clamp to LVC_MAG
  reg [LVC_W-1:0] lvc_next_sm;
  always @(*) begin
    integer imax = (1<<LVC_MAG) - 1;
    reg [QV_W+MIN_W:0] abs_val;
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

  // Registered outputs & write enable logic
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      out_pc <= 1'b0;
      out_sc <= 1'b0;
      out_min1 <= {MIN_W{1'b1}};
      out_min2 <= {MIN_W{1'b1}};
      lvc_wdata <= 0; lvc_wen <= 1'b0;
      qv_wdata <= 0; qv_wen <= 1'b0;
      c_hat_out <= 1'b0;
    end else begin
      // Default: hold enables low
      lvc_wen <= 1'b0;
      qv_wen <= 1'b0;

      if (do_cycle) begin
        // When scheduled this cycle, behave according to active & current phase:
        if (active) begin
          // Apply CN accumulation in CN phase (we still compute new layer message)
          out_pc <= in_pc;
          out_sc <= sc_after;
          out_min1 <= new_min1;
          out_min2 <= new_min2;
          if (!phase_cn) begin
            // VN phase: write LVC and QV and output c_hat
            lvc_wdata <= lvc_next_sm;
            lvc_wen <= 1'b1;
            qv_wdata <= lv_clamped;
            qv_wen <= 1'b1;
            c_hat_out <= c_hat;
          end
        end else begin
          // Bypass routing: forward layer message unchanged, avoid writes
          out_pc <= in_pc;
          out_sc <= in_sc;
          out_min1 <= in_min1;
          out_min2 <= in_min2;
          // compute c_hat from stored_qv but DO NOT write memories
          c_hat_out <= c_hat;
        end
      end
    end
  end
endmodule