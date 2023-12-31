# -------------------------------------------------------------------------
# ACE timing constaint file
# Clocks, clock relationships, and IO timing constraints should be set
# in this file
# Clocks are set in the <design_name>_ioring.sdc file
# -------------------------------------------------------------------------

# -------------------------------------------------------------------------
# Example of adding new clocks, (in this example through a GPIO pin)
# -------------------------------------------------------------------------
# Set 500MHz target
# set INCLK_PERIOD 2.0
# create_clock -name gpio_clk [get_ports i_gpio_clk] -period $INCLK_PERIOD

# -------------------------------------------------------------------------
# Example of IO timing constraints
# -------------------------------------------------------------------------
# It is recommended that in_clk and out_clk are virtual clocks, based on the
# IO ports of their respective clocks.  This allows for the clock skew 
# into the device fabric.
# set_input_delay  -clock in_clk  -min  2   [get_ports din\[*\]]
# set_input_delay  -clock in_clk  -max  2.8 [get_ports din\[*\]]
# set_output_delay -clock out_clk -min -0.2 [get_ports dout\[*\]]
# set_output_delay -clock out_clk -max -0.6 [get_ports dout\[*\]]

# -------------------------------------------------------------------------
# Example of defining a generated clock
# -------------------------------------------------------------------------
# create_generated_clock -name clk_gate [ get_pins {i_clkgate/clk_out} ] -source  [get_ports {i_clk} ] -divide_by 1

# -------------------------------------------------------------------------
# Example of setting asynchronous clock groups if more than one clock
# -------------------------------------------------------------------------
# Create a new async clock
# create_clock -name clk_dummy [get_ports i_clk_dummy] -period 1.33

# From example above, the clk_gate is related to clk, 
# but clk_dummy is asynchronous to both
# set_clock_groups -asynchronous -group {clk clk_gate} \
#                                -group {clk_dummy}


# -------------------------------------------------------------------------
# Example of optionally creating clocks based on the build
# -------------------------------------------------------------------------
# Auto detect if snapshot is in the design
# if { [get_ports tck] != "" } { 
#     set use_snapshot 1
# } else {
#     set use_snapshot 0
# }
# if { $use_snapshot==1 } {
#     create_clock -period 100.0 -name tck   [get_ports tck]
#     set_clock_groups -asynchronous -group {tck}
# }

# -------------------------------------------------------------------------
# Primary clock timing constraints defined in IORING sdc files.
# -------------------------------------------------------------------------

# Set i_eth_clk and i_reg_clk as async.
#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
# HOWEVER, must review all paths. Some single bits have synchronization, but some control busses
# and signals into Snapshot are not being synchronized.  This is not a solution for a final design
#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
set_clock_groups -asynchronous -group {i_eth_clk} \
                               -group {i_clk} 
#-------------------------------------------------------------------------
# Snapshot JTAG clock: 25MHz
# ------------------------------------------------------------------------
create_clock -period 40 [get_ports {i_jtag_in[0]}] -name tck
set_clock_groups -asynchronous -group {tck}

