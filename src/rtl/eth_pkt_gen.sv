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
// Generate IPv4 packets with random or fixed size
// Packet size from 64Bytes to 9022Bytes(Jumbo frame support)
// No VLAN support
// Preamble and FCS insertion by the Ethernet MAC core
// ------------------------------------------------------------------

`include "nap_interfaces.svh"
`include "ethernet_utils.svh"

module eth_pkt_gen
  #(
    parameter   DATA_WIDTH              = `ACX_NAP_ETH_DATA_WIDTH,  // Set to 256 for packet mode, 1024 for quad mode
    parameter   LINEAR_PAYLOAD          = 0,        // Set to 1 to make payloads have linear counts
    parameter   FIXED_PAYLOAD_LENGTH    = 46,       // Fixed payload Length must be in the range of [46...9000]
    parameter   RANDOM_LENGTH           = 1,        // Set to 1 to generate packets with random length. When set to 1, FIXED_PAYLOAD_LENGTH will be ignored.
    parameter   JUMBO_SUPPORT           = 1,        // Support up to 9k jumbo frame in random packet length mode
    // Test
    parameter   MAC_STREAM_ID           = 0,        // If non-zero, value will be written to first byte of MAC address
                                                    // Used to identify streams in packet mode
    parameter   PKT_COUNT_INSERT        = 0,        // Insert a packet count to the second byte of MAC address
    parameter   NO_IP_HEADER            = 0,        // Set to disable an IP header being included.
    parameter  logic [15:0] RANDOM_SEED = 16'h17C2  // Random seed for Random length and Random data generation
    )
    (
    // Inputs
    input wire                  i_clk,              // Clock input
    input wire                  i_reset_n,          // Negative synchronous reset
    input wire                  i_start,            // Start packet generator
    input wire                  i_enable,           // Enable packet generator.  Allows pausing the next packet start
    input wire [64 -1:0]        i_num_pkts,         // How many packets to generate.  If set to 0, then generator will run
                                                    // continously
    input wire                  i_hold_eop,         // Hold eop word output until released.
                                                    // Enables packet ordering based on end of packet
    input wire                  i_ts_enable,        // Traffic shaper enable
    t_ETH_STREAM.tx             if_eth_tx,          // Ethernet stream interface

    // Outputs
    output logic                o_done              // Indicate when i_num_pkts have been transmitted
    );

    // Block is designed to interface to Ethernet NAP
    // However it supports quad mode when data width is 1024 bits wide
    localparam int    BYTE_WIDTH     = DATA_WIDTH/8;
    localparam int    MOD_WIDTH      = $clog2(BYTE_WIDTH);
    localparam int    ADDR_WIDTH     = `ACX_NAP_DS_ADDR_WIDTH;

    // Interface signals
    logic                       pkt_send_valid;
    logic                       pkt_send_ready;
    logic [DATA_WIDTH -1:0]     pkt_send_data;
    logic [DATA_WIDTH -1:0]     send_word;
    logic [MOD_WIDTH  -1:0]     pkt_send_mod;

    // Internal signals
    // Following create a 32-bit random value
    logic [15:0]                payload_len_rand_out;
    logic [15:0]                payload_len_rand_out_d;
    logic [31:0]                payload_len_int;
    logic [31:0]                payload_len_int_d /* synthesis syn_preserve=1 */;

    logic [13:0]                payload_len           /* synthesis syn_preserve=1 */; // Random payload length from 46Bytes to 1500Bytes or 9000Bytes depending on JUMBO_SUPPORT
                                                      // 9K can be supported in a 14-bit counter, (16K)
    logic [13:0]                pkt_size_total;       // payload_len + 6Bytes Dest MAC + 6Bytes Src MAC + 2Bytes Length/Type
    logic                       pkt_size_total_short  /* synthesis syn_preserve=1 */; // First packet is short packet
    logic [13:0]                pkt_byte_cnt;         // Number of remaining Bytes
    logic                       pkt_byte_cnt_rem      /* synthesis syn_preserve=1 */;     // More than 2 words remaining
    logic [13:0]                pkt_size_total_next   /* synthesis syn_preserve=1 */;// payload_len + 6Bytes Dest MAC + 6Bytes Src MAC + 2Bytes Length/Type
    logic [13:0]                payload_len_next      /* synthesis syn_preserve=1 */;     // Number of remaining Bytes

    logic [8 -1:0]              pkt_cnt_slow[0:6];
    logic [7 -1:0]              pkt_cnt_slow_co;

    logic [ 4 -1:0]             pkt_cnt_fast;
    logic [ 8 -1:0]             pkt_cnt_mac;

    logic [2 :0]                start_d;
    logic                       pkt_gen_start;

    logic                       gen_payload;
    logic                       payload_enable;
    logic [DATA_WIDTH -1:0]     payload_stream_out;

    // Local variables which are modified within the header
    logic [15:0]                ip_total_len         /* synthesis syn_preserve=1 */;
    logic [15:0]                ip_checksum;
    logic                       gen_first_payload;
    logic                       ld_header_word;
    // Initialise headers
    t_MAC_HEADER                mac_header;
    t_IP_HEADER                 ip_header;

    logic                       sop_value_hold /* synthesis syn_maxfan=8 */;
    logic                       eop_value_hold /* synthesis syn_maxfan=8 */;
    logic                       send_start_en;
    logic                       inc_pkt_count;
    logic                       ld_next;

    // If MAC_STREAM is non-zero, then write this value as the first MAC byte
    // This is then used in multi-stream systems to identify the packet source
    always_comb
    begin
        mac_header = MAC_HEADER_DEFAULT;
        if (MAC_STREAM_ID != 0 )
            mac_header.mac_src_addr[47 -: 8] = MAC_STREAM_ID;
        if (PKT_COUNT_INSERT != 0 )
            mac_header.mac_src_addr[39 -: 8] = pkt_cnt_mac;
    end

    always @(payload_len_next) //ip_total_len)
    begin
        ip_header          = IP_HEADER_DEFAULT;
        ip_header.pkt_len  = {2'b00, payload_len_next}; //ip_total_len;
        ip_checksum        = calculate_checksum(ip_header);
        ip_header.checksum = ip_checksum;
    end

    assign pkt_send_ready = if_eth_tx.ready;

    // Generate start pulse
    always @(posedge i_clk)
    begin
        if (~i_reset_n) begin
            start_d        <= 3'h0;
            pkt_gen_start  <= 1'b0;
        end else begin
            start_d        <= {start_d[1:0], i_start};
            pkt_gen_start  <= start_d[1] & !start_d[2];
        end
    end

    // Generate random or fixed packet size
    // Improve timing by registering signals
    always @(posedge i_clk)
    begin
        if (~i_reset_n) begin
            payload_len_rand_out   <= RANDOM_SEED;
            payload_len_rand_out_d <= 16'h0;
        end else begin
            payload_len_rand_out   <= rand_payload_len(payload_len_rand_out);
            payload_len_rand_out_d <= payload_len_rand_out;
        end
    end

    // Add pipelining to assist with timing
    always @(posedge i_clk)
    begin
        // Random payload length from 46 to 1500 if JUMBO_SUPPORT set to 0
        // Random payload length from 46 to 9000 if JUMBO_SUPPORT set to 1
        payload_len_int_d <= payload_len_int + {16'd46,16'd0};
        if (~i_reset_n) begin
            payload_len_int <= 32'h0;
        end else if (JUMBO_SUPPORT == 0) begin
            payload_len_int <= payload_len_rand_out_d * 16'd1454;
        end else begin
            payload_len_int <= payload_len_rand_out_d * 16'd8954;
        end
    end

    int idx;
    always @(posedge i_clk)
    begin
        if (~i_reset_n) begin
            payload_len           <= 32'h0;
            payload_len_next      <= 32'h0;
            idx                   <= 0;
            pkt_size_total        <= ($bits(t_MAC_HEADER)/8);
            pkt_size_total_short  <= 1'b0;
            pkt_size_total_next   <= ($bits(t_MAC_HEADER)/8);
        end else if (RANDOM_LENGTH == 1) begin  // Use Random Length
            if (pkt_gen_start || (pkt_send_ready & sop_value_hold) || (pkt_send_ready & eop_value_hold & (pkt_size_total_next <= (BYTE_WIDTH)))) begin
                pkt_size_total_next <=  payload_len_int_d[31:16] + payload_len_int_d[15] + ($bits(t_MAC_HEADER)/8);
                payload_len_next    <= payload_len_int_d[31:16] + payload_len_int_d[15];
            end
            if (gen_first_payload || (pkt_send_ready & eop_value_hold) )begin
                payload_len     <= payload_len_next;
                pkt_size_total  <= pkt_size_total_next;
                if (pkt_size_total_next <= (BYTE_WIDTH))
                    pkt_size_total_short <= 1'b1;
                else
                    pkt_size_total_short <= 1'b0;
            end
        end else begin  // Fixed Packet Length
            if (pkt_gen_start || (pkt_send_ready & sop_value_hold) || (pkt_send_ready & eop_value_hold & (pkt_size_total_next <= (BYTE_WIDTH)))) begin
                payload_len_next    <= FIXED_PAYLOAD_LENGTH;
                pkt_size_total_next <= FIXED_PAYLOAD_LENGTH + ($bits(t_MAC_HEADER)/8) ;
            end
            if (gen_first_payload || (pkt_send_ready & eop_value_hold)) begin
                payload_len     <= payload_len_next;
                pkt_size_total  <= pkt_size_total_next;
                if (pkt_size_total_next <= (BYTE_WIDTH))
                    pkt_size_total_short <= 1'b1;
                else
                    pkt_size_total_short <= 1'b0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // State machine to generate IPv4 packets
    // -------------------------------------------------------------------------
    enum {PKT_STATE_IDLE, PKT_STATE_FIRST, PKT_STATE_READY, PKT_STATE_SOP, PKT_STATE_SOP_EOP, PKT_STATE_PAYLOAD, PKT_STATE_EOP}
            pkt_send_state;
    logic continuous_pkts;
    logic continuous_pkts_q;

    // i_num_pkts is coming from a different clock domain. However, it will be static one it's used here by continuous_pkts
    always @(posedge i_clk)
    begin
        continuous_pkts_q <= (i_num_pkts == 0);
        continuous_pkts   <= continuous_pkts_q;
    end

    // Refactored Statemachine to support make packet ready before starting
    // Ready is used as target acknowledge instead checking the target readyness
    // Data/valid/sop can be asserted when READY is de-asserted, and wait until READY is asserted.
    always @(posedge i_clk)
    begin
        if (~i_reset_n)
        begin
            pkt_send_state   <= PKT_STATE_IDLE;
            o_done           <= 1'b0;
            send_start_en    <= 1'b0;
            inc_pkt_count    <= 1'b0;
            ld_next          <= 1'b0;
        end
        else case (pkt_send_state)
            PKT_STATE_IDLE:
            begin
              if (pkt_gen_start) begin
                pkt_send_state <= PKT_STATE_FIRST;
              end else
                pkt_send_state <= PKT_STATE_IDLE;
            end
            PKT_STATE_FIRST:  // Only once when generator started. (S1)
            begin
              pkt_send_state <= PKT_STATE_READY;
            end
            PKT_STATE_READY: // Generate the packer header word loading signal (S2)
            begin
                if (pkt_size_total_short) begin  // SOP/EOP generated at the same time (Short Packet)
                    pkt_send_state  <= PKT_STATE_SOP_EOP;
                    ld_next         <= 1'b1;
                end else begin
                    pkt_send_state  <= PKT_STATE_SOP;
                    ld_next         <= 1'b0;
                end
                send_start_en <= 1'b1;
            end
            PKT_STATE_SOP:  // SOP state will transit it is acknowledged by READY signal
            begin
                inc_pkt_count <= 1'b0;
                if (pkt_send_ready & i_enable & i_ts_enable) begin
                    if (pkt_byte_cnt_rem) begin  // More than 2 words remaining
                        pkt_send_state  <= PKT_STATE_PAYLOAD;
                    end else begin // Less than a whole word once this one sent, so go to EoP
                        pkt_send_state  <= PKT_STATE_EOP;
                        ld_next         <= 1'b1;
                    end
                end else begin
                  pkt_send_state <= PKT_STATE_SOP;
                end
            end
            PKT_STATE_SOP_EOP:
            begin
                if (pkt_send_ready & i_enable & i_ts_enable) begin
                    if ((pkt_cnt_slow_co[6] == 1'b1) && (pkt_cnt_fast == 4'hf) && ~continuous_pkts) begin
                        pkt_send_state <= PKT_STATE_IDLE;
                        o_done         <= 1'b1;
                        inc_pkt_count  <= 1'b0;
                    end else begin
                        if (pkt_size_total_next > (BYTE_WIDTH)) begin
                            pkt_send_state  <= PKT_STATE_SOP;
                            ld_next         <= 1'b0;
                        end else begin
                            pkt_send_state  <= PKT_STATE_SOP_EOP;
                            ld_next         <= 1'b1;
                        end
                        inc_pkt_count <= 1'b1;
                    end
                end else begin
                    pkt_send_state  <= PKT_STATE_SOP_EOP;
                    inc_pkt_count   <= 1'b0;
                    ld_next         <= 1'b0;
                end
            end
            PKT_STATE_PAYLOAD:
            begin
                if (pkt_send_ready & i_ts_enable) begin
                    if (pkt_byte_cnt_rem) begin  // More than 2 words remaning
                        pkt_send_state  <= PKT_STATE_PAYLOAD;
                        ld_next         <= 1'b1;
                    end else begin
                        ld_next         <= 1'b0;
                        pkt_send_state  <= PKT_STATE_EOP;
                    end
                end else begin
                    ld_next         <= 1'b0;
                    pkt_send_state  <= PKT_STATE_PAYLOAD;
                end
            end
            PKT_STATE_EOP:
            begin
                ld_next <= 1'b0;
                if (pkt_send_ready & i_ts_enable) begin
                    if ((pkt_cnt_slow_co[6] == 1'b1) && (pkt_cnt_fast == 4'hf) & ~continuous_pkts) begin
                        pkt_send_state <= PKT_STATE_IDLE;
                        o_done         <= 1'b1;
                    end else begin
                        if (pkt_size_total_next > (BYTE_WIDTH))
                            pkt_send_state <= PKT_STATE_SOP;
                        else
                            pkt_send_state <= PKT_STATE_SOP_EOP;

                        inc_pkt_count <= 1'b1;
                    end
                end else
                    pkt_send_state <= PKT_STATE_EOP;
            end
            default : pkt_send_state <= PKT_STATE_IDLE;
        endcase
    end

    // Refactored: Added three new signals
    //    gen_first_payload : generate first payload data when start is asserted
    //    ld_header_word    : load the first packet word (hearder + payload)
    //    gen_payload       : generate next payload
    always_comb
    begin
        gen_first_payload = 1'b0;
        ld_header_word    = 1'b0;
        gen_payload       = 1'b0;
        sop_value_hold    = 1'b0;
        eop_value_hold    = 1'b0;
        case (pkt_send_state)
            PKT_STATE_FIRST:
            begin
                gen_first_payload = 1'b1;
            end
            PKT_STATE_READY:
            begin
                ld_header_word = 1'b1;
                gen_payload    = 1'b1;
            end
            PKT_STATE_SOP:
            begin
                sop_value_hold = i_enable & i_ts_enable;
                eop_value_hold = 1'b0;
                 if (pkt_send_ready & i_enable & i_ts_enable) begin
                    gen_payload = 1'b1;
                end
            end
            PKT_STATE_SOP_EOP:
            begin
                sop_value_hold = i_enable & i_ts_enable;
                eop_value_hold = i_enable & i_ts_enable;
                if (pkt_send_ready & i_enable & i_ts_enable) begin
                    gen_payload = 1'b1;
                end
            end
            PKT_STATE_PAYLOAD:
            begin
                sop_value_hold = 1'b0;
                eop_value_hold = 1'b0;
                if (pkt_send_ready & i_ts_enable) begin
                    gen_payload = 1'b1;
                end
            end
            PKT_STATE_EOP:
            begin
                if (i_hold_eop != 1'b1 && pkt_send_ready & i_ts_enable) begin
                    gen_payload = 1'b1;
                end
                eop_value_hold = i_ts_enable;
            end
            default :
            begin
                gen_payload       = 1'b0;
                sop_value_hold    = 1'b0;
                eop_value_hold    = 1'b0;
                gen_first_payload = 1'b0;
                ld_header_word    = 1'b0;
            end
        endcase
    end

    // MOD
    always @(posedge i_clk)
    begin
        if (~i_reset_n) begin
            pkt_send_mod <= {MOD_WIDTH{1'b0}};
        end else if ((eop_value_hold && pkt_send_ready) || ld_header_word) begin
            if (pkt_size_total_next == BYTE_WIDTH) begin
                pkt_send_mod <= {MOD_WIDTH{1'b0}};
            end else begin
                pkt_send_mod <= pkt_size_total_next[MOD_WIDTH-1:0];
            end
        end
    end

    // Assert valid during the packet time
    // Use combinational logic instead one-clock delay, Valid asserted when Ready is de-asserted.
    always_comb
    begin
        pkt_send_valid   = 1'b0;

        case (pkt_send_state)
            PKT_STATE_SOP:
            begin
                pkt_send_valid = i_enable & i_ts_enable;
            end
            PKT_STATE_PAYLOAD:
            begin
                pkt_send_valid = i_ts_enable;
            end
            PKT_STATE_SOP_EOP:
            begin
                pkt_send_valid = i_enable & i_ts_enable;
            end
            PKT_STATE_EOP:
            begin
                pkt_send_valid = i_ts_enable;
            end

            default : pkt_send_valid = 1'b0;
        endcase
    end

    // Count the number of packets
    // Split the counter into a fast 4-bit counter than can be incremented on every cycle
    // (necessary when BYTE_WIDTH > 60, so a packet per cycle), and a slower 24-bit counter
    // made of 3x 8-bit counters which only increments every 16 packets.
    logic [56 -1:0] pkt_cnt_start_value;
    // CDC here, but i_num_pkts should be stable when pkt_gen_start is asserted
    assign pkt_cnt_start_value = (56'h00_0000 - {1'b0, i_num_pkts[58:4]});
    logic [7:0] inc_pkt_cnt;

    always @(posedge i_clk)
        inc_pkt_cnt <= {inc_pkt_cnt[6:0], (pkt_send_ready && eop_value_hold && (pkt_cnt_fast == 4'h0))};

    always @(posedge i_clk)
    begin
        if (pkt_gen_start)
        begin
            pkt_cnt_slow[0]    <= pkt_cnt_start_value[7:0];
            pkt_cnt_slow_co[0] <= 1'b0;
        end
        else if (inc_pkt_cnt[0])
        begin
            pkt_cnt_slow[0]    <= pkt_cnt_slow[0] + 8'd1;
            pkt_cnt_slow_co[0] <= (pkt_cnt_slow[0] == 8'hff);
        end
    end

    generate
    genvar scnt_idx;
    begin
        for (scnt_idx = 1; scnt_idx < 6 ; scnt_idx = scnt_idx+1) begin
            always @(posedge i_clk)
            begin
                if (pkt_gen_start)
                begin
                    pkt_cnt_slow[scnt_idx]    <= pkt_cnt_start_value[(8*(scnt_idx+1))-1:(scnt_idx*8)];
                    pkt_cnt_slow_co[scnt_idx] <= 1'b0;
                end
                else if (inc_pkt_cnt[scnt_idx])
                begin
                    if (pkt_cnt_slow_co[scnt_idx-1])
                    begin
                        pkt_cnt_slow[scnt_idx]    <= pkt_cnt_slow[scnt_idx] + 8'd1;
                        pkt_cnt_slow_co[scnt_idx] <= (pkt_cnt_slow[scnt_idx] == 8'hff);
                    end
                    else
                    begin
                        pkt_cnt_slow[scnt_idx]    <= pkt_cnt_slow[scnt_idx] ;
                        pkt_cnt_slow_co[scnt_idx] <= 1'b0;
                    end
                end
            end
        end
    end
    endgenerate

    always @(posedge i_clk)
    begin
        if (pkt_gen_start)
        begin
            pkt_cnt_slow[6]    <= pkt_cnt_start_value[(8*(7))-1:(6*8)];
            pkt_cnt_slow_co[6] <= 1'b0;
        end
        else if (inc_pkt_cnt[6])
        begin
            if (pkt_cnt_slow_co[5])
            begin
                pkt_cnt_slow[6]    <= pkt_cnt_slow[6] + 8'd1;
                pkt_cnt_slow_co[6] <= (pkt_cnt_slow[6] == 8'hff);
            end
            else
            begin
                pkt_cnt_slow[6]    <= pkt_cnt_slow[6];
                pkt_cnt_slow_co[6] <= 1'b0;
            end
        end
    end

    always @(posedge i_clk)
    begin
        if (pkt_gen_start) begin
            pkt_cnt_fast <= 5'h10 - {1'b0, i_num_pkts[3:0]};  // CDC here, but i_num_pkts should be stable when pkt_gen_start is asserted
        end else if (pkt_send_ready && eop_value_hold) begin
            pkt_cnt_fast <= pkt_cnt_fast + 4'd1;
        end
    end

    // Count down bytes transmitted
    always @(posedge i_clk)
    begin
        if (~i_reset_n) begin
            pkt_byte_cnt      <= 14'b0;
            pkt_byte_cnt_rem  <= 1'b0;
        end else if (gen_first_payload) begin // Generate First packet ahead
            pkt_byte_cnt <= pkt_size_total_next;
            if (pkt_size_total_next > (2*BYTE_WIDTH))
                pkt_byte_cnt_rem <= 1'b1;
            else
                pkt_byte_cnt_rem <= 1'b0;
        end else if (pkt_send_valid & pkt_send_ready) begin
            if (pkt_byte_cnt[13:MOD_WIDTH] == 0 || pkt_byte_cnt == BYTE_WIDTH) begin
                pkt_byte_cnt <= pkt_size_total_next;
                if (pkt_size_total_next > (2*BYTE_WIDTH))
                    pkt_byte_cnt_rem <= 1'b1;
                else
                    pkt_byte_cnt_rem <= 1'b0;
            end else begin
                pkt_byte_cnt[13:MOD_WIDTH] <= pkt_byte_cnt[13:MOD_WIDTH] - 'd1;
                if (pkt_byte_cnt > (3*BYTE_WIDTH))
                    pkt_byte_cnt_rem <= 1'b1;
                else
                    pkt_byte_cnt_rem <= 1'b0;
            end
        end
    end

    // Create a counter to insert into the MAC header
    // Keep separate from the main counter to improve timing
    always @(posedge i_clk)
        if (~i_reset_n)
            pkt_cnt_mac <= 8'd0;
        else if (ld_header_word || (eop_value_hold & pkt_send_ready)) //inc_mac_count)
            pkt_cnt_mac <= pkt_cnt_mac + 8'd1;

    // Register payload length for the IP header
    always @(posedge i_clk)
        if (~i_reset_n)
            ip_total_len   <= 16'b0;
        else if (gen_first_payload|| (pkt_send_ready & ld_next) || (pkt_send_ready & sop_value_hold & (pkt_byte_cnt[13:MOD_WIDTH] == 1)))
            ip_total_len   <= {2'b00, payload_len_next}; // Using next payload length to generate IP total length
                                                         // It required when pkt_send_ready is asserted, current payload length is not
                                                         // updated immediately.

    // generate layload enable signal
    assign payload_enable = (pkt_send_ready & gen_payload)|| gen_first_payload;

    // Instantiate random sequence generator for data
    random_seq_gen #(
        .OUTPUT_WIDTH       (DATA_WIDTH),
        .WORD_WIDTH         (8),
        .LINEAR_COUNT       (LINEAR_PAYLOAD),
        .COUNT_DOWN         (0))
    i_data_gen (
        // Inputs
        .i_clk              (i_clk),
        .i_reset_n          (i_reset_n),
        .i_start            (1'b1),
        .i_enable           (payload_enable),
        // Outputs
        .o_dout             (payload_stream_out)
    );

    // First two words vary based on data width
    localparam FIRST_WORD_OVERFLOW = ((NO_IP_HEADER) ? 0 : $bits(ip_header)) + $bits(mac_header) - DATA_WIDTH;

    // Instantiate byte order reverse module
    acx_byte_order_reverse #(.DATA_WIDTH(DATA_WIDTH)) i_acx_byte_order_reverse (.in(send_word), .rev(pkt_send_data));

    logic gen_pkt_header;

    // Need generate loops for two cases of whether mac and ip header overflow the first word
    generate if( FIRST_WORD_OVERFLOW > 0 ) begin : gb_fw_pos
        always @(posedge i_clk)
        begin
            if (~i_reset_n) begin
                send_word <= {DATA_WIDTH{1'b0}};
            end else begin
                if (ld_header_word || (eop_value_hold & pkt_send_ready)) begin
                    send_word <= (NO_IP_HEADER) ? {mac_header[$bits(mac_header)-1:FIRST_WORD_OVERFLOW]} :
                                                  {mac_header, ip_header[$bits(ip_header)-1:FIRST_WORD_OVERFLOW]};
                end else if (sop_value_hold) begin
                    send_word <= (NO_IP_HEADER) ?
                        {mac_header[FIRST_WORD_OVERFLOW-1:0], payload_stream_out[0 +: (DATA_WIDTH-FIRST_WORD_OVERFLOW)]} :
                        {ip_header[FIRST_WORD_OVERFLOW-1:0], payload_stream_out[0 +: (DATA_WIDTH-FIRST_WORD_OVERFLOW)]};
                end else if (pkt_send_valid & pkt_send_ready) begin
                    send_word <= payload_stream_out;
                end
            end
        end
    end
    else
    begin : gb_fw_neg   //  FIRST_WORD_OVERFLOW <= 0
        // Refactored: load the first word early, and changed data when valid and ready is asserted.
        always @(posedge i_clk)
        begin
            if (~i_reset_n) begin
                send_word <= {DATA_WIDTH{1'b0}};
            end else begin
                if (ld_header_word || (eop_value_hold & pkt_send_ready)) begin
                    send_word <= (NO_IP_HEADER) ? {mac_header, payload_stream_out[0 +: -FIRST_WORD_OVERFLOW]} :
                                                  {mac_header, ip_header, payload_stream_out[0 +: -FIRST_WORD_OVERFLOW]};
                end else if (pkt_send_valid & pkt_send_ready) begin
                    send_word <= payload_stream_out;
                end
            end
        end
    end
    endgenerate

    // -------------------------------------------------------------------------
    // Function to generate 16bit random data
    // -------------------------------------------------------------------------
    function [15:0] rand_payload_len;
        input [15:0] seed;
        begin
            rand_payload_len = seed;
            rand_payload_len = {(rand_payload_len[2] ^ rand_payload_len[4] ^ rand_payload_len[7]),
                                 rand_payload_len[9] ^ rand_payload_len[13],
                                 rand_payload_len[6] ^ rand_payload_len[1],
                                 rand_payload_len[15:3]};
        end
    endfunction

    assign if_eth_tx.addr   = 'h0;  // Overwritten by nap_ethernet_wrapper
    assign if_eth_tx.data   = pkt_send_data;
    assign if_eth_tx.mod    = pkt_send_mod;
    assign if_eth_tx.valid  = pkt_send_valid;
    assign if_eth_tx.sop    = sop_value_hold;
    assign if_eth_tx.eop    = eop_value_hold;
    // Do not drive flags, they can then be driven from outside the generator block

endmodule :eth_pkt_gen
