// =============================================================================
// nrz_mapper.sv — Binary to NRZ amplitude mapper
// =============================================================================
// Maps a single bit to a signed two-level NRZ symbol:
//   bit = 1  →  +(2^(WIDTH-1) - 1)   e.g. +2047 for WIDTH=12
//   bit = 0  →  -(2^(WIDTH-1))        e.g. -2048 for WIDTH=12
//
// Output is registered to prevent glitches propagating into the FIR filter.
// =============================================================================
`timescale 1ns / 1ps

module nrz_mapper #(
    parameter int WIDTH = 12
) (
    input  logic                      clk,
    input  logic                      rst_n,    // active-low reset
    input  logic                      clk_en,   // symbol-rate clock enable
    input  logic                      bit_in,   // PRBS / data bit
    output logic signed [WIDTH-1:0]   nrz_out   // NRZ amplitude
);

    // Use parameters to avoid elaboration-time constant evaluation issues
    localparam signed [WIDTH-1:0] POS_AMP =  (2 ** (WIDTH-1)) - 1;  // +2047
    localparam signed [WIDTH-1:0] NEG_AMP = -(2 ** (WIDTH-1));       // -2048

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            nrz_out <= POS_AMP;
        else if (clk_en)
            nrz_out <= bit_in ? POS_AMP : NEG_AMP;
    end

endmodule
