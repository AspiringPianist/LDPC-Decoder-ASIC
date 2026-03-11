// top_decoder.v
`include "defs.v"
module top_decoder (
  input  wire clk,
  input  wire rst_n,
  // simple test/status ports
  input  wire start,
  output reg done_all // high when all frames finished
);
  // instantiate controller
  wire [$clog2(NUM_COLS)-1:0] cycle_idx;
  wire [3:0] faddr_for_slice [0:NUM_COLS-1];
  wire en_slice [0:NUM_COLS-1];
  // frame_done array - gather parity across slices
  reg frame_done [0:NUM_FRAMES-1];

  controller ctrl (
    .clk(clk), .rst_n(rst_n),
    .cycle_idx(cycle_idx),
    .faddr_for_slice(faddr_for_slice),
    .en_slice(en_slice),
    .frame_done(frame_done)
  );

  // instantiate column slices
  genvar c;
  wire [Z_ROWS*(1+1+LVC_MAG+LVC_MAG)-1:0] layer_bus_in [0:NUM_COLS-1];
  wire [Z_ROWS*(1+1+LVC_MAG+LVC_MAG)-1:0] layer_bus_out [0:NUM_COLS-1];
  wire [Z_ROWS-1:0] parity_bits [0:NUM_COLS-1];

  generate
    for (c=0;c<NUM_COLS;c=c+1) begin : cols
      column_slice #(.COL_ID(c), .Z(Z_ROWS), .QV_W(QV_W), .LVC_MAG(LVC_MAG), .LVC_W(LVC_W), .NFRAMES(NUM_FRAMES)) cs (
        .clk(clk), .rst_n(rst_n),
        .cycle_idx(cycle_idx),
        .faddr_read(faddr_for_slice[c]),
        .en_slice(en_slice[c]),
        .in_layer_bus(layer_bus_in[c]),
        .out_layer_bus(layer_bus_out[c]),
        .parity_bits_out(parity_bits[c])
      );
    end
  endgenerate

  // connect buses between columns (hardwired permuted wires via router)
  // For simplicity in this top-level: connect out of col c to in of col (c+1)%NUM_COLS with identity mapping.
  // Replace with router logic that uses qc_shift table to perform cyclic shifts across rows.
  integer i;
  always @(*) begin
    for (i=0;i<NUM_COLS;i=i+1) begin
      layer_bus_in[i] = layer_bus_out[(i+NUM_COLS-1) % NUM_COLS];
    end
  end

  // parity reduction: for each frame we need to detect if all parity bits are zero at start column
  // Simple approach: every cycle compute parity for currently processed frame faddr_for_slice[0] (start column)
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      done_all <= 1'b0;
      for (i=0;i<NUM_FRAMES;i=i+1) frame_done[i] <= 1'b0;
    end else begin
      // reduce parity across all rows of column 0 for the current frame pointer
      integer p; reg any_one;
      any_one = 1'b0;
      for (p=0;p<Z_ROWS;p=p+1) begin
        any_one = any_one | parity_bits[0][p];
      end
      // If none set => frame converged at its start column - mark frame done
      integer f0;
      if (cycle_idx >= 0) f0 = cycle_idx % NUM_FRAMES; else f0 = 0;
      if (!any_one) frame_done[f0] <= 1'b1;

      // done_all when all frames done or special condition
      integer fid; reg all;
      all = 1'b1;
      for (fid=0; fid<NUM_FRAMES; fid=fid+1) if (!frame_done[fid]) all = 1'b0;
      if (all) done_all <= 1'b1;
    end
  end

endmodule