# synth.tcl
# Cadence Genus Synthesis Script for LDPC Decoder

# -------------------------------------------------------------------------
# 1. Setup Libraries and Environment
# -------------------------------------------------------------------------
# TODO: FILL IN YOUR TARGET TECHNOLOGY LIBRARY PATHS HERE
set lib_search_path   { <INSERT_LIBRARY_DIRECTORY_PATH_HERE> }
set target_library    { <INSERT_TARGET_LIB_FILE_HERE.lib> }
set lef_files         { <INSERT_LEF_FILES_HERE.lef> }

set_db init_lib_search_path $lib_search_path
set_db library $target_library
# set_db lef_library $lef_files  ;# Uncomment if physical synthesis is needed

# Enable ultra-high effort for best area and timing (useful for resource sharing)
set_db syn_generic_effort high
set_db syn_map_effort     high
set_db syn_opt_effort     high

# -------------------------------------------------------------------------
# 2. Read RTL
# -------------------------------------------------------------------------
set search_path "."
set_db init_hdl_search_path $search_path

# Read the SystemVerilog files in dependency order
# Note: defs_pkg.sv must be read first!
read_hdl -sv {
    defs_pkg.sv
    clock_gate_stub.sv
    esram_macro_stub.sv
    parity_checker.sv
    pe.sv
    router.sv
    global_control.sv
    column_slice.sv
    top_decoder_synth.sv
}

# -------------------------------------------------------------------------
# 3. Elaborate Top Module
# -------------------------------------------------------------------------
set top_module "top_decoder_synth"
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
file mkdir reports

report_timing  > reports/timing.rpt
report_area    > reports/area.rpt
report_power   > reports/power.rpt
report_gates   > reports/gates.rpt
report_qor     > reports/qor.rpt

# -------------------------------------------------------------------------
# 7. Write Output Data
# -------------------------------------------------------------------------
file mkdir outputs

# Write the synthesized netlist
write_hdl > outputs/${top_module}_mapped.v

# Write the constraints used (SDC)
write_sdc > outputs/${top_module}_mapped.sdc

# Write the design database (for later loading into Innovus or Genus)
write_db outputs/${top_module}_mapped.db

puts "Synthesis completed successfully!"
quit
