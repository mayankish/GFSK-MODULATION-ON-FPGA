% gfsk_reference.m
% -----------------------------------------------------------------------
% MATLAB reference script for GFSK modem RTL co-simulation support.
%
% Sections:
%   1. Generate exact Gaussian FIR coefficients (paste into gaussian_fir.sv)
%   2. Generate exact LPF coefficients (paste into lpf_fir.sv)
%   3. Plot theoretical BER curves (reference for hardware results)
%   4. Simulate GFSK TX waveform (visual sanity check)
%
% Usage: Run BEFORE going to the lab.  Save all figures.
%        Section 1 output → replace COEF array in gaussian_fir.sv
% -----------------------------------------------------------------------
clear; clc; close all;

%% -----------------------------------------------------------------------
%  SECTION 1 — Gaussian FIR Coefficients (BT=0.5, OSR=8, 49 taps)
% -----------------------------------------------------------------------
fprintf('=== SECTION 1: Gaussian FIR Coefficients ===\n\n');

BT       = 0.5;       % Bandwidth-time product
OSR      = 8;         % Oversampling ratio (8 samples/symbol)
n_taps   = 49;        % Number of taps (must be odd)
T_sym    = 1.0;       % Normalized symbol period
T_samp   = T_sym / OSR;

M = (n_taps - 1) / 2;   % half-filter length = 24
n = -M : M;              % tap index

% Gaussian impulse response (continuous-time formula, sampled)
h = sqrt(2*pi) * BT / T_sym * exp(-2 * pi^2 * BT^2 * (n * T_samp).^2 / T_sym^2);
h = h / sum(h);          % normalize to DC gain = 1

% Quantize to 10-bit coefficients
COEF_MAX  = 511;
scale     = COEF_MAX / max(h);
h_q       = round(h * scale);

fprintf('Quantized coefficients (10-bit, index 0..%d):\n', n_taps-1);
fprintf('Centre tap (index %d): %d\n\n', M, h_q(M+1));
fprintf('SystemVerilog COEF array (paste into gaussian_fir.sv):\n');
fprintf("localparam signed [COEF_W-1:0] COEF [0:%d] = '{\n", n_taps-1);
for k = 1 : n_taps
    comma = ',';
    if k == n_taps, comma = ''; end
    fprintf("    10'sd%d%s", h_q(k), comma);
    if mod(k, 7) == 0, fprintf('\n'); end
end
fprintf('\n};\n\n');
fprintf('Sum of coefficients = %d  (divide by this after MAC)\n', sum(h_q));
fprintf('Nearest power-of-2 shift: >> %d\n\n', round(log2(sum(h_q))));

% Plot filter
fig1 = figure('Name', 'Gaussian FIR — BT=0.5, 49 taps');
subplot(2,1,1);
stem(0:n_taps-1, h_q, 'filled');
xlabel('Tap index'); ylabel('Coefficient value');
title('Gaussian FIR: Quantized coefficients (10-bit)');
grid on;

subplot(2,1,2);
[H, f] = freqz(h_q, 1, 2048, OSR);  % normalized to symbol rate
plot(f, 20*log10(abs(H)/max(abs(H))));
xlabel('Normalized frequency (× symbol rate)');
ylabel('Magnitude (dB)');
title('Gaussian FIR: Frequency response');
ylim([-80 5]); grid on;
saveas(fig1, 'gaussian_fir_coefs.png');

%% -----------------------------------------------------------------------
%  SECTION 2 — LPF FIR Coefficients (31 taps, Gaussian window)
% -----------------------------------------------------------------------
fprintf('=== SECTION 2: LPF FIR Coefficients ===\n\n');

lpf_taps = 31;
sigma    = 4;    % samples (for 1 MHz sample rate, sigma = 4 µs = ~0.5 symbol)
m_lpf    = (lpf_taps-1)/2;
n_lpf    = -m_lpf : m_lpf;
h_lpf    = exp(-n_lpf.^2 / (2*sigma^2));
h_lpf    = h_lpf / sum(h_lpf);   % normalize

% Quantize to 10-bit
scale_lpf  = 1024 / sum(round(h_lpf * 1024));
h_lpf_q    = round(h_lpf * 1024 * scale_lpf);
% Force sum = 1024
h_lpf_q(m_lpf+1) = h_lpf_q(m_lpf+1) + (1024 - sum(h_lpf_q));

fprintf('LPF coefficients (sum = %d):\n', sum(h_lpf_q));
fprintf("localparam signed [COEF_W-1:0] COEF [0:%d] = '{\n", lpf_taps-1);
for k = 1 : lpf_taps
    comma = ',';
    if k == lpf_taps, comma = ''; end
    fprintf("    10'sd%d%s", h_lpf_q(k), comma);
    if mod(k, 7) == 0, fprintf('\n'); end
end
fprintf('\n};\n\n');

%% -----------------------------------------------------------------------
%  SECTION 3 — Theoretical BER Curves
% -----------------------------------------------------------------------
fprintf('=== SECTION 3: Theoretical BER Curves ===\n\n');

ebn0_db  = 0 : 0.1 : 14;
ebn0_lin = 10.^(ebn0_db / 10);

% GFSK approximation (Murota & Hirade, 1981) — eta ≈ 0.68 for BT=0.5
eta_gfsk  = 0.68;
ber_gfsk  = qfunc(sqrt(2 * eta_gfsk * ebn0_lin));

% Ideal MSK reference
ber_msk   = qfunc(sqrt(2 * ebn0_lin));

fig2 = figure('Name', 'Theoretical BER — GFSK vs MSK');
semilogy(ebn0_db, ber_gfsk, 'b-', 'LineWidth', 2, 'DisplayName', 'GFSK BT=0.5');
hold on;
semilogy(ebn0_db, ber_msk,  'k--','LineWidth', 1.5, 'DisplayName', 'MSK (ideal)');
grid on; grid minor;
xlabel('E_b/N_0 (dB)');  ylabel('BER');
ylim([1e-5 1]); xlim([0 14]);
title('Theoretical BER — GFSK (BT=0.5, h=0.5)');
legend('Location','southwest');
saveas(fig2, 'ber_theoretical.png');

fprintf('Saved: ber_theoretical.png\n\n');

% Print Eb/N0 at BER targets
ber_targets = [1e-2, 1e-3, 1e-4];
for bt = ber_targets
    idx = find(ber_gfsk < bt, 1);
    if ~isempty(idx)
        fprintf('GFSK: BER < %.0e at Eb/N0 = %.1f dB\n', bt, ebn0_db(idx));
    end
end

%% -----------------------------------------------------------------------
%  SECTION 4 — GFSK TX Waveform Simulation
% -----------------------------------------------------------------------
fprintf('\n=== SECTION 4: GFSK TX Waveform Simulation ===\n\n');

rng(1);
N_sym  = 20;           % number of symbols to show
fs     = OSR;          % normalized sample rate (samples per symbol)
h_mod  = 0.5;          % FM modulation index
bits   = randi([0 1], 1, N_sym + ceil(n_taps/(OSR)) + 2);
nrz    = 2*bits - 1;   % +1/-1

% Upsample to OSR
nrz_up = repelem(nrz, OSR);

% Apply Gaussian filter
gauss_out = conv(nrz_up, h / sum(h), 'same');

% FM integrate and modulate
phi   = pi * h_mod * cumsum(gauss_out) / OSR;   % cumulative phase
t     = (0 : length(phi)-1) / OSR;              % time in symbol periods
tx_i  = cos(phi);
tx_q  = sin(phi);

% FM discriminator (differentiate phase)
disc  = diff(unwrap(phi)) * OSR / pi;            % normalized to ±1

fig3 = figure('Name', 'GFSK TX Waveform', 'Units', 'inches', 'Position', [1 1 10 7]);

subplot(4,1,1);
plot(t(1:N_sym*OSR), nrz(1:N_sym*OSR) .* ones(1, N_sym*OSR), 'b-', 'LineWidth', 1.5);
% Upsample NRZ for plotting
nrz_plot = repelem(nrz(1:N_sym), OSR);
stairs(t(1:N_sym*OSR), nrz_plot, 'b-', 'LineWidth', 1.5);
ylim([-1.5 1.5]); ylabel('NRZ'); title('GFSK TX Signal Chain');
grid on;

subplot(4,1,2);
plot(t(1:N_sym*OSR), gauss_out(1:N_sym*OSR), 'r-', 'LineWidth', 1.5);
ylim([-1.2 1.2]); ylabel('Gaussian FIR out');
grid on;

subplot(4,1,3);
plot(t(1:N_sym*OSR), tx_i(1:N_sym*OSR), 'g-', 'LineWidth', 1.2);
hold on;
plot(t(1:N_sym*OSR), tx_q(1:N_sym*OSR), 'm--', 'LineWidth', 1.2);
legend('I', 'Q', 'Location', 'northeast');
ylabel('FM mod (I/Q)');
grid on;

subplot(4,1,4);
t_disc = t(1:min(N_sym*OSR, length(disc)));
plot(t_disc, disc(1:length(t_disc)), 'k-', 'LineWidth', 1.5);
ylim([-1.5 1.5]); ylabel('FM disc out'); xlabel('Time (symbol periods)');
grid on;

saveas(fig3, 'gfsk_waveform.png');
fprintf('Saved: gfsk_waveform.png\n');
fprintf('\nAll done.  Take screenshots of the three figures for your report.\n');

%% -----------------------------------------------------------------------
%  Helper: Q function
% -----------------------------------------------------------------------
function y = qfunc(x)
    y = erfc(x / sqrt(2)) / 2;
end
