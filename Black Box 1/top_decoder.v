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
  localparam integer MSG_W = 1 + 1 + MIN_W + MIN_W; // pc + sc + min1 + min2

  // controller
  wire [$clog2(NUM_COLS)-1:0] cycle_idx;
  wire [NUM_COLS*4-1:0] faddr_bus;
  wire [NUM_COLS-1:0] en_slice_bus;
  reg [NUM_COLS-1:0] frame_done; // to be driven by parity checker
  // layer_bus_out[c] is a bus of Z entries of MSG_W bits each
  // layer_bus_in[c]  is similarly sized and is driven by this block.
  reg [NUM_COLS-1:0][Z*MSG_W-1:0] layer_bus_in_reg; // Verilog may need alternate packed form
  // For simpler code, use flat regs and index slices manually:

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
  // For each column c, each row r we must map layer_bus[c][row] -> layer_bus[(c+1)%NUM_COLS][to_row]
  // Use the router module to compute to_row and active for each (col, row, layer).

  // Parameters for router
  localparam integer NUM_LAYERS = 8; // as in router.v
  localparam integer RATE_SELECT = 0; // can be parameterized as needed

  // Router outputs
  wire [NUM_COLS-1:0][Z-1:0][NUM_LAYERS-1:0][$clog2(Z)-1:0] to_row;
  wire [NUM_COLS-1:0][Z-1:0][NUM_LAYERS-1:0] active;
  wire [NUM_COLS-1:0][Z-1:0][NUM_LAYERS-1:0] inactive_layer;

  genvar gc, gr, gl;
  generate
    for (gc = 0; gc < NUM_COLS; gc = gc + 1) begin : router_col
      for (gr = 0; gr < Z; gr = gr + 1) begin : router_row
        for (gl = 0; gl < NUM_LAYERS; gl = gl + 1) begin : router_layer
          router #(
            .NUM_COLS(NUM_COLS),
            .Z(Z),
            .NUM_LAYERS(NUM_LAYERS),
            .RATE_SELECT(RATE_SELECT)
          ) router_inst (
            .from_col(gc[$clog2(NUM_COLS)-1:0]),
            .from_row(gr[$clog2(Z)-1:0]),
            .from_layer(gl[$clog2(NUM_LAYERS)-1:0]),
            .to_row(to_row[gc][gr][gl]),
            .active(active[gc][gr][gl]),
            .inactive_layer(inactive_layer[gc][gr][gl])
          );
        end
      end
    end
  endgenerate

  // Now, wire up the layer_bus using the router outputs
  // For each column, for each row, for each layer, if active, connect the output to the correct to_row in the next column
  // Assume MSG_W = width of each message in the bus (as defined above)
  // The following is a combinational assignment
  integer wc, wr, wl;
  always @(*) begin
    // Default: zero all inputs
    for (wc = 0; wc < NUM_COLS; wc = wc + 1) begin
      for (wr = 0; wr < Z; wr = wr + 1) begin
        for (wl = 0; wl < NUM_LAYERS; wl = wl + 1) begin
          // Calculate bit indices for each message
          // Each layer's message is MSG_W bits wide
          // Flat bus: [Z*MSG_W-1:0] per column
          // For each (col, row, layer), get the message from layer_bus[wc][wr*MSG_W +: MSG_W]
          // If active, assign to next column's input at to_row
          if (active[wc][wr][wl]) begin
            // Next column index
            integer next_col = (wc + 1) % NUM_COLS;
            integer dest_row = to_row[wc][wr][wl];
            // Source bit indices
            integer src_idx = (wr * MSG_W) + (wl * Z * MSG_W);
            // Dest bit indices
            integer dst_idx = (dest_row * MSG_W) + (wl * Z * MSG_W);
            // Assign: layer_bus[next_col][dst_idx +: MSG_W] = layer_bus[wc][src_idx +: MSG_W];
            // This is a conceptual assignment; in synthesizable code, use assign or always_comb
            // For now, leave as a comment for clarity
            // assign layer_bus[next_col][dst_idx +: MSG_W] = layer_bus[wc][src_idx +: MSG_W];
          end
        end
      end
    end
  end

  // Done-all: simple reduction of frame_done (all frames completed)
  assign done_all = &frame_done;

endmodule