% ber_analysis.m
% -----------------------------------------------------------------------
% Plot measured BER (from ber_results.txt or UART log) vs theoretical
% GFSK curve. Produces a publication-quality BER vs Eb/N0 plot.
%
% Usage:
%   1. Simulation: run tb_ber_gfsk.sv → ber_results.txt → run this script
%   2. Hardware:   collect UART "ERR=... TOT=..." lines → parse below
% -----------------------------------------------------------------------

clear; clc; close all;

%% ---- 1. Load simulated data ----------------------------------------
if exist('ber_results.txt', 'file')
    raw = readmatrix('ber_results.txt', 'CommentStyle', '#', ...
                     'Delimiter', ' ', 'ConsecutiveDelimitersRule', 'join');
    ebn0_sim = raw(:, 1);
    ber_sim  = raw(:, 2);
    has_sim  = true;
else
    warning('ber_results.txt not found — skipping simulation curve.');
    has_sim  = false;
end

%% ---- 2. Load hardware UART data (optional) -------------------------
% Place your UART log in 'uart_log.txt', one line per second:
%   ERR=0000000A TOT=000F4240
uart_file = 'uart_log.txt';
has_hw    = false;
if exist(uart_file, 'file')
    lines = readlines(uart_file);
    err_hw  = [];
    tot_hw  = [];
    for k = 1:numel(lines)
        ln = char(lines(k));
        tok = regexp(ln, 'ERR=([0-9A-Fa-f]+)\s+TOT=([0-9A-Fa-f]+)', 'tokens');
        if ~isempty(tok)
            err_hw(end+1) = hex2dec(tok{1}{1}); %#ok<SAGROW>
            tot_hw(end+1) = hex2dec(tok{1}{2}); %#ok<SAGROW>
        end
    end
    if ~isempty(err_hw) && ~isempty(tot_hw)
        % Hardware log is time-series — compute cumulative BER at end
        ber_hw   = err_hw(end) / tot_hw(end);
        has_hw   = true;
        fprintf('Hardware: %d errors / %d bits  →  BER = %.3e\n', ...
                err_hw(end), tot_hw(end), ber_hw);
    end
end

%% ---- 3. Theoretical GFSK BER (BT=0.5, h=0.5) ----------------------
% Approximate theoretical BER for GFSK using Pawula's formula:
%   BER ≈ Q( sqrt(2 * eta * Eb/N0) )
% where eta ≈ 0.68 for BT=0.5 (efficiency factor vs MSK)
% Reference: Murota & Hirade, IEEE Trans. Commun. 1981

ebn0_th_db  = 0:0.1:14;
ebn0_th_lin = 10.^(ebn0_th_db / 10);
eta_gfsk    = 0.68;          % BT=0.5 efficiency factor
ber_th_gfsk = qfunc(sqrt(2 * eta_gfsk * ebn0_th_lin));

% Also plot ideal MSK (h=0.5) for reference
ber_th_msk = qfunc(sqrt(2 * ebn0_th_lin));

% And BFSK (non-coherent) upper bound
ber_th_bfsk = 0.5 * exp(-ebn0_th_lin / 2);

%% ---- 4. Plot -----------------------------------------------------------
fig = figure('Name', 'GFSK BER Analysis', 'Units', 'inches', ...
             'Position', [1 1 7 5]);

semilogy(ebn0_th_db, ber_th_gfsk, 'b-',  'LineWidth', 1.5, ...
         'DisplayName', 'Theoretical GFSK (BT=0.5)');
hold on;
semilogy(ebn0_th_db, ber_th_msk,  'k--', 'LineWidth', 1.2, ...
         'DisplayName', 'Theoretical MSK (ideal)');
semilogy(ebn0_th_db, ber_th_bfsk, 'r-.', 'LineWidth', 1.0, ...
         'DisplayName', 'Non-coherent BFSK');

if has_sim
    semilogy(ebn0_sim, ber_sim, 'bs', 'MarkerSize', 8, 'LineWidth', 1.5, ...
             'DisplayName', 'Simulated (RTL)');
end
if has_hw
    % Plot hardware point — need to know which Eb/N0 it was measured at
    % Modify ebn0_hw_db to match your hardware test condition
    ebn0_hw_db = input('Enter hardware Eb/N0 [dB] for this measurement: ');
    semilogy(ebn0_hw_db, ber_hw, 'r^', 'MarkerSize', 10, 'LineWidth', 2, ...
             'DisplayName', 'Measured (FPGA hardware)');
end

grid on; grid minor;
ylim([1e-5 1]);
xlim([0 14]);
xlabel('E_b/N_0 (dB)', 'FontSize', 12);
ylabel('Bit Error Rate (BER)', 'FontSize', 12);
title('GFSK Modem BER  —  BT=0.5,  h=0.5,  F_{sym}=1 MHz', 'FontSize', 13);
legend('Location', 'southwest', 'FontSize', 10);

% Annotation: implementation loss
if has_sim && numel(ebn0_sim) > 3
    % Find 1e-3 crossing
    idx_th  = find(ber_th_gfsk < 1e-3, 1);
    idx_sim = find(ber_sim     < 1e-3, 1);
    if ~isempty(idx_th) && ~isempty(idx_sim)
        loss_db = ebn0_sim(idx_sim) - ebn0_th_db(idx_th);
        text(8, 5e-3, sprintf('Impl. loss @ BER=10^{-3}: %.1f dB', loss_db), ...
             'FontSize', 10, 'Color', [0 0.4 0.8]);
    end
end

%% ---- 5. Save figure ---------------------------------------------------
saveas(fig, 'ber_curve.png');
saveas(fig, 'ber_curve.fig');
fprintf('\nSaved: ber_curve.png  and  ber_curve.fig\n');

%% ---- Helper: Q-function (compatible with older MATLAB versions) ------
function y = qfunc(x)
    y = erfc(x / sqrt(2)) / 2;
end
