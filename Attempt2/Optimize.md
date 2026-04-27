# LDPC Decoder — Area Optimization Report

This document details all area optimizations applied to the LDPC Decoder ASIC RTL.
The original (unoptimized) PE is preserved as `pe_old.sv` for comparison.

---

## Summary of Changes

| # | Module | Optimization | Expected Impact |
|---|--------|-------------|-----------------|
| 1 | `router.sv` | Replace `% Z` modulo (Z=42) with conditional subtract | **HIGH** — ~200+ gates saved per router × 672 instances |
| 2 | `global_control.sv` | Replace `% NUM_FRAMES` modulo with bitmask (`& 3'b111`) | **MEDIUM** — eliminates 16 divider instances |
| 3 | `pe.sv` | Reduce accumulator width from 11 to 9 bits | **MEDIUM** — 2 bits saved across 8 adders × 672 PEs |
| 4 | `pe.sv` | Saturation detection via MSB overflow (not full comparators) | **MEDIUM** — 2 comparators → 2 gates × 672 PEs |
| 5 | `pe.sv` | OFFSET_BETA=1 exploit: zero-detect replaces general comparator | **LOW-MEDIUM** — 1 comparator → NOR gate × 8 layers × 672 PEs |
| 6 | `pe.sv` | Absolute value via bit-invert + carry | **LOW** — cleaner synthesis mapping |
| 7 | `pe.sv` | Cleaner output register gating | **LOW** — reduces mux logic |
| 8 | `column_slice.sv` | Gate memory read enables with `en_slice` | **LOW** — reduces switching, may reduce read-port logic |

---

## Detailed Optimization Descriptions

### 1. Router Modulo Removal (router.sv) — HIGHEST IMPACT

**Problem:** The original router computes `(from_row + s_val) % Z` where Z=42 (non-power-of-2).  
The `%` operator for a non-power-of-2 divisor synthesizes to a **full integer division circuit** (hundreds of gates), involving multiply-and-shift or iterative subtraction logic.

**Solution:** Since `from_row ∈ [0,41]` and `s_val ∈ [0,41]`, the sum is always in `[0,82]`, which is less than `2×Z=84`. This means the modulo can be replaced with a single conditional subtract:
```systemverilog
// BEFORE (expensive):
tr = (from_row + s_val) % Z;

// AFTER (cheap):
raw_sum = {1'b0, from_row} + s_val[TR_W-1:0];
tr = (raw_sum >= Z) ? (raw_sum[TR_W-1:0] - Z[TR_W-1:0]) : raw_sum[TR_W-1:0];
```
This replaces a ~200-gate divider with a 7-bit adder + 7-bit comparator + 7-bit subtractor (~30-40 gates total).

**Additional:** Inactive layers (`s_val == -2`) now output `tr = 0` instead of `tr = from_row`, reducing mux tree fan-in since the output is a don't-care.

**Scale:** 672 router instances × ~160 gates saved = **~107,500 gates eliminated**.

---

### 2. Global Control Bitmask (global_control.sv)

**Problem:** Frame address generation uses `signed_val % NUM_FRAMES_p` with sign correction. This is a signed integer modulo requiring: 32-bit divider + sign check + conditional add.

**Solution:** Since `NUM_FRAMES = 8 = 2^3`, the modulo is equivalent to taking the lower 3 bits:
```systemverilog
// BEFORE (expensive — 32-bit signed modulo):
wire [31:0] signed_val = c - cyc_cnt;
wire [31:0] mod_raw    = signed_val % NUM_FRAMES_p;
wire [31:0] mod_pos    = (mod_raw[31]) ? (mod_raw + NUM_FRAMES_p) : mod_raw;
assign faddr_bus[c*4 +: 4] = mod_pos[3:0];

// AFTER (cheap — 4-bit subtract + bitmask):
wire [3:0] raw_diff = c[3:0] - cyc_cnt[3:0];
assign faddr_bus[c*4 +: 4] = {{(4-FR_BITS){1'b0}}, raw_diff[FR_BITS-1:0]};
```

**Scale:** 16 columns × ~300 gates (32-bit divider) eliminated = **~4,800 gates**.

---

### 3. PE Accumulator Width Reduction (pe.sv)

**Problem:** The original MCV accumulator uses `QV_W_p + 5 = 11` bit width. This is over-provisioned.

**Analysis:**
- Each `mcv_signed_w` is `MIN_W+1 = 5` bits (range: -15 to +15)
- At most `N_LAYERS = 8` layers are summed
- Max absolute sum: `8 × 15 = 120`, fits in 8 unsigned bits → 9 signed bits
- Adding `qv_in` (6-bit signed, range -32 to +31): max result = `120 + 31 = 151`, fits in 9 bits signed

**Solution:**
```systemverilog
// BEFORE:
localparam integer ACCUM_W = QV_W_p + 5; // 11 bits

// AFTER:
localparam integer ACCUM_W = QV_W_p + 3; // 9 bits
```

**Scale:** 2 bits saved × 8 adders in chain × 672 PEs + all downstream signal widths reduced.

---

### 4. PE Saturation Detection (pe.sv)

**Problem:** Original clamping uses two full-width signed comparisons:
```systemverilog
// BEFORE:
lv_clamped = (lv_tmp > $signed(QV_MAX)) ? QV_MAX :
             (lv_tmp < $signed(QV_MIN)) ? QV_MIN : lv_tmp[QV_W_p-1:0];
```
Each comparison synthesizes to a full adder/subtractor for the comparison.

**Solution:** Detect overflow by checking if the sign-extension bits are inconsistent:
```systemverilog
// AFTER:
wire overflow_pos = ~lv_tmp[ACCUM_W-1] & (|lv_tmp[ACCUM_W-2:QV_W_p-1]);
wire overflow_neg =  lv_tmp[ACCUM_W-1] & ~(&lv_tmp[ACCUM_W-2:QV_W_p-1]);
assign lv_clamped = overflow_pos ? QV_MAX :
                    overflow_neg ? QV_MIN : lv_tmp[QV_W_p-1:0];
```
This uses OR/AND reduction on 3 MSBs (2-3 gates) instead of two 9-bit comparators.

**Scale:** ~2 comparators → ~4 gates × 672 PEs.

---

### 5. PE OFFSET_BETA Constant Exploit (pe.sv)

**Problem:** Original code: `(chosen_mag > OFFSET_BETA_p) ? (chosen_mag - OFFSET_BETA_p) : 0` synthesizes a general 4-bit comparator + 4-bit subtractor.

**Solution:** Since `OFFSET_BETA = 1`:
- The guard `chosen_mag > 1` is equivalent to `chosen_mag != 0` (since magnitudes are unsigned and subtraction only underflows at 0)
- `chosen_mag - 1` is a simple decrement
- `|chosen_mag` (zero-detect) is a single NOR gate
```systemverilog
// AFTER:
wire [MIN_W_p-1:0] chosen_mag_off =
    (OFFSET_BETA_p == 1) ?
        ((|chosen_mag) ? (chosen_mag - 1'b1) : {MIN_W_p{1'b0}}) :
        ((chosen_mag > OFFSET_BETA_p) ? (chosen_mag - OFFSET_BETA_p) : {MIN_W_p{1'b0}});
```
The constant condition `OFFSET_BETA_p == 1` is resolved at elaboration time; Genus removes the dead branch entirely.

**Scale:** 1 comparator → 1 NOR gate × 8 layers × 672 PEs.

---

### 6. PE Absolute Value Simplification (pe.sv)

**Solution:** The LVC update computes `|lvc_diff|`. Rather than using the generic `-lvc_diff` (which synthesizes as `0 - lvc_diff`, a full subtractor), we use conditional bit-inversion:
```systemverilog
wire [ACCUM_W-1:0] lvc_abs_val = lvc_neg ? (~lvc_diff + 1'b1) : lvc_diff;
```
The `~x + 1` form maps directly to an inverter chain + carry-propagate, which many cell libraries can implement more efficiently than a full subtractor.

---

### 7. PE Register Gating (pe.sv)

**Solution:** Combined `~phase_cn & en` into a single `vn_active` signal that gates write-enables **before** they reach the register, so the register mux has fewer branches to evaluate.

---

### 8. Column Slice Memory Read Gating (column_slice.sv)

**Problem:** All QV and LVC memory banks had `ren = 1'b1` — always reading, even when the slice is inactive. This wastes power and may prevent tools from optimizing read-port logic.

**Solution:**
```systemverilog
// BEFORE:
.ren(1'b1)

// AFTER:
.ren(en_slice)
```

---

## Files Modified

| File | Type of Change |
|------|---------------|
| `pe.sv` | **NEW** — area-optimized PE (created from `pe_old.sv`) |
| `pe_old.sv` | Unchanged — preserved as baseline for comparison |
| `router.sv` | Modified — modulo → conditional subtract |
| `global_control.sv` | Modified — modulo → bitmask |
| `column_slice.sv` | Modified — memory read gating |
| `synth_router.tcl` | **NEW** — synthesis script for router-only comparison |

---

## How to Verify Area Improvement

### PE Comparison
```bash
# 1. Synthesize original PE (copy pe_old.sv to pe.sv first):
cp pe_old.sv pe.sv
source synth_pe.tcl
cp reports_pe/area.rpt reports_pe/area_old.rpt

# 2. Synthesize optimized PE (restore):
cp pe_optimized.sv pe.sv   # or just use the current pe.sv
source synth_pe.tcl
# Compare reports_pe/area.rpt vs reports_pe/area_old.rpt
```

### Router Comparison
```bash
# Use the new synth_router.tcl to synthesize the router module
source synth_router.tcl
# Check reports_router/area.rpt — the modulo removal should show clear savings
```

### Full Decoder
```bash
source synth.tcl
# Check reports/area.rpt (requires sufficient server RAM)
```

---

## Expected Total Area Reduction

| Optimization | Per Instance | × Instances | Total Gates Saved |
|-------------|-------------|-------------|-------------------|
| Router modulo → cond. sub. | ~160 gates | 672 | ~107,500 |
| Global control modulo → mask | ~300 gates | 16 | ~4,800 |
| PE accumulator width | ~16 gates | 672 | ~10,750 |
| PE saturation detection | ~12 gates | 672 | ~8,060 |
| PE OFFSET_BETA exploit | ~8 gates | 5,376 (8×672) | ~43,000 |
| PE abs-value simplification | ~4 gates | 5,376 | ~21,500 |
| **Estimated Total** | | | **~195,600 gates** |

> **Note:** Exact savings depend on the synthesis tool's optimization level and the target cell library. The router modulo removal alone should produce a clearly measurable area difference. Run Genus to get actual numbers.
