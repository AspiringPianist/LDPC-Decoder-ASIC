# Cadence Genus QoR Comparison: Processing Element (`pe.sv`)

This document provides a side-by-side comparison of the Cadence Genus Quality of Results (QoR) reports for the baseline (unoptimized) Processing Element versus the area-optimized Processing Element. 

The synthesis was performed using the Cadence 45nm `slow_vdd1v0_basicCells.lib` at PVT_0P9V_125C.

---

## 1. Executive Summary

The manual RTL datapath optimizations yielded massive improvements across all key synthesis metrics:

* **Area Reduction:** ~20% reduction in cell count and total silicon area.
* **Timing Improvement:** ~24% improvement in critical path slack, indicating significantly shallower logic depth.
* **Synthesis Runtime:** ~45% reduction in compilation time due to simplified arithmetic logic.

---

## 2. Detailed Metrics Comparison

| Metric | Original (`pe_old.sv`) | Optimized (`pe.sv`) | Improvement |
| :--- | :--- | :--- | :--- |
| **Cell Count** | 3,204 | 2,559 | **-645 cells (-20.1%)** |
| **Total Cell Area** | 5,777.013 µm² | 4,624.763 µm² | **-1152.25 µm² (-19.9%)** |
| **Critical Path Slack** | -2255.8 ps | -1712.0 ps | **+543.8 ps (+24.1%)** |
| **Total Negative Slack (TNS)** | -111,901.5 | -89,385.9 | **+20.1%** |
| **Synthesis Runtime** | 44.39 seconds | 24.52 seconds | **-19.87s (-44.8%)** |

---

## 3. Global Impact Analysis

The Processing Element is the most frequently instantiated module in the LDPC Decoder ASIC. 
There are **16 column slices**, each containing **42 rows**, resulting in **672 PE instances** across the chip.

Scaling the per-block savings up to the global architecture:

* **Total Area Saved:** 1152.25 µm² × 672 = **~774,312 µm²**
* **Total Cells Eliminated:** 645 cells × 672 = **433,440 fewer logic cells**

This means nearly half a million logic cells were stripped from the final design, massively reducing both static leakage power and dynamic switching power, all while simultaneously improving the clock speed limit (timing slack).

---

## 4. Why Did the Metrics Improve?

1. **Cell Area (-20%):** We narrowed the accumulator from 11 bits to 9 bits, saving flip-flops and adders. We also converted complex two's complement negations to simpler bitwise-inversions.
2. **Timing Slack (+24%):** We removed full-width generic comparators from the saturation logic and `OFFSET_BETA` subtraction logic. Replacing these deep logic gates with shallow MSB overflow checks and NOR gates drastically reduced the critical path delay.
3. **Runtime (-45%):** Because there are fewer complex generic comparators and arithmetic operators, Genus's Datapath Compiler had an exponentially smaller search space to optimize, cutting compilation time nearly in half.
