function result = phaseSlope(phaseRad, fHz, c)
%PHASESLOPE Independent unwrap-and-regress PBR reference estimator.
% Mathematical cross-check inspired by Zephyr's Apache-2.0 CS sample:
% https://github.com/zephyrproject-rtos/zephyr/blob/main/samples/bluetooth/channel_sounding/src/distance_estimation.c
% Independently implemented here; no upstream source code is incorporated.
% Adjacent phase changes must be below pi for unwrap to choose the physical
% branch. This routine cannot resolve sparse-frequency distance aliases.
if nargin < 3, c=299792458; end
validateattributes(fHz,{'numeric'},{'vector','real','finite','positive'});
validateattributes(phaseRad,{'numeric'},{'vector','real','finite'});
if numel(fHz)~=numel(phaseRad) || numel(fHz)<2
    error('td1:PhaseShape','Need at least two paired frequencies and phases.');
end
[f,order]=sort(fHz(:));
if any(diff(f)<=0),error('td1:DuplicateFrequency','Frequencies must be distinct.');end
phase=unwrap(phaseRad(order));
centered=f-mean(f); centeredPhase=phase-mean(phase);
slope=(centered.'*centeredPhase)/(centered.'*centered);
residual=centeredPhase-slope*centered;
result=struct('distanceM',-c*slope/(4*pi),'slopeRadPerHz',slope, ...
    'residualRmsRad',sqrt(mean(residual.^2)), ...
    'unambiguousHalfRangeM',c/(4*max(diff(f))));
end
