// top_decoder.v
`include "defs.v"
module top_decoder (
  input  wire clk,
  input  wire rst_n,
  input  wire start,
  output wire done_all
);
  // parameters
  localparam integer NUM_COLS = 16;
  localparam integer Z = 42;
  // controller
  wire [$clog2(NUM_COLS)-1:0] cycle_idx;
  wire [NUM_COLS*4-1:0] faddr_bus;
  wire [NUM_COLS-1:0] en_slice_bus;
  reg [NUM_COLS-1:0] frame_done; // to be driven by parity checker
  // instantiate controller
  controller #(.NUM_COLS(NUM_COLS), .NUM_FRAMES(16)) ctrl (
    .clk(clk), .rst_n(rst_n),
    .faddr_bus(faddr_bus),
    .en_slice_bus(en_slice_bus),
    .frame_done(frame_done),
    .cycle_idx(cycle_idx)
  );

  // Layer buses between columns: layer_bus[c] is out of column c => input to column (c+1)
  wire [Z*(1+1+LVC_MAG+LVC_MAG)-1:0] layer_bus [0:NUM_COLS-1];

  // Instantiate column slices
  genvar c;
  generate
    for (c=0;c<NUM_COLS;c=c+1) begin : cols
      // pick frame pointer for this slice from controller
      wire [3:0] faddr = faddr_bus[c*4 +: 4];
      wire en_slice = en_slice_bus[c];
      column_slice #(.COL_ID(c), .Z(Z), .QV_W(QV_W), .LVC_MAG(LVC_MAG), .LVC_W(LVC_W), .NFRAMES(16), .MEM_TYPE("BRAM")) cs (
        .clk(clk), .rst_n(rst_n),
        .cycle_idx(cycle_idx),
        .faddr_read(faddr),
        .en_slice(en_slice),
        .in_layer_bus(layer_bus[c]),  // In: from previous column (wired below)
        .out_layer_bus(layer_bus[(c+1) % NUM_COLS]), // Out: goes to next column's in_bus (wired here for loop)
        .parity_bits_out() // connect to parity reduction logic
      );
    end
  endgenerate

  // Router wiring: PER-ROW mapping using router table.
  // For each column c, each row r we must map layer_bus[c].out[row] -> layer_bus[(c+1)%NUM_COLS].in[to_row]
  // Implementation approach: build combinational mapping nets in generate loops (explicit net assignments).
  // For simplicity we leave a placeholder here: the router will be used to compute to_row and active flag,
  // and you should implement the per-bit connections accordingly. This is mechanical once qc_shift is present.

  // Done-all: simple reduction of frame_done (all frames completed)
  assign done_all = &frame_done;

endmodule