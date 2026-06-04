// =============================================================================
// gardner_ted.sv — Gardner Timing Error Detector + Symbol Synchroniser
// =============================================================================
// Implements the Gardner timing error detector for symbol timing recovery.
//
// Gardner TED formula:
//   e[k] = Re{ (x[k] - x[k-1]) × x*[k-1/2] }
// For a real signal:
//   e[k] = (x[k] - x[k-1]) × x[k - SPY/2]
//
// The PI loop filter adjusts a countdown modulo SPY so that the symbol
// strobe (sym_valid) aligns to the best sampling instant over time.
//
// Parameters:
//   WIDTH          — data word width (12 bits)
//   SAMPLES_PER_SYM — oversampling ratio (8 samples per symbol)
//
// Outputs:
//   timing_err  — Gardner TED error value (debug / ILA)
//   sym_valid   — pulses HIGH for one clk when a symbol sample is ready
//   (data to slicer is taken directly from lpf_fir output in top module)
// =============================================================================
`timescale 1ns / 1ps

module gardner_ted #(
    parameter int WIDTH          = 12,
    parameter int SAMPLES_PER_SYM = 8
) (
    input  logic                    clk,
    input  logic                    rst_n,      // active-low reset
    input  logic                    clk_en,     // sample-rate clock enable
    input  logic signed [WIDTH-1:0] data_in,    // from lpf_fir
    output logic signed [WIDTH-1:0] timing_err, // Gardner error (debug)
    output logic                    sym_valid    // symbol strobe
);

    localparam int SPY      = SAMPLES_PER_SYM;
    localparam int HALF_SPY = SPY / 2;

    // -------------------------------------------------------------------------
    // Sample buffer — store SPY samples to compute TED
    // -------------------------------------------------------------------------
    logic signed [WIDTH-1:0] buf [0:SPY-1];   // circular buffer
    logic [$clog2(SPY)-1:0]  wr_ptr;

    // -------------------------------------------------------------------------
    // PI loop filter
    // -------------------------------------------------------------------------
    localparam int KP = 2;    // proportional gain (right-shift count)
    localparam int KI = 5;    // integral gain (right-shift count)

    logic signed [WIDTH+2:0] integ_acc;       // integrator accumulator
    logic [$clog2(SPY)-1:0]  countdown;       // fractional sample counter
    logic                    use_early;        // 1 = advance by 1 sample

    // -------------------------------------------------------------------------
    // Gardner TED computation
    // -------------------------------------------------------------------------
    logic signed [WIDTH-1:0]   x_cur, x_prev, x_mid;
    logic signed [WIDTH*2-1:0] ted_raw;
    logic signed [WIDTH-1:0]   ted_err;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < SPY; i++) buf[i] <= '0;
            wr_ptr     <= '0;
            countdown  <= SPY - 1;
            integ_acc  <= '0;
            timing_err <= '0;
            sym_valid  <= 1'b0;
        end else begin
            sym_valid <= 1'b0;   // default

            if (clk_en) begin
                // Write new sample into circular buffer
                buf[wr_ptr] <= data_in;
                wr_ptr      <= wr_ptr + 1'b1;

                // Decrement symbol countdown
                if (countdown == '0) begin
                    // --- Symbol boundary ---
                    countdown <= use_early ? (SPY - 2) : (SPY - 1);
                    sym_valid <= 1'b1;

                    // Retrieve samples: current, previous, mid-point
                    x_cur  = data_in;
                    x_prev = buf[(wr_ptr - SPY    + SPY) % SPY];
                    x_mid  = buf[(wr_ptr - HALF_SPY + SPY) % SPY];

                    // Gardner TED: e = (x_cur - x_prev) * x_mid
                    ted_raw   = (x_cur - x_prev) * x_mid;
                    ted_err   = ted_raw[WIDTH*2-1 : WIDTH];  // normalise

                    timing_err <= ted_err;

                    // PI filter
                    integ_acc  <= integ_acc + (ted_err >>> KI);
                    use_early  <= (ted_err + (integ_acc >>> KP)) > 0;
                end else begin
                    countdown <= countdown - 1'b1;
                end
            end
        end
    end

endmodule
