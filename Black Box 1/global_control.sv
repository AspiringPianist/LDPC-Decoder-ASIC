// global_control.sv
`timescale 1ns/1ps
import defs_pkg::*;
module global_control #(
  parameter int NUM_COLS_p = NUM_COLS,
  parameter int Z_p = Z,
  parameter int NUM_LAYERS_p = NUM_LAYERS,
  parameter int NUM_FRAMES_p = NUM_FRAMES
)(
  input  logic clk,
  input  logic rst_n,
  input  logic start,
  input  logic [1:0] rate_select_in,
  output logic [$clog2(NUM_LAYERS_p*2)-1:0] cycle_idx, // 0..(2*NUM_LAYERS-1)
  output logic [$clog2(NUM_LAYERS_p)-1:0] current_layer,
  output logic phase_cn,            // 1 => CN pass, 0 => VN pass (BB1 semantics)
  output logic [NUM_COLS_p*4-1:0] faddr_bus, // 4 bits per column (NUM_FRAMES<=16)
  output logic [NUM_COLS_p-1:0] en_slice_bus,
  output logic check_now,           // pulse for parity check at end of iteration
  output logic [1:0] rate_select
);

  localparam int CYCLES_PER_ITER = NUM_LAYERS_p * 2; // 8 -> 16 cycles per iteration

  // cycle counter: increments while 'start' is high (simple controller)
  logic [$clog2(CYCLES_PER_ITER)-1:0] cyc_cnt;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) cyc_cnt <= 0;
    else if (start) cyc_cnt <= (cyc_cnt + 1) % CYCLES_PER_ITER;
  end
  assign cycle_idx = cyc_cnt;

  // phase and current layer mapping
  assign phase_cn = (cyc_cnt < NUM_LAYERS_p) ? 1'b1 : 1'b0;
  assign current_layer = phase_cn ? cyc_cnt[$clog2(NUM_LAYERS_p)-1:0]
                                  : (cyc_cnt - NUM_LAYERS_p)[$clog2(NUM_LAYERS_p)-1:0];

  assign rate_select = rate_select_in;

  // Fig.7 cyclic frame-shift mapping:
  // faddr[col] = (col - cyc_cnt) mod NUM_FRAMES   (result 0..NUM_FRAMES-1)
  // This reproduces the frame sliding pattern in Fig.7 for NUM_FRAMES = 8.
  genvar c;
  generate
    for (c = 0; c < NUM_COLS_p; c = c + 1) begin : gen_faddr
      always_comb begin
        int signed_val = c - cyc_cnt;
        int modv = signed_val % NUM_FRAMES_p;
        if (modv < 0) modv = modv + NUM_FRAMES_p;
        faddr_bus[c*4 +: 4] = modv[$clog2(NUM_FRAMES_p)-1:0];
      end
    end
  endgenerate

  // Default: all slices enabled; parity/early termination externally gates these (top links frame_done)
  assign en_slice_bus = {NUM_COLS_p{1'b1}};

  // check_now asserted at end of VN pass (end of iteration)
  assign check_now = (cyc_cnt == (CYCLES_PER_ITER - 1));

endmodule