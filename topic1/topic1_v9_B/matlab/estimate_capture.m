function estimate = estimate_capture(captureFile, calibrationFile)
%ESTIMATE_CAPTURE Process saved IQ with the same estimator as simulation.
% captureFile: MAT with obs and cfg (design configuration, no range truth).
% calibrationFile: MAT with cal fitted from independent known-range packets.
% obs contains syncIq, forwardTone, reverseTone, replyDelayS, exchangeGapS.
% Acquisition must establish device-side sample alignment, reply timing and
% bidirectional phase reference. Host/USB wall-clock times are insufficient.
capture=load(captureFile,'obs','cfg');
calibration=load(calibrationFile,'cal');
if ~isfield(capture,'obs') || ~isfield(capture,'cfg') || ~isfield(calibration,'cal')
    error('td1:CaptureSchema','Need obs/cfg in capture MAT and cal in calibration MAT.');
end
required={'syncIq','forwardTone','reverseTone','replyDelayS','exchangeGapS'};
for k=1:numel(required)
    if ~isfield(capture.obs,required{k})
        error('td1:CaptureSchema','Missing obs.%s',required{k});
    end
end
receiver=td1.receiverConfig(capture.cfg);
feat=td1.observe(capture.obs,receiver);
estimate=td1.estimate(feat,calibration.cal,receiver);
end
