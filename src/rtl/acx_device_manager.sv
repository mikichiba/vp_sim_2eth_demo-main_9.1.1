//////////////////////////////////////
// ACE GENERATED SYSTEMVERILOG FILE
// Generated on: 2023.06.15 at 10:09:04 PDT
// By:           ACE 9.1
// From file:    ddr4_pcie_eth_vp_demo/src/acxip/acx_device_manager.acxip
// For Property: output.systemverilog_file
//
// IP                  : Speedster7t AC7t1500 Device Manager
// Configuration Name  : acx_device_manager
//

// Set the Verilog included files search path to:
//       $ACE_INSTALL_DIR/libraries
//  Details of setting the search path is given in:
//       $ACE_INSTALL_DIR/libraries/README.pdf
//`include "speedster7t/macros/ACX_DEVICE_MANAGER.svp"
`include "../include/ACX_DEVICE_MANAGER.svp"

//////////////////////////////////////
// Speedster7t AC7t1500 Device Manager Wrapper User Model
//////////////////////////////////////

`timescale 1 ps / 1 ps
module acx_device_manager
  (

   // JTAG Interface

   input wire t_JTAG_INPUT i_jtag_in,             // Should be connected to top-level ports with the same declaration
   input wire i_tdo_bus,             // Pass-through the JTAG bus to connect to Snapshot. If not used, this input should be tied to 1'b0
   output wire t_JTAG_OUTPUT o_jtag_out,            // Should be connected to top-level ports with the same declaration
   output wire t_JTAP_BUS o_jtap_bus,            // Pass-through of the JTAG bus to connect to Snapshot (or other JTAG components)

   // PERSTN and Hot Reset Interface

   input wire [5:0] i_pcie_1_ltssm_state,  // This pin should be exposed for Hot Reset and Gen2 De-emphasis support for the PCIE_1 subsystem.
   input wire i_pcie_1_perstn,       // This pin should be exposed for the AC7t1500ES1, AC7t1550ES1, AC7t1500, and AC7t1550 devices when the PCIe enumeration work-around is required for the PCIE_1 subsystem.  The PCIE_1 PERSTN GPIO input should be connected to the exposed i_pcie_1_perstn pin.
   output wire o_pcie_1_irq_to_avr,   // This pin should be exposed for Hot Reset support for the PCIE_1 subsystem.

   // User Design

   input wire i_clk,                 // 100 MHz Clock input for Device Manager block.
   input wire i_start,               // A high input starts the Device Manager. In most cases this signal is simply tied to 1'b1, but it can also be tied to a PLL lock signal if necessary.
   output wire [31:0] o_status,               // Progress indication, error status, alarms
   output wire [63:0] o_serdes_status
  );

   wire [1023:0] not_used;

  ACX_DEVICE_MANAGER #
  (
  .ENABLE_PCIE_1_GEN2_DEEMPH(1),             // Enable PCIE_1 Gen2 De-emphasis Support
  .ENABLE_PCIE_0_GEN2_DEEMPH(0),             // Enable PCIE_0 Gen2 De-emphasis Support
  .ENABLE_PCIE_0_PERSTN     (0),             // Enable PCIE_0 PERSTN Support
  .NAP_ROW                  (4'h6),          // NAP Row
  .ENABLE_PCIE_IRQ_TO_AVR   (1),             // Enable PCIE IRQ to AVR connections
  .ENABLE_PCIE_1_PERSTN     (1),             // Enable PCIE_1 PERSTN Support
  .NAP_COLUMN               (4'h6),          // NAP Column
  .ENABLE_PCIE_0_HOT_RSTN   (0),             // Enable PCIE_0 Hot Reset Support
  .ENABLE_PCIE_1_HOT_RSTN   (0)              // Enable PCIE_1 Hot Reset Support
  )
  x_dev_mgr
  (

   // JTAG Interface

   .i_jtag_in (i_jtag_in),             // Should be connected to top-level ports with the same declaration
   .i_tdo_bus (i_tdo_bus),             // Pass-through the JTAG bus to connect to Snapshot. If not used, this input should be tied to 1'b0
   .o_jtag_out (o_jtag_out),            // Should be connected to top-level ports with the same declaration
   .o_jtap_bus (o_jtap_bus),            // Pass-through of the JTAG bus to connect to Snapshot (or other JTAG components)

   // PERSTN and Hot Reset Interface

   .i_pcie_0_ltssm_state (6'h0),  // This pin should be exposed for Hot Reset and Gen2 De-emphasis support for the PCIE_0 subsystem.
   .i_pcie_0_perstn (1'h0),       // This pin should be exposed for the AC7t1500ES1, AC7t1550ES1, AC7t1500, and AC7t1550 devices when the PCIe enumeration work-around is required for the PCIE_0 subsystem.  The PCIE_0 PERSTN GPIO input should be connected to the exposed i_pcie_0_perstn pin.
   .i_pcie_1_ltssm_state (i_pcie_1_ltssm_state),  // This pin should be exposed for Hot Reset and Gen2 De-emphasis support for the PCIE_1 subsystem.
   .i_pcie_1_perstn (i_pcie_1_perstn),       // This pin should be exposed for the AC7t1500ES1, AC7t1550ES1, AC7t1500, and AC7t1550 devices when the PCIe enumeration work-around is required for the PCIE_1 subsystem.  The PCIE_1 PERSTN GPIO input should be connected to the exposed i_pcie_1_perstn pin.
   .o_pcie_0_irq_to_avr (),   // This pin should be exposed for Hot Reset support for the PCIE_0 subsystem.
   .o_pcie_1_irq_to_avr (o_pcie_1_irq_to_avr),   // This pin should be exposed for Hot Reset support for the PCIE_1 subsystem.

   // User Design

   .i_clk (i_clk),                    // 100 MHz Clock input for Device Manager block.
   .i_start (i_start),                // A high input starts the Device Manager. In most cases this signal is simply tied to 1'b1, but it can also be tied to a PLL lock signal if necessary.
   .o_status (o_status),              // Progress indication, error status, alarms
   .o_serdes_status (o_serdes_status) // Progress indication, error status, alarms
  );

endmodule  // acx_device_manager

//////////////////////////////////////
// End Speedster7t AC7t1500 Device Manager Wrapper User Model
//////////////////////////////////////
