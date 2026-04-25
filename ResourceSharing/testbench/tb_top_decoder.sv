// tb_top_decoder.sv — Integration testbench for all 4 code rates
`timescale 1ns/1ps
import defs_pkg::*;

module tb_top_decoder;

  logic clk, rst_n, start;
  logic [1:0] rate_select_in;
  wire done_all;

  top_decoder_synth dut (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .rate_select_in(rate_select_in),
    .done_all(done_all)
  );

  // Clock generation
  initial clk = 0;
  always #2.5 clk = ~clk; // 200MHz

  integer r;
  initial begin
    $dumpfile("tb_top_decoder.vcd");
    $dumpvars(0, tb_top_decoder);

    $display("============================================");
    $display("Top Decoder Integration Testbench");
    $display("============================================");
    $display("Config: NUM_COLS=%0d, Z=%0d, NUM_LAYERS=%0d, NUM_FRAMES=%0d", NUM_COLS, Z, NUM_LAYERS, NUM_FRAMES);

    for (r = 0; r < 4; r = r + 1) begin
      $display("\n--- Testing Rate Index %0d ---", r);
      rate_select_in = r[1:0];
      rst_n = 0; start = 0;
      #20;
      rst_n = 1;
      #20;
      start = 1;

      $display("  [TB] T=%0t start set, gctrl.running=%b, frame_done=%b", $time, dut.gctrl.running, dut.frame_done);

      fork : monitor_block
        begin
          wait(dut.done_all === 1'b1);
          $display("  [TB] T=%0t EARLY TERMINATION / MAX ITER DETECTED!", $time);
          $display("       Final Status: iter=%0d, frame_done=%b", dut.gctrl.iter_cnt, dut.frame_done);
        end
        begin
          // Monitor for several iterations to see convergence progress
          repeat (160) begin
            @(posedge clk);
            #1;
            if (r == 0 && (dut.cycle_idx == 0 || dut.cycle_idx == 15 || (dut.frame_done != 0 && $time < 150000))) begin
              $display("  T=%0t | cyc=%0d | iter=%0d | frame_done=%b | done_all=%b", 
                       $time, dut.cycle_idx, dut.gctrl.iter_cnt, dut.frame_done, dut.done_all);
            end
          end
        end
        begin
          #100000;
          $display("  FAIL: rate %0d - timeout", r);
        end
      join_any
      disable monitor_block;
      
      start = 0;
      #100;
    end

    $display("\n============================================");
    $display("Top Decoder Integration Testbench Complete");
    $display("============================================");
    $finish;
  end

  // Watchdog timer (absolute)
  initial begin
    #500000;
    $display("TIMEOUT: Global Testbench exceeded limit");
    $finish;
  end

endmodule
