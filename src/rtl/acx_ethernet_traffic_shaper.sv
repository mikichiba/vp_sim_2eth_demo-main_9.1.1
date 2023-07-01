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
// Achronix Ethernet traffic shaper
//      Ensures that NAP only transmits at the rate selected.
//      Required as NAPs are set to a higher frequency that the rate
//      in order to support all packet lengths.
// ------------------------------------------------------------------

module acx_ethernet_traffic_shaper #(
    parameter integer   DATA_WIDTH                 = 256,
    parameter real      TX_EQUIVALENT_FREQUENCY    = 390.0,
    parameter real      NAP_TX_FREQUENCY           = 510.0,
    parameter integer   IPG_LENGTH                 = 12,     // Default IPG gap between packets, in bytes
    parameter integer   FCS_LENGTH                 = 4,      // FCS size in bytes

    localparam  BYTE_WIDTH                      = (DATA_WIDTH/8),
    localparam  MOD_WIDTH                       = $clog2(BYTE_WIDTH)
)
(
    input  wire                     clk,
    input  wire                     rstn,

    output logic                    in_ready,       // Direct from out_ready
    output logic                    ts_enable,      // Traffic shaper enabling traffic
    input  wire                     in_valid,
    input  wire                     in_sop,
    input  wire                     in_eop,
    input  wire  [MOD_WIDTH  -1:0]  in_mod,
    input  wire  [DATA_WIDTH -1:0]  in_data,
    input  wire  [32  -1:0]         in_data_extra,

    input  wire                     out_ready,
    output logic                    out_valid,
    output logic                    out_sop,
    output logic                    out_eop,
    output logic [MOD_WIDTH  -1:0]  out_mod,
    output logic [DATA_WIDTH -1:0]  out_data,
    output logic [32  -1:0]         out_data_extra
);

    // This shaper is designed for 256-bit, (32'byte), wide NAPs
    // On that basis, sop and eop cannot occur on the same cycle.  
    // Ensure number of bytes is less than a minimum packet
    generate if (BYTE_WIDTH >= 46) begin : gb_bytes_gt_46
        ERROR_shaper_byte_width_greater_than_46 u_ERROR ();
    end
    endgenerate

    // Use standard length preamble
    // MAC does support shortened preamble - consider as future enhancement
    localparam PREAMBLE_LENGTH = 8;

    // Overall design needs 0.3% accuracy, to deliver jumbo packet, (9KB, 300 cycles)
    // Biggest inaccuracy is with 10G, this will give the smallest value, then any rounding makes it inaccurate
    // Possible error is +/- 0.5.  So for 0.3% accuracy, 10G value must be greater than (100%/0.3%) * 0.5 = 166.6
    // Overall scale is then, (assuming a 300MHz minimum clock), (300/39.0625) * 166 = 1279.
    // Set NCO to 11-bits allowing for 2048.

    // Calculate the noc_counter.
    // Need to subtract 0.51 as casting real to integer rounds to the nearest int, (it has +0.5 built in) see SV LRM.
    // As X.5 is rounded up, it is necessary to subtract 0.51 rather than just 0.5
    // The NCO needs to truncate and always round down, it can never go overrate.
    localparam logic [10:0] NCO_TC_COUNT = integer'(((TX_EQUIVALENT_FREQUENCY * 2048.0) / NAP_TX_FREQUENCY) - 0.51 - 1.0);

    // Create duty cycle using an NCO.
    logic [11:0] nco_count;
    logic        subtract_bytes;

    // By using out_ready to limit the NCO, this means that the rate limit
    // limits the throughput when out_ready is asserted, it does not catch up
    // after a prolonged period of out_ready being deasserted
    always @(posedge clk)
        if ( ~rstn )
            nco_count <= 10'b0;
        else if (out_ready)
            nco_count <= {1'b0, nco_count[10:0]} + {1'b0, NCO_TC_COUNT};

    // Register subtract_bytes to improve timing            
    always @(posedge clk)
        subtract_bytes <= (nco_count[11] & out_ready);

    // Measure bytes in
    logic [5:0] bytes_in_comb;
    logic       xact_in;
    logic       mod0;

    assign mod0 = (in_mod == {BYTE_WIDTH{1'b0}});

    // This shaper is designed for 256-bit, (32'byte), wide NAPs
    // So sop and eop cannot occur on the same cycle
    // Add preamble at end of packet, otherwise if added with sop could cause
    // second byte of packet to be delayed.
    // Also keeps net_bytes in range, only adding +12 to either sop or eop
    always_comb
    begin

        if (in_sop)
            bytes_in_comb = BYTE_WIDTH + IPG_LENGTH;     // Full word + IPG
        else
        begin
            // Parallel case to reduce logic levels
            case ({mod0, in_eop})
                2'b00 : bytes_in_comb = BYTE_WIDTH;                 // Not eop
                2'b10 : bytes_in_comb = BYTE_WIDTH;                 // Not eop
                // eop with mod!=0.  Add mod value and 4 cycles of FCS
                2'b01 : bytes_in_comb = in_mod     + FCS_LENGTH + PREAMBLE_LENGTH;
                // eop with mod =0.  Add all bytes and 4 cycles of FCS
                2'b11 : bytes_in_comb = BYTE_WIDTH + FCS_LENGTH + PREAMBLE_LENGTH;
            endcase
        end
        /*
        if (in_eop) -- ERROR, did not check for mod=0
            bytes_in_comb = in_mod + 4;  // 4 cycles of FCS
        else
            bytes_in_comb = BYTE_WIDTH;
        */
    end

    assign xact_in = (in_valid & in_ready);

    // Deduct bytes at playout rate
    logic signed [8:0] net_bytes;

    always @(posedge clk)
        case ({subtract_bytes, xact_in})
            2'b00 : net_bytes <= $signed(9'd0);
            2'b01 : net_bytes <= $signed({3'b000, bytes_in_comb});
            2'b10 : net_bytes <= $signed(9'd0 - BYTE_WIDTH);
            2'b11 : net_bytes <= $signed({3'b000, bytes_in_comb} - BYTE_WIDTH);
        endcase 

    logic signed [8:0] level;
    logic signed [8:0] level_limit;

    // Limits mean that the level calculation can never over or underflow.
    // net bytes has a max value of 44, or -44. Set limits to 64 byte boundaries to make comparison less bits
    localparam signed [8:0] MIN_LIMIT = $signed(-9'd255 + 63);
    localparam signed [8:0] MAX_LIMIT = $signed( 9'd255 - 63);

    logic below_min;
    logic above_max;

    // NCO measuring bytes in 
    always @(posedge clk)
    begin
        if ( ~rstn )
            level <= $signed(9'd0);
        else
            level <= $signed(net_bytes + level_limit);
    end

    // Set levels
    assign below_min = (level < $signed(MIN_LIMIT));
    assign above_max = (level > $signed(MAX_LIMIT));

    always_comb
    begin
        // Cannot have error message as values unknown at beginning due to reset being 1'x
        case ({above_max, below_min})
            2'b00 : level_limit = level;
            2'b01 : level_limit = MIN_LIMIT;
            2'b10 : level_limit = MAX_LIMIT;
            2'b11 : begin /* $error("Value above and below limits at the same time!");*/ level_limit = level; end
        endcase

    end

    logic level_negative;
    // Register top bit of level_limit, which indicates that the level is negative
    always @(posedge clk)
        level_negative <= level_limit[$high(level_limit)];

    // Doing flow control of the input at this level causes timing failure
    // Need to propogate the enable signal, which allows high level client logic to combine it with it's other logic
    // Do not allow traffic if the rate is positive
    assign in_ready  = out_ready;
    assign ts_enable = level_negative;

    // Assign the signals through the block
    always_comb
    begin
        out_sop        = in_sop;
        out_eop        = in_eop;
        out_data       = in_data;
        out_mod        = in_mod;
        out_data_extra = in_data_extra;
        out_valid      = in_valid;
    end

endmodule : acx_ethernet_traffic_shaper

