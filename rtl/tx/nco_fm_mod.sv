// =============================================================================
// nco_fm_mod.sv — Numerically Controlled Oscillator for FM modulation
// =============================================================================
// Implements FM modulation via a phase accumulator NCO.
// The instantaneous frequency deviation is proportional to freq_dev (the
// Gaussian-filtered NRZ signal).
//
// Architecture:
//   phase_acc += freq_word  (every clk_en)
//   sine_out  = sin_lut[phase_acc[ACCUM_WIDTH-1 : ACCUM_WIDTH-LUT_ADDR_W]]
//   phase_acc exposed for debug
//
// Parameters:
//   ACCUM_WIDTH — phase accumulator width in bits (22 → ~0.024 Hz resolution at 1 MHz)
//   OUT_WIDTH   — output sine amplitude word width (12 bits)
//   LUT_DEPTH   — number of LUT entries (must be power of 2; default 1024)
//
// Modulation index:
//   Peak phase step = freq_dev_max / fs × 2^ACCUM_WIDTH
//   For GFSK h=0.5, fd = h/(2T) = 0.5×125kHz = 62.5kHz
//   At fs=1MHz: peak_step = 62500/1000000 × 2^22 = 261208
//   This is baked into FREQ_SCALE below (scaled by max amplitude 2047).
//
// NOTE: $sin/$cos in initial blocks are simulation-only.
//       For synthesis, replace with a BROM or CORDIC IP.
// =============================================================================
`timescale 1ns / 1ps

module nco_fm_mod #(
    parameter int ACCUM_WIDTH = 22,
    parameter int OUT_WIDTH   = 12,
    parameter int LUT_DEPTH   = 1024
) (
    input  logic                         clk,
    input  logic                         rst_n,       // active-low reset
    input  logic                         clk_en,      // sample-rate clock enable
    input  logic signed [OUT_WIDTH-1:0]  freq_dev,    // from gaussian_fir output
    output logic signed [OUT_WIDTH-1:0]  sine_out,    // FM modulated sample
    output logic        [ACCUM_WIDTH-1:0] phase_acc   // instantaneous phase (debug)
);

    localparam int LUT_ADDR_W  = $clog2(LUT_DEPTH);

    // -------------------------------------------------------------------------
    // Frequency scaling factor
    // Maps freq_dev (±2047 full scale) to peak phase increment.
    // FREQ_SCALE = round(fd_max / fs × 2^ACCUM_WIDTH / freq_dev_max)
    //            = round(62500 / 1e6 × 2^22 / 2047) = round(128) = 128
    // Adjust if symbol rate or modulation index changes.
    // -------------------------------------------------------------------------
    localparam int FREQ_SCALE = 128;

    // -------------------------------------------------------------------------
    // Sine LUT  — initialised with $sin (simulation & synthesis with IP)
    // -------------------------------------------------------------------------
    logic signed [OUT_WIDTH-1:0] sin_lut [0:LUT_DEPTH-1];

    initial begin
        for (int k = 0; k < LUT_DEPTH; k++) begin
            sin_lut[k] = $rtoi($sin(2.0 * 3.14159265358979 * k / LUT_DEPTH)
                                * (2.0 ** (OUT_WIDTH-1) - 1.0));
        end
    end

    // -------------------------------------------------------------------------
    // Phase accumulator + NCO
    // -------------------------------------------------------------------------
    logic signed [ACCUM_WIDTH + OUT_WIDTH - 1 : 0] freq_word_ext;
    logic signed [ACCUM_WIDTH-1:0]                  freq_word;

    always_comb begin
        // Scale freq_dev to a signed phase increment
        freq_word_ext = {{(ACCUM_WIDTH){freq_dev[OUT_WIDTH-1]}}, freq_dev}
                        * $signed(FREQ_SCALE[ACCUM_WIDTH-1:0]);
        freq_word     = freq_word_ext[ACCUM_WIDTH + OUT_WIDTH - 2 : OUT_WIDTH - 1];
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_acc <= '0;
            sine_out  <= '0;
        end else if (clk_en) begin
            phase_acc <= phase_acc + $unsigned(freq_word);
            sine_out  <= sin_lut[phase_acc[ACCUM_WIDTH-1 : ACCUM_WIDTH-LUT_ADDR_W]];
        end
    end

endmodule
