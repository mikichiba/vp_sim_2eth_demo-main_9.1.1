//=========================================================================================================
// sender.sv
//
// This module continuously sends sequential 64-bit values to the "simulated ethernet" module
//=========================================================================================================

`include "nap_interfaces.svh"

module sender
(
    input wire          clk,
    input wire          resetn,
    input wire          enable,
    input wire          id,
    input wire[3:0]     dest_addr,
    t_ETH_STREAM.tx     tx
);

    // This counter serves as a countdown timer
    logic[63:0] counter;


    assign tx.addr = dest_addr;
    assign tx.data = {191'b0, id, counter};
    assign tx.sop  = (counter[1:0] == 0);
    assign tx.eop  = (counter[1:0] == 3);
    assign tx.valid = tx.ready & enable;

    always @(posedge clk) begin
        if (resetn == 0) begin
            counter  <= 0;
        end else begin
            counter  <= counter;
            if (tx.ready & enable) begin
                counter++;
            end
        end
    end

endmodule
