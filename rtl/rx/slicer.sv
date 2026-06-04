// =============================================================================
// slicer.sv — Hard decision slicer
// =============================================================================
// Makes a binary hard decision on each received sample:
//   data_in >= 0  →  bit_out = 1
//   data_in <  0  →  bit_out = 0
//
// Decision is latched on sym_valid (asserted by gardner_ted).
//
// Parameters:
//   WIDTH — input data word width (12 bits)
// =============================================================================
`timescale 1ns / 1ps

module slicer #(
    parameter int WIDTH = 12
) (
    input  logic                    clk,
    input  logic                    rst_n,     // active-low reset
    input  logic                    sym_valid, // from gardner_ted
    input  logic signed [WIDTH-1:0] data_in,   // from lpf_fir
    output logic                    bit_out    // recovered data bit
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_out <= 1'b0;
        end else if (sym_valid) begin
            bit_out <= (data_in >= 0) ? 1'b1 : 1'b0;
        end
    end

endmodule
