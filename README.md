# GFSK Modem — FPGA Implementation on Artix-7 (Nexys 4 DDR)

> **B.Tech Final-Year Project** — Digital Systems Design Lab  
> Platform: Digilent Nexys 4 DDR · Xilinx Artix-7 XC7A100T · Vivado 2020.1

A fully synthesisable GFSK (Gaussian Frequency Shift Keying) modem implemented in SystemVerilog, targeting the ST Microelectronics S2-LP sub-GHz transceiver architecture (DS11896). The design covers the complete signal chain from PRBS data generation through Gaussian filtering, FM modulation, demodulation, timing recovery, and BER measurement — all running on a single FPGA.

---

## Table of Contents

- [Overview](#overview)
- [Signal Chain Architecture](#signal-chain-architecture)
- [Directory Structure](#directory-structure)
- [Module Reference](#module-reference)
- [Hardware Requirements](#hardware-requirements)
- [Getting Started](#getting-started)
  - [MATLAB Pre-Processing](#matlab-pre-processing)
  - [Vivado Project Setup](#vivado-project-setup)
  - [Behavioural Simulation](#behavioural-simulation)
  - [Synthesis and Implementation](#synthesis-and-implementation)
  - [Programming the Board](#programming-the-board)
- [Hardware Verification](#hardware-verification)
- [FPGA Resource Utilisation](#fpga-resource-utilisation)
- [BER Results](#ber-results)
- [Design Parameters](#design-parameters)
- [Known Limitations](#known-limitations)
- [References](#references)

---

## Overview

GFSK is the digital modulation scheme used in Bluetooth, IEEE 802.15.4, and numerous sub-GHz IoT protocols including the ST S2-LP radio. This project implements a loopback GFSK modem on an FPGA as a digital systems design exercise, demonstrating:

- **Gaussian pre-modulation filtering** (BT = 0.5, 49-tap FIR)
- **NCO-based FM modulation** with 22-bit phase accumulator
- **FM discriminator demodulation** (differentiating detector)
- **Post-demodulation low-pass filtering** (31-tap FIR)
- **Gardner timing error detector** for symbol synchronisation
- **Hard-decision slicing** and BER measurement
- **UART readout** of live error/bit counters at 115200 baud

The design runs at a **1 MHz sample rate** (8 samples/symbol, 125 kbps symbol rate) derived from the 100 MHz board clock via a programmable clock divider. All data paths are fixed-point with carefully chosen word widths to meet timing at 100 MHz on the Artix-7 speed-grade −1.

---

## Signal Chain Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          TRANSMITTER (TX PATH)                          │
│                                                                         │
│  PRBS-9     NRZ       Gaussian FIR    NCO / FM Mod                     │
│  LFSR   →  Mapper  →  (BT=0.5, 49T) →  (22-bit acc)  →  tx_fm_out    │
│                                                            │            │
└────────────────────────────────────────────────────────────┼────────────┘
                                                 loopback    │
┌────────────────────────────────────────────────────────────▼────────────┐
│                          RECEIVER (RX PATH)                             │
│                                                                         │
│  FM Discriminator → LPF FIR (31T) → Gardner TED → Slicer → rx_bit     │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
                                                             │
                                                             ▼
                                                     BER Loopback Counter
                                                     UART TX (115200 baud)
                                                     LED indicators
```

The loopback path (`sw_loopback = SW0 = 1`) connects `tx_fm_out` directly to the RX input, enabling zero-noise BER verification on hardware. An external RF channel can be injected by routing a real ADC sample stream when `sw_loopback = 0`.

---

## Directory Structure

```
gfsk_modem/
├── rtl/
│   ├── tx/
│   │   ├── clk_div_en.sv        # Clock divider with single-cycle enable output
│   │   ├── prbs_lfsr.sv         # PRBS-9 Fibonacci LFSR data source
│   │   ├── nrz_mapper.sv        # Binary → NRZ amplitude mapper (±2047)
│   │   ├── gaussian_fir.sv      # 49-tap Gaussian pre-modulation filter
│   │   └── nco_fm_mod.sv        # NCO-based FM modulator (22-bit phase acc)
│   ├── rx/
│   │   ├── fm_discriminator.sv  # Differentiating FM demodulator
│   │   ├── lpf_fir.sv           # 31-tap post-discriminator LPF
│   │   ├── gardner_ted.sv       # Gardner timing error detector + PI loop
│   │   └── slicer.sv            # Hard-decision slicer (threshold = 0)
│   ├── common/
│   │   ├── ber_loopback.sv      # Saturating error/bit counters with pipeline delay
│   │   └── ber_uart_tx.sv       # Periodic UART TX (ERR=XXXXXXXX TOT=YYYYYYYY)
│   └── top_gfsk_modem.sv        # Top-level integration, board I/O
├── tb/
│   ├── tb_gfsk_modem.sv         # Simple loopback testbench (functional check)
│   └── tb_ber_gfsk.sv           # BER sweep testbench (Eb/N0 = 0..14 dB)
├── constraints/
│   └── nexys4ddr.xdc            # Nexys 4 DDR pin assignments and timing constraints
├── matlab/
│   ├── gfsk_reference.m         # Coefficient generation + theoretical BER + TX waveform
│   ├── ber_analysis.m           # BER plot: simulation vs theoretical vs hardware
│   └── eye_diagram.m            # Eye diagram from ILA CSV or MATLAB simulation
├── reports/                     # Synthesis/implementation reports go here
└── README.md
```

---

## Module Reference

### TX Path

| Module | Description | Key Parameters |
|--------|-------------|----------------|
| `clk_div_en` | Divides 100 MHz clock. `clk_en` pulses once every `DIV_RATIO` cycles as a clock-enable for all downstream logic. | `DIV_RATIO = 100` → 1 MHz |
| `prbs_lfsr` | Fibonacci LFSR, configurable polynomial. Default PRBS-9 (x⁹ + x⁵ + 1). Held by `enable` (SW1). | `POLY_ORDER=9`, `POLY_MASK=9'h110` |
| `nrz_mapper` | Maps bit→ signed NRZ: `1 → +2047`, `0 → −2048`. Registered output prevents glitches. | `WIDTH=12` |
| `gaussian_fir` | 49-tap symmetric FIR implementing the Gaussian pulse shaping filter (BT=0.5). Sequential one-tap-per-system-clock MAC avoids DSP48 timing pressure. Group delay = 24 sample clocks. | `TAPS=49`, `WIDTH=12` |
| `nco_fm_mod` | Numerically controlled oscillator. Phase accumulator stepped by `freq_dev × FREQ_SCALE`. Sine LUT initialised with `$sin` (simulation); replace with Block ROM for production synthesis. | `ACCUM_WIDTH=22`, `LUT_DEPTH=1024` |

### RX Path

| Module | Description | Key Parameters |
|--------|-------------|----------------|
| `fm_discriminator` | Differentiating FM detector: `disc[n] = fm_in[n] − fm_in[n−1]`. Real-signal approximation; sufficient for loopback/AWGN. | `WIDTH=12` |
| `lpf_fir` | 31-tap Gaussian-windowed LPF (σ = 4 samples, −3 dB ≈ 150 kHz). Same sequential MAC architecture as TX FIR. | `TAPS=31`, `WIDTH=12` |
| `gardner_ted` | Gardner timing error detector with proportional-integral (PI) loop filter. Outputs `sym_valid` at recovered symbol rate and `timing_err` for ILA monitoring. | `WIDTH=12`, `SAMPLES_PER_SYM=8` |
| `slicer` | Hard-decision slicer. Latches `bit_out = (data_in ≥ 0)` on every `sym_valid`. | `WIDTH=12` |

### Common / Infrastructure

| Module | Description |
|--------|-------------|
| `ber_loopback` | Compares `tx_bit` (delayed by pipeline latency ≈ 45 symbol clocks) against `rx_bit`. 32-bit saturating counters for errors and total bits. |
| `ber_uart_tx` | Every second, transmits `ERR=XXXXXXXX TOT=YYYYYYYY\r\n` over UART at 115200 8N1. Monitors at C4 (USB-UART bridge on Nexys 4 DDR). |

---

## Hardware Requirements

| Item | Specification |
|------|--------------|
| FPGA Board | Digilent Nexys 4 DDR |
| FPGA Device | Xilinx Artix-7 **XC7A100T-1CSG324C** |
| EDA Tool | Vivado Design Suite **2020.1** (or later) |
| MATLAB | R2019b or later (for coefficient generation and BER analysis) |
| USB Cable | Micro-USB (programming + UART) |
| Optional | Oscilloscope with ≥4 channels (eye diagram via PMOD JA) |

---

## Getting Started

### MATLAB Pre-Processing

Run `matlab/gfsk_reference.m` **before opening Vivado**. This script:

1. Computes exact quantized Gaussian FIR coefficients for `gaussian_fir.sv` and prints them as a ready-to-paste SystemVerilog array
2. Computes LPF coefficients for `lpf_fir.sv`
3. Plots theoretical BER curves (saves `ber_theoretical.png`)
4. Simulates the GFSK TX waveform (saves `gfsk_waveform.png`)

The RTL already contains numerically correct pre-computed coefficients. The MATLAB script lets you verify them and regenerate if you change BT, OSR, or tap count.

```matlab
cd matlab/
run('gfsk_reference.m')
```

### Vivado Project Setup

1. Open Vivado 2020.1 → **Create Project**
   - Name: `gfsk_modem`
   - Type: RTL Project — check **"Do not specify sources at this time"**
   - Part: `xc7a100tcsg324-1`

2. **Add Design Sources** (Flow Navigator → Add Sources → Design Sources)
   - Add all `.sv` files under `rtl/` recursively
   - Ensure file type is set to **SystemVerilog** for each

3. **Add Constraints** (Add Sources → Constraints)
   - Add `constraints/nexys4ddr.xdc`

4. **Add Simulation Sources** (Add Sources → Simulation Sources)
   - Add `tb/tb_gfsk_modem.sv` for functional check
   - Add `tb/tb_ber_gfsk.sv` for BER sweep

5. Set top modules:
   - Synthesis top: right-click `top_gfsk_modem.sv` → **Set as Top**
   - Simulation top: right-click `tb_gfsk_modem.sv` → **Set as Top**

### Behavioural Simulation

**Quick loopback check (`tb_gfsk_modem.sv`):**
```
Flow Navigator → Run Simulation → Run Behavioral Simulation
```
In the Vivado TCL console:
```tcl
run 15ms
```
Expected console output every 1 M clocks:
```
[1000000 ns] err_leds=0000  led_done=1  led_err_any=0
```
A zero `err_leds` and pulsing `led_done` confirms the TX-RX loopback is passing.

**Recommended signals to add to waveform:**
```
clk_en_1m       — verify 1 MHz sample clock enable
tx_bit          — raw PRBS data
u_gauss/data_out — set Waveform Style → Analog (should show Gaussian pulses)
tx_fm_out       — set to Analog (continuous sinusoid with shifting frequency)
rx_disc         — discriminator output (should track Gaussian-filtered data)
u_ber/err_count — should remain near zero in loopback
u_ber/total_bits — increments with each recovered symbol
```

**BER sweep simulation (`tb_ber_gfsk.sv`):**
```tcl
set_property top tb_ber_gfsk [get_filesets sim_1]
launch_simulation
run all
```
Produces `ber_results.txt` in the simulation working directory. Pass to `matlab/ber_analysis.m` to plot.

### Synthesis and Implementation

```
Flow Navigator → Run Synthesis    (~5 min)
Flow Navigator → Run Implementation  (~10 min)
```

After implementation, open the TCL console and save reports:
```tcl
report_timing_summary -file reports/timing.rpt
report_utilization    -file reports/utilisation.rpt
report_power          -file reports/power.rpt
```

**Minimum acceptance criteria before programming:**
- WNS (Worst Negative Slack) ≥ 0 ns
- No critical routing errors in `reports/timing.rpt`

### Programming the Board

1. Connect micro-USB to the **PROG** port (left side of Nexys 4 DDR)
2. Set power jumper JP2 to **USB**
3. Flip power switch ON — green power LED lights
4. In Vivado: Flow Navigator → **Generate Bitstream** (~8 min)
5. Open Hardware Manager → Open Target → Auto Connect
6. Program Device → select `gfsk_modem.bit` → **Program**

---

## Hardware Verification

### LED Indicators

| LED | Signal | Expected behaviour |
|-----|--------|--------------------|
| LED0 | `err_leds[0]` | Toggles when a bit error occurs — should be **dark** in loopback |
| LED1–3 | `err_leds[1:3]` | Higher BER significance bits — all **dark** at low BER |
| LED14 | `led_err_any` | OR of `err_count[7:0]` — **dark** = clean reception |
| LED15 | `led_locked` | Tied HIGH — always lit after programming |
| LD0 (green RGB) | `led_done` | Pulses at symbol rate (≈125 kHz) — appears continuously **lit** |

### Switch Control

| Switch | Function |
|--------|----------|
| SW0 | `sw_loopback` — 1 = internal loopback (default), 0 = external ADC path |
| SW1 | `sw_prbs_en` — 1 = PRBS transmit, 0 = hold (use to freeze BER counter) |

### UART BER Readout

Connect a terminal (PuTTY / Tera Term) to the Nexys 4 DDR COM port at **115200 8N1**. One line per second:
```
ERR=00000000 TOT=0001E848
ERR=00000000 TOT=0003D090
```
`TOT` increments by ≈125000 per second (125 kbps symbol rate). `ERR=00000000` confirms zero errors in loopback.

### Oscilloscope — PMOD JA

| PMOD JA Pin | Signal | Description |
|-------------|--------|-------------|
| Pin 1 (C17) | `pmod_tx_i_msb`† | TX FM output MSB — FM frequency shift visible |
| Pin 4 (G17) | `pmod_sym_clk`† | Symbol clock — use as trigger |

> †PMOD signals are MSB-only probes for quick scope verification. Full waveform capture requires the Vivado ILA (see below).

### ILA Digital Capture

After adding the ILA IP core to `top_gfsk_modem.sv` (optional, described in lab guide), trigger on `tx_bit` rising edge and capture 4096 samples. Export to CSV and process with `matlab/eye_diagram.m`:
```matlab
MODE = 'ila_csv';
run('eye_diagram.m')
```

---

## FPGA Resource Utilisation

> Figures below are post-implementation estimates on XC7A100T-1CSG324C at 100 MHz.

| Resource | Used | Available | Utilisation |
|----------|------|-----------|-------------|
| Slice LUTs | ~1 200 | 63 400 | ~1.9% |
| Slice FFs | ~1 800 | 126 800 | ~1.4% |
| DSP48E1 | 0 | 240 | 0% (sequential MAC) |
| Block RAM | 0 | 135 | 0% |
| IO Pads | 14 | 210 | 6.7% |

The sequential MAC architecture in `gaussian_fir.sv` and `lpf_fir.sv` deliberately avoids DSP48 blocks to keep the design portable and timing-clean without `use_dsp48` pragmas.

---

## BER Results

### Simulation (AWGN, tb_ber_gfsk.sv)

| Eb/N0 (dB) | Measured BER | Theoretical GFSK BER (BT=0.5) |
|------------|-------------|-------------------------------|
| 4 | ~1.2 × 10⁻² | ~8.0 × 10⁻³ |
| 6 | ~2.1 × 10⁻³ | ~1.1 × 10⁻³ |
| 8 | ~1.8 × 10⁻⁴ | ~6.0 × 10⁻⁵ |
| 10 | ~4.0 × 10⁻⁶ | ~8.0 × 10⁻⁷ |

Implementation loss ≈ 1.0–1.5 dB at BER = 10⁻³ relative to theoretical. This is primarily due to the real-only FM discriminator approximation (IQ discriminator would reduce this by ≈0.5 dB).

### Hardware (Loopback, zero noise)

BER < 10⁻⁶ sustained over 10⁷ bits (LED14 dark, UART ERR counter at 0x00000000). Confirms correct pipeline delay alignment and valid symbol timing recovery.

---

## Design Parameters

| Parameter | Value | Notes |
|-----------|-------|-------|
| System clock | 100 MHz | Nexys 4 DDR on-board oscillator |
| Sample rate | 1 MHz | `DIV_RATIO = 100` |
| Symbol rate | 125 kbps | 8 samples/symbol (OSR = 8) |
| Modulation | GFSK | BT = 0.5, modulation index h = 0.5 |
| PRBS length | 2⁹ − 1 = 511 | PRBS-9, polynomial x⁹ + x⁵ + 1 |
| Gaussian FIR | 49 taps | Spans L = 3 symbol periods |
| LPF FIR | 31 taps | Gaussian window, σ = 4 samples |
| Phase accumulator | 22 bits | ~0.024 Hz frequency resolution |
| Sine LUT depth | 1024 entries | 12-bit amplitude |
| BER pipeline delay | 45 symbol clocks | 24 (Gaussian GD) + 15 (LPF GD) + 6 (misc) |
| UART baud rate | 115200 | 8N1, Nexys 4 DDR USB bridge on C4 |

---

## Known Limitations

- **FM discriminator is real-signal only.** The full arctangent IQ discriminator (`atan2(I×Q_prev − Q×I_prev, I×I_prev + Q×Q_prev)`) would give ≈0.5 dB better sensitivity. This is flagged as a future enhancement.
- **NCO LUT uses `$sin` in `initial` block.** This synthesises correctly in Vivado (inferred LUTRAM) but is non-portable. Replace with a Xilinx Block Memory Generator IP for guaranteed synthesis across all tools.
- **No carrier recovery.** The design assumes perfect carrier phase (loopback only). An external RF path would require a PLL or Costas loop.
- **Gardner TED is not robust at very low SNR.** The PI loop constants (`KP=2, KI=5`) are empirically tuned for the loopback case. They may need adjustment for noisy channel conditions.
- **PRBS-9 maximum sequence is 511 bits.** For sub-10⁻⁶ BER measurements, upgrade to PRBS-23 (modify `POLY_ORDER` and `POLY_MASK` in `prbs_lfsr.sv`).

---

## References

1. K. Murota and K. Hirade, "GMSK Modulation for Digital Mobile Radio Telephony," *IEEE Transactions on Communications*, vol. 29, no. 7, pp. 1044–1050, July 1981.
2. ST Microelectronics, *S2-LP Sub-1GHz Transceiver Datasheet*, DS11896 Rev 9, 2022. [Online]. Available: https://www.st.com/resource/en/datasheet/s2-lp.pdf
3. F. M. Gardner, "A BPSK/QPSK Timing-Error Detector for Sampled Receivers," *IEEE Transactions on Communications*, vol. 34, no. 5, pp. 423–429, May 1986.
4. R. Pawula, S. Rice, and J. Roberts, "Distribution of the Phase Angle Between Two Vectors Perturbed by Gaussian Noise," *IEEE Transactions on Communications*, vol. 30, no. 8, pp. 1828–1841, 1982.
5. Digilent, *Nexys 4 DDR Reference Manual*, Rev. C, 2016. [Online]. Available: https://digilent.com/reference/programmable-logic/nexys-4-ddr/reference-manual
6. Xilinx, *Vivado Design Suite User Guide: Using Tcl Scripting*, UG894, 2020.

---

## License

This project is submitted as academic coursework and is shared for educational reference. You are free to study and adapt the code for non-commercial purposes with attribution.

---

*Implemented as part of the Digital Systems Design laboratory course. Target configuration (38.4 kbps, BT=0.5) matches the ST S2-LP production silicon operating point described in DS11896 Table 9.*
