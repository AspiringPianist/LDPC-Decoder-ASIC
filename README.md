# LDPC-Decoder-ASIC

Frame-interleaved, path-unrolled QC-LDPC decoder RTL inspired by:

Mario Milicevic and P. Glenn Gulak, "A Multi-Gb/s Frame-Interleaved LDPC Decoder With Path-Unrolled Message Passing in 28-nm CMOS," IEEE TVLSI, 2018.

This repository contains a SystemVerilog implementation of a multi-rate LDPC decoder architecture with:

- Path-unrolled message passing (CN work distributed in time)
- Combined CN+VN processing elements
- QC-aware hard-wired inter-column routing
- Frame interleaving and iteration control
- Early termination hooks and coarse slice-level clock gating

## 1. Project Overview

The design targets QC-LDPC decoding with a low-to-moderate clock regime by trading off global permutation complexity for local processing/memory. Instead of a large central CN array and crossbar-like interconnect, each column slice contains local memory and compute, and layer messages move to the next column each cycle.

Current repository focus:

- RTL architecture exploration and functional simulation
- Parameterized module decomposition
- Per-block and integration testbenches
- Macro stubs for synthesis-flow replacement

This repo does not currently include a complete OpenLane project setup (no flow scripts/config TCL in-tree at the moment), but the RTL is organized to be synthesis-friendly.

## 2. Architecture at a Glance

Top-level structure is implemented in [top_decoder_synth.sv](top_decoder_synth.sv):

- `NUM_COLS = 16` column slices
- `Z = 42` rows per column slice
- `NUM_LAYERS = 8` routing/processing layers
- `NUM_FRAMES = 8` interleaved frames

High-level dataflow per cycle:

1. Global control selects phase (CN or VN), cycle index, and per-column frame address.
2. Each column slice processes all rows in parallel for active layers.
3. Layer messages are routed to the next column using fixed QC shift tables.
4. Last-column parity is checked for early frame completion.
5. Done condition is asserted on max iteration or all frames done.

## 3. Algorithmic Mapping (Path-Unrolled Min-Sum)

The design follows a two-phase iteration over columns:

1. CN phase (`phase_cn = 1`):
	 - Each PE reads stored `Lvc` (VN->CN message) for active layers.
	 - Running CN state in the incoming layer message is updated:
		 - sign product `sc`
		 - `min1`, `min2`
		 - parity token `pc`
2. VN phase (`phase_cn = 0`):
	 - PE computes outgoing `mcv` from propagated CN state and local `Lvc` sign/magnitude.
	 - Updates variable belief (`Lv`), hard decision (`c_hat`), and writes back new `Lvc`.

This is "path-unrolled" because a full CN update is not done in one monolithic CN unit; it is accumulated across the path as the message traverses columns.

## 4. Module Map

### 4.1 Core RTL

- [top_decoder_synth.sv](top_decoder_synth.sv)
	- Top integration: control, router fabric, column slices, parity checker.
	- Generates inter-column routing and slice-level clock gating.

- [global_control.sv](global_control.sv)
	- Iteration/cycle FSM-like counters.
	- Generates `phase_cn`, `cycle_idx`, and per-column frame addresses.
	- Supports runtime `rate_select_in`.

- [column_slice.sv](column_slice.sv)
	- Instantiates `Z` processing rows.
	- Contains per-row Qv memory and per-layer Lvc memories.
	- Handles active/inactive/bypass behavior from router flags.

- [pe.sv](pe.sv)
	- Combined CN+VN PE.
	- Supports parallel layer processing (`N_LAYERS`) and optional registered output stage (`REGISTERED`).
	- Performs Min-Sum style updates and saturating arithmetic.

- [router.sv](router.sv)
	- QC shift-table driven mapping for all four supported rate indices.
	- Emits per-layer destination row and active/inactive flags.

- [parity_checker.sv](parity_checker.sv)
	- Samples parity vector for frame under test and updates `frame_done` flags.

### 4.2 Memory and Clocking Stubs

- [esram_bram_sim.sv](esram_bram_sim.sv)
	- Behavioral synchronous SRAM model used in simulation.

- [esram_macro_stub.sv](esram_macro_stub.sv)
	- Macro replacement shell; can fall back to behavioral model.

- [clock_gate_stub.sv](clock_gate_stub.sv)
	- Simple AND-based sim gate; replace with library-integrated ICG for real synthesis/signoff.

### 4.3 Legacy/Reference

- [controller.sv](controller.sv)
	- Marked as unused in comments; [global_control.sv](global_control.sv) is the active control path.

## 5. Parameters and Numeric Formats

Main architectural/package parameters are in [defs_pkg.sv](defs_pkg.sv):

- `NUM_COLS = 16`
- `Z = 42`
- `NUM_LAYERS = 8`
- `NUM_FRAMES = 8`
- `MAX_ITER = 10`

Data/message widths:

- `MIN_W = 4`
- `LVC_W = 1 + LVC_MAG = 5` (sign-magnitude)
- `QV_W = 6` (signed soft LLR)
- `MSG_W = 1 + 1 + MIN_W + MIN_W = 10`
	- packed as `{pc, sc, min1, min2}`

Memory depth controls:

- `NUM_QV_FRAMES = 16`
- `NUM_LVC_FRAMES = 8`

Note: Some values differ from the paper's exact quantization/profile; this repo should be treated as a practical RTL realization and experimentation baseline.

## 6. Router Semantics and Code Rates

Rate is selected at runtime via `rate_select_in` (2-bit):

- `0`: rate 1/2 profile
- `1`: rate 5/8 profile
- `2`: rate 3/4 profile
- `3`: rate 13/16 profile

In [router.sv](router.sv), each shift-table entry has meaning:

- `-2`: inactive layer slot (no edge)
- `-1`: bypass (no shift, pass-through)
- `>= 0`: active edge with cyclic row shift

This avoids a global permutation network and keeps routing local between adjacent columns.

## 7. Timing and Throughput Model in This RTL

In [global_control.sv](global_control.sv):

- `CYCLES_PER_ITER = NUM_COLS = 16`
- First half of the cycle window is CN phase (`cycle_idx < 8`)
- Second half is VN phase (`cycle_idx >= 8`)

`done_all` in [top_decoder_synth.sv](top_decoder_synth.sv) is asserted when:

- max iterations reached (`iter_done`), or
- all interleaved frames are marked done by parity checker

## 8. Memory Organization

Each column slice has:

- One Qv memory per row (depth `NUM_QV_FRAMES`)
- One Lvc memory per layer per row (depth `NUM_LVC_FRAMES`)

At current package defaults, modeled storage is:

- Qv bits: `NUM_COLS * Z * NUM_QV_FRAMES * QV_W = 64,512`
- Lvc bits: `NUM_COLS * Z * NUM_LAYERS * NUM_LVC_FRAMES * LVC_W = 215,040`
- Total modeled storage: `279,552 bits` (about `273.0 Kb`)

This includes simulation-model storage and is not a direct one-to-one replica of the silicon macro budgeting in the reference paper.

## 9. Simulation Guide

This section provides commands to compile and simulate the SystemVerilog testbenches using Icarus Verilog (`iverilog`) and inspect waveforms in GTKWave.

### Prerequisites

Ensure the following tools are installed:

- Icarus Verilog
- GTKWave

All commands below assume your terminal is opened at the project root.

### 9.1 Run the Top-Level Decoder Testbench (`tb_top_decoder.sv`)

This testbench integrates all major components and runs across all four IEEE 802.11ad rate profiles.

Step 1: Compile design + top testbench

```bash
iverilog -g2012 -o tb_top_decoder.vvp defs_pkg.sv clock_gate_stub.sv esram_macro_stub.sv esram_bram_sim.sv parity_checker.sv pe.sv router.sv global_control.sv controller.sv column_slice.sv top_decoder_synth.sv testbench/tb_top_decoder.sv
```

Step 2: Run simulation

```bash
vvp tb_top_decoder.vvp
```

Step 3: View waveforms

```bash
gtkwave tb_top_decoder.vcd
```

### 9.2 Run Component-Level Testbenches

Use these if you want to isolate specific blocks.

#### A) Processing Element (PE) Testbench

```bash
# Compile
iverilog -g2012 -o tb_pe.vvp defs_pkg.sv pe.sv testbench/tb_pe.sv

# Run
vvp tb_pe.vvp
```

#### B) Column Slice Testbench

```bash
# Compile
iverilog -g2012 -o tb_column_slice.vvp defs_pkg.sv clock_gate_stub.sv esram_macro_stub.sv esram_bram_sim.sv pe.sv controller.sv column_slice.sv testbench/tb_column_slice.sv

# Run
vvp tb_column_slice.vvp
```

### 9.3 Troubleshooting

- If you see errors around `import defs_pkg::*`, ensure `defs_pkg.sv` is listed first in the compile file list.
- If `logic`, `always_comb`, or package syntax is rejected, ensure `-g2012` is present.
- If GTKWave opens with no activity, confirm the simulation generated `tb_top_decoder.vcd` in your current directory.

## 10. Repository Layout

```text
.
|-- defs_pkg.sv               # Global params and bit widths
|-- top_decoder_synth.sv      # Top-level integration
|-- global_control.sv         # Iteration/cycle/frame controller
|-- router.sv                 # QC routing tables and mapping logic
|-- column_slice.sv           # Column-slice compute + local memories
|-- pe.sv                     # Combined CN+VN processing element
|-- parity_checker.sv         # Early-termination parity sampling
|-- esram_bram_sim.sv         # Behavioral SRAM model
|-- esram_macro_stub.sv       # Synthesis macro stub/fallback
|-- clock_gate_stub.sv        # Simulation clock-gating stub
|-- testbench/
|   |-- tb_pe.sv
|   |-- tb_column_slice.sv
|   `-- tb_top_decoder.sv
|-- paper_text.txt            # Paper text extract for reference
`-- paper/                    # Supporting paper assets
```
