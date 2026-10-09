function rx = receiverConfig(cfg)
%RECEIVERCONFIG Whitelist only design information for the receiver boundary.
% Channel fixtures (scenarios, clock/CFO/hardware truths) never cross it.
required={'c','fs','knownSync','syncSpectrum','fftLength','binRad', ...
    'rttSearchRangeM','rttCoarseStepSamples','fHz','toneRef','toneTimeS', ...
    'cfoCaptureHz','distanceRangeM','pbrStepM'};
optional={'rttLagBounds','rttLagGrid','rttBasis','rttBasisReplyDelayS', ...
    'cfoPairToleranceHz','minSyncQuality','minToneCoherence','rttSigmaFloorM', ...
    'phaseSigmaFloorRad','minCalibrationResultant','minPbrCoherence', ...
    'maxFusionInnovationSigma','minAliasLikelihoodRatio', ...
    'phaseCurvatureThresholdRad','allowPbrOnlyOnDisagreement'};
rx=struct();
for k=1:numel(required)
    if ~isfield(cfg,required{k})
        error('td1:ReceiverConfig','Missing prepared design field %s.',required{k});
    end
    rx.(required{k})=cfg.(required{k});
end
for k=1:numel(optional)
    if isfield(cfg,optional{k}),rx.(optional{k})=cfg.(optional{k});end
end
end
