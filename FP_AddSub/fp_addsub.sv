`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/15/2026 09:10:27 PM
// Design Name: 
// Module Name: fp_addsub
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module fp_addsub (
    input  logic        clk,
    input  logic        reset,
    input  logic        in_valid,
    input  logic        sub,
    input  logic [31:0] a,
    input  logic [31:0] b,
    output logic        out_valid,
    output logic [31:0] result
);

    // Right shift with sticky-bit preservation
    function automatic [26:0] shift_right_jam(
        input logic [26:0] value,
        input integer amount
    );
        logic [26:0] shifted;
        integer j;
        begin
            if (amount <= 0)
                shifted = value;
            else if (amount >= 27)
                shifted = {26'b0, (|value)};
            else begin
                shifted = value >> amount;

                for (j = 0; j < 27; j = j + 1)
                    if (j < amount)
                        shifted[0] = shifted[0] | value[j];
            end

            shift_right_jam = shifted;
        end
    endfunction


    // Floating-point addition/subtraction
    function automatic [31:0] calculate(
        input logic [31:0] aa,
        input logic [31:0] bb,
        input logic subtract
    );

        logic sa, sb, sr;

        logic [7:0] ea, eb;
        logic [22:0] fa, fb;

        logic [23:0] ma, mb;

        logic [26:0] xa, xb, mag;
        logic [27:0] sum;

        logic [24:0] rounded;
        logic [23:0] sig;

        logic [7:0] exp_field;

        integer exponent;
        integer diff;
        integer k;

        logic increment;

        begin

            sa = aa[31];
            sb = bb[31] ^ subtract;

            ea = aa[30:23];
            eb = bb[30:23];

            fa = aa[22:0];
            fb = bb[22:0];

            calculate = 32'b0;

            // --------------------------------
            // SPECIAL CASE: NaN and infinity
            // --------------------------------

            if ((ea == 8'hff && fa != 0) ||
                (eb == 8'hff && fb != 0) ||
                (ea == 8'hff && eb == 8'hff && sa != sb)) begin

                calculate = 32'h7fc00000;

            end

            else if (ea == 8'hff) begin

                calculate = {sa, 8'hff, 23'b0};

            end

            else if (eb == 8'hff) begin

                calculate = {sb, 8'hff, 23'b0};

            end

            // --------------------------------
            // SPECIAL CASE: Both operands zero
            // --------------------------------

            else if ((ea == 0 && fa == 0) &&
                     (eb == 0 && fb == 0)) begin

                calculate = {sa & sb, 31'b0};

            end

            else begin

                // --------------------------------
                // Extract significands
                // --------------------------------

                ma = {(ea != 0), fa};
                mb = {(eb != 0), fb};

                xa = {ma, 3'b000};
                xb = {mb, 3'b000};

                // --------------------------------
                // Align exponents
                // --------------------------------

                if ((ea == 0 ? 1 : $signed({24'b0,ea})) >=
                    (eb == 0 ? 1 : $signed({24'b0,eb}))) begin

                    exponent = (ea == 0) ? 1 : $signed({24'b0,ea});

                    diff = exponent -
                           ((eb == 0) ? 1 : $signed({24'b0,eb}));

                    xb = shift_right_jam(xb, diff);

                end

                else begin

                    exponent = (eb == 0) ? 1 : $signed({24'b0,eb});

                    diff = exponent -
                           ((ea == 0) ? 1 : $signed({24'b0,ea}));

                    xa = shift_right_jam(xa, diff);

                end

                // --------------------------------
                // Addition or subtraction
                // --------------------------------

                if (sa == sb) begin

                    sum = {1'b0, xa} + {1'b0, xb};

                    sr = sa;

                    if (sum[27]) begin

                        mag = sum[27:1];

                        mag[0] = mag[0] | sum[0];

                        exponent = exponent + 1;

                    end

                    else begin

                        mag = sum[26:0];

                    end

                end

                else begin

                    if (xa >= xb) begin

                        mag = xa - xb;

                        sr = sa;

                    end

                    else begin

                        mag = xb - xa;

                        sr = sb;

                    end

                end

                // --------------------------------
                // Exact cancellation
                // --------------------------------

                if (mag == 0) begin

                    calculate = 32'b0;

                end

                else begin

                    // --------------------------------
                    // Normalize
                    // --------------------------------

                    for (k = 0; k < 26; k = k + 1) begin

                        if (!mag[26] && exponent > 1) begin

                            mag = mag << 1;

                            exponent = exponent - 1;

                        end

                    end

                    // --------------------------------
                    // Round to nearest, ties to even
                    // --------------------------------

                    increment = mag[2] &
                                (mag[1] | mag[0] | mag[3]);

                    rounded = {1'b0, mag[26:3]} + increment;

                    if (rounded[24]) begin

                        sig = rounded[24:1];

                        exponent = exponent + 1;

                    end

                    else begin

                        sig = rounded[23:0];

                    end

                    // --------------------------------
                    // Overflow
                    // --------------------------------

                    if (exponent >= 255) begin

                        calculate = {sr, 8'hff, 23'b0};

                    end

                    else begin

                        // --------------------------------
                        // Normal or subnormal result
                        // --------------------------------

                        if (exponent == 1 && !sig[23])
                            exp_field = 8'b0;

                        else
                            exp_field = exponent[7:0];

                        calculate = {sr, exp_field, sig[22:0]};

                    end

                end

            end

        end

    endfunction


    // --------------------------------
    // Sequential output stage
    // --------------------------------

    always_ff @(posedge clk) begin

        if (reset) begin

            out_valid <= 1'b0;

            result <= 32'b0;

        end

        else begin

            out_valid <= in_valid;

            if (in_valid)
                result <= calculate(a, b, sub);

        end

    end

endmodule
