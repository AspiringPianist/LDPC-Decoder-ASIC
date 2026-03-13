# LDPC Decoder ASIC - Black Box 1 Compatibility Report

**Date**: March 13, 2026  
**Scope**: All 11 modules in Black Box 1 folder  
**Status**: ✅ **FIXED** - All critical blocking issues resolved

---

## Summary of Fixes Applied

### ✅ FIXED: Package Import Errors
**Files**: `pe.sv`, `controller.sv`  
**Change**: `import defs::*;` → `import defs_pkg::*;`  
**Impact**: All package constants now properly imported

---

### ✅ FIXED: PE Module Interface Redesign
**File**: `pe.sv`  
**Changes**:
- Added new packed message interface: `msg_in[MSG_W-1:0]` instead of individual bits
- Added required control inputs: `phase_cn`, `layer_id`, `en` (enable)
- Changed output to packed format: `msg_out[MSG_W-1:0]`
- Added unpacking/packing logic for message format
- Removed unused `active` and `do_cycle` control signals
- Updated internal logic to work with packed message format

**Result**: PE module now compatible with column_slice instantiation

---

### ✅ FIXED: PE Output Format
**Files**: `pe.sv`, `column_slice.sv`  
**Changes**:
- PE now outputs packed `msg_out[MSG_W-1:0]` instead of individual bits
- column_slice packing logic updated to handle packed messages properly

---

### ✅ FIXED: Parity Checker Parameter Mismatch
**File**: `top_decoder_synth.sv`  
**Change**: `parity_checker #(.Z_p(Z), .NUM_FRAMES_p(NUM_FRAMES))` → `#(.Z(Z), .NUM_FRAMES(NUM_FRAMES))`  
**Result**: Parameter names now match definition

---

### ✅ FIXED: Unconnected Parity Bits
**File**: `top_decoder_synth.sv`  
**Changes**:
- Added `parity_bits_from_col[NUM_COLS-1:0]` array to capture parity output from each column
- Updated column_slice instantiation to connect `.parity_bits_out(parity_bits_from_col[c])`
- Connected parity checker input: `wire [Z-1:0] start_parity_bits = parity_bits_from_col[START_COL];`

**Result**: Parity bits now properly connected from column 0 to parity checker

---

### ✅ FIXED: Rate Select Runtime Input
**File**: `top_decoder_synth.sv`  
**Changes**:
- Added input port: `input wire [1:0] rate_select_in`
- Connected to global_control: `.rate_select_in(rate_select_in)`
- Removed non-existent `.USE_PAPER_TABLE(0)` parameter

**Result**: Rate can now be changed at runtime

---

### ✅ FIXED: Memory Read Logic in column_slice
**File**: `column_slice.sv`  
**Changes**:
- Added per-row memory interface: `qv_rdata_per_row[Z_local-1:0]`, `lvc_rdata_per_row[Z_local-1:0]`
- Implemented row sequencing with `read_row_idx` counter
- Added pipeline delay register `read_row_idx_d1` for proper data routing
- Implemented per-row read data latching and multiplexing
- Added memory write arbitration logic for all rows

**Result**: All Z rows can now be accessed; memory bottleneck resolved

---

### ✅ IMPROVED: Router Module SystemVerilog Compliance
**File**: `router.sv`  
**Changes**:
- Changed input/output declarations from `wire`/`reg` to `logic`
- Changed `always @(*)` to `always_comb`

**Result**: Consistent SystemVerilog style across all modules

---

### ✅ NOTE: Duplicate Control Module
**File**: `controller.sv`  
**Status**: Left in place but marked with comment
- Added comment: "This module is currently unused. global_control.sv is the active control module."
- Kept for reference/alternative implementation
- Not removed as it may be useful for future parallel implementations

---

## Compatibility Matrix (After Fixes)

```
top_decoder_synth.sv (TOP MODULE) ✅
├─ global_control.sv ✅ Connected
│   └ Outputs: phase_cn, current_layer, faddr_bus, en_slice_bus, check_now, rate_select
│
├─ column_slice.sv ✅ Port compatible
│   ├─ pe.sv ✅ NOW COMPATIBLE - Interface redesigned
│   ├─ esram_bram_sim.sv ✅ Connected
│   └─ Memory interface ✅ ALL ROWS ACCESSIBLE
│
├─ router.sv ✅ Consistent with top-level routing
│   └ Outputs: to_row, active, inactive_layer
│
└─ parity_checker.sv ✅ PARAMETERS AND INPUTS CONNECTED
    ├ Input: parity_bits_from_col[START_COL]
    ├ Input: faddr_bus for frame_id
    ├ Input: check_now pulse
    └ Output: frame_done (used for early termination)
```

---

## Compilation Status

✅ **All files compile without errors**

Verified files:
- top_decoder_synth.sv
- pe.sv
- column_slice.sv
- router.sv
- global_control.sv
- parity_checker.sv
- controller.sv
- esram_bram_sim.sv
- esram_macro_stub.sv
- clock_gate_stub.sv
- defs_pkg.sv

---

## Functional Improvements

| Feature | Before | After |
|---------|--------|-------|
| Package imports | ❌ Broken | ✅ Working |
| PE interface | ❌ Incompatible | ✅ Matched |
| Message format | ❌ Mixed (packed/unpacked) | ✅ Consistent |
| Memory reads | ❌ Only row 0 addressable | ✅ All Z rows |
| Parity checking | ❌ Never executed | ✅ Fully connected |
| Rate selection | ❌ Parameter only | ✅ Runtime input |
| Code style | ⚠️ Mixed wire/reg/logic | ✅ Consistent logic |

---

## Next Steps (Optional Enhancements)

1. **Performance**: Replace `esram_bram_sim` with actual multi-ported SRAM macros for true parallel reads
2. **Testing**: Create comprehensive test benches to verify end-to-end functionality
3. **Documentation**: Update module-level comments with clearer interfaces
4. **Synthesis**: Verify timing closure with target technology
5. **Optimization**: Optimize memory arbitration if write conflicts occur during pipelined operation

---

## Files Modified

- `pe.sv` - Complete interface redesign
- `column_slice.sv` - Updated PE instantiation and memory interface
- `top_decoder_synth.sv` - Fixed parameters, added inputs, connected parity bits
- `router.sv` - Standardized to SystemVerilog logic/always_comb
- `controller.sv` - Added import fix and deprecation notice
- `global_control.sv` - No changes needed (already correct)
- `parity_checker.sv` - No changes needed (already correct)
- `esram_bram_sim.sv` - No changes needed (already correct)
- `esram_macro_stub.sv` - No changes needed (already correct)
- `clock_gate_stub.sv` - No changes needed (already correct)
- `defs_pkg.sv` - No changes needed (already correct)

---

## Verification Checklist

- [x] Package imports fixed
- [x] PE module interface matches column_slice expectations
- [x] Message format consistent across all modules
- [x] Parity bits properly connected
- [x] Rate select exposed as runtime input
- [x] Memory read logic supports all rows
- [x] Parameter names consistent
- [x] SystemVerilog syntax compliance
- [x] No compilation errors
- [x] Module hierarchy verified

**Status**: All compatibility issues resolved ✅

---

## Executive Summary (RESOLVED)

