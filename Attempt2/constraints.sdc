# constraints.sdc
# Standard Design Constraints for top_decoder_synth

# -------------------------------------------------------------------------
# Clock Definition
# -------------------------------------------------------------------------
# Define the main clock 'clk'. 
# Adjust the period (in ns) based on your target technology and performance goals.
# Example: 2.0 ns = 500 MHz
create_clock -name clk -period 2.0 [get_ports clk]

# Set clock uncertainty (jitter, skew)
set_clock_uncertainty 0.1 [get_clocks clk]

# Set clock transition (slew)
set_clock_transition 0.05 [get_clocks clk]

# -------------------------------------------------------------------------
# Input/Output Constraints
# -------------------------------------------------------------------------
# Assume inputs arrive after 20% of the clock period
set input_delay_val [expr 0.2 * 2.0]
# Assume outputs must be stable 20% before the next clock edge
set output_delay_val [expr 0.2 * 2.0]

# Set input delay for all inputs except the clock
set_input_delay $input_delay_val -clock clk [remove_from_collection [all_inputs] [get_ports clk]]

# Set output delay for all outputs
set_output_delay $output_delay_val -clock clk [all_outputs]

# -------------------------------------------------------------------------
# Environment Constraints (Optional but recommended)
# -------------------------------------------------------------------------
# Set a default driving cell for inputs (e.g., a standard buffer from your lib)
# set_driving_cell -lib_cell <YOUR_BUFFER_CELL> [all_inputs]

# Set a default load capacitance on outputs (e.g., 10fF)
set_load 0.010 [all_outputs]

# -------------------------------------------------------------------------
# Optimization Constraints
# -------------------------------------------------------------------------
# Force the synthesizer to push hard for area reduction to leverage the
# resource sharing we implemented.
set_max_area 0
