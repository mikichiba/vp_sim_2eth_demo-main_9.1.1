# -------------------------------------------------------------------------
# Synplify timing constaint file
# All clocks and clock relationships should be defined in this file for synthesis
# Note : There are small differences between Synplify Pro and ACE SDC syntax
# therefore it is not recommended to use the same file for both, instead to
# have two separate files.
# -------------------------------------------------------------------------

# -------------------------------------------------------------------------
# Primary clock timing constraints
# -------------------------------------------------------------------------

# Set 100MHz target for i_clk
set I_CLK_PERIOD 10.00
create_clock [get_ports i_clk]        -period $I_CLK_PERIOD

# Set 485MHz target for i_eth_clk
create_clock [get_ports i_eth_clk]    -period 2.061
# Set 200MHz target for i_reg_clk
create_clock [get_ports i_reg_clk]    -period 5
# Set 500MHz target for i_eth_ts_clk
create_clock [get_ports i_eth_ts_clk] -period 2

# Set i_eth_clk and i_reg_clk as async.
#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
# HOWEVER, must review all paths. Some single bits have synchronization, but some control busses
# and signals into Snapshot are not being synchronized.  This is not a solution for a final design
#!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
set_clock_groups -asynchronous -group {i_eth_clk} \
                               -group {i_reg_clk} 

# Set 400MHz target for NAP clock
# set NAP_CLK_PERIOD 2.500
# create_clock -name nap_clk [get_ports i_nap_clk] -period $NAP_CLK_PERIOD

# Set 200MHz target for reg clock
# set REG_CLK_PERIOD 5.000
# create_clock -name reg_clk [get_ports i_reg_clk] -period $REG_CLK_PERIOD

# Set 500MHz target for pcie_ts clock
# set TS_CLK_PERIOD 2.000
# create_clock -name pcie_ts_clk [get_ports i_pcie_ts_clk] -period $TS_CLK_PERIOD

# -------------------------------------------------------------------------
# Example of defining a generated clock
# -------------------------------------------------------------------------
# create_generated_clock -name clk_gate [ get_pins {i_clkgate/clk_out} ] -source  [get_ports {i_clk} ] -divide_by 1

# -------------------------------------------------------------------------
# Design has two async clocks.  Actually synchronous, but treat as async
# -------------------------------------------------------------------------
# set_clock_groups -asynchronous -group {nap_clk} \
#                               -group {reg_clk} \
#                               -group {pcie_ts_clk}
