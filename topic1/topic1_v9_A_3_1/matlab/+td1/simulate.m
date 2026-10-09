function obs = simulate(distanceM, snrDb, scene, cfg, isCalibration)
%SIMULATE Generate noisy sync and reciprocal-tone IQ, without truth outputs.
%   obs = td1.simulate(distanceM, snrDb, scene, cfg, isCalibration)
%   Calibration uses a known-distance LOS/reference channel (echo absent),
%   retaining the stable hardware, clock, CFO and phase-noise terms. Test
%   channel multipath is not calibrated using its distance truth. Explicit
%   post-calibration drift is also absent during calibration. +Inf SNR is useful
%   for deterministic self-checks; it does not disable scene phase noise.
%
%   replyDelayS and exchangeGapS are nominal, known scheduling metadata.
%   The gaps use a common ideal schedule; USB latency, firmware turnaround,
%   radio PLL settling and full BLE packets are not simulated. Reciprocal
%   phase cancellation is an ideal coherent-radio assumption. The random
%   hop-phase scenario deliberately violates it.

if nargin < 5
    isCalibration = false;
end
validateattributes(distanceM, {'numeric'}, ...
    {'real', 'finite', 'scalar', 'nonnegative'});
validateattributes(snrDb, {'numeric'}, {'real', 'scalar', 'nonnan'});
validateattributes(isCalibration, {'logical', 'numeric'}, ...
    {'real', 'scalar', 'binary'});
validateattributes(cfg.c, {'numeric'}, {'real', 'finite', 'scalar', 'positive'});
validateattributes(cfg.replyDelayS, {'numeric'}, ...
    {'real', 'finite', 'scalar', 'nonnegative'});
validateScene(scene);
if ~isfield(cfg, 'prepared') || ~cfg.prepared || ...
        ~isfield(cfg, 'fHz') || ~isequal(cfg.fHz, scene.fHz(:))
    cfg = td1.prepare(cfg, scene);
end
if numel(scene.phaseResidualRad) ~= numel(cfg.fHz)
    error('td1:ResidualShape', 'phaseResidualRad must have one entry per frequency.');
end
if isinf(snrDb) && snrDb < 0
    error('td1:InvalidSnr', 'Negative infinite SNR is not supported.');
end

driftDelayS = 0;
driftClockBppm = 0;
echoAmplitude = 0;
% V9_A_1: A dedicated known-distance reference channel does not see the
% target echo, but it DOES share the current RF hardware delay and clocks.
% Legacy behavior remains available for direct A/B fault reproduction.
trackReferenceDrift = isfield(scene,'referenceTracksDrift') && ...
    scene.referenceTracksDrift;
if ~isCalibration || trackReferenceDrift
    driftDelayS = scene.driftDelayS;
    driftClockBppm = scene.driftClockBppm;
end
if ~isCalibration
    echoAmplitude = scene.echoAmplitude;
end
clockA = 1 + scene.clockAppm*1e-6;
clockB = 1 + (scene.clockBppm + driftClockBppm)*1e-6;
if clockA <= 0 || clockB <= 0
    error('td1:ClockRate', 'Device clock rates must be positive.');
end
hardwareDelayS = scene.hwDelayS + driftDelayS;

% Device A timestamps in its own time units; device B waits the nominal
% number of local-clock seconds. CFO is an independent LO error, not a
% substitute for either clock multiplier.
roundTripS = clockA * (2*distanceM/cfg.c + cfg.replyDelayS/clockB) + hardwareDelayS;
delaySamples = roundTripS * cfg.fs;
if delaySamples < 0 || ...
        max(cfg.syncActiveSamples) + ceil(delaySamples + 2*scene.echoDelayS*cfg.fs) ...
        >= cfg.syncLength
    error('td1:RecordOverflow', 'Delay/echo moves the sync waveform outside the record.');
end

% H^2 represents two identical reciprocal one-way channels. The excess
% echo phase is referenced to toneAnchorHz in both the tone and sync model.
oneWaySyncH = 1 + echoAmplitude*exp(1i*scene.echoPhaseRad) .* ...
    exp(-1i*cfg.binRad*(scene.echoDelayS*cfg.fs));
delayedSpectrum = cfg.syncSpectrum .* exp(-1i*cfg.binRad*delaySamples) ...
    .* oneWaySyncH.^2;
sync = ifft(delayedSpectrum);
sync = sync(1:cfg.syncLength);
sync = sync .* exp(1i*2*pi*scene.cfoHz*cfg.syncTimeS);

K = numel(cfg.fHz);
echoToneH = 1 + echoAmplitude*exp(1i*scene.echoPhaseRad) .* ...
    exp(-1i*2*pi*(cfg.fHz-cfg.toneAnchorHz)*scene.echoDelayS);
oneWayToneH = exp(-1i*2*pi*cfg.fHz*(distanceM/cfg.c)) .* echoToneH;
theta = 2*pi*rand(K, 1) - pi;
pairPhase = 0.61 + scene.phaseResidualRad(:) ...
    + scene.phaseNoiseRad*randn(K, 1);
if scene.randomHopPhase
    % A fresh independent restart each trial, including calibration. There
    % is no fixed residual that could be learned and corrected per tone.
    pairPhase = pairPhase + 2*pi*rand(K, 1) - pi;
end
forwardAmplitude = oneWayToneH .* exp(1i*theta);
reverseAmplitude = oneWayToneH .* exp(1i*(-theta + pairPhase ...
    - 2*pi*scene.cfoHz*cfg.exchangeGapS ...
    - 2*pi*cfg.fHz*hardwareDelayS));
forwardReference = cfg.toneRef .* exp(1i*2*pi*scene.cfoHz*cfg.toneTimeS);
reverseReference = cfg.toneRef .* exp(-1i*2*pi*scene.cfoHz*cfg.toneTimeS);
forwardTone = forwardReference * forwardAmplitude.';
reverseTone = reverseReference * reverseAmplitude.';

% SNR refers to unit direct-path power in the active IQ samples, never to
% the record average or to a per-realization multipath normalization.
noiseScale = sqrt(10^(-snrDb/10)/2);
sync = sync + noiseScale * (randn(size(sync)) + 1i*randn(size(sync)));
forwardTone = forwardTone + noiseScale * ...
    (randn(size(forwardTone)) + 1i*randn(size(forwardTone)));
reverseTone = reverseTone + noiseScale * ...
    (randn(size(reverseTone)) + 1i*randn(size(reverseTone)));

obs = struct('syncIq', sync, 'forwardTone', forwardTone, ...
    'reverseTone', reverseTone, 'replyDelayS', cfg.replyDelayS, ...
    'exchangeGapS', cfg.exchangeGapS);
end

function validateScene(scene)
% Validate model inputs locally; the estimator never receives these truths.
scalarFields = {'clockAppm', 'clockBppm', 'cfoHz', 'hwDelayS', ...
    'echoAmplitude', 'echoDelayS', 'echoPhaseRad', 'phaseNoiseRad', ...
    'driftDelayS', 'driftClockBppm'};
for k = 1:numel(scalarFields)
    validateattributes(scene.(scalarFields{k}), {'numeric'}, ...
        {'real', 'finite', 'scalar'}, 'td1.simulate', scalarFields{k});
end
validateattributes(scene.echoAmplitude, {'numeric'}, {'nonnegative'});
validateattributes(scene.echoDelayS, {'numeric'}, {'nonnegative'});
validateattributes(scene.phaseNoiseRad, {'numeric'}, {'nonnegative'});
validateattributes(scene.phaseResidualRad, {'numeric'}, ...
    {'real', 'finite', 'vector'}, 'td1.simulate', 'phaseResidualRad');
validateattributes(scene.randomHopPhase, {'logical', 'numeric'}, ...
    {'real', 'scalar', 'binary'}, 'td1.simulate', 'randomHopPhase');
end
