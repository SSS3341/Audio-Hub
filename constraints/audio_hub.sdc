# Placeholder SDC. Replace clock names and periods with SoC integration values.

create_clock -name pclk -period 10.000 [get_ports pclk]

set_input_delay  1.0 -clock pclk [remove_from_collection [all_inputs] [get_ports {pclk presetn}]]
set_output_delay 1.0 -clock pclk [all_outputs]

# If DWC_i2s adapter is in another clock domain, do not use this single-clock SDC.
# Add CDC synchronizers/async FIFOs and declare async clock groups.
