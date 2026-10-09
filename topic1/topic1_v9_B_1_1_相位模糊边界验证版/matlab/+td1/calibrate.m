function cal = calibrate(features,knownDistancesM,cfg)
%CALIBRATE Fit an independent known-range reference; no test truth is used.
% A linear hardware phase slope is confounded with distance until a known
% reference is supplied.  This calibration is only valid while the fixture
% and hopping phase response remain stable.  Floors are conservative design
% choices, not measured Pluto accuracy or statistical coverage guarantees.

knownDistancesM = knownDistancesM(:);
if numel(features)~=numel(knownDistancesM) || numel(features)<2 || ...
        any(~isfinite(knownDistancesM))
    error('td1:BadCalibration','Need at least two matched known-range features.');
end
k = numel(cfg.fHz); n = numel(features);
rttResidual = nan(n,1); phaseResidual = nan(k,n);
for j=1:n
    ft = features(j);
    syncOK = isfinite(ft.rawRttM);
    if isfield(ft,'syncValid'), syncOK=syncOK && ft.syncValid; end
    if syncOK && ft.cfoValid
        rttResidual(j) = ft.rawRttM-knownDistancesM(j);
    end
    if ft.cfoValid && all(isfinite(ft.phaseRad(:)))
        phaseResidual(:,j) = angle(exp(1i*(ft.phaseRad(:)+ ...
            4*pi*cfg.fHz(:)*knownDistancesM(j)/cfg.c)));
    end
end
rttResidual = rttResidual(isfinite(rttResidual));
phaseResidual = phaseResidual(:,all(isfinite(phaseResidual),1));
if numel(rttResidual)<2 || size(phaseResidual,2)<2
    error('td1:InvalidCalibration','Insufficient valid independent references.');
end
cal.N = n;
cal.NValidRtt = numel(rttResidual);
cal.NValidPhase = size(phaseResidual,2);
cal.rttBiasM = mean(rttResidual);
cal.rttSampleSigmaM = std(rttResidual,0);
cal.rttSigmaFloorM = option(cfg,'rttSigmaFloorM',0.25);
cal.rttSigmaM = max(cal.rttSampleSigmaM,cal.rttSigmaFloorM);
cal.rttBiasStandardErrorM = cal.rttSampleSigmaM/sqrt(cal.NValidRtt);

% Remove the unidentifiable common phase for each acquisition before fitting
% the frequency response.  A reference column aligns arbitrary intercepts,
% avoiding cancellation when the shared phase changes between acquisitions.
reference = phaseResidual(:,1);
alignPhase = angle(sum(exp(1i*bsxfun(@minus,phaseResidual,reference)),1));
aligned = bsxfun(@minus,phaseResidual,alignPhase);
meanPhasor = mean(exp(1i*aligned),2);
cal.phaseBiasRad = angle(meanPhasor);
cal.phaseCalibrationResultant = abs(meanPhasor);
errorPhase = angle(exp(1i*bsxfun(@minus,aligned,cal.phaseBiasRad)));
common = angle(sum(exp(1i*errorPhase),1));
errorPhase = angle(exp(1i*bsxfun(@minus,errorPhase,common)));
cal.phaseSampleStdRad = std(errorPhase,0,2);
cal.phaseSigmaFloorRad = option(cfg,'phaseSigmaFloorRad',0.025);
cal.phaseStdRad = max(cal.phaseSampleStdRad,cal.phaseSigmaFloorRad);
cal.phaseCalibrationValid = median(cal.phaseCalibrationResultant)>= ...
    option(cfg,'minCalibrationResultant',0.65);
cal.assumptions = {'Independent known-range calibration observations', ...
    'Stable frequency-dependent hardware phase and nominal delay bias', ...
    'LO CFO does not identify an independent sampling or scheduling clock', ...
    'Variance floors do not bound NLOS or calibration drift'};
end

function value = option(cfg,name,fallback)
if isfield(cfg,name), value=cfg.(name); else, value=fallback; end
end
