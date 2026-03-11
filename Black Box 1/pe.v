// pe.v
// Single PE for one row (one sub-row of a macrocolumn). Performs CN accumulation and VN update
// for the active frame & row when enabled by controller in that cycle.
// The PE expects to read: incoming layer message (pc, sc, min1, min2) from prev column,
// stored Lvc (sign-magnitude), stored Qv (2's comp). It outputs the next layer message and updated Lvc/Qv.

`include "defs.v"
module pe #(
  parameter integer QV_W = 5,
  parameter integer LVC_MAG = 4,
  parameter integer LVC_W = 1 + LVC_MAG,
  parameter integer MIN_W = LVC_MAG
)(
  input  wire                     clk,
  input  wire                     rst_n,
  // control
  input  wire                     active,     // this edge is active (non-zero submatrix)
  input  wire                     en_cycle,   // global enable (PE is scheduled this cycle for some frame)
  // inbound layer message
  input  wire                     in_pc,
  input  wire                     in_sc,
  input  wire [MIN_W-1:0]         in_min1,
  input  wire [MIN_W-1:0]         in_min2,
  // stored local messages read ports
  input  wire [LVC_W-1:0]         stored_lvc_sm, // sign magnitude
  input  wire signed [QV_W-1:0]   stored_qv,     // Qv
  // outputs (to next column)
  output reg                      out_pc,
  output reg                      out_sc,
  output reg [MIN_W-1:0]          out_min1,
  output reg [MIN_W-1:0]          out_min2,
  // memory writebacks
  output reg [LVC_W-1:0]          lvc_wdata,
  output reg                      lvc_wen,
  output reg signed [QV_W-1:0]    qv_wdata,
  output reg                      qv_wen,
  // parity/hard decision output for global parity check
  output reg                      c_hat_out
);

  // internal unpack
  wire lvc_sign = stored_lvc_sm[LVC_MAG];
  wire [LVC_MAG-1:0] lvc_mag = stored_lvc_sm[LVC_MAG-1:0];

  // internal combinational logic following piecewise Min-Sum rules
  // 1) CN accumulation step: update sign and min1/min2 with local Lvc contribution
  wire new_sc = in_sc ^ lvc_sign;
  wire [MIN_W-1:0] new_min1;
  wire [MIN_W-1:0] new_min2;
  // compare and update
  assign {new_min1, new_min2} =
    (lvc_mag <= in_min1) ? {lvc_mag, in_min1} :
    (lvc_mag <  in_min2) ? {in_min1, lvc_mag} :
                           {in_min1, in_min2};

  // 2) mcv generation - use: use_mag = (lvc_mag==in_min1) ? in_min2 : in_min1; sign = new_sc
  wire [MIN_W-1:0] use_mag = (lvc_mag == in_min1) ? in_min2 : in_min1;
  wire use_sign = new_sc;

  // expand mcv to signed (MIN_W+1) two's complement
  wire signed [MIN_W:0] mcv_signed = use_sign ? -$signed({1'b0, use_mag}) : $signed({1'b0, use_mag});

  // 3) VN update: Lv = Qv + mcv_signed  (paper uses sum across all connected CNs over iterations; here we treat single contribution)
  wire signed [QV_W+MIN_W:0] lv_tmp = $signed(stored_qv) + $signed(mcv_signed);
  // clamp to QV_W
  localparam signed [QV_W-1:0] QV_MAX = (1 << (QV_W-1)) - 1;
  localparam signed [QV_W-1:0] QV_MIN = - (1 << (QV_W-1));
  reg signed [QV_W-1:0] lv_clamped;
  always @(*) begin
    if (lv_tmp > QV_MAX) lv_clamped = QV_MAX;
    else if (lv_tmp < QV_MIN) lv_clamped = QV_MIN;
    else lv_clamped = lv_tmp[QV_W-1:0];
  end

  // compute c_hat (hard decision) from lv_clamped (MSB)
  wire c_hat = lv_clamped[QV_W-1];

  // compute new Lvc to store: lvc_new = lv_clamped - mcv_signed
  wire signed [QV_W+MIN_W:0] lvc_tmp = $signed(lv_clamped) - $signed(mcv_signed);

  // convert lvc_tmp to sign-magnitude clipped to LVC_MAG
  reg [LVC_W-1:0] lvc_next_sm;
  integer imax;
  always @(*) begin
    imax = (1<<LVC_MAG) - 1;
    if (lvc_tmp < 0) begin
      // magnitude clip
      if ((-lvc_tmp) > imax) lvc_next_sm = {1'b1, imax[LVC_MAG-1:0]};
      else lvc_next_sm = {1'b1, (-lvc_tmp)[LVC_MAG-1:0]};
    end else begin
      if (lvc_tmp > imax) lvc_next_sm = {1'b0, imax[LVC_MAG-1:0]};
      else lvc_next_sm = {1'b0, (lvc_tmp)[LVC_MAG-1:0]};
    end
  end

  // Pe behavior per cycle (registered outputs)
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      out_pc <= 0; out_sc <= 0; out_min1 <= {MIN_W{1'b1}}; out_min2 <= {MIN_W{1'b1}};
      lvc_wdata <= 0; lvc_wen <= 1'b0; qv_wdata <= 0; qv_wen <= 1'b0; c_hat_out <= 0;
    end else begin
      // only update when controller schedules this PE this cycle and the edge is active
      if (en_cycle) begin
        if (active) begin
          // CN reduction followed by VN update in one cycle
          out_pc <= in_pc; // piecewise parity propagation (higher-level parity combiner collects final)
          out_sc <= new_sc;
          out_min1 <= new_min1;
          out_min2 <= new_min2;
          // writeback new lvc and qv
          lvc_wdata <= lvc_next_sm;
          lvc_wen <= 1'b1;
          qv_wdata <= lv_clamped;
          qv_wen <= 1'b1;
          c_hat_out <= c_hat;
        end else begin
          // bypass: forward input message unchanged, do not touch local memories
          out_pc <= in_pc;
          out_sc <= in_sc;
          out_min1 <= in_min1;
          out_min2 <= in_min2;
          lvc_wen <= 1'b0;
          qv_wen <= 1'b0;
          c_hat_out <= c_hat; // c_hat computed from stored_qv only
        end
      end else begin
        // not scheduled; outputs idle / retain
        out_pc <= out_pc;
        out_sc <= out_sc;
        out_min1 <= out_min1;
        out_min2 <= out_min2;
        lvc_wen <= 1'b0;
        qv_wen <= 1'b0;
        c_hat_out <= c_hat_out;
      end
    end
  end
endmodule