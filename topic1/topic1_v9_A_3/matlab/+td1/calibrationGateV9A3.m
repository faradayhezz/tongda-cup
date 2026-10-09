function [weight, score, jumpFlag, newTrend] = calibrationGateV9A3(current, previous, prevTrend, updatePeriod)
%CALIBRATIONGATEV9A3 Reference-only adaptive prediction gate.
% Returns multiplier [0,1] on legacy extrapolation. NOT a calibrated detector.
weight=1;score=NaN;jumpFlag=false;newTrend=[];
if isempty(previous),return;end
newTrend=current.rttBiasM-previous.rttBiasM;
if ~isfinite(newTrend),weight=0;return;end
% Avoid using target truth, simulated drift amplitude, or scene labels.
if isempty(prevTrend) || ~isfinite(prevTrend),return;end
sigma=max([current.rttBiasStandardErrorM,previous.rttBiasStandardErrorM,0.03]);
score=abs(newTrend-prevTrend)/max(sqrt(2)*sigma,0.05);
% A genuinely abrupt change or trend reversal suppresses extrapolation.
% Soft attenuation avoids hard decisions for noisy reference observations.
weight=1/(1+(score/3)^2);
jumpFlag=score>3;
if ~(current.phaseCalibrationValid && previous.phaseCalibrationValid),weight=0;end
if ~(isfinite(updatePeriod) && updatePeriod>0),weight=0;end
end
