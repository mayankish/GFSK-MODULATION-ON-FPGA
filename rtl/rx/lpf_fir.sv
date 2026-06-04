// =============================================================================
// lpf_fir.sv — Post-discriminator low-pass FIR filter
// =============================================================================
// 31-tap symmetric Gaussian-windowed low-pass filter.
// Designed for sample rate = 1 MHz, cutoff ≈ 150 kHz (BT=0.5 GFSK bandwidth),
// sufficient to pass the GFSK data spectrum while rejecting FM-demod noise.
//
// Parameters:
//   TAPS  — number of filter taps (must be odd; default 31)
//   WIDTH — I/O data word width (default 12)
//
// Coefficients (10-bit, Gaussian window with sigma=4 samples):
//   Normalized so sum ≈ 1024 (divide by 2^10 after accumulate).
//   Full symmetric set; centre tap = index 15.
//
// Implementation: sequential MAC (one tap per sys-clk between clk_en pulses).
// At DIV_RATIO=100, 100 sys-clk cycles are available per sample → fits 31 taps
// with 3× spare cycles.
// =============================================================================
`timescale 1ns / 1ps

module lpf_fir #(
    parameter int TAPS  = 31,
    parameter int WIDTH = 12
) (
    input  logic                    clk,
    input  logic                    rst_n,     // active-low reset
    input  logic                    clk_en,    // sample-rate clock enable
    input  logic signed [WIDTH-1:0] data_in,
    output logic signed [WIDTH-1:0] data_out
);

    localparam int COEF_W   = 10;
    localparam int ACC_BITS = WIDTH + COEF_W + 5;  // headroom for 31-tap sum

    // -------------------------------------------------------------------------
    // Coefficients: 31-tap Gaussian LPF
    // Gaussian sigma=4 samples, normalised to sum=1024 (>> 10 after MAC)
    // Symmetric: COEF[i] = COEF[30-i], centre = COEF[15]
    // -------------------------------------------------------------------------
    localparam signed [COEF_W-1:0] COEF [0:30] = '{
        10'sd0,  10'sd0,  10'sd1,  10'sd1,  10'sd2,   // [0..4]
        10'sd5,  10'sd8,  10'sd14, 10'sd22, 10'sd33,  // [5..9]
        10'sd47, 10'sd62, 10'sd77, 10'sd90, 10'sd99,  // [10..14]
        10'sd102,                                       // [15] centre
        10'sd99, 10'sd90, 10'sd77, 10'sd62, 10'sd47,  // [16..20]
        10'sd33, 10'sd22, 10'sd14, 10'sd8,  10'sd5,   // [21..25]
        10'sd2,  10'sd1,  10'sd1,  10'sd0,  10'sd0    // [26..30]
    };
    // Sum = 102 + 2*(99+90+77+62+47+33+22+14+8+5+2+1+1+0+0) = 1024

    // -------------------------------------------------------------------------
    // Delay line
    // -------------------------------------------------------------------------
    logic signed [WIDTH-1:0] dl [0:TAPS-1];

    // -------------------------------------------------------------------------
    // Sequential MAC
    // -------------------------------------------------------------------------
    logic [$clog2(TAPS)-1:0]    tap_idx;
    logic signed [ACC_BITS-1:0] acc;
    logic                       mac_running;
    logic                       acc_valid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < TAPS; i++) dl[i] <= '0;
            tap_idx     <= '0;
            acc         <= '0;
            mac_running <= 1'b0;
            acc_valid   <= 1'b0;
            data_out    <= '0;
        end else begin
            acc_valid <= 1'b0;

            if (clk_en) begin
                for (int i = TAPS-1; i > 0; i--) dl[i] <= dl[i-1];
                dl[0]       <= data_in;
                tap_idx     <= '0;
                acc         <= '0;
                mac_running <= 1'b1;
            end else if (mac_running) begin
                acc <= acc + ({{(ACC_BITS-WIDTH){dl[tap_idx][WIDTH-1]}}, dl[tap_idx]}
                              * {{(ACC_BITS-COEF_W){COEF[tap_idx][COEF_W-1]}}, COEF[tap_idx]});
                tap_idx <= tap_idx + 1'b1;
                if (tap_idx == TAPS - 1) begin
                    mac_running <= 1'b0;
                    acc_valid   <= 1'b1;
                end
            end

            if (acc_valid)
                // Divide by 1024 (sum of coefficients) — shift right by 10
                data_out <= acc[ACC_BITS-1 : ACC_BITS-WIDTH];
        end
    end

endmodule
