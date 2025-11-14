`timescale 1ns/1ps
`default_nettype none

module reduce_mod_poly1305(
    input wire clk,
    input wire reset_n,
    input wire start,
    input wire [257:0] value_in,
    output reg [129:0] value_out,
    output reg busy,
    output reg done
);
    reg [257:0] val_reg;
    reg [129:0] lo;
    reg [127:0] hi;
    reg [130:0] tmp;
    reg running;

    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            val_reg <= 0;
            value_out <= 0;
            busy <= 0;
            done <= 0;
            running <= 0;
        end else begin
            done <= 0; // pulse

            if(start && !running) begin
                val_reg <= value_in;
                busy <= 1;
                running <= 1;
            end else if(running) begin
                lo = val_reg[129:0];
                hi = val_reg[257:130];
                tmp = lo + (hi * 5);
                if(tmp >= (1'b1 << 130))
                    value_out <= tmp - (1'b1 << 130) + 5;
                else
                    value_out <= tmp[129:0];

                busy <= 0;
                done <= 1;   // single-cycle pulse
                running <= 0;
            end
        end
    end
endmodule
