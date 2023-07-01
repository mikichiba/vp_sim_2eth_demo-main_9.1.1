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
// Reset processor V3
//      Combines an array of negative sense reset signals, 
//      The input stage can optionally include a synchronizer and pipeline
//      per reset if SYNC_INPUT_RESETS is enabled
//      If not, then set_multicycle path will be required on each input
//      to allow for propogation from the edge of the fabric to the centre
//      For the output there is again either a pipeline to allow for 
//      distance and fanout across the die, or else a single synchronizer
//      if RESET_OVER_CLOCK is enabled
//      V3 adds the ability to fanout and pipeline the reset output so
//      it can span to different areas of the die.
//      Remove syn_maxfan since Synplify has no knowledge of back end placement
//      and will not intelligently split the fanned out register geographically
//      A user still has the option to place a syn_maxfan in the fdc file
// ------------------------------------------------------------------


module reset_processor_v3
#(
    parameter   NUM_INPUT_RESETS        = 1,        // Number of clocks, (and hence resets).
    parameter   NUM_OUTPUT_RESETS       = 8,        // Number of output resets that can be used to span different geographical 
                                                    // areas of the FPGA die.
    parameter   IN_RST_PIPE_LENGTH      = 2,        // Length of input flop pipeline, minimum of 2
                                                    // Ignored if SYNC_INPUT_RESETS = 0
    parameter   SYNC_INPUT_RESETS       = 0,
    parameter   OUT_RST_PIPE_LENGTH     = 2,        // Length of reset flop pipeline, minimum of 2
                                                    // Ignored if RESET_OVER_CLOCK = 1
    parameter   RESET_OVER_CLOCK        = 0         // Will the output reset be routed over the clock network
                                                    // If so, then the output signal needs to have a
                                                    // set_clock_type -data_center [get_nets <output_net>]
                                                    // set in the project .pdc file
)
(
    // Inputs
    input  wire [NUM_INPUT_RESETS -1:0]  i_rstn_array,  // Array of negative sense reset inputs
    input  wire                          i_clk,         // Input clock array

    // Outputs
    output wire [NUM_OUTPUT_RESETS -1:0] o_rstn         // Processed resets
);

    // Combine the input array into one main reset
    logic main_rstn;

    generate if (SYNC_INPUT_RESETS) begin : gb_sync_inputs
        logic [NUM_INPUT_RESETS -1:0] sync_rstn_pipe_out;

        for (genvar ii=0; ii < NUM_INPUT_RESETS; ii = ii + 1) begin : gb_per_input
            logic                           sync_rstn;
            logic [IN_RST_PIPE_LENGTH -1:0] sync_rstn_pipe;

            ACX_SYNCHRONIZER x_sync (.din(1'b1), .dout(sync_rstn), .clk(i_clk), .rstn(i_rstn_array[ii]));

            always @(posedge i_clk)
                sync_rstn_pipe <= {sync_rstn_pipe[IN_RST_PIPE_LENGTH-2:0], sync_rstn};

            assign sync_rstn_pipe_out[ii] = sync_rstn_pipe[IN_RST_PIPE_LENGTH-1];
        end
        // Code to not propogate X
        assign main_rstn = (sync_rstn_pipe_out === {NUM_INPUT_RESETS{1'b1}}) ? 1'b1 : 1'b0;
    end
    else 
    begin : gb_async_inputs
        assign main_rstn = (i_rstn_array === {NUM_INPUT_RESETS{1'b1}}) ? 1'b1 : 1'b0;
    end
    endgenerate

    generate if (RESET_OVER_CLOCK) begin : gb_roc
        // If reset over clock required, use a further synchronizer to ensure there is the single retained flop
        // that is not retimed or duplicated
        ACX_SYNCHRONIZER x_sync_rstn  (.din(1'b1), .dout(o_rstn[0]),  .clk(i_clk), .rstn(main_rstn));
    end
    else if (NUM_OUTPUT_RESETS == 1) 
    begin : gb_out_pipe
        // Create an output pipeline
        // Preserve so that the pipeline stages are not combined or placed into memory storage elements.
        logic [OUT_RST_PIPE_LENGTH -1:0] sync_rstn_out_pipe  = {OUT_RST_PIPE_LENGTH{1'b0}} /* synthesis syn_preserve=1 */;

        always @(posedge i_clk)
            sync_rstn_out_pipe <= {sync_rstn_out_pipe[OUT_RST_PIPE_LENGTH-2:0], main_rstn};

        assign o_rstn[0] = sync_rstn_out_pipe[OUT_RST_PIPE_LENGTH-1];
    end
    else
    begin : gb_out_pipes
        // Create an output pipeline
        // Set a default maxfan to have Synplify duplicate the necessary flops
        logic [NUM_OUTPUT_RESETS-1 :0][OUT_RST_PIPE_LENGTH -1:0] sync_rstn_out_pipe = '{default:0} /* synthesis syn_preserve=1 */;

        for (genvar ii=0; ii < NUM_OUTPUT_RESETS; ii = ii + 1) begin : gb_per_output
            always @(posedge i_clk)
                sync_rstn_out_pipe[ii] <= {sync_rstn_out_pipe[ii][OUT_RST_PIPE_LENGTH-2:0], main_rstn};
  
            // Create an output pipeline
            // Preserve so that the pipeline stages are not combined or placed into memory storage elements.
            assign o_rstn[ii] = sync_rstn_out_pipe[ii][OUT_RST_PIPE_LENGTH-1];
        end
    end
    endgenerate

endmodule : reset_processor_v3

