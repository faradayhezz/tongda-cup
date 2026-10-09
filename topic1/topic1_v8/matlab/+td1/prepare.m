function cfg = prepare(cfg, scene)
%PREPARE Build reusable IQ templates for a scenario, without consuming rng.
%   cfg = td1.prepare(cfg, scene) returns cfg with templates and the selected
%   frequency list. Call once per scenario, then reuse cfg in simulate().

validateattributes(cfg.fs, {'numeric'}, {'real', 'finite', 'scalar', 'positive'});
validateattributes(cfg.symbolRateHz, {'numeric'}, ...
    {'real', 'finite', 'scalar', 'positive'});
validateattributes(cfg.syncLength, {'numeric'}, ...
    {'real', 'finite', 'scalar', 'integer', 'positive'});
validateattributes(cfg.fftLength, {'numeric'}, ...
    {'real', 'finite', 'scalar', 'integer', 'positive'});
validateattributes(cfg.toneLength, {'numeric'}, ...
    {'real', 'finite', 'scalar', 'integer', '>=', 4});
validateattributes(scene.fHz, {'numeric'}, ...
    {'real', 'finite', 'vector', 'positive', 'nonempty'});
validateattributes(cfg.gfskBT, {'numeric'}, ...
    {'real', 'finite', 'scalar', 'positive'});
validateattributes(cfg.gfskModulationIndex, {'numeric'}, ...
    {'real', 'finite', 'scalar', 'positive'});
validateattributes(cfg.toneBasebandHz, {'numeric'}, ...
    {'real', 'finite', 'scalar'});
validateattributes(cfg.c, {'numeric'}, ...
    {'real', 'finite', 'scalar', 'positive'});
validateattributes(cfg.replyDelayS, {'numeric'}, ...
    {'real', 'finite', 'scalar', 'nonnegative'});
validateattributes(cfg.distanceRangeM, {'numeric'}, ...
    {'real', 'finite', 'vector', 'numel', 2, 'nonnegative'});
validateattributes(cfg.rttSearchRangeM, {'numeric'}, ...
    {'real', 'finite', 'vector', 'numel', 2});
validateattributes(cfg.rttCoarseStepSamples, {'numeric'}, ...
    {'real', 'finite', 'scalar', 'positive'});
validateattributes(cfg.pbrStepM, {'numeric'}, ...
    {'real', 'finite', 'scalar', 'positive'});
validateattributes(cfg.cfoCaptureHz, {'numeric'}, ...
    {'real', 'finite', 'scalar', 'positive'});
if cfg.distanceRangeM(2) <= cfg.distanceRangeM(1) || ...
        cfg.rttSearchRangeM(2) <= cfg.rttSearchRangeM(1)
    error('td1:RangeOrder', 'Distance and RTT search bounds must be increasing.');
end
if cfg.cfoCaptureHz >= cfg.fs / (2*64)
    error('td1:CfoCapture', 'CFO capture must be below the lag-64 alias limit fs/128.');
end

sps = cfg.fs / cfg.symbolRateHz;
if abs(sps - round(sps)) > 1e-10
    error('td1:SamplesPerSymbol', 'fs/symbolRateHz must be an integer.');
end
sps = round(sps);
if mod(cfg.fftLength, 2) ~= 0 || cfg.fftLength < 2 * cfg.syncLength
    error('td1:FftPadding', 'fftLength must be at least twice syncLength.');
end
fHz = scene.fHz(:);
if numel(fHz) < 2 || numel(unique(fHz)) ~= numel(fHz) || any(diff(fHz) <= 0)
    error('td1:FrequencyOrder', 'Scenario frequencies must be distinct and increasing.');
end
if abs(cfg.toneBasebandHz) + cfg.cfoCaptureHz >= cfg.fs / 2
    error('td1:ToneNyquist', 'Tone plus CFO capture range exceeds Nyquist.');
end

% Deterministic PRBS7, x^7+x^6+1, followed by a fixed 32-bit access word.
% The access word, framing and envelopes are our experiment fixtures: they
% deliberately do not claim BLE access-address or LE 2M conformance.
state = true(1, 7);
prbs = false(127, 1);
for k = 1:127
    prbs(k) = state(7);
    feedback = xor(state(7), state(6));
    state = [feedback, state(1:6)];
end
accessWord = uint32(hex2dec('6D9A73C5'));
access = false(32, 1);
for k = 1:32
    access(k) = bitget(accessWord, 33-k) ~= 0;
end
symbols = 2 * double([access; prbs]) - 1;
nrz = repelem(symbols, sps);

% Unit-sum Gaussian pulse and continuous phase integration require only
% base MATLAB. Smoothing and a tapered active interval suppress the edge
% discontinuities that would pollute FFT fractional-delay interpolation.
spanSymbols = 4;
kernelTime = (-spanSymbols*sps/2:spanSymbols*sps/2)' / sps;
sigmaSymbols = sqrt(log(2)) / (2*pi*cfg.gfskBT);
gaussian = exp(-0.5 * (kernelTime / sigmaSymbols).^2);
gaussian = gaussian / sum(gaussian);
smoothed = conv(nrz, gaussian, 'same');
phase = cumsum(smoothed) * pi * cfg.gfskModulationIndex / sps;
active = exp(1i * phase);
edgeLength = min(4*sps, floor(numel(active)/4));
edge = sin(linspace(0, pi/2, edgeLength)').^2;
active(1:edgeLength) = active(1:edgeLength) .* edge;
active(end-edgeLength+1:end) = ...
    active(end-edgeLength+1:end) .* flipud(edge);

guardSamples = 256;
maxRoundTripS = cfg.replyDelayS + 2*max(cfg.rttSearchRangeM)/cfg.c;
if guardSamples + numel(active) + ceil(maxRoundTripS*cfg.fs) + 32 > cfg.syncLength
    error('td1:SyncSupport', 'Sync record is too short for waveform and search delay.');
end
knownSync = complex(zeros(cfg.syncLength, 1));
activeIndices = guardSamples + (1:numel(active));
knownSync(activeIndices) = active;

cfg.fHz = fHz;
cfg.knownSync = knownSync;
cfg.syncSpectrum = fft(knownSync, cfg.fftLength);
% Frequency bins in fft() order, represented as signed radians/sample.
binIndex = [0:cfg.fftLength/2-1, -cfg.fftLength/2:-1]';
cfg.binRad = 2*pi*binIndex / cfg.fftLength;
% Reuse the same coarse matched-filter search basis across Monte Carlo
% trials. observe() may use it only when replyDelayS matches this cache.
cfg.rttLagBounds = cfg.replyDelayS*cfg.fs ...
    + 2*cfg.rttSearchRangeM(:).'*cfg.fs/cfg.c;
cfg.rttLagGrid = unique([ ...
    cfg.rttLagBounds(1):cfg.rttCoarseStepSamples:cfg.rttLagBounds(2), ...
    cfg.rttLagBounds(2)]);
cfg.rttBasis = exp(1i*cfg.binRad*cfg.rttLagGrid);
cfg.rttBasisReplyDelayS = cfg.replyDelayS;
cfg.toneTimeS = (0:cfg.toneLength-1)' / cfg.fs;
cfg.toneRef = exp(1i * 2*pi*cfg.toneBasebandHz*cfg.toneTimeS);
cfg.syncTimeS = (0:cfg.syncLength-1)' / cfg.fs;
cfg.syncActiveSamples = activeIndices(:);
cfg.exchangeGapS = cfg.exchangeGapStartS + ...
    (0:numel(fHz)-1)' * cfg.exchangeGapStepS;
cfg.phaseAmbiguityPeriodM = cfg.c / (2 * min(diff(fHz)));
cfg.prepared = true;
cfg.preparedSceneName = scene.name;
end
