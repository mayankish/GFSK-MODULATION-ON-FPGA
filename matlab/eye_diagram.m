% eye_diagram.m
% -----------------------------------------------------------------------
% Reconstruct and plot eye diagram from GFSK demodulator output samples.
%
% Two modes:
%   MODE 1 (Vivado ILA capture): load IQ samples from a .csv exported
%           from the Vivado ILA waveform viewer.
%   MODE 2 (MATLAB simulation):  generate samples internally using the
%           theoretical GFSK impulse response — useful to verify eye quality
%           before hardware capture.
%
% Output: eye_diagram.png + eye_diagram.fig
% -----------------------------------------------------------------------

clear; clc; close all;

MODE = 'simulation';    % 'ila_csv'  or  'simulation'

SPY  = 8;   % samples per symbol (must match gardner_ted SAMPLES_PER_SYM)
NSYM = 500; % symbols to overlay

%% ---- MODE 1: Load from Vivado ILA CSV ---------------------------------
if strcmp(MODE, 'ila_csv')
    csv_file = 'ila_capture.csv';
    if ~exist(csv_file, 'file')
        error('ILA capture file "%s" not found.\nExport from Vivado: '  + ...
              'ILA → File → Export Samples to CSV', csv_file);
    end
    tbl = readtable(csv_file);
    % Column name may vary — adapt to your ILA probe names
    % Probe expected: rx_lpf[11:0] (12-bit signed, 2's complement)
    col = tbl.Properties.VariableNames;
    rx_col = col{contains(col, 'rx_lpf', 'IgnoreCase', true)};
    samples = double(tbl.(rx_col));
    % Convert 12-bit unsigned hex string to signed integer if needed
    if iscell(samples) || ischar(samples(1))
        samples = double(hex2dec(samples));
        samples(samples >= 2048) = samples(samples >= 2048) - 4096;
    end
    Fs = 1e6 * SPY;  % 8 MHz sample rate in this mode
    fprintf('Loaded %d samples from %s\n', numel(samples), csv_file);

%% ---- MODE 2: Generate from GFSK model ---------------------------------
else
    % Gaussian FIR coefficients (BT=0.5, 49 taps, fs=8 MHz)
    bt     = 0.5;
    T_sym  = 1 / 1e6;       % 1 µs symbol period
    Ts     = T_sym / SPY;   % sample period
    n_taps = 49;
    n      = -(n_taps-1)/2 : (n_taps-1)/2;
    t      = n * Ts;

    % Gaussian filter impulse response
    h_gauss = (sqrt(2*pi) * bt / T_sym) * ...
              exp(-2 * pi^2 * bt^2 * t.^2 / T_sym^2);
    h_gauss = h_gauss / sum(h_gauss);  % normalize

    % FM modulation index
    h_mod   = 0.5;

    % Generate random PRBS-9 symbols
    rng(42);
    bits  = randi([0 1], 1, NSYM + ceil(n_taps/SPY) + 10);
    nrz   = 2*bits - 1;  % +1/-1

    % Upsample to SPY samples/symbol
    nrz_up = repelem(nrz, SPY);

    % Gaussian filter
    gauss_out = conv(nrz_up, h_gauss, 'same');

    % FM phase integration: phi(t) = pi*h * integral(g(t))
    phi   = pi * h_mod * cumsum(gauss_out) * Ts / T_sym;
    tx_iq = exp(1j * phi);  % complex baseband

    % FM discriminator (atan2 differentiator)
    disc  = angle(tx_iq(2:end) .* conj(tx_iq(1:end-1))) / (2*pi*Ts) * T_sym;

    % Simple matched filter (LPF with same Gaussian shape)
    h_lpf  = gausswin(31) / sum(gausswin(31));
    lpf_out = conv(disc, h_lpf, 'same');

    % Use lpf_out as samples for eye diagram
    samples  = lpf_out;
    % Trim to NSYM symbols after filter settling
    start_s  = n_taps + 1;
    samples  = samples(start_s : start_s + NSYM*SPY - 1);
    fprintf('Generated %d simulated samples (%d symbols × %d sps)\n', ...
            numel(samples), NSYM, SPY);
end

%% ---- Build eye diagram (2-symbol window) ------------------------------
win    = 2 * SPY;     % 2-symbol eye window
n_eyes = floor(numel(samples) / win);
eye_mat = reshape(samples(1 : n_eyes*win), win, n_eyes);

t_eye  = linspace(0, 2, win);   % normalized time axis (0..2 symbols)

fig = figure('Name', 'GFSK Eye Diagram', 'Units', 'inches', ...
             'Position', [1 1 7 5]);

% Plot individual eye traces
plot(t_eye, eye_mat(:, 1:min(200, n_eyes)), 'Color', [0.2 0.5 0.8 0.15], ...
     'LineWidth', 0.5);
hold on;

% Overlay mean eye
plot(t_eye, mean(eye_mat, 2), 'b-', 'LineWidth', 2, 'DisplayName', 'Mean');

% Mark symbol sampling instants (eye center = t = 0.5 and 1.5)
xline(0.5, 'r--', 'LineWidth', 1.5, 'DisplayName', 'Sampling instants');
xline(1.5, 'r--', 'LineWidth', 1.5, 'HandleVisibility', 'off');

% Eye opening metrics
center_samples = eye_mat(round(win/4), :);  % samples at t=0.5
eye_opening    = max(center_samples) - min(center_samples);
eye_noise      = std(center_samples);
fprintf('\nEye opening (peak-to-peak): %.4f\n', eye_opening);
fprintf('Noise floor at eye center:  %.4f\n',   eye_noise);
fprintf('Q factor estimate:          %.2f (%.1f dB)\n', ...
        eye_opening/(2*eye_noise), 20*log10(eye_opening/(2*eye_noise)));

% Annotate eye
text(0.05, max(samples)*0.85, ...
     sprintf('Eye opening: %.3f\nQ ≈ %.1f dB', ...
             eye_opening, 20*log10(eye_opening/(2*eye_noise))), ...
     'FontSize', 10, 'BackgroundColor', 'w');

grid on;
xlabel('Symbol periods', 'FontSize', 12);
ylabel('Normalized amplitude', 'FontSize', 12);
title('GFSK Demodulator Eye Diagram  —  BT=0.5,  h=0.5', 'FontSize', 13);
legend('Location', 'northeast', 'FontSize', 10);

%% ---- Save ---------------------------------------------------------------
saveas(fig, 'eye_diagram.png');
saveas(fig, 'eye_diagram.fig');
fprintf('\nSaved: eye_diagram.png  and  eye_diagram.fig\n');
