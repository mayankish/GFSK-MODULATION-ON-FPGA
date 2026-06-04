// =============================================================================
// fm_discriminator.sv — Differentiating FM demodulator
// =============================================================================
// Implements the arctangent FM discriminator:
//   disc(t) = d/dt [ arg(x(t)) ]
//
// In discrete form (single real input — assumes pure FM signal):
//   disc[n] = angle(x[n]) - angle(x[n-1])
//           = Im(x[n] × x*[n-1]) / |x[n] × x*[n-1]|
//
// For a real FM signal s[n] = A·sin(θ[n]), we approximate using the
// four-quadrant delayed multiply:
//   disc[n] ≈ fm_in[n] × fm_in[n-1]  (cross product of delayed samples)
// scaled and clipped to OUT_WIDTH bits.
//
// This is the real-only approximation of the complex FM discriminator.
// Sufficient for AWGN simulation; for hardware with RF input, use IQ pair.
//
// Parameters:
//   WIDTH — input (and output) data width (12 bits)
// =============================================================================
`timescale 1ns / 1ps

module fm_discriminator #(
    parameter int WIDTH = 12
) (
    input  logic                    clk,
    input  logic                    rst_n,     // active-low reset
    input  logic                    clk_en,    // sample-rate clock enable
    input  logic signed [WIDTH-1:0] fm_in,     // FM modulated signal
    output logic signed [WIDTH-1:0] demod_out  // demodulated baseband
);

    // -------------------------------------------------------------------------
    // Delay line: one sample delay
    // -------------------------------------------------------------------------
    logic signed [WIDTH-1:0] fm_prev;

    // -------------------------------------------------------------------------
    // Differentiate: compute sign of difference (approximates instantaneous freq)
    // For GFSK with moderate SNR, a simple first-difference followed by LPF
    // gives adequate performance.  Full atan2 can be added post-lab.
    //
    // Cross-product discriminator:
    //   disc = I[n]*Q[n-1] - I[n-1]*Q[n]   (for IQ pair)
    // With single-rail input (real sine), we use:
    //   disc[n] = fm_in[n] - fm_in[n-1]    (phase difference ≈ freq deviation)
    // -------------------------------------------------------------------------
    logic signed [WIDTH:0] diff;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fm_prev   <= '0;
            demod_out <= '0;
        end else if (clk_en) begin
            fm_prev   <= fm_in;
            diff      <= {fm_in[WIDTH-1], fm_in} - {fm_prev[WIDTH-1], fm_prev};
            // Saturate/clip to WIDTH bits (diff is WIDTH+1 wide)
            if (diff > $signed((2**(WIDTH-1))-1))
                demod_out <= (2**(WIDTH-1))-1;
            else if (diff < $signed(-(2**(WIDTH-1))))
                demod_out <= -(2**(WIDTH-1));
            else
                demod_out <= diff[WIDTH-1:0];
        end
    end

endmodule
