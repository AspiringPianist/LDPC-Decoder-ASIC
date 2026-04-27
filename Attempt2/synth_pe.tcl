# synth_pe.tcl
# Cadence Genus Synthesis Script for Processing Element (pe) Only

# -------------------------------------------------------------------------
# 1. Setup Libraries and Environment
# -------------------------------------------------------------------------
set lib_search_path   { /home/redhatacademy19/N_test/cadence_45nm/lib }
set target_library    { slow_vdd1v0_basicCells.lib }

set_db init_lib_search_path $lib_search_path
set_db library $target_library

# Enable ultra-high effort for best area and timing (useful for resource sharing)
set_db syn_generic_effort high
set_db syn_map_effort     high
set_db syn_opt_effort     high

# -------------------------------------------------------------------------
# 2. Read RTL
# -------------------------------------------------------------------------
set search_path "."
set_db init_hdl_search_path $search_path

# Read ONLY the required SystemVerilog files for the PE module
read_hdl -sv {
    defs_pkg.sv
    pe.sv
}

# -------------------------------------------------------------------------
# 3. Elaborate Top Module
# -------------------------------------------------------------------------
set top_module "pe"
elaborate $top_module

# Check for any unresolved references
check_design -unresolved

# -------------------------------------------------------------------------
# 4. Apply Constraints
# -------------------------------------------------------------------------
read_sdc constraints.sdc

# -------------------------------------------------------------------------
# 5. Synthesize
# -------------------------------------------------------------------------
puts "--- Starting Generic Synthesis ---"
syn_generic

puts "--- Starting Technology Mapping ---"
syn_map

puts "--- Starting Optimization ---"
syn_opt

# -------------------------------------------------------------------------
# 6. Generate Reports
# -------------------------------------------------------------------------
file mkdir reports_pe

report_timing  > reports_pe/timing.rpt
report_area    > reports_pe/area.rpt
report_power   > reports_pe/power.rpt
report_gates   > reports_pe/gates.rpt
report_qor     > reports_pe/qor.rpt

# -------------------------------------------------------------------------
# 7. Write Output Data
# -------------------------------------------------------------------------
file mkdir outputs_pe

# Write the synthesized netlist
write_hdl > outputs_pe/${top_module}_mapped.v

# Write the constraints used (SDC)
write_sdc > outputs_pe/${top_module}_mapped.sdc

# Write the design database (for later loading into Innovus or Genus)
write_db outputs_pe/${top_module}_mapped.db

puts "Synthesis completed successfully!"
quit
