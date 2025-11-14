`timescale 1ns/1ps
`default_nettype none

module mult_130x128_limb(
    input  wire clk,
    input  wire reset_n,
    input  wire start,
    input  wire [129:0] a_in,
    input  wire [127:0] b_in,
    output reg [257:0] product_out,
    output reg busy,
    output reg done
);
    reg [257:0] acc;
    reg [257:0] a_shift;
    reg [127:0] b_reg;
    reg [7:0] bit_idx;
    reg running;

    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            acc <= 0;
            a_shift <= 0;
            b_reg <= 0;
            bit_idx <= 0;
            product_out <= 0;
            busy <= 0;
            done <= 0;
            running <= 0;
        end else begin
            done <= 0; // pulse
            if(start && !running) begin
                acc <= 0;
                a_shift <= {128'b0, a_in};
                b_reg <= b_in;
                bit_idx <= 0;
                busy <= 1;
                running <= 1;
            end else if(running) begin
                // Perform multiply-add step
                if(b_reg[0]) acc <= acc + a_shift;
                a_shift <= a_shift << 1;
                b_reg <= b_reg >> 1;
                bit_idx <= bit_idx + 1;

                // Done condition
                if(bit_idx == 127) begin
                    product_out <= acc;
                    busy <= 0;
                    done <= 1;  // single-cycle pulse
                    running <= 0;
                end
            end
        end
    end
endmodule

