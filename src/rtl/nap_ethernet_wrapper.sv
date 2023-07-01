// ------------------------------------------------------------------
//
// Copyright (c) 2021 Achronix Semiconductor Corp.
// All Rights Reserved.
//
// This Software constitutes an unpublished work and contains
// valuable proprietary information and trade secrets belonging
// to Achronix Semiconductor Corp.
//
// Permission is hereby granted to use this Software including
// without limitation the right to copy, modify, merge or distribute
// copies of the software subject to the following condition:
//
// The above copyright notice and this permission notice shall
// be included in in all copies of the Software.
//
// The Software is provided “as is” without warranty of any kind
// expressed or implied, including  but not limited to the warranties
// of merchantability fitness for a particular purpose and non-infringement.
// In no event shall the copyright holder be liable for any claim,
// damages, or other liability for any damages or other liability,
// whether an action of contract, tort or otherwise, arising from, 
// out of, or in connection with the Software
//
// ------------------------------------------------------------------
// Wrapper around an ETHERNET NAP to convert IO to an Ethernet
// SystemVerilog interface
// ------------------------------------------------------------------

`include "nap_interfaces.svh"

module nap_ethernet_wrapper
#(
    // Arbitration parameters.  If these are left at x, then defaults will be used
    // Normally set in pdc file as related to placement.  Retained for single or dual NAP implementations
    parameter N2S_ARB_SCHED             = 32'hxxxxxxxx, // north-to-south arbitration schedule
    parameter S2N_ARB_SCHED             = 32'hxxxxxxxx, // south-to-north arbitration schedule

    // Configuration parameters.  These must be set to a value
    parameter        TX_ENABLE          = 1'hx,
    parameter        RX_ENABLE          = 1'hx,
    parameter [3:0]  TX_MODE            = 4'hx,
    parameter [3:0]  RX_MODE            = 4'hx,
    parameter [1:0]  TX_MAC_ID          = 2'hx,
    parameter [1:0]  RX_MAC_ID          = 2'hx,
    parameter [4:0]  TX_EIU_CHANNEL     = 5'hx,
    parameter [4:0]  RX_EIU_CHANNEL     = 5'hx,
    parameter [31:0] TX_THRESHOLD       = 32'hxxxx_xxxx,
    parameter [31:0] RX_THRESHOLD       = 32'hxxxx_xxxx,
    parameter real   NAP_TX_FREQUENCY   = 507.0,
    parameter        FCS_LENGTH         = 4                 // Default is for MAC to add and remove FCS
                                                            // If fabric is adding and removing FCS, set this to 0 in the instantiation

)
(
    // Inputs
    input wire          i_clk,
    input wire          i_reset_n,          // Negative synchronous reset
    // Modport types are swapped here compared to names
    // This is because the NAP rx channel is data received from the NoC,
    // hence it has to be a transmitter from the NAP
    // The stream names are then correct from the perspective of the user design
    t_ETH_STREAM.rx     if_eth_tx,          // Ethernet stream to transmit to NoC, (NAP receives data)
    output wire         ts_enable,          // Traffic shaper ready to transmit
    t_ETH_STREAM.tx     if_eth_rx,          // Ethernet stream to receive from NoC, (NAP transmits data)
    input wire          i_flow_control_add, // Insert addition data from traffic shaper
    output wire         o_output_rstn
);

    // Vertical NAP data width is 293 bits.
    // Composed of data=256, mod=5, flags=30, spare=2
    logic [`ACX_NAP_VERTICAL_DATA_WIDTH -1:0] if_eth_tx_data;
    logic [`ACX_NAP_ETH_FLAG_WIDTH      -1:0] if_eth_tx_flags;
    logic [2                            -1:0] if_eth_tx_spare = 2'b00;
    logic [`ACX_NAP_VERTICAL_DATA_WIDTH -1:0] if_eth_rx_data;
    logic [`ACX_NAP_ETH_FLAG_WIDTH      -1:0] if_eth_rx_flags;
    logic [2                            -1:0] if_eth_rx_spare;

    // Assign elements to concatenated data buses
    assign if_eth_tx_data = {if_eth_tx_spare, if_eth_tx_flags, if_eth_tx.mod, if_eth_tx.data};
    assign {if_eth_rx_spare, if_eth_rx_flags, if_eth_rx.mod, if_eth_rx.data} = if_eth_rx_data;

    // Default EIU destination is row 0xf.
    // Ignore the address assignment input to this wrapper
    logic [`ACX_NAP_DS_ADDR_WIDTH -1:0] if_eth_tx_addr;
    assign if_eth_tx_addr = `ACX_NAP_DS_ADDR_WIDTH'hf;

    // Instantiate Ethernet NAP and connect ports to SV interface
    // Do not connect the row and column parameters
    // For simulation, the row and column are set by the bind macro
    // For implementation, the row and column are set by the pdc
    // The above two files must match
    ACX_ETHERNET_NODE #(
       .tx_enable           (TX_ENABLE),
       .tx_mode             (TX_MODE),
       .tx_mac_id           (TX_MAC_ID),
       .tx_eiu_channel      (TX_EIU_CHANNEL),
       .tx_threshold        (TX_THRESHOLD),
       .rx_enable           (RX_ENABLE),
       .rx_mode             (RX_MODE),
       .rx_mac_id           (RX_MAC_ID),
       .rx_eiu_channel      (RX_EIU_CHANNEL),
       .rx_threshold        (RX_THRESHOLD),
       .nap_tx_frequency    (NAP_TX_FREQUENCY),
       .fcs_length          (FCS_LENGTH)
   ) i_ethernet_node (
        .clk                (i_clk),
        .rstn               (i_reset_n),

        .output_rstn        (o_output_rstn),
        // rx_ signals are data stream output from NAP
        .rx_ready           (if_eth_rx.ready),
        .rx_valid           (if_eth_rx.valid),
        .rx_sop             (if_eth_rx.sop),
        .rx_eop             (if_eth_rx.eop),
        .rx_data            (if_eth_rx_data),
        .rx_src             (if_eth_rx.addr),
        // tx_ signals are data stream input to NAP
        .ts_enable          (ts_enable),             // Ready to transmit from traffic shaper
        .tx_ready           (if_eth_tx.ready),
        .tx_valid           (if_eth_tx.valid),
        .tx_sop             (if_eth_tx.sop),
        .tx_eop             (if_eth_tx.eop),
        .tx_dest            (if_eth_tx_addr),
        .tx_data            (if_eth_tx_data)
    ) /* synthesis syn_noprune=1 */;


    // Timestamp is valid on SoP cycle, flags are valid on all other cycles
    // Union joins the flags together.  Only one data set, so drive directly from data input
    assign if_eth_rx.flags     = (if_eth_rx.sop) ? `ACX_NAP_ETH_FLAG_WIDTH'b0 : if_eth_rx_flags;
    assign if_eth_rx.timestamp = (if_eth_rx.sop) ? if_eth_rx_flags : `ACX_NAP_ETH_FLAG_WIDTH'b0;

    assign if_eth_tx_flags = (if_eth_tx.sop) ?  if_eth_tx.timestamp : if_eth_tx.flags.tx;

endmodule : nap_ethernet_wrapper
