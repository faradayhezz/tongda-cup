function decision = selectTwoPathV4(baseline,probe,feat,cal,cfg,policy)
%SELECTTWOPATHV4 Experimental quality/stability gate. Never uses truth/SNR.
% The ordinary V3 gate is first; split-frequency repeat fits run ONLY when
% V3 would change the answer. This is expensive, deliberately probe-only.
if nargin<6 || isempty(policy),policy=struct();end
decision=td1.selectTwoPathV3(baseline,probe,policy);
decision.v3M=decision.selectedM;
decision.v3Selected=decision.useTwoPath;
decision.splitRangeM=NaN;
decision.phaseNoiseRad=NaN;
if ~decision.useTwoPath,return;end
if ~isfield(feat,'phaseNoiseStdRad') || isempty(feat.phaseNoiseStdRad)
    decision.selectedM=baseline.fusedM;decision.useTwoPath=false;
    decision.reason='missing_noise_quality';return;
end
noise=feat.phaseNoiseStdRad(:);
decision.phaseNoiseRad=median(noise(isfinite(noise)));
maxNoise=opt(policy,'maxPhaseNoiseRad',0.10); % exploratory, not optimized
if isempty(decision.phaseNoiseRad) || ~isfinite(decision.phaseNoiseRad) || ...
        decision.phaseNoiseRad>maxNoise
    decision.selectedM=baseline.fusedM;decision.useTwoPath=false;
    decision.reason='low_quality_phase';return;
end
% Interleaved partitions each see roughly the whole frequency span.
n=numel(cfg.fHz); a=1:2:n; b=2:2:n;
if numel(a)<8 || numel(b)<8
    decision.selectedM=baseline.fusedM;decision.useTwoPath=false;
    decision.reason='insufficient_split_tones';return;
end
pa=subfit(a);pb=subfit(b);
if ~pa.eligible || ~pb.eligible || ...
        ~isfinite(pa.candidateM) || ~isfinite(pb.candidateM)
    decision.selectedM=baseline.fusedM;decision.useTwoPath=false;
    decision.reason='split_invalid';return;
end
decision.splitRangeM=abs(pa.candidateM-pb.candidateM);
maxSplit=opt(policy,'maxSplitDisagreementM',0.75); % exploratory
maxFull=opt(policy,'maxSplitToFullM',1.00);
if decision.splitRangeM>maxSplit || ...
        max(abs([pa.candidateM pb.candidateM]-probe.candidateM))>maxFull
    decision.selectedM=baseline.fusedM;decision.useTwoPath=false;
    decision.reason='unstable_split_fit';return;
end
decision.reason='stable_two_path_selected';
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
function v=opt(s,k,d)
if isfield(s,k),v=s.(k);else,v=d;end
end
