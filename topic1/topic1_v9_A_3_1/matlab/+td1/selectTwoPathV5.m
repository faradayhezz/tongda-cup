function decision = selectTwoPathV5(baseline,probe,feat,cal,cfg,policy)
%SELECTTWOPATHV5 V3 base + complexity evidence + SOFT split confidence.
% Diagnostic candidate only. No reference distance or simulated true SNR used.
% This is a heuristic, not a calibrated posterior probability.
if nargin<6 || isempty(policy),policy=struct();end
v3=td1.selectTwoPathV3(baseline,probe);
decision=struct('selectedM',baseline.fusedM,'useTwoPath',false,...
 'reason','retain_baseline','bicGain',NaN,'splitRangeM',NaN,...
 'confidence',0,'correctionWeight',0,'v3Selected',v3.useTwoPath);
if ~v3.useTwoPath
 decision.reason=['v3_' v3.reason];return;
end
% Approximate BIC with an effective phase-residual loss; both models use
% identical data and fitted nuisance phase. Three extra parameters in 2-ray.
n=numel(cfg.fHz);
if ~isfinite(probe.singleCost) || ~isfinite(probe.twoPathCost) || ...
        probe.singleCost<=0 || probe.twoPathCost<=0 || n<12
 decision.reason='invalid_model_cost';return;
end
decision.bicGain=n*log(max(probe.singleCost,1e-12)/max(probe.twoPathCost,1e-12))-3*log(n);
minBic=option(policy,'minBicGain',4.0);
if decision.bicGain<=minBic
 decision.reason='insufficient_bic_evidence';return;
end
% Split fit is supplementary and ONLY soft-weights the correction.
% Few tones + short total bandwidth => split fits often unstable even if
% the full-band path fit helps. Never use split discrepancy as hard veto.
a=1:2:n;b=2:2:n;
if numel(a)>=8 && numel(b)>=8
 pa=subfit(a);pb=subfit(b);
 if pa.eligible && pb.eligible && isfinite(pa.candidateM) && isfinite(pb.candidateM)
   decision.splitRangeM=abs(pa.candidateM-pb.candidateM);
 end
end
% BIC evidence grows smoothly rather than thresholding multiple metrics.
evidence=1-exp(-max(0,decision.bicGain-minBic)/option(policy,'bicScale',8));
if isfinite(decision.splitRangeM)
 soft=1/(1+max(0,decision.splitRangeM-option(policy,'splitFreeM',0.75)) ...
      /option(policy,'splitSoftScaleM',3));
else
 soft=option(policy,'missingSplitFactor',0.75);
end
% Retain some robust correction if evidence is high; weight is diagnostic.
w=evidence*soft;
decision.confidence=w;
minWeight=option(policy,'minWeight',0.15);
if w<minWeight
 decision.reason='weak_combined_evidence';return;
end
% Attenuating untrusted corrections avoids full-size jumps on LOS.
decision.correctionWeight=w;
decision.selectedM=baseline.fusedM+w*(probe.candidateM-baseline.fusedM);
decision.useTwoPath=true;
decision.reason='soft_two_path_correction';
    function p=subfit(idx)
        c=cfg;c.fHz=cfg.fHz(idx);
        f=feat;f.phaseRad=feat.phaseRad(idx);
        if isfield(f,'phaseNoiseStdRad')
            f.phaseNoiseStdRad=feat.phaseNoiseStdRad(idx);
        end
        k=cal;k.phaseBiasRad=cal.phaseBiasRad(idx);
        if numel(cal.phaseStdRad)>1,k.phaseStdRad=cal.phaseStdRad(idx);end
        p=td1.twoPathProbe(f,k,c,baseline);
    end
end
function value=option(s,key,defaultValue)
if isfield(s,key),value=s.(key);else,value=defaultValue;end
end
