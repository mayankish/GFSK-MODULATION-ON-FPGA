// =============================================================================
// tb_ber_gfsk.sv
// BER simulation testbench for GFSK modem
//
// Sweeps Eb/N0 from 0 dB to 14 dB in 1 dB steps.
// At each step: transmits NUM_BITS bits through modem + AWGN channel,
// counts errors, writes BER to "ber_results.txt".
//
// Run with: xvlog/xelab in Vivado Sim, or Questa/Modelsim
// Output file: ber_results.txt  (parse with ber_analysis.m)
// =============================================================================
`timescale 1ns / 1ps

module tb_ber_gfsk;

    // -----------------------------------------------------------------------
    // Parameters
    // -----------------------------------------------------------------------
    localparam int CLK_PERIOD_NS = 10;        // 100 MHz
    localparam int SYMCLK_DIV    = 100;       // → 1 MHz symbol rate
    localparam int NUM_BITS      = 100_000;   // bits per Eb/N0 point
    localparam int EBN0_MIN_DB   = 0;
    localparam int EBN0_MAX_DB   = 14;
    localparam int SAMPLES_SYM   = 8;         // oversampling ratio in sim
    localparam int WIDTH         = 12;

    // -----------------------------------------------------------------------
    // DUT signals
    // -----------------------------------------------------------------------
    logic        clk   = 0;
    logic        rst_n;
    logic        clk_en;
    logic        tx_bit_src;       // PRBS
    logic        tx_nrz;
    logic [11:0] tx_gauss;
    logic [11:0] tx_mod;           // FM modulated
    logic [11:0] rx_noisy;         // tx_mod + AWGN
    logic [11:0] rx_disc;
    logic [11:0] rx_lpf;
    logic        rx_valid;
    logic        rx_bit;
    logic [31:0] err_count;
    logic [31:0] total_bits;
    logic        overflow;

    // -----------------------------------------------------------------------
    // Clock
    // -----------------------------------------------------------------------
    always #(CLK_PERIOD_NS/2) clk = ~clk;

    // -----------------------------------------------------------------------
    // DUT instantiation
    // -----------------------------------------------------------------------
    clk_div_en #(.DIV_RATIO(SYMCLK_DIV)) u_clkdiv (
        .clk(clk), .rst_n(rst_n), .clk_out(), .clk_en(clk_en)
    );

    prbs_lfsr #(.POLY_ORDER(9), .POLY_MASK(9'b100010000)) u_prbs (
        .clk(clk), .rst_n(rst_n), .clk_en(clk_en),
        .enable(1'b1), .data_out(tx_bit_src)
    );

    nrz_mapper #(.WIDTH(WIDTH)) u_nrz (
        .clk(clk), .rst_n(rst_n), .clk_en(clk_en),
        .bit_in(tx_bit_src), .nrz_out(tx_nrz)
    );

    gaussian_fir #(.TAPS(49), .WIDTH(WIDTH)) u_gauss (
        .clk(clk), .rst_n(rst_n), .clk_en(clk_en),
        .data_in(tx_nrz), .data_out(tx_gauss)
    );

    nco_fm_mod #(.ACCUM_WIDTH(22), .OUT_WIDTH(WIDTH), .LUT_DEPTH(1024)) u_nco (
        .clk(clk), .rst_n(rst_n), .clk_en(clk_en),
        .freq_dev(tx_gauss), .sine_out(tx_mod), .phase_acc()
    );

    fm_discriminator #(.WIDTH(WIDTH)) u_disc (
        .clk(clk), .rst_n(rst_n), .clk_en(clk_en),
        .fm_in(rx_noisy), .demod_out(rx_disc)
    );

    lpf_fir #(.TAPS(31), .WIDTH(WIDTH)) u_lpf (
        .clk(clk), .rst_n(rst_n), .clk_en(clk_en),
        .data_in(rx_disc), .data_out(rx_lpf)
    );

    gardner_ted #(.WIDTH(WIDTH), .SAMPLES_PER_SYM(8)) u_ted (
        .clk(clk), .rst_n(rst_n), .clk_en(clk_en),
        .data_in(rx_lpf), .timing_err(), .sym_valid(rx_valid)
    );

    slicer #(.WIDTH(WIDTH)) u_slicer (
        .clk(clk), .rst_n(rst_n),
        .sym_valid(rx_valid), .data_in(rx_lpf), .bit_out(rx_bit)
    );

    ber_loopback u_ber (
        .clk(clk), .rst_n(rst_n), .clk_en(clk_en),
        .rx_valid(rx_valid), .tx_bit(tx_bit_src), .rx_bit(rx_bit),
        .err_count(err_count), .total_bits(total_bits), .overflow(overflow)
    );

    // -----------------------------------------------------------------------
    // AWGN noise injection
    // Real AWGN via Box-Muller using $random (simulation only)
    // noise_sigma computed from Eb/N0 at each sweep point
    // -----------------------------------------------------------------------
    real noise_sigma;
    real noise_sample;

    // Box-Muller via $realtobits / $bitstoreal not directly available in
    // all simulators; use a simplified noise injection via task below.
    task automatic inject_awgn(input real sigma, output logic [11:0] noisy_out);
        real u1, u2, z0;
        int  noise_int;
        u1 = $urandom_range(1, 32767) / 32768.0;
        u2 = $urandom_range(1, 32767) / 32768.0;
        z0 = sigma * $sqrt(-2.0 * $ln(u1)) * $cos(2.0 * 3.14159265 * u2);
        noise_int = $rtoi(z0 * 2048.0); // scale to 12-bit range
        noisy_out = tx_mod + 12'(noise_int);
    endtask

    // Apply noise every clock cycle when clk_en
    always_ff @(posedge clk) begin
        if (!rst_n)
            rx_noisy <= 12'h000;
        else if (clk_en)
            inject_awgn(noise_sigma, rx_noisy);
    end

    // -----------------------------------------------------------------------
    // Sweep stimulus
    // -----------------------------------------------------------------------
    integer fd;
    real    ebn0_db, ebn0_linear, ber_val;
    integer i;

    // Modem constants for Eb/N0 → sigma conversion
    // GFSK: BT=0.5, modulation index h=0.5
    // Signal power (12-bit sine, amplitude ~2047): Ps = 2047^2 / 2
    // Eb/N0 → N0 = Eb / (Eb/N0) ; sigma^2 = N0 / 2 (one-sided)
    localparam real SIGNAL_AMPLITUDE = 2047.0;
    localparam real Eb = (SIGNAL_AMPLITUDE * SIGNAL_AMPLITUDE) / 2.0; // normalized

    initial begin : sweep
        // Reset
        rst_n       = 0;
        noise_sigma = 0.0;
        @(posedge clk); @(posedge clk);
        rst_n = 1;
        repeat(200) @(posedge clk); // allow pipeline fill

        fd = $fopen("ber_results.txt", "w");
        $fwrite(fd, "# GFSK BER Simulation Results\n");
        $fwrite(fd, "# EbN0_dB  BER  err_count  total_bits\n");

        for (i = EBN0_MIN_DB; i <= EBN0_MAX_DB; i++) begin
            // Reset counters for this point
            rst_n = 0;
            @(posedge clk); @(posedge clk);
            rst_n = 1;
            repeat(200) @(posedge clk);

            // Compute noise sigma from Eb/N0
            ebn0_db     = real'(i);
            ebn0_linear = 10.0 ** (ebn0_db / 10.0);
            // N0 = Eb / ebn0_linear ; sigma = sqrt(N0/2)
            noise_sigma = $sqrt(Eb / (ebn0_linear * 2.0));

            // Run NUM_BITS worth of symbols
            // Each symbol = SYMCLK_DIV clocks at 100 MHz
            repeat(NUM_BITS * SYMCLK_DIV) @(posedge clk);

            // Read BER
            if (total_bits > 0)
                ber_val = real'(err_count) / real'(total_bits);
            else
                ber_val = 0.0;

            $fwrite(fd, "%0d  %.6e  %0d  %0d\n",
                    i, ber_val, err_count, total_bits);
            $display("Eb/N0=%0d dB: BER=%.4e  (%0d errors / %0d bits)",
                     i, ber_val, err_count, total_bits);
        end

        $fclose(fd);
        $display("Simulation complete. Results in ber_results.txt");
        $finish;
    end

endmodule
