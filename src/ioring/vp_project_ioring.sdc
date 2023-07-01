#######################################
# ACE GENERATED SDC FILE
# Generated on: 2023.06.12 at 14:46:13 PDT
# By: ACE 9.0.1
# From project: vp_project
#######################################
# IO Ring Boundary SDC File
#######################################

# Boundary clocks for ethernet_0
create_clock -period 2.272727272727273 ethernet_0_ref_clk_divby2
# Frequency = 440.0 MHz
set_clock_uncertainty -setup 0.022727272727272728 [get_clocks ethernet_0_ref_clk_divby2]

create_clock -period 3.409090909090909 ethernet_0_m0_ff_clk_divby2
# Frequency = 293.3333333333333 MHz
set_clock_uncertainty -setup 0.03409090909090909 [get_clocks ethernet_0_m0_ff_clk_divby2]

create_clock -period 3.409090909090909 ethernet_0_m1_ff_clk_divby2
# Frequency = 293.3333333333333 MHz
set_clock_uncertainty -setup 0.03409090909090909 [get_clocks ethernet_0_m1_ff_clk_divby2]


# Boundary clocks for ethernet_1
create_clock -period 2.272727272727273 ethernet_1_ref_clk_divby2
# Frequency = 440.0 MHz
set_clock_uncertainty -setup 0.022727272727272728 [get_clocks ethernet_1_ref_clk_divby2]

create_clock -period 3.409090909090909 ethernet_1_m0_ff_clk_divby2
# Frequency = 293.3333333333333 MHz
set_clock_uncertainty -setup 0.03409090909090909 [get_clocks ethernet_1_m0_ff_clk_divby2]

create_clock -period 3.409090909090909 ethernet_1_m1_ff_clk_divby2
# Frequency = 293.3333333333333 MHz
set_clock_uncertainty -setup 0.03409090909090909 [get_clocks ethernet_1_m1_ff_clk_divby2]


# Boundary clocks for noc

# Boundary clocks for pll_ddr

# Boundary clocks for pll_eth_sys_ne_0

# Boundary clocks for pll_eth_usr_ne_3
create_clock -period 2.0618556701030926 i_eth_clk
# Frequency = 485.0 MHz
set_clock_uncertainty -setup 0.020618556701030924 [get_clocks i_eth_clk]


# Boundary clocks for pll_gddr_SE

# Boundary clocks for pll_gddr_SW

# Boundary clocks for pll_noc_ne_1
create_clock -period 5.0 i_reg_clk
# Frequency = 200.0 MHz
set_clock_uncertainty -setup 0.05 [get_clocks i_reg_clk]

create_clock -period 2.0 i_eth_ts_clk
# Frequency = 500.0 MHz
set_clock_uncertainty -setup 0.02 [get_clocks i_eth_ts_clk]

create_clock -period 10.0 i_clk
# Frequency = 100.0 MHz
set_clock_uncertainty -setup 0.1 [get_clocks i_clk]


# Boundary clocks for pll_pcie

# Boundary clocks for vp_clkio_ne

# Boundary clocks for vp_clkio_nw

# Boundary clocks for vp_clkio_se

# Boundary clocks for vp_clkio_sw

# Boundary clocks for vp_gpio_n_b0

# Boundary clocks for vp_gpio_n_b1

# Boundary clocks for vp_gpio_n_b2

# Boundary clocks for vp_gpio_s_b0

# Boundary clocks for vp_gpio_s_b1
create_clock -period 100.0 mcio_vio_45_10_clk
# Frequency = 10.0 MHz
set_clock_uncertainty -setup 0.1 [get_clocks mcio_vio_45_10_clk]


# Boundary clocks for vp_gpio_s_b2

# Boundary clocks for vp_pll_nw_2
create_clock -period 3.2 pll_nw_2_ref0_312p5_clk
# Frequency = 312.5 MHz
set_clock_uncertainty -setup 0.032 [get_clocks pll_nw_2_ref0_312p5_clk]


# Boundary clocks for vp_pll_sw_2
create_clock -period 3.2 pll_sw_2_ref1_312p5_clk
# Frequency = 312.5 MHz
set_clock_uncertainty -setup 0.032 [get_clocks pll_sw_2_ref1_312p5_clk]


# Virtual clocks for IO Ring IPs
create_clock -name v_acx_sc_ETH_0_REF_CLK -period 1.1363636363636365
create_clock -name v_acx_sc_ETH_0_M0_FF_CLK -period 1.7045454545454546
create_clock -name v_acx_sc_ETH_0_M1_FF_CLK -period 1.7045454545454546
create_clock -name v_acx_sc_ETH_1_REF_CLK -period 1.1363636363636365
create_clock -name v_acx_sc_ETH_1_M0_FF_CLK -period 1.7045454545454546
create_clock -name v_acx_sc_ETH_1_M1_FF_CLK -period 1.7045454545454546
create_clock -name v_acx_sc_GPIO_H_IOB1_GLB_SER_GEN_CLK -period 100.0

######################################
# End IO Ring Boundary SDC File
######################################
