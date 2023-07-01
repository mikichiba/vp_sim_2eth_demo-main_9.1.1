//=========================================================================================================
// This is an example/tutorial project that demonstrates two modules communicating over the NoC via "data-
// streaming".  There is a separate example that demonstrates two modules communicating over the NoC via
// AXI4.  "Data streaming" over the NoC is very similar to the way an AXI4-Stream works.
//
// This example also demonstrates the use of the Snapshot debugger
//
// In this example:
//
// The "sender" module is responsible for periodically sending 8-bit wide messages to the "ethnet" module.
// The "ethnet" module will use those 8-bit messages to drive the LEDs on the VectorPath.
//
// Unlike AXI, when two modules communicate via "Data Streaming", their NAPs (i.e., Network Access Points) 
// must be either in the same vertical column of the NoC or in the same horizontal row of the Noc.  In 
// this example, we will place them in the same vertical row.
//
// For reference:
//   NoC rows are numbered 1 thru 8, moving from south-to-north.
//   NoC columns are numbered 1 thru 10, moving west-to-east
//
// For more information about instantiating NAPs (Network Access Points), see:
//   "Achronix Speedster7t Component Library Users Guide (UG086)"
//
// For more information about instantiating the Snapshot debugger, see:
//    "Snapshot User's Guide (UG016)"
//
//=========================================================================================================


//=========================================================================================================
//                                       I M P O R T A N T
//
// Any design that uses a Snapshot debugger must define the 25 MHz JTAG clock in the user-constraints file.
//
// An example of that clock declaration is below.
//
// The user-constraints file is (in this example project) called "ace_constraints.sdc"
//=========================================================================================================
/*

#-------------------------------------------------------------------------
# Snapshot JTAG clock: 25MHz
# ------------------------------------------------------------------------
create_clock -period 40 [get_ports {i_jtag_in[0]}] -name tck
set_clock_groups -asynchronous -group {tck}

*/
//=========================================================================================================

// Any design that uses a NAP (Network Access Point) must include this file
`include "nap_interfaces.svh"

// Any design that uses an Ethernet NAP, nap_ethernet_wrapper, or ACX_ETHERNET_NODE must include this file.
`include "ethernet_utils.svh"

// Any design that includes a Snapshot debugger must include this file
`include "speedster7t/common/speedster7t_snapshot_v3.sv"

module project_top
( 
    input wire i_clk,                 // 100MHz clock used in LED reference design. Not used in simple Ethernet design
    input wire i_eth_clk,             // 485MHz Ethernet system clock

    input wire i_reg_clk,             // 200MHz register clock used for Ethernet design
    input wire i_eth_ts_clk,          // 500MHz Ethernet timestamp clock. Not connected in this design as of 5/24/23
    input wire pll_ddr_lock,
    input wire pll_eth_sys_ne_0_lock,
    input wire pll_eth_usr_ne_3_lock,
    input wire pll_gddr_SE_lock,
    input wire pll_gddr_SW_lock,
    input wire pll_noc_ne_1_lock,
    input wire pll_pcie_lock,

    // These are the JTAG interfaces for the Snapshot debugger
    input  wire t_JTAG_INPUT   i_jtag_in,
    output wire t_JTAG_OUTPUT  o_jtag_out,

    // Ethernet 0

    // Ethernet ff divided clocks (unused)
    input  wire                         ethernet_0_m0_ff_clk_divby2,
    input  wire                         ethernet_0_m1_ff_clk_divby2,
    input  wire                         ethernet_0_ref_clk_divby2,

    // Ethernet MAC flow control signals
    // emac is Express MAC
    // Quad MAC 0 flow control (unused)
    input  wire  [3:0]                  ethernet_0_quad0_emac_enable,
    input  wire  [3:0]                  ethernet_0_quad0_emac_pause_en,
    input  wire  [31:0]                 ethernet_0_quad0_emac_pause_on,
    output wire  [31:0]                 ethernet_0_quad0_emac_xoff_gen,
    output wire  [3:0]                  ethernet_0_quad0_lpi_txhold,
    output wire  [3:0]                  ethernet_0_quad0_mac_stop_tx,
    output wire  [3:0]                  ethernet_0_quad0_tx_hold_req,

    // Quad MAC 0 Status (unused)
    input  wire  [3:0]                  ethernet_0_m0_ffe_tx_ovr,
    input  wire  [3:0]                  ethernet_0_m0_ffp_tx_ovr,
    input  wire  [3:0]                  ethernet_0_m0_mac_tx_underflow,

    // Ethernet 1

    // Ethernet ff divided clocks (unused)
    input  wire                         ethernet_1_m0_ff_clk_divby2,
    input  wire                         ethernet_1_m1_ff_clk_divby2,
    input  wire                         ethernet_1_ref_clk_divby2,

    // Ethernet MAC flow control signals
    // emac is Express MAC
    // Quad MAC 0 flow control (unused)
    input  wire  [3:0]                  ethernet_1_quad0_emac_enable,
    input  wire  [3:0]                  ethernet_1_quad0_emac_pause_en,
    input  wire  [31:0]                 ethernet_1_quad0_emac_pause_on,
    output wire  [31:0]                 ethernet_1_quad0_emac_xoff_gen,
    output wire  [3:0]                  ethernet_1_quad0_lpi_txhold,
    output wire  [3:0]                  ethernet_1_quad0_mac_stop_tx,
    output wire  [3:0]                  ethernet_1_quad0_tx_hold_req,

    // Quad MAC 0 Status (unused)
    input  wire  [3:0]                  ethernet_1_m0_ffe_tx_ovr,
    input  wire  [3:0]                  ethernet_1_m0_ffp_tx_ovr,
    input  wire  [3:0]                  ethernet_1_m0_mac_tx_underflow,

    // This must be included in the port-list of any VectorPath project
    `include "vectorpath_rev1_port_list.svh"
);

    // Drive ethernet unused outputs
    assign ethernet_0_quad0_emac_xoff_gen = 'h0;
    assign ethernet_0_quad0_lpi_txhold    = 'h0;
    assign ethernet_0_quad0_mac_stop_tx   = 'h0;
    assign ethernet_0_quad0_tx_hold_req   = 'h0;

    assign ethernet_1_quad0_emac_xoff_gen = 'h0;
    assign ethernet_1_quad0_lpi_txhold    = 'h0;
    assign ethernet_1_quad0_mac_stop_tx   = 'h0;
    assign ethernet_1_quad0_tx_hold_req   = 'h0;

    //-----------------------------------------------------------------------------------------------------
    // The system reset manager - Generates the active-low "resetn" signal
    //-----------------------------------------------------------------------------------------------------
    wire stimuli_valid  /* synthesis syn_keep=1 */;
    wire do_reset       /* synthesis syn_keep=1 */;
    wire resetn         /* synthesis syn_keep=1 */;
    sys_reset_mgr i_sys_reset_mgr
    (
        .clk            (i_eth_clk),
        .stimuli_valid  (stimuli_valid),
        .do_reset       (do_reset),
        .resetn         (resetn)
    );
    //-----------------------------------------------------------------------------------------------------

    //-----------------------------------------------------------------------------------------------------
    // This block simply counts clock-cycles.   It's convenient to display this in the Snapshot GUI.
    //-----------------------------------------------------------------------------------------------------
    reg[15:0] clock_cycle;
    always @(posedge i_eth_clk) begin
        if (resetn == 0)
            clock_cycle <= 0;
        else
            clock_cycle <= clock_cycle + 1;
    end
    //-----------------------------------------------------------------------------------------------------


    // Create handy constants that define the size of the NAP (Network Access Point) signals
    // Defined in nap_interfaces.svh
    localparam NAP_H_DATA_WIDTH = `ACX_NAP_HORIZONTAL_DATA_WIDTH;
    localparam NAP_V_DATA_WIDTH = `ACX_NAP_VERTICAL_DATA_WIDTH;
    localparam NAP_ADDR_WIDTH   = `ACX_NAP_DS_ADDR_WIDTH;

    // Device     | Ethernet Subsystem
    //-----------------------------------
    //            |    0     |    1     |
    // ACT7t1500  | Cols 1,2 | Cols 4&5 |
    //-----------------------------------
    // VP card has QSFPDD conected to Ethernet Subsystem 1, 8 channels
    // VP card has QSFP56 conected to Ethernet Subsystem 0, 4 channels
    // Ethernet TX/RX traffic will connect to column 4 of the NOC for Ethernet subsystem 1 and column 1 for Ethernet subssytem 0    

    // Create the ethernet-stream interfaces that the ACX_ETHERNET_NODE will use to talk to its NAP
    t_ETH_STREAM  iface_ethnet0_rx() /* synthesis syn_keep=1 */;
    t_ETH_STREAM  iface_ethnet0_tx() /* synthesis syn_keep=1 */;
    t_ETH_STREAM  iface_ethnet1_rx() /* synthesis syn_keep=1 */;
    t_ETH_STREAM  iface_ethnet1_tx() /* synthesis syn_keep=1 */;

    // No reset input to VectorPath card, so generate a self-starting reset from power up
    // Once the circuit is running, the various blocks have their individual resets controlled from
    // the reg_control_block
    logic [32 -1:0] reset_pipe = 16'h0;
    wire  [5:0] proc_rstn /* synthesis syn_keep=1 */;

    always @(posedge i_eth_clk)
        reset_pipe <= {reset_pipe[$bits(reset_pipe)-2 : 0], 1'b1};


    // Create a reg clock reset
    reset_processor_v3 #(
        .NUM_INPUT_RESETS       (5),    // Five reset sources
        .NUM_OUTPUT_RESETS      (6),    // Eight reset outputs used to fanout to different locations on the FPGA die
        .IN_RST_PIPE_LENGTH     (5),    // Length of input pipelines. Ignored when SYNC_INPUT_RESETS = 0
        .SYNC_INPUT_RESETS      (1),    // Synchronize reset inputs
        .OUT_RST_PIPE_LENGTH    (4),    // Output pipeline length. Ignored when RESET_OVER_CLOCK = 1
        .RESET_OVER_CLOCK       (0)     // Set output to be reset over the clock network
    ) i_reset_processor_reg (
        .i_rstn_array       ({reset_pipe[$bits(reset_pipe)-1], pll_eth_usr_ne_3_lock, pll_eth_sys_ne_0_lock, pll_noc_ne_1_lock, resetn}),
        .i_clk              (i_eth_clk),
        .o_rstn             (proc_rstn)
    );

 
    //--------------------------------------------------------------------
    // SS valid signal gates when SS stimulus has settled
    //--------------------------------------------------------------------
    // Do not synchronize the other values as they will be set and static
    // before enable and start are issued
    // Status signals will be static at the time they are read, so CDC not required for them.
    wire  SS_tx_enable                 /* synthesis syn_keep=1 */; // Stimulus from SnapShot
    wire  SS_tx_id                     /* synthesis syn_keep=1 */; // Stimulus from SnapShot

    wire  [1:0] tx_enable                    /* synthesis syn_keep=1 */;
    logic [1:0] tx_enable_valid              /* synthesis syn_preserve=1 */;
    wire  [1:0] tx_id                        /* synthesis syn_keep=1 */;
    logic [1:0] tx_id_valid                  /* synthesis syn_preserve=1 */;

    // Bring in signals from SS only when stimuli_valid is high  
    always @(posedge i_eth_clk) begin
      if (resetn == 1'b0) begin
        tx_enable_valid <= 0;
        tx_id_valid     <= 0;
      end else begin
        tx_enable_valid     <= tx_enable_valid;  
        tx_id_valid         <= tx_id_valid;  
        if (stimuli_valid == 1'b1) begin
          tx_enable_valid   <= {2{SS_tx_enable}};
          tx_id_valid       <= {2{SS_tx_id}};
        end
      end
    end

    // Synchronize from control register to eth_clk

    // Have pipelines as signals have to go to top and bottom of column
    // Preserve through synthesis so ACE can then look to use for layout
    shift_reg #(.LENGTH (3), .WIDTH (1)) x_shift_tx_enable0 (
                .i_clk (i_eth_clk), .i_rstn (1'b1), .i_din (tx_enable_valid[0]),     .o_dout (tx_enable[0]) );
    shift_reg #(.LENGTH (3), .WIDTH (1)) x_shift_tx_id0 (
                .i_clk (i_eth_clk), .i_rstn (1'b1), .i_din (tx_id_valid[0]),         .o_dout (tx_id[0]) );

    shift_reg #(.LENGTH (3), .WIDTH (1)) x_shift_tx_enable1 (
                .i_clk (i_eth_clk), .i_rstn (1'b1), .i_din (tx_enable_valid[1]),     .o_dout (tx_enable[1]) );
    shift_reg #(.LENGTH (3), .WIDTH (1)) x_shift_tx_id1 (
                .i_clk (i_eth_clk), .i_rstn (1'b1), .i_din (tx_id_valid[1]),         .o_dout (tx_id[1]) );

    //--------------------------------------------------------------------
    // Ethernet NAP for channel 0 QSFP-28
    //--------------------------------------------------------------------
    logic ts_enable0;
    logic led_l0;
    nap_ethernet_wrapper #(
        // Arbitration parameters.  
        // Do not assign in RTL.  If needed assign in .pdc
        // Will not be required as single NAP on the column.
        // If these are left at x, then defaults will be used
        // A 32-bit value used to initialize the arbitration schedule mechanism. 
        // Bit 0 of the arbitration schedule vector is used to determine if the local node wins arbitration when there is 
        // competing traffic from the upstream node. If bit 0 has a value of '1', the local traffic wins, while if bit 0 
        // has a value of '0', the upstream node wins. After each cycle where both the local node and the upstream node are 
        // competing for access, the value in the schedule register rotates to the left. A value of 32'h8888_8888 means that 
        // the local node has high priority on every fourth cycle. A value of  32'haaaa_aaaa means that the local 
        // node has high priority on every second cycle.
        // The default value is 32'haaaa_aaaa.  Refer to Speedster7t Component Library User Guide UG086 for more info.

        .N2S_ARB_SCHED          (32'hxxxxxxxx),           // north-to-south arbitration schedule
        .S2N_ARB_SCHED          (32'hxxxxxxxx),           // south-to-north arbitration schedule

        // Configuration parameters.  These must be set to a value
        .TX_ENABLE              (1'b1),                   // Always want to transmit
        .RX_ENABLE              (1'b1),                   // Always want to receive
        .TX_MODE                (`ACX_ETH_MODE_100G),     // Defined in ethernet_utils.svh
        .RX_MODE                (`ACX_ETH_MODE_100G),     // Defined in ethernet_utils.svh
        .TX_MAC_ID              (`ACX_ETH_QUAD0),         // Defined in ethernet_utils.svh 
        .RX_MAC_ID              (`ACX_ETH_QUAD0),         // Defined in ethernet_utils.svh
        .TX_EIU_CHANNEL         (`ACX_ETH_CH_QUAD0_EXP0), // Defined in ethernet_utils.svh
        .RX_EIU_CHANNEL         (`ACX_ETH_CH_QUAD0_EXP0), // Defined in ethernet_utils.svh

        // Threshold values for the EIU buffer channel FIFOs. When the NAP is assigned to a buffering subsystem within the 
        // EIU, traffic from the NAP is transmitted via the EIU TX FIFO. This FIFO has four threshold indicators. The levels 
        // at which each of these indicators are set are determined by the corresponding byte within the four-byte tx_threshold. 
        // If the EIU TX FIFO fill level exceeds a threshold value, the corresponding <ethernet name>_<mac name>_tx_buffer<num>_at_threshold 
        // signal is asserted. For example, for a tx_threshold value of 32'he0c0_8040, the four threshold indicators are 
        // asserted if the TX FIFO level exceeds 0x40, 0x80, 0xc0, and 0xe0 words, respectively.
        // If the NAP is assigned to a pass-through EIU channel, the rx_threshold the value is unused.
        // Refer to Speedster7t Component Library User Guide UG086 for more info.

        .TX_THRESHOLD           (32'h4030_2010),
        .RX_THRESHOLD           (32'h4030_2010),

        .NAP_TX_FREQUENCY       (485.0)                 // Clock frequency of NAP TX clock for traffic shaper. Set to i_eth_clk.
    ) i_nap_eth0 (
        .i_clk                  (i_eth_clk),            // 485MHz Ethernet system clock
        .i_reset_n              (proc_rstn[0]),             // Negative synchronous reset
        .if_eth_tx              (iface_ethnet0_tx),
        .ts_enable              (ts_enable0),
        .if_eth_rx              (iface_ethnet0_rx),
        .o_output_rstn          ()
    );

    sender i_sender0 (
        .clk         (i_eth_clk),
        .resetn      (proc_rstn[1]),
        .enable      (tx_enable[0]),
        .id          (tx_id[0]),
        .dest_addr   (4'hF),
        .tx          (iface_ethnet0_tx)
    );

    logic[255:0] rx0data    /* synthesis syn_keep=1 */;
    logic[3:0]   rx0addr    /* synthesis syn_keep=1 */;
    logic        rx0sop     /* synthesis syn_keep=1 */;
    logic        rx0eop     /* synthesis syn_keep=1 */;
    logic        rx0error   /* synthesis syn_keep=1 */;
    logic[63:0]  rx0counter /* synthesis syn_keep=1 */;

    ethnet i_ethnet0 (
        .clk         (i_eth_clk),
        .resetn      (proc_rstn[2]),
        .leds        (led_l0),
        .rxdata      (rx0data),
        .rxaddr      (rx0addr),
        .rxsop       (rx0sop),
        .rxeop       (rx0eop),
        .error       (rx0error),
        .o_counter   (rx0counter),
        .rx          (iface_ethnet0_rx)
    );

    //--------------------------------------------------------------------
    // Ethernet NAP for channel 1 QSFP-DD
    //--------------------------------------------------------------------
    logic ts_enable1;
    logic led_l1;
    nap_ethernet_wrapper #(
        // Arbitration parameters.  
        // Do not assign in RTL.  If needed assign in .pdc
        // Will not be required as single NAP on the column.
        // If these are left at x, then defaults will be used
        // A 32-bit value used to initialize the arbitration schedule mechanism. 
        // Bit 0 of the arbitration schedule vector is used to determine if the local node wins arbitration when there is 
        // competing traffic from the upstream node. If bit 0 has a value of '1', the local traffic wins, while if bit 0 
        // has a value of '0', the upstream node wins. After each cycle where both the local node and the upstream node are 
        // competing for access, the value in the schedule register rotates to the left. A value of 32'h8888_8888 means that 
        // the local node has high priority on every fourth cycle. A value of  32'haaaa_aaaa means that the local 
        // node has high priority on every second cycle.
        // The default value is 32'haaaa_aaaa.  Refer to Speedster7t Component Library User Guide UG086 for more info.

        .N2S_ARB_SCHED          (32'hxxxxxxxx),           // north-to-south arbitration schedule
        .S2N_ARB_SCHED          (32'hxxxxxxxx),           // south-to-north arbitration schedule

        // Configuration parameters.  These must be set to a value
        .TX_ENABLE              (1'b1),                   // Always want to transmit
        .RX_ENABLE              (1'b1),                   // Always want to receive
        .TX_MODE                (`ACX_ETH_MODE_100G),     // Defined in ethernet_utils.svh
        .RX_MODE                (`ACX_ETH_MODE_100G),     // Defined in ethernet_utils.svh
        .TX_MAC_ID              (`ACX_ETH_QUAD0),         // Defined in ethernet_utils.svh 
        .RX_MAC_ID              (`ACX_ETH_QUAD0),         // Defined in ethernet_utils.svh
        .TX_EIU_CHANNEL         (`ACX_ETH_CH_QUAD0_EXP0), // Defined in ethernet_utils.svh
        .RX_EIU_CHANNEL         (`ACX_ETH_CH_QUAD0_EXP0), // Defined in ethernet_utils.svh

        // Threshold values for the EIU buffer channel FIFOs. When the NAP is assigned to a buffering subsystem within the 
        // EIU, traffic from the NAP is transmitted via the EIU TX FIFO. This FIFO has four threshold indicators. The levels 
        // at which each of these indicators are set are determined by the corresponding byte within the four-byte tx_threshold. 
        // If the EIU TX FIFO fill level exceeds a threshold value, the corresponding <ethernet name>_<mac name>_tx_buffer<num>_at_threshold 
        // signal is asserted. For example, for a tx_threshold value of 32'he0c0_8040, the four threshold indicators are 
        // asserted if the TX FIFO level exceeds 0x40, 0x80, 0xc0, and 0xe0 words, respectively.
        // If the NAP is assigned to a pass-through EIU channel, the rx_threshold the value is unused.
        // Refer to Speedster7t Component Library User Guide UG086 for more info.

        .TX_THRESHOLD           (32'h4030_2010),
        .RX_THRESHOLD           (32'h4030_2010),

        .NAP_TX_FREQUENCY       (485.0)                 // Clock frequency of NAP TX clock for traffic shaper. Set to i_eth_clk.
    ) i_nap_eth1 (
        .i_clk                  (i_eth_clk),            // 485MHz Ethernet system clock
        .i_reset_n              (proc_rstn[3]),             // Negative synchronous reset
        .if_eth_tx              (iface_ethnet1_tx),
        .ts_enable              (ts_enable1),
        .if_eth_rx              (iface_ethnet1_rx),
        .o_output_rstn          ()
    );

    sender i_sender1 (
        .clk         (i_eth_clk),
        .resetn      (proc_rstn[4]),
        .enable      (tx_enable[1]),
        .id          (tx_id[1]),
        .dest_addr   (4'hF),
        .tx          (iface_ethnet1_tx)
    );

    logic[255:0] rx1data    /* synthesis syn_keep=1 */;
    logic[3:0]   rx1addr    /* synthesis syn_keep=1 */;
    logic        rx1sop     /* synthesis syn_keep=1 */;
    logic        rx1eop     /* synthesis syn_keep=1 */;
    logic        rx1error   /* synthesis syn_keep=1 */;
    logic[63:0]  rx1counter /* synthesis syn_keep=1 */;

    ethnet i_ethnet1 (
        .clk         (i_eth_clk),
        .resetn      (proc_rstn[5]),
        .leds        (led_l1),
        .rxdata      (rx1data),
        .rxaddr      (rx1addr),
        .rxsop       (rx1sop),
        .rxeop       (rx1eop),
        .error       (rx1error),
        .o_counter   (rx1counter),
        .rx          (iface_ethnet1_rx)
    );

    //-----------------------------------------------------------------------------------------------------
    // From here down is the Snapshot debugger
    //-----------------------------------------------------------------------------------------------------
    localparam integer MONITOR_WIDTH = 256;  
    localparam integer MONITOR_DEPTH = 1024; 
    
    // The Snapshot IP allows a maximum of 40 triggers.
    localparam TRIGGER_WIDTH = MONITOR_WIDTH < 40? MONITOR_WIDTH : 40;

    // Create a bus wide enough to hold all of the signals we want to monitor
    wire [MONITOR_WIDTH-1 : 0] monitor;

    // This will go high when the user presses the "Arm" button in the GUI
    wire arm;

    // This is a list of all the waveforms we want to capture and display in the debugger
    assign monitor =
    {
        arm,

        clock_cycle,

        iface_ethnet1_tx.valid,
        iface_ethnet1_tx.sop,
        iface_ethnet1_tx.eop,
        iface_ethnet1_tx.ready,
        iface_ethnet1_tx.flags.tx.force_error,

        iface_ethnet0_tx.data[64],
        iface_ethnet0_tx.data[63:0],
        iface_ethnet0_tx.valid,
        iface_ethnet0_tx.sop,
        iface_ethnet0_tx.eop,
        iface_ethnet0_tx.ready,
        iface_ethnet0_tx.flags.tx.force_error,

        rx0data[64],
        rx0data[63:0],
        rx0counter,

        iface_ethnet1_rx.valid,
        rx1error,
        rx1sop,
        rx1eop,
        iface_ethnet1_rx.ready,
        iface_ethnet1_rx.flags.rx.transmit_error,
        iface_ethnet1_rx.flags.rx.short_frame,
        iface_ethnet1_rx.flags.rx.fifo_overflow,
        iface_ethnet1_rx.flags.rx.decode_error,
        iface_ethnet1_rx.flags.rx.crc_error,
        iface_ethnet1_rx.flags.rx.length_error,
        iface_ethnet1_rx.flags.rx.error,

        iface_ethnet0_rx.valid,
        rx0error,
        rx0sop,
        rx0eop,
        iface_ethnet0_rx.ready,
        iface_ethnet0_rx.flags.rx.transmit_error,
        iface_ethnet0_rx.flags.rx.short_frame,
        iface_ethnet0_rx.flags.rx.fifo_overflow,
        iface_ethnet0_rx.flags.rx.decode_error,
        iface_ethnet0_rx.flags.rx.crc_error,
        iface_ethnet0_rx.flags.rx.length_error,
        iface_ethnet0_rx.flags.rx.error,

        proc_rstn[0],
        resetn       
    };

    // Declare the various stimuli that can arrive from the GUI
    localparam STIMULI_WIDTH = 3;
    wire [STIMULI_WIDTH-1 : 0] stimuli;
    assign SS_tx_id         = stimuli[2];
    assign SS_tx_enable     = stimuli[1];
    assign do_reset         = stimuli[0];

    ACX_SNAPSHOT #
    (
        .DUT_NAME           ("snapshot_example"),
        .MONITOR_WIDTH      (MONITOR_WIDTH),    // 1..4080
        .MONITOR_DEPTH      (MONITOR_DEPTH),    // 1..16384
        .TRIGGER_WIDTH      (TRIGGER_WIDTH),    // 1..40
        .STANDARD_TRIGGERS  (1),                // use i_monitor[39:0] as trigger input
        .STIMULI_WIDTH      (STIMULI_WIDTH),    // 0..512
        .INPUT_PIPELINING   (3),                // for i_monitor and i_trigger
        .OUTPUT_PIPELINING  (0),                // for o_stimuli(_valid) and o_arm
        .ARM_DELAY          (2)                 // between o_stimuli_valid and o_arm
    )
    debugger_ethernet
    (
      .i_jtag_in        (i_jtag_in),
      .o_jtag_out       (o_jtag_out),
      .i_user_clk       (i_eth_clk),
      .i_monitor        (monitor),
      .i_trigger        (), 
      .o_stimuli        (stimuli),
      .o_stimuli_valid  (stimuli_valid),
      .o_arm            (arm),
      .o_trigger        ()
    );
    //-----------------------------------------------------------------------------------------------------

    assign led_l = led_l1 ^ led_l0;

    // Turn on the output-enables for each LED
    assign led_l_oe = 8'hff; 

    // Turn on the output-enable for the pin that drives the LED level-shifter
    assign led_oe_l_oe = 1'b1;   
    
    // That level shifter is active-low.  Active = "drives current to the LEDs"
    assign led_oe_l = 1'b0;

endmodule
