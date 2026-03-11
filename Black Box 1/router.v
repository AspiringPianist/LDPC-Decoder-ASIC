// router.v
// computes destination row index when sending a message from column `col` row `row`
// to the next column, based on QC cyclic shifts. If a subblock is all-zero, shift = -1 and
// we bypass (no CN update) for that layer/column.
//
// IMPORTANT: fill qc_shift[col][row] with actual shift values from the paper (Fig.5).
// Format for constants (example small toy); replace with paper table.

module router #(
  parameter integer NUM_COLS = 16,
  parameter integer Z = 42
)(
  input  wire [$clog2(NUM_COLS)-1:0] from_col,
  input  wire [$clog2(Z)-1:0]         from_row,
  output reg [$clog2(Z)-1:0]         to_row,
  output reg                         active // 1 => non-zero subblock (CN active)
);
  // --- PAPER PLACEHOLDER: replace these with the real 16x42 table ---
  // For now we synthesize a toy identity shift: to_row = (from_row + shift) % Z
  // Replace with actual qc_shift[NUM_COLS][Z] values.
  integer shift;
  always @(*) begin
    // toy: shift = (from_col * 3) % Z; // demo
    // DEFAULT: identity mapping (no permutation) to keep top-level runnable
    shift = 0;
    // compute to_row and active
    to_row = (from_row + shift) % Z;
    active = 1'b1; // set 0 if subblock is all-zero (paper uses -1 to encode that)
  end
endmodule