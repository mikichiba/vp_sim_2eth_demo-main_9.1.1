//=========================================================================================================
// ethnet.sv
//
// This module waits for messages to data to arrive via the NoC and sends those messeges back to the
// sender.  This simulates a QSFP/Ethernet port with a loopback-connector inserted.
//
// A valid data-transfer (with the NAP) occurs on any clock cycle in which "ready" and "valid" are both
// high.
//=========================================================================================================

`include "nap_interfaces.svh"


module ethnet
(
    input wire          clk,
    input wire          resetn,
    output wire[7:0]    leds,
    output logic[255:0] rxdata,
    output logic[3:0]   rxaddr,
    output logic        rxsop,
    output logic        rxeop,
    output logic        error,
    output wire[63:0]   o_counter,     
    t_ETH_STREAM.rx     rx
);

    // When a data-cycle arrives from the NAP, we'll store the lower 8 bits here
    reg[7:0] led_bits;
    logic[63:0] counter;
    reg first_valid;

    // The physical LEDs are active-low
    assign leds = ~led_bits;
    assign o_counter = counter;

    always @(posedge clk) begin

        // If we're in reset, turn all the LEDs off and tell the NAP we're not ready
        if (resetn == 0) begin
            led_bits  <= 0;
            rx.ready  <= 0;
            rxdata    <= 0;
            rxaddr    <= 0;
            rxsop     <= 0;
            rxeop     <= 0;
            counter   <= 0;
            first_valid <= 0;
            error     <= 0;
        end else begin
        // Otherwise, we're always ready to receive, and any time we receive valid
        // data from the NAP, we'll drive it out to the LEDs
            rx.ready <= 1;

            rxdata   <= rxdata;
            rxaddr   <= rxaddr;
            rxsop    <= rxsop;
            rxeop    <= rxeop;
            led_bits <= led_bits;
            if (rx.valid) begin
                rxdata   <= rx.data;
                rxaddr   <= rx.addr;
                rxsop    <= rx.sop;
                rxeop    <= rx.eop;
                led_bits <= rx.data[31:24];
            end

            first_valid <= first_valid;
            if (rx.valid) begin
                first_valid <= 1;
            end

            counter <= counter;
            if (rx.valid & first_valid) begin
                counter++;
            end

            error <= 0;
            if (rx.valid & first_valid) begin
              if (rxdata[63:0] != counter) begin
                  error <= 1;
              end
            end
        end
    end

endmodule
