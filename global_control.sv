// global_control.sv
// Controller: all layers processed in parallel; cycle_idx tracks column hops.
`timescale 1ns/1ps
import defs_pkg::*;

module global_control #(
  parameter int NUM_COLS_p   = NUM_COLS,
  parameter int Z_p          = Z,
  parameter int NUM_LAYERS_p = NUM_LAYERS,
  parameter int NUM_FRAMES_p = NUM_FRAMES,
  parameter int MAX_ITER_p   = MAX_ITER
)(
  input  logic clk,
  input  logic rst_n,
  input  logic start,
  input  logic [1:0] rate_select_in,
  output logic [$clog2(NUM_COLS_p)-1:0] cycle_idx,
  output logic phase_cn,
  output logic [NUM_COLS_p*4-1:0] faddr_bus,
  output logic [NUM_COLS_p-1:0] en_slice_bus,
  output logic check_now,
  output logic [1:0] rate_select,
  output logic iter_done  // Asserted when MAX_ITER iterations are complete
);

  localparam int CYCLES_PER_ITER = NUM_COLS_p; // 16
  localparam int HALF = NUM_COLS_p / 2;        // 8

  logic [$clog2(CYCLES_PER_ITER)-1:0] cyc_cnt;
  logic [$clog2(MAX_ITER_p+1)-1:0]    iter_cnt;
  logic                               running;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cyc_cnt   <= 0;
      iter_cnt  <= 0;
      running   <= 0;
      iter_done <= 0;
    end else begin
      if (start && !iter_done) begin
        running <= 1'b1;
        if (cyc_cnt == (CYCLES_PER_ITER - 1)) begin
          cyc_cnt <= 0;
          if (iter_cnt == MAX_ITER_p - 1) begin
            iter_done <= 1'b1;
            iter_cnt  <= MAX_ITER_p;
          end else begin
            iter_cnt <= iter_cnt + 1;
          end
        end else begin
          cyc_cnt <= cyc_cnt + 1;
        end
        // $display("  [GCTRL] run=1 cyc=%0d iter=%0d done=%b", cyc_cnt, iter_cnt, iter_done);
      end else if (!start) begin
        running   <= 1'b0;
        cyc_cnt   <= 0;
        iter_cnt  <= 0;
        iter_done <= 0;
      end
    end
  end

  assign cycle_idx   = cyc_cnt;
  assign phase_cn    = (cyc_cnt < HALF) ? 1'b1 : 1'b0;
  assign rate_select = rate_select_in;

  // Fig.7 cyclic frame-shift: faddr[col] = (col - cyc_cnt) mod NUM_FRAMES
  genvar c;
  generate
    for (c = 0; c < NUM_COLS_p; c = c + 1) begin : gen_faddr
      wire [31:0] signed_val = c - cyc_cnt;
      wire [31:0] mod_raw    = signed_val % NUM_FRAMES_p;
      wire [31:0] mod_pos    = (mod_raw[31]) ? (mod_raw + NUM_FRAMES_p) : mod_raw;
      assign faddr_bus[c*4 +: 4] = mod_pos[3:0];
    end
  endgenerate

  assign en_slice_bus = {NUM_COLS_p{1'b1}};
  // Early Termination: check parity for the frame currently at the end of the pipeline.
  // We start checking after the first iteration (iter_cnt > 0) to ensure pipeline is full.
  assign check_now = running && (iter_cnt > 0);

endmodule