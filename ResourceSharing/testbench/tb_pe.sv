// tb_pe.sv — Testbench for multi-layer PE
`timescale 1ns/1ps
import defs_pkg::*;

module tb_pe;

  localparam int NL   = MAX_LAYERS_PER_COL;
  localparam int MW   = MSG_W;
  localparam int LW   = LVC_W;
  localparam int QW   = QV_W;
  localparam int MINW = MIN_W;

  logic clk, rst_n;
  logic phase_cn, en;
  logic [NL-1:0] layer_active;
  logic [NL*MW-1:0] msg_in_flat;
  logic [NL*LW-1:0] lvc_in_flat;
  logic signed [QW-1:0] qv_in;

  wire [NL*MW-1:0] msg_out_flat;
  wire [NL*LW-1:0] lvc_wdata_flat;
  wire [NL-1:0] lvc_wen;
  wire signed [QW-1:0] qv_wdata;
  wire qv_wen;
  wire c_hat_out;

  // DUT 1: Combinational outputs (REGISTERED=0)
  pe #(.N_LAYERS(NL), .REGISTERED(0)) dut_comb (
    .clk(clk), .rst_n(rst_n),
    .phase_cn(phase_cn), .en(en),
    .layer_active(layer_active),
    .msg_in_flat(msg_in_flat),
    .lvc_in_flat(lvc_in_flat),
    .qv_in(qv_in),
    .msg_out_flat(msg_out_flat),
    .lvc_wdata_flat(lvc_wdata_flat),
    .lvc_wen(lvc_wen),
    .qv_wdata(qv_wdata),
    .qv_wen(qv_wen),
    .c_hat_out(c_hat_out)
  );

  // DUT 2: Registered outputs (REGISTERED=1)
  wire [NL*MW-1:0] reg_pe_msg_out;
  wire [NL*LW-1:0] reg_pe_lvc_wd;
  wire [NL-1:0] reg_pe_lvc_we;
  wire signed [QW-1:0] reg_pe_qv_wd;
  wire reg_pe_qv_we, reg_pe_chat;

  pe #(.N_LAYERS(NL), .REGISTERED(1)) dut_reg (
    .clk(clk), .rst_n(rst_n),
    .phase_cn(phase_cn), .en(en),
    .layer_active(layer_active),
    .msg_in_flat(msg_in_flat),
    .lvc_in_flat(lvc_in_flat),
    .qv_in(qv_in),
    .msg_out_flat(reg_pe_msg_out),
    .lvc_wdata_flat(reg_pe_lvc_wd),
    .lvc_wen(reg_pe_lvc_we),
    .qv_wdata(reg_pe_qv_wd),
    .qv_wen(reg_pe_qv_we),
    .c_hat_out(reg_pe_chat)
  );

  // Clock generation
  initial clk = 0;
  always #5 clk = ~clk;

  // Helper: pack a layer message
  function [MW-1:0] pack_msg(input logic pc, sc, input logic [MINW-1:0] m1, m2);
    pack_msg = {pc, sc, m1, m2};
  endfunction

  // Helper: pack an LVC value (sign-magnitude)
  function [LW-1:0] pack_lvc(input logic sign, input logic [LVC_MAG-1:0] mag);
    pack_lvc = {sign, mag};
  endfunction

  integer pass_count, fail_count;

  // Extract output msg fields for a given layer
  wire [MW-1:0] out_msg_0 = msg_out_flat[0*MW +: MW];
  wire [MW-1:0] out_msg_1 = msg_out_flat[1*MW +: MW];

  initial begin
    $display("============================================");
    $display("PE Testbench Start");
    $display("============================================");
    pass_count = 0;
    fail_count = 0;

    rst_n = 0; en = 0; phase_cn = 1;
    layer_active = 4'b0000;
    msg_in_flat = '0; lvc_in_flat = '0; qv_in = 0;
    #20;
    rst_n = 1;
    #10;

    // =========================================================
    // TEST 1: CN Phase — single layer active
    //   msg_in: pc=0, sc=0, min1=15, min2=15
    //   lvc_in: sign=0, mag=5
    //   Expected: sc_after = 0^0=0, new_min1=5 (since 5 < 15), new_min2=15
    // =========================================================
    $display("\n--- TEST 1: CN phase, layer 0 active ---");
    phase_cn = 1; en = 1;
    layer_active = 4'b0001;
    msg_in_flat[0*MW +: MW] = pack_msg(0, 0, 4'hF, 4'hF);
    lvc_in_flat[0*LW +: LW] = pack_lvc(0, 4'd5);
    #1;

    if (out_msg_0[MW-2] == 1'b0 && out_msg_0[MW-3 -: MINW] == 4'd5 && out_msg_0[MINW-1:0] == 4'd15) begin
      $display("  PASS: CN Numerical Check 1 - sc=0, min1=5, min2=15");
      pass_count = pass_count + 1;
    end else begin
      $display("  FAIL: CN Numerical Check 1 - got %h", out_msg_0);
      fail_count = fail_count + 1;
    end

    // =========================================================
    // TEST 2: CN Phase — multiple messages, sign flip
    //   msg_in: pc=0, sc=1, min1=3, min2=8
    //   lvc_in: sign=1, mag=2
    //   Expected: sc_after = 1^1=0, new_min1=2, new_min2=3
    // =========================================================
    $display("\n--- TEST 2: CN phase, layer 0 numerical sign flip ---");
    msg_in_flat[0*MW +: MW] = pack_msg(0, 1, 4'd3, 4'd8);
    lvc_in_flat[0*LW +: LW] = pack_lvc(1, 4'd2);
    #1;
    if (out_msg_0[MW-2] == 1'b0 && out_msg_0[MW-3 -: MINW] == 4'd2 && out_msg_0[MINW-1:0] == 4'd3) begin
      $display("  PASS: CN Numerical Check 2 - sc=0, min1=2, min2=3");
      pass_count = pass_count + 1;
    end else begin
      $display("  FAIL: CN Numerical Check 2 - got %h", out_msg_0);
      fail_count = fail_count + 1;
    end

    // =========================================================
    // TEST 3: VN Phase — sum accumulation and Lvc update
    //   qv_in = 10
    //   msg_in (layer 0): sc=0, min1=5, min2=15
    //   lvc_in (layer 0): sign=0, mag=5 (since mag==min1, chosen_mag=min2=15, offset=14)
    //   mcv_0 = +14
    //   Lv = 10 + 14 = 24
    //   Lvc_new = 24 - 14 = 10 => {sign=0, mag=10} (clamped to 15)
    // =========================================================
    $display("\n--- TEST 3: VN phase, numerical check ---");
    phase_cn = 0; en = 1;
    layer_active = 4'b0001;
    msg_in_flat[0*MW +: MW] = pack_msg(0, 0, 4'd5, 4'd15);
    lvc_in_flat[0*LW +: LW] = pack_lvc(0, 4'd5);
    qv_in = 6'sd10;
    #2; // slightly longer delay for evaluation

    $display("  DEBUG: mcv_total=%d, lv_tmp=%d, lv_clamped=%d, final_qv=%d", 
             dut_comb.mcv_total, dut_comb.lv_tmp, dut_comb.lv_clamped, dut_comb.final_qv);

    if (qv_wdata === 6'sd24 && lvc_wdata_flat[0*LW +: LW] === pack_lvc(0, 4'd10)) begin
      $display("  PASS: VN Numerical Check - qv=%0d(0x%h), lvc=%0d(0x%h)", qv_wdata, qv_wdata, lvc_wdata_flat[0*LW +: LW], lvc_wdata_flat[0*LW +: LW]);
      pass_count = pass_count + 1;
    end else begin
      $display("  FAIL: VN Numerical Check - got qv=%0d(0x%h), lvc=%0d(0x%h)", qv_wdata, qv_wdata, lvc_wdata_flat[0*LW +: LW], lvc_wdata_flat[0*LW +: LW]);
      fail_count = fail_count + 1;
    end

    // =========================================================
    // TEST 4: Full Sequence — 3-hop CN accumulation followed by VN update
    //   CN Goal: Process 3 Lvc values: +5, -2, +10
    //   Hop 0: in={pc=1, sc=0, min1=15, min2=15} Lvc=+5  => out={pc=1, sc=0, min1=5, min2=15}
    //   Hop 1: in={pc=1, sc=0, min1=5, min2=15}  Lvc=-2  => out={pc=1, sc=1, min1=2, min2=5}
    //   Hop 2: in={pc=1, sc=1, min1=2, min2=5}   Lvc=+10 => out={pc=1, sc=1, min1=2, min2=5} (Final CN)
    //   VN Phase: 
    //     qv_in = -4
    //     Lvc_0 (+5): mag5==min2? No, mag5==min1? No. wait.
    //     Wait, this is path unrolled. Each PE sees its OWN Lvc.
    //     Let's simulate PE 0 which had Lvc=+5.
    //     Global CN results: sc=1, min1=2, min2=5.
    //     mcv for PE 0: (sc_global ^ sc_local) * min1 = (1 ^ 0) * 2 = -2.
    //     Note: sc_local in VN phase is sc_after_w from CN phase.
    //     Actually, Algorithm says: mcv = (sc_global ^ sgn(Lvc)) * chosen_mag.
    //     Wait, my PE uses in_sc (which is sc_global) and lvc_sign.
    //     mcv = (sc_global ^ lvc_sign) ? -offset_mag : +offset_mag.
    //     For PE 0 (Lvc=+5): sc_global=1, sign=0 => mcv = - (chosen_mag-1).
    //     chosen_mag (mag5 == min1(2))? No => chosen_mag = min1 = 2.
    //     offset_mag = 2-1 = 1.
    //     mcv = -1.
    //     Lv = qv_in + mcv = -4 + (-1) = -5.
    //     c_hat = 1 (negative).
    // =========================================================
    $display("\n--- TEST 4: Multi-hop CN + VN sequence ---");
    // Hop 0
    phase_cn = 1; layer_active = 4'b0001;
    msg_in_flat[0*MW +: MW] = pack_msg(1, 0, 4'd15, 4'd15);
    lvc_in_flat[0*LW +: LW] = pack_lvc(0, 4'd5);
    #1;
    $display("  Hop 0: out_msg=%h (exp sc=0, m1=5, m2=15)", out_msg_0);

    // Hop 1 (using out of Hop 0 as in)
    msg_in_flat[0*MW +: MW] = out_msg_0;
    lvc_in_flat[0*LW +: LW] = pack_lvc(1, 4'd2);
    #1;
    $display("  Hop 1: out_msg=%h (exp sc=1, m1=2, m2=5)", out_msg_0);

    // Hop 2 (using out of Hop 1 as in)
    msg_in_flat[0*MW +: MW] = out_msg_0;
    lvc_in_flat[0*LW +: LW] = pack_lvc(0, 4'd10);
    #1;
    $display("  Hop 2: out_msg=%h (exp sc=1, m1=2, m2=5)", out_msg_0);
    
    // VN Phase
    phase_cn = 0;
    qv_in = -6'sd4;
    // We use the FINAL CN message (sc=1, m1=2, m2=5) as input
    msg_in_flat[0*MW +: MW] = out_msg_0; 
    // We test for PE that had Lvc=+5 (sign 0, mag 5)
    lvc_in_flat[0*LW +: LW] = pack_lvc(0, 4'd5); 
    #1;
    
    $display("  VN Result: mcv_total=%d, qv_w=%d, chat=%b", dut_comb.mcv_total, qv_wdata, c_hat_out);
    
    // Check results
    // mcv = (sc=1 ^ sign=0) ? -(2-1) : +(2-1) => -1.
    // Lv = -4 + (-1) = -5.
    if (qv_wdata === -6'sd5 && c_hat_out === 1'b1) begin
      $display("  PASS: Multi-hop sequence numerical check");
      pass_count = pass_count + 1;
    end else begin
      $display("  FAIL: Multi-hop sequence - qv_wdata=%d, c_hat=%b", qv_wdata, c_hat_out);
      fail_count = fail_count + 1;
    end

    // Summary
    #10;
    $display("\n============================================");
    $display("PE Testbench Complete: %0d PASS, %0d FAIL", pass_count, fail_count);
    $display("============================================");
    if (fail_count > 0) $display("*** FAILURES DETECTED ***");
    else $display("*** ALL TESTS PASSED ***");
    $finish;
  end

endmodule
