function cal = predictCalibrationV9(current,previous,stepsSinceUpdate,stepsBetweenUpdates,alpha)
%PREDICTCALIBRATIONV9 Extrapolate ONLY from independent known-range references.
% No target truth, channel fixture or simulator drift variable is used.
% alpha is a capped fraction of a preceding update interval, not a Kalman gain.
cal = current;
if nargin<5 || isempty(alpha),alpha=0.5;end
if isempty(previous) || stepsSinceUpdate<=0,return;end
if ~(isfinite(stepsBetweenUpdates) && stepsBetweenUpdates>0),return;end
fraction=min(max(stepsSinceUpdate/stepsBetweenUpdates,0),1)*alpha;
cal.rttBiasM=current.rttBiasM+fraction*(current.rttBiasM-previous.rttBiasM);
if all(isfinite(current.phaseBiasRad(:))) && all(isfinite(previous.phaseBiasRad(:)))
    difference=angle(exp(1i*(current.phaseBiasRad-previous.phaseBiasRad)));
    cal.phaseBiasRad=angle(exp(1i*(current.phaseBiasRad+fraction*difference)));
end
% Do not artificially shrink the uncertainty of an extrapolated calibration.
cal.rttSigmaM=max(current.rttSigmaM,previous.rttSigmaM);
cal.phaseStdRad=max(current.phaseStdRad,previous.phaseStdRad);
cal.phaseCalibrationValid=current.phaseCalibrationValid && previous.phaseCalibrationValid;
end
