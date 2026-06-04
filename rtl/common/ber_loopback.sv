// =============================================================================
// ber_loopback.sv
// On-FPGA hardware BER measurement block
//
// Compares TX bit (from PRBS source) against recovered RX bit at each valid
// symbol, accumulates error count and total bit count.  A 32-bit saturating
// counter for each.  Overflow flag goes high if either counter hits 2^32-1.
//
// Usage:
//   Connect tx_bit → the PRBS output before any latency (or compensate latency)
//   Connect rx_bit → slicer output
//   Connect rx_valid → Gardner TED sym_valid (asserts one clock per symbol)
//   Read err_count and total_bits via UART or ILA
// =============================================================================
`timescale 1ns / 1ps

module ber_loopback (
    input  logic        clk,
    input  logic        rst_n,       // active-low
    input  logic        clk_en,      // 1 MHz symbol-rate enable

    input  logic        rx_valid,    // asserts for one clk when symbol is ready
    input  logic        tx_bit,      // reference TX bit (pre-channel)
    input  logic        rx_bit,      // recovered RX bit

    output logic [31:0] err_count,   // cumulative bit errors (saturating)
    output logic [31:0] total_bits,  // cumulative total bits (saturating)
    output logic        overflow     // either counter hit max value
);

    // -----------------------------------------------------------------------
    // Pipeline the TX bit to align with RX latency
    // GFSK modem pipeline latency (cycles at 1 MHz clk_en):
    //   gaussian_fir  : (49-1)/2 = 24 symbol clocks (group delay)
    //   fm_discriminator: 1
    //   lpf_fir       : (31-1)/2 = 15
    //   gardner_ted   : SAMPLES_PER_SYM/2 = 4
    //   slicer        : 1
    //   total         : ~45 symbol-clock cycles
    // Adjust PIPE_DEPTH to match your actual measured latency.
    // -----------------------------------------------------------------------
    localparam int PIPE_DEPTH = 45;

    logic [PIPE_DEPTH-1:0] tx_pipe;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            tx_pipe <= '0;
        end else if (clk_en) begin
            tx_pipe <= {tx_pipe[PIPE_DEPTH-2:0], tx_bit};
        end
    end

    logic tx_delayed;
    assign tx_delayed = tx_pipe[PIPE_DEPTH-1];

    // -----------------------------------------------------------------------
    // Error and total-bit counters (saturating at 32'hFFFF_FFFF)
    // -----------------------------------------------------------------------
    logic bit_error;
    assign bit_error = rx_valid & (tx_delayed ^ rx_bit); // XOR → 1 if error

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            err_count   <= 32'h0;
            total_bits  <= 32'h0;
        end else if (clk_en && rx_valid) begin
            // Total bits
            if (total_bits != 32'hFFFF_FFFF)
                total_bits <= total_bits + 1'b1;

            // Error count
            if (bit_error) begin
                if (err_count != 32'hFFFF_FFFF)
                    err_count <= err_count + 1'b1;
            end
        end
    end

    assign overflow = (err_count == 32'hFFFF_FFFF) | (total_bits == 32'hFFFF_FFFF);

endmodule
