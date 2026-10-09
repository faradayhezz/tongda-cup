function cfg = defaultConfig()
%DEFAULTCONFIG Reproducible configuration for the Topic 1 IQ simulation.
%   This is a teaching simulation of reciprocal two-way ranging. The GFSK
%   sync waveform is BLE-inspired; it is not a BLE packet or a conforming
%   Bluetooth Channel Sounding implementation. No PlutoSDR hardware data is
%   used. All distances and times below use SI units unless named otherwise.
%
%   This function does not touch MATLAB's global random number generator.
%   The runner owns rng(cfg.seed, 'twister') and records that seed.

cfg = struct();
cfg.seed = 20261008;
cfg.nTrials = 30;
cfg.c = 299792458;
cfg.fs = 20e6;
cfg.symbolRateHz = 2e6;
cfg.gfskBT = 0.5;
cfg.gfskModulationIndex = 0.5;
cfg.syncLength = 4096;
cfg.fftLength = 8192;
cfg.toneLength = 256;
cfg.toneBasebandHz = 400e3;
cfg.toneAnchorHz = 2.4e9;
cfg.replyDelayS = 64e-6;
cfg.exchangeGapStartS = 20e-6;
cfg.exchangeGapStepS = 2e-6;
cfg.cfoCaptureHz = 80e3;
cfg.rttSearchRangeM = [-10 70];
cfg.rttCoarseStepSamples = 0.1;
cfg.distanceRangeM = [0 40];
cfg.pbrStepM = 0.05;
cfg.distancesM = [1 3 5 10 15 20];
cfg.snrDb = [0 10 20 30];
cfg.calibrationDistanceM = 2.718;
cfg.calibrationTrials = 24;
% V1 diagnostics and opt-in experimental policy.
cfg.phaseCurvatureThresholdRad = 0.12;
cfg.allowPbrOnlyOnDisagreement = true; % baseline unchanged by default


% Every scenario has the same field topology. Residual hardware phase is a
% fixed fixture generated with sin(), independent of rng() and trial count.
% CFO and device clock errors are intentionally separate physical inputs.
base = struct('name', 'LOS', ...
    'description', 'Reciprocal line of sight, no hardware offset.', ...
    'fHz', cfg.toneAnchorHz + (0:16)' * 1e6, ...
    'clockAppm', 0, 'clockBppm', 0, 'cfoHz', 0, ...
    'hwDelayS', 0, 'phaseResidualRad', zeros(17, 1), ...
    'echoAmplitude', 0, 'echoDelayS', 0, 'echoPhaseRad', 0, ...
    'phaseNoiseRad', 0.01, 'driftDelayS', 0, ...
    'driftClockBppm', 0, 'randomHopPhase', false);
scenarios = repmat(base, 1, 6);

scenarios(2).name = 'CFO_clock';
scenarios(2).description = ...
    'Independent oscillator CFO, clock-rate error and fixed hardware phase.';
scenarios(2).clockAppm = 30;
scenarios(2).clockBppm = -30;
scenarios(2).cfoHz = 12e3;
scenarios(2).hwDelayS = 16e-9;
scenarios(2).phaseResidualRad = ...
    0.2 * sin((1:17)' * sqrt(2) + 0.37);

scenarios(3).name = 'Light_multipath';
scenarios(3).description = ...
    'One reciprocal echo at 0.25 amplitude and 25 ns excess one-way delay.';
scenarios(3).echoAmplitude = 0.25;
scenarios(3).echoDelayS = 25e-9;
scenarios(3).echoPhaseRad = 0.7;

scenarios(4).name = 'Sparse_alias';
scenarios(4).description = ...
    'Five 8 MHz-spaced tones; phase range wraps every 18.737 m.';
scenarios(4).fHz = cfg.toneAnchorHz + (0:4)' * 8e6;
scenarios(4).phaseResidualRad = zeros(5, 1);

scenarios(5).name = 'Calibration_drift';
scenarios(5).description = ...
    'After calibration, add 16 ns hardware delay and 60 ppm B-clock drift.';
scenarios(5).clockAppm = 30;
scenarios(5).clockBppm = -30;
scenarios(5).cfoHz = 12e3;
scenarios(5).hwDelayS = 16e-9;
scenarios(5).phaseResidualRad = ...
    0.2 * sin((1:17)' * sqrt(2) + 0.37);
scenarios(5).driftDelayS = 16e-9;
scenarios(5).driftClockBppm = 60;

scenarios(6).name = 'Random_hop_phase';
scenarios(6).description = ...
    'Independent phase restart on each exchange; reciprocal phase is lost.';
scenarios(6).randomHopPhase = true;

cfg.scenarios = scenarios;
cfg = td1.prepare(cfg, scenarios(1));
end
