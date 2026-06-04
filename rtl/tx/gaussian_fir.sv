// =============================================================================
// gaussian_fir.sv — Gaussian pre-modulation filter for GFSK (BT = 0.5)
// =============================================================================
// 49-tap symmetric FIR.  Sequential one-tap-per-clock MAC avoids DSP timing
// closure issues (critical path is one multiply-accumulate per system clock).
//
// Parameters:
//   TAPS  — number of filter taps (must be odd; default 49)
//   WIDTH — I/O word width in bits (default 12)
//
// Coefficients (COEF_W = 10 bits, Q0.9 fixed-point):
//   Designed for BT=0.5, OSR=8 (8 samples/symbol at 1 MHz sample clock).
//   Spans L=3 symbol periods.  sum(coef) = 3259 ≈ 2^12 → output MSBs scaled
//   by >> 12 after accumulation to keep WIDTH-bit output.
//
// Timing:
//   Group delay = (TAPS-1)/2 = 24 sample clocks.
//   valid_out rises TAPS clocks after first valid_in.
//
// Interface note: uses clk_en (symbol-rate enable) — register updates and MAC
// only happen when clk_en = 1.
// =============================================================================
`timescale 1ns / 1ps

module gaussian_fir #(
    parameter int TAPS  = 49,
    parameter int WIDTH = 12
) (
    input  logic                    clk,
    input  logic                    rst_n,     // active-low reset
    input  logic                    clk_en,    // sample-rate clock enable (1 MHz)
    input  logic signed [WIDTH-1:0] data_in,   // NRZ input symbol
    output logic signed [WIDTH-1:0] data_out   // Gaussian-shaped output
);

    // -------------------------------------------------------------------------
    // Gaussian filter coefficients: BT=0.5, OSR=8, 49 taps
    // Symmetric — coef[i] = coef[TAPS-1-i], center at index 24
    // Quantized to 10-bit unsigned, scale = 511/h_max
    // Row order: coef[0] .. coef[48]
    // -------------------------------------------------------------------------
    localparam int COEF_W   = 10;
    localparam int ACC_BITS = WIDTH + COEF_W + 7;  // headroom for sum of 49 products

    localparam signed [COEF_W-1:0] COEF [0:48] = '{
        10'sd0,  10'sd0,  10'sd0,  10'sd0,  10'sd0,   // [0..4]   outer tails
        10'sd0,  10'sd0,  10'sd0,  10'sd0,  10'sd0,   // [5..9]
        10'sd0,  10'sd0,  10'sd0,  10'sd0,  10'sd0,   // [10..14]
        10'sd1,  10'sd4,  10'sd12, 10'sd32, 10'sd74,  // [15..19]
        10'sd149,10'sd255,10'sd375,10'sd472,10'sd511,  // [20..24] center=511
        10'sd472,10'sd375,10'sd255,10'sd149,10'sd74,  // [25..29]
        10'sd32, 10'sd12, 10'sd4,  10'sd1,  10'sd0,   // [30..34]
        10'sd0,  10'sd0,  10'sd0,  10'sd0,  10'sd0,   // [35..39]
        10'sd0,  10'sd0,  10'sd0,  10'sd0,  10'sd0,   // [40..44]
        10'sd0,  10'sd0,  10'sd0,  10'sd0              // [45..48]
    };

    // -------------------------------------------------------------------------
    // Delay line (shift register, updates on clk_en)
    // -------------------------------------------------------------------------
    logic signed [WIDTH-1:0] dl [0:TAPS-1];

    // -------------------------------------------------------------------------
    // Sequential MAC: one multiply per clock cycle using tap_idx counter
    // tap_idx runs 0..TAPS-1 over TAPS system clocks between each clk_en.
    // Because clk_en fires once every DIV_RATIO=100 sys-clks, we have 100
    // cycles to compute 49 multiplies — plenty of headroom.
    // -------------------------------------------------------------------------
    logic [$clog2(TAPS)-1:0]      tap_idx;
    logic signed [ACC_BITS-1:0]   acc;
    logic                         acc_valid;   // goes high when MAC is complete
    logic                         mac_running;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < TAPS; i++) dl[i] <= '0;
            tap_idx   <= '0;
            acc       <= '0;
            acc_valid <= 1'b0;
            mac_running <= 1'b0;
            data_out  <= '0;
        end else begin
            acc_valid <= 1'b0;

            if (clk_en) begin
                // Shift delay line: dl[TAPS-1] = oldest, dl[0] = newest
                for (int i = TAPS-1; i > 0; i--) dl[i] <= dl[i-1];
                dl[0]       <= data_in;
                // Start MAC on next cycle
                tap_idx     <= '0;
                acc         <= '0;
                mac_running <= 1'b1;
            end else if (mac_running) begin
                // Accumulate one tap per system clock
                acc     <= acc + ({{(ACC_BITS-WIDTH){dl[tap_idx][WIDTH-1]}}, dl[tap_idx]}
                                  * {{(ACC_BITS-COEF_W){COEF[tap_idx][COEF_W-1]}}, COEF[tap_idx]});
                tap_idx <= tap_idx + 1'b1;
                if (tap_idx == TAPS - 1) begin
                    mac_running <= 1'b0;
                    acc_valid   <= 1'b1;
                end
            end

            // Latch output when accumulation completes
            // Divide by sum_of_coefs ≈ 3259 ≈ 2^11.67; use >> 12 for simplicity
            if (acc_valid)
                data_out <= acc[ACC_BITS-1 : ACC_BITS-WIDTH];
        end
    end

endmodule
