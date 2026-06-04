// =============================================================================
// tb_gfsk_modem.sv — Simple loopback testbench for top_gfsk_modem
// =============================================================================
// Drives clock and reset, holds sw_loopback=1 and sw_prbs_en=1, then
// monitors BER counters via UART TX ASCII output.
//
// Run for 15 million clocks (~150ms simulated) to collect ~18750 bits at
// 125 kbps symbol rate.  Watch for uart_tx waveform to decode ERR/TOT counts.
//
// Usage in Vivado:
//   Set this as simulation top.
//   Run behavioural simulation → add uart_tx, ber signals to waveform.
//   In Tcl: run 15ms
// =============================================================================
`timescale 1ns / 1ps

module tb_gfsk_modem;

    // -------------------------------------------------------------------------
    // Clock and reset
    // -------------------------------------------------------------------------
    localparam int CLK_PERIOD = 10;  // 100 MHz → 10 ns

    logic clk   = 0;
    logic rst_n = 1;   // active-HIGH on Nexys4 (top module inverts internally)

    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // DUT
    // -------------------------------------------------------------------------
    logic [3:0] err_leds;
    logic       led_locked, led_done, led_err_any;
    logic       uart_tx;

    top_gfsk_modem dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .sw_loopback (1'b1),   // loopback enabled
        .sw_prbs_en  (1'b1),   // PRBS source enabled
        .err_leds    (err_leds),
        .led_locked  (led_locked),
        .led_done    (led_done),
        .led_err_any (led_err_any),
        .uart_tx     (uart_tx)
    );

    // -------------------------------------------------------------------------
    // VCD dump for GTKWave
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_gfsk_modem.vcd");
        $dumpvars(0, tb_gfsk_modem);
    end

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        // Assert reset (BTNC = active-HIGH on Nexys4)
        rst_n = 1;
        repeat (20) @(posedge clk);
        rst_n = 0;   // release reset (button not pressed → modem runs)
        $display("[%0t ns] Reset released. Modem running.", $time);

        // Run 15 million clocks (≈ 18750 symbols at 125 kbps)
        repeat (15_000_000) @(posedge clk);

        $display("[%0t ns] Simulation done. err_leds=%b led_locked=%b",
                 $time, err_leds, led_locked);
        $finish;
    end

    // -------------------------------------------------------------------------
    // Periodic status printout every 1 million clocks
    // -------------------------------------------------------------------------
    always begin
        repeat (1_000_000) @(posedge clk);
        $display("[%0t ns] err_leds=%b  led_done=%b  led_err_any=%b",
                 $time, err_leds, led_done, led_err_any);
    end

endmodule
