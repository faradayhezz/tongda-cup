function choice=selectTwoPathV7(base,fit,v3,policy,nTones)
%SELECTTWOPATHV7 Experimental complexity-aware gate and strong-echo rescue.
% Receiver decisions use ONLY observed estimates / fit diagnostics.
% No truth, scene label, or simulation SNR is accessed.
if nargin<4 || isempty(policy), policy=struct(); end
if nargin<5 || isempty(nTones), nTones=17; end
choice=struct('selectedM',base.fusedM,'useTwoPath',false,'reason','retain_baseline',...
    'bicGain',NaN,'rescue',false,'shiftM',NaN);
if ~isfinite(base.fusedM) || ~fit.eligible || ~isfinite(fit.candidateM) || ...
        ~isfinite(fit.singleCost) || ~isfinite(fit.twoPathCost) || ...
        fit.singleCost<=0 || fit.twoPathCost<=0
    choice.reason='invalid_candidate'; return;
end
choice.bicGain=nTones*log(max(fit.singleCost,1e-12)/max(fit.twoPathCost,1e-12)) ...
    -3*log(nTones);
choice.shiftM=fit.candidateM-base.fusedM;
% The strict branch attempts to reject extra parameters when their evidence
% is insufficient. These are experimental, not calibrated probabilities.
if v3.useTwoPath
    if choice.bicGain>=localOpt(policy,'bicAccept',4)
        choice.selectedM=fit.candidateM;choice.useTwoPath=true;
        choice.reason='v3_bic_accepted';
    else
        choice.reason='v3_bic_veto';
    end
    return;
end
% Diagnose and TEST a rescue of plausible long-echo candidates. Unlike V3,
% this can exceed the 2.5m correction gate but never goes outside 0..40m.
% Do not enable in production without independent validation.
if strcmp(v3.reason,'excessive_shift') && ...
       choice.bicGain>=localOpt(policy,'bicRescue',14) && ...
       fit.relativeImprovement>0.80 && ...
       fit.echoAmplitude>=0.15 && fit.echoAmplitude<0.65 && ...
       fit.excessDelayNs>=35 && fit.excessDelayNs<=90 && ...
       abs(choice.shiftM)<=localOpt(policy,'maxRescueShiftM',6) && ...
       fit.candidateM>=0 && fit.candidateM<=40
    choice.selectedM=fit.candidateM;choice.useTwoPath=true;
    choice.rescue=true;choice.reason='strong_echo_rescue_experimental';
else
    choice.reason=['v3_' v3.reason];
end
end
function x=localOpt(s,k,fallback)
if isfield(s,k),x=s.(k);else,x=fallback;end
end
