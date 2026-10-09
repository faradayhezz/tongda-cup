function decision = selectTwoPathV3(baseline,probe,policy)
%SELECTTWOPATHV3 Conservative two-path model gate. No ground-truth inputs.
% Experimental thresholds set on PRIOR V2 data; validate independently.
if nargin<3 || isempty(policy),policy=struct();end
minGain=option(policy,'minRelativeImprovement',0.60);
minEcho=option(policy,'minEchoAmplitude',0.08);
minDelay=option(policy,'minExcessDelayNs',8);
maxDelay=option(policy,'maxExcessDelayNs',90);
maxShift=option(policy,'maxCorrectionM',2.5);
decision=struct('selectedM',baseline.fusedM,'useTwoPath',false,'reason','retain_baseline');
if ~baseline.pbrValid || ~isfinite(baseline.fusedM)
    decision.reason='baseline_invalid';return;
end
if ~probe.eligible || ~isfinite(probe.candidateM) || ...
        ~isfinite(probe.relativeImprovement) || ~isfinite(probe.echoAmplitude) || ...
        ~isfinite(probe.excessDelayNs)
    decision.reason='candidate_invalid';return;
end
if probe.relativeImprovement<=minGain
    decision.reason='insufficient_gain';return;
end
if probe.echoAmplitude<=minEcho
    decision.reason='weak_echo';return;
end
if probe.excessDelayNs<=minDelay || probe.excessDelayNs>=maxDelay
    decision.reason='delay_boundary';return;
end
if abs(probe.candidateM-baseline.fusedM)>maxShift
    decision.reason='excessive_shift';return;
end
decision.selectedM=probe.candidateM;
decision.useTwoPath=true;
decision.reason='two_path_selected';
end
function v=option(s,k,defaultValue)
if isfield(s,k),v=s.(k);else,v=defaultValue;end
end
