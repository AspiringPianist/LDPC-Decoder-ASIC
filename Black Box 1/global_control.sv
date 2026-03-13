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
  input  logic [1:0] rate_select_in, // optional runtime rate select
  output logic [$clog2(NUM_LAYERS_p*2)-1:0] cycle_idx, // 0..CYCLES-1
  output logic [$clog2(NUM_LAYERS_p)-1:0] current_layer,
  output logic phase_cn, // 1 => CN phase, 0 => VN phase (BB1 semantics)
  output logic [NUM_COLS_p*4-1:0] faddr_bus, // 4 bits per column (NUM_FRAMES<=16)
  output logic [NUM_COLS_p-1:0] en_slice_bus, // per-slice coarse enable
  output logic check_now,  // pulse to trigger parity check at iteration end
  output logic [1:0] rate_select
);

  localparam int CYCLES_PER_ITER = NUM_LAYERS_p * 2; // 8 -> 16

  // cycle counter increments while 'start' is high (you can modify start semantics)
  logic [$clog2(CYCLES_PER_ITER)-1:0] cyc_cnt;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) cyc_cnt <= 0;
    else if (start) cyc_cnt <= (cyc_cnt + 1) % CYCLES_PER_ITER;
  end
  assign cycle_idx = cyc_cnt;

  // CN phase for cycles 0..NUM_LAYERS-1, VN phase for cycles NUM_LAYERS..2*NUM_LAYERS-1
  assign phase_cn = (cyc_cnt < NUM_LAYERS_p) ? 1'b1 : 1'b0;
  // current_layer is the layer index within 0..NUM_LAYERS-1
  assign current_layer = phase_cn ? cyc_cnt[$clog2(NUM_LAYERS_p)-1:0] : (cyc_cnt - NUM_LAYERS_p)[$clog2(NUM_LAYERS_p)-1:0];

  // rate select passthrough
  assign rate_select = rate_select_in;

  // cyclic frame-shifting mapping (Fig.7):
  // For each cycle t and column c:
  //   faddr[c] = (c - t) mod NUM_FRAMES   (value 0..NUM_FRAMES-1)
  // This produces the cyclic-shift property shown in Fig.7 (frame indices 0..NUM_FRAMES-1 slide across columns).
  genvar c;
  generate
    for (c = 0; c < NUM_COLS_p; c = c + 1) begin : gen_faddr
      // compute signed offset (c - cyc_cnt) mod NUM_FRAMES_p
      // Use arithmetic and normalize to 0..NUM_FRAMES_p-1
      always_comb begin
        int signed_val = c - cyc_cnt;
        int modv = signed_val % NUM_FRAMES_p;
        if (modv < 0) modv = modv + NUM_FRAMES_p;
        faddr_bus[c*4 +: 4] = modv[$clog2(NUM_FRAMES_p)-1:0];
      end
    end
  endgenerate

  // default enable: all slices enabled unless gated externally by 'frame_done'
  assign en_slice_bus = {NUM_COLS_p{1'b1}};

  // check_now: pulse at end of iteration when parity check should be performed (paper uses end of VN pass)
  assign check_now = (cyc_cnt == (CYCLES_PER_ITER - 1));

endmodule