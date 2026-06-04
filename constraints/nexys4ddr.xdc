# =============================================================================
# gfsk_modem.xdc — Nexys 4 DDR (Artix-7 XC7A100T-CSG324)
# =============================================================================

# ---- Clock ------------------------------------------------------------------
set_property -dict {PACKAGE_PIN W5 IOSTANDARD LVCMOS33} [get_ports clk]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk]

# ---- Reset: BTNC (active-HIGH, inverted in RTL to rst_n_int) ----------------
set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVCMOS33} [get_ports rst_n]

# ---- Switches ---------------------------------------------------------------
set_property -dict {PACKAGE_PIN V17 IOSTANDARD LVCMOS33} [get_ports sw_loopback]  ;# SW0
set_property -dict {PACKAGE_PIN V16 IOSTANDARD LVCMOS33} [get_ports sw_prbs_en]   ;# SW1

# ---- LEDs -------------------------------------------------------------------
set_property -dict {PACKAGE_PIN U16 IOSTANDARD LVCMOS33} [get_ports {err_leds[0]}]  ;# LED0
set_property -dict {PACKAGE_PIN E19 IOSTANDARD LVCMOS33} [get_ports {err_leds[1]}]  ;# LED1
set_property -dict {PACKAGE_PIN U19 IOSTANDARD LVCMOS33} [get_ports {err_leds[2]}]  ;# LED2
set_property -dict {PACKAGE_PIN V19 IOSTANDARD LVCMOS33} [get_ports {err_leds[3]}]  ;# LED3
set_property -dict {PACKAGE_PIN U15 IOSTANDARD LVCMOS33} [get_ports led_err_any]    ;# LED14
set_property -dict {PACKAGE_PIN V14 IOSTANDARD LVCMOS33} [get_ports led_locked]     ;# LED15
set_property -dict {PACKAGE_PIN V11 IOSTANDARD LVCMOS33} [get_ports led_done]       ;# LD0 green (RGB)

# ---- UART TX ----------------------------------------------------------------
# Nexys 4 DDR: UART_TXD_IN = C4, USB-UART bridge (CP2103)
set_property -dict {PACKAGE_PIN C4  IOSTANDARD LVCMOS33} [get_ports uart_tx]

# ---- Timing false paths (output LEDs are asynchronous indicators) -----------
# Enumerate each bit individually — bracket [] syntax not valid in XDC
set_false_path -to [get_ports {err_leds[0]}]
set_false_path -to [get_ports {err_leds[1]}]
set_false_path -to [get_ports {err_leds[2]}]
set_false_path -to [get_ports {err_leds[3]}]
set_false_path -to [get_ports led_err_any]
set_false_path -to [get_ports led_locked]
set_false_path -to [get_ports led_done]
