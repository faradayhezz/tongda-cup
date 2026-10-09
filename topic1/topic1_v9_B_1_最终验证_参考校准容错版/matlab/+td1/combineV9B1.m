function choice=combineV9B1(base,v8,v3,v7,probe,fHz,policy)
%COMBINEV9B1 Conservative evidence-gated optional two-path correction.
% No true target range, scene label, or simulator SNR enters the decision.
if nargin<7 || isempty(policy),policy=struct();end
choice=struct('selectedM',v8.selectedM,'usePbr',v8.usePbr, ...
 'useTwoPath',false,'reason','retain_v8','correctionM',0, ...
 'evidence',NaN,'deltaBic',NaN);
if ~isfinite(v8.selectedM)
 choice.reason='v8_invalid';return;
end
if v8.usePbr
 choice.reason='protect_v8_pbr';return;
end
if ~base.pbrValid || ~probe.eligible || ~isfinite(probe.candidateM) || ...
 ~isfinite(probe.singleCost) || ~isfinite(probe.twoPathCost)
 choice.reason='invalid_two_path';return;
end
if ~(v3.useTwoPath || v7.useTwoPath)
 choice.reason='not_selected_by_v3_v7';return;
end
n=numel(fHz);
if n<10 || probe.singleCost<=0 || probe.twoPathCost<=0
 choice.reason='invalid_fit_cost';return;
end
% Three additional two-path parameters: delay, amplitude, reflection phase.
choice.deltaBic=n*log(max(probe.singleCost,eps)/max(probe.twoPathCost,eps))-3*log(n);
minBic=localOption(policy,'minDeltaBic',12);
minGain=localOption(policy,'minRelativeGain',0.70);
if choice.deltaBic<minBic || probe.relativeImprovement<minGain
 choice.reason='insufficient_model_evidence';return;
end
% The short 32-MHz span is poorly conditioned for small-delay two-path fitting.
% This is a conservative experimental safeguard, not a universal cutoff.
spanMHz=(max(fHz)-min(fHz))/1e6;
if spanMHz<48
 choice.reason='narrow_span_requires_independent_validation';return;
end
maxChange=localOption(policy,'maxCorrectionM',0.75);
shift=probe.candidateM-v8.selectedM;
if ~isfinite(shift) || abs(shift)>maxChange
 choice.reason='excessive_correction';return;
end
% Apply only an independently selected, moderate two-path correction.
choice.selectedM=probe.candidateM;
choice.useTwoPath=true;
choice.correctionM=shift;
choice.evidence=probe.relativeImprovement;
choice.reason='accepted_two_path_v9b1';
end
function val=localOption(s,k,def)
if isfield(s,k),val=s.(k);else,val=def;end
end
