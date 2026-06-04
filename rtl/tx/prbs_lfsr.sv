// =============================================================================
// prbs_lfsr.sv — Pseudo-Random Binary Sequence generator (Fibonacci LFSR)
// =============================================================================
// Implements a configurable-length LFSR for PRBS-N generation.
// The polynomial is specified as a bitmask (POLY_MASK); bit k of POLY_MASK
// corresponds to tap at LFSR position k.
//
// Default: PRBS-9  (poly x^9 + x^5 + 1, mask = 9'b1_0001_0000 = 9'h110)
// Output rate: one bit per clk_en assertion.
//
// Parameters:
//   POLY_ORDER — shift register length (equals LFSR degree)
//   POLY_MASK  — feedback tap bitmask (must include bit [POLY_ORDER-1])
// =============================================================================
`timescale 1ns / 1ps

module prbs_lfsr #(
    parameter int          POLY_ORDER = 9,
    parameter logic [8:0]  POLY_MASK  = 9'b1_0001_0000   // x^9 + x^5 + 1
) (
    input  logic clk,
    input  logic rst_n,     // active-low reset
    input  logic clk_en,    // symbol-rate clock enable
    input  logic enable,    // 1 = run LFSR, 0 = hold (SW-controlled)
    output logic data_out   // MSB of LFSR shift register
);

    logic [POLY_ORDER-1:0] lfsr;
    logic                  feedback;

    // XOR all tapped positions
    always_comb begin
        feedback = 1'b0;
        for (int i = 0; i < POLY_ORDER; i++) begin
            if (POLY_MASK[i]) feedback ^= lfsr[i];
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr <= {POLY_ORDER{1'b1}};     // all-ones seed (never all-zeros)
        end else if (clk_en && enable) begin
            lfsr <= {lfsr[POLY_ORDER-2:0], feedback};
        end
    end

    assign data_out = lfsr[POLY_ORDER-1];

endmodule
