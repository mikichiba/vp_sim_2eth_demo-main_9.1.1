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
// Achronix Ethernet Node
//      Combines an Ethernet NAP with the traffic shaper, to give a
//      single entity that can be used for Ethernet traffic
// ------------------------------------------------------------------

`include "ethernet_utils.svh"

module ACX_ETHERNET_NODE #( 
    // Configuration parameters.  These must be set to a value
    parameter               tx_enable           = 1'hx,
    parameter               rx_enable           = 1'hx,
    parameter [3:0]         tx_mode             = 4'hx,
    parameter [3:0]         rx_mode             = 4'hx,
    parameter [1:0]         tx_mac_id           = 2'hx,
    parameter [1:0]         rx_mac_id           = 2'hx,
    parameter [4:0]         tx_eiu_channel      = 5'hx,
    parameter [4:0]         rx_eiu_channel      = 5'hx,
    parameter [31:0]        tx_threshold        = 32'hxxxx_xxxx,
    parameter [31:0]        rx_threshold        = 32'hxxxx_xxxx,
    parameter real          nap_tx_frequency    = 507.0,
    parameter integer       fcs_length          = 4         // Default is for MAC to add and remove FCS
                                                            // If fabric is adding and removing FCS, set this to 0 in the instantiation
)
(
    input  wire             clk,
    input  wire             rstn,
    output wire             output_rstn,

    // TX port
    output logic            tx_ready,
    output logic            ts_enable,
    input  wire             tx_valid,
    input  wire             tx_sop,
    input  wire             tx_eop,
    input  wire [293 -1:0]  tx_data,
    input  wire [4   -1:0]  tx_dest,

    // RX port
    input  wire             rx_ready,
    output logic            rx_valid,
    output logic            rx_sop,
    output logic            rx_eop,
    output logic [293 -1:0] rx_data,
    output logic [4   -1:0] rx_src
);

    logic                   nap_tx_valid;
    logic                   nap_tx_ready;
    logic                   nap_tx_sop;
    logic                   nap_tx_eop;
    logic [255:0]           nap_tx_data;
    logic [31:0]            nap_tx_flags;   // Field is 32-bits, only 30 bits is used.
    logic [4:0]             nap_tx_mod;

    logic                   nap_rx_valid;
    logic                   nap_rx_sop;
    logic                   nap_rx_eop;
    logic [292:0]           nap_rx_data;
    logic [31:0]            nap_rx_flags;
    logic [4:0]             nap_rx_mod;
    logic                   nap_rx_ready;
    logic [3:0]             nap_rx_src;

    localparam real         TX_EQUIVALENT_FREQUENCY = (tx_mode == `ACX_ETH_MODE_10G) ? (10000.0/256.0) :
                                                      (tx_mode == `ACX_ETH_MODE_25G) ? (25000.0/256.0) :
                                                      (tx_mode == `ACX_ETH_MODE_40G) ? (40000.0/256.0) :
                                                      (tx_mode == `ACX_ETH_MODE_50G) ? (50000.0/256.0) : 
                                                                                       (100000.0/256.0) ;

    // Future enhancements.
    // 10G & 25G can use an IPG=5.  50G+ can use IPG=1.  Current programming leaves IPG=12.
    // The programming would need to set a lower IPG, at which point these values could be lowered.
    localparam integer IPG_LENGTH = (tx_mode == `ACX_ETH_MODE_10G) ? 12 :
                                    (tx_mode == `ACX_ETH_MODE_25G) ? 12 :
                                    (tx_mode == `ACX_ETH_MODE_40G) ? 12 :
                                    (tx_mode == `ACX_ETH_MODE_50G) ? 12 : 
                                                                     12 ;
 
    // Receive signal selection
    always_comb
    begin
        if (rx_enable)
        begin         
            nap_rx_ready = rx_ready;

            rx_valid     = nap_rx_valid;
            rx_data      = nap_rx_data;
            rx_sop       = nap_rx_sop;
            rx_eop       = nap_rx_eop;
            rx_src       = nap_rx_src;
        end // if (rx_enable)
        else
        begin
            rx_valid       = 'h0;
            rx_data        = 'h0;
            rx_sop         = 'h0;
            rx_eop         = 'h0;
            rx_src         = 'h0;
            nap_rx_ready   = 1'b0;  // Should be 0 as this block is now disabled from receiving.
            // synthesis synthesis_off 
            if (nap_rx_valid) begin
                $error ("Instance \" %m \" is not configured to receive date on its rx channel");    
            end
            // synthesis synthesis_on 

        end // else: !if(rx_enable)
    end // always_comb
   


   // Generate and instantiate the ACX_ETHERNET_SHAPER and tx path assignments 
   generate if (tx_enable == 1'b1) begin : gb_tx_shaper 

        // If TX_MODE is 100G or lower data rates, then need the traffic shaper.
        // For 400G pkt mode, need traffic shaper to keep each nap under 100G
        if ( tx_mode != `ACX_ETH_MODE_400G_QSI)
        begin
            acx_ethernet_traffic_shaper #(
                .DATA_WIDTH                 (256),
                .TX_EQUIVALENT_FREQUENCY    (TX_EQUIVALENT_FREQUENCY),
                .NAP_TX_FREQUENCY           (nap_tx_frequency),
                .IPG_LENGTH                 (IPG_LENGTH),
                .FCS_LENGTH                 (fcs_length)
            ) u_shaper (
                .clk                (clk),
                .rstn               (rstn),

                .in_ready           (tx_ready),
                .ts_enable          (ts_enable),
                .in_valid           (tx_valid),
                .in_sop             (tx_sop),
                .in_eop             (tx_eop),
                .in_data            (tx_data[255:0]),
                .in_mod             (tx_data[260:256]),
                .in_data_extra      (tx_data[292:261]),

                .out_ready          (nap_tx_ready),
                .out_valid          (nap_tx_valid),
                .out_sop            (nap_tx_sop),
                .out_eop            (nap_tx_eop),
                .out_mod            (nap_tx_mod),
                .out_data           (nap_tx_data),
                .out_data_extra     (nap_tx_flags)
            );
        end // if (TX_MODE <= `ACX_ETH_MODE_100G)

        else
        begin
            // For higher rates, do not instantiate shaper, connect directly.
            assign nap_tx_valid = tx_valid;
            assign nap_tx_sop   = tx_sop;
            assign nap_tx_eop   = tx_eop;
            assign nap_tx_data  = tx_data[255:0];
            assign nap_tx_mod   = tx_data[260:256];
            assign nap_tx_flags = tx_data[292:261];
            assign tx_ready     = nap_tx_ready;
            assign ts_enable    = 1'b1;
        end // else: !if(tx_mode < 4'h5)
    end     // if (tx_enable == 1'b1)
    else
    begin   // !if(tx_enable == 1'b1)
        assign nap_tx_valid = 1'h0;
        assign nap_tx_sop   = 1'h0;
        assign nap_tx_eop   = 1'h0;
        assign nap_tx_mod   = 5'h0;
        assign nap_tx_data  = 256'h0;
        assign nap_tx_flags = 32'h0;
        assign tx_ready     = 1'b0;
        assign ts_enable    = 1'b0;
    end // else: !if(tx_enable == 1'b1)
    endgenerate
   

    // Instantiate NAP_ETHERNET primitive
    ACX_NAP_ETHERNET #(
        .must_keep      (1),
        .tx_enable      (tx_enable),
        .tx_mode        (tx_mode),
        .tx_mac_id      (tx_mac_id),
        .tx_eiu_channel (tx_eiu_channel),
        .tx_threshold   (tx_threshold),
        .rx_enable      (rx_enable),
        .rx_mode        (rx_mode),
        .rx_mac_id      (rx_mac_id),
        .rx_eiu_channel (rx_eiu_channel),
        .rx_threshold   (rx_threshold)              
    ) u_nap_ethernet (
        .clk            (clk),
        .rstn           (rstn),
        .output_rstn    (output_rstn),

        .rx_ready       (nap_rx_ready),
        .rx_valid       (nap_rx_valid),
        .rx_sop         (nap_rx_sop),
        .rx_eop         (nap_rx_eop),
        .rx_data        (nap_rx_data),
        .rx_src         (nap_rx_src),   // RX source will always 'hF, as EIU is top of the Ethernet column

        .tx_ready       (nap_tx_ready),
        .tx_valid       (nap_tx_valid),
        .tx_sop         (nap_tx_sop),
        .tx_eop         (nap_tx_eop),
        .tx_dest        (tx_dest),      // TX destination must be set to 'hF, as EIU is top of the Ethernet column
        .tx_data        ({nap_tx_flags,nap_tx_mod,nap_tx_data})
        ) /* synthesis syn_noprune=1 */;
   

endmodule : ACX_ETHERNET_NODE 

