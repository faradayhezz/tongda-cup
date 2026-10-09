function est = estimate(feat,cal,cfg)
%ESTIMATE Calibrated ranging and RTT-guided phase alias selection.
% Truth, scene labels and hidden channel/hardware parameters are absent.
% The standalone PBR output chooses the smallest equivalent alias by policy;
% pbrAmbiguous records that this policy is not independent disambiguation.
% The local soft likelihood assumes calibrated LOS random errors.  Common
% multipath/clock/hardware biases violate that model and can harm fusion.

f = cfg.fHz(:); range = cfg.distanceRangeM(:).';
phase = angle(exp(1i*(feat.phaseRad(:)-cal.phaseBiasRad(:))));
phaseVariance = cal.phaseStdRad(:).^2;
if numel(phaseVariance)==1, phaseVariance=repmat(phaseVariance,numel(f),1); end
if isfield(feat,'phaseNoiseStdRad')
    phaseVariance = phaseVariance+feat.phaseNoiseStdRad(:).^2;
end
w = 1./max(phaseVariance,realmin);
[pbr,candidates,coherence,period] = phaseFit(phase,w,cfg);
[rawPbr,~,~,~] = phaseFit(feat.rawPhaseRad(:),ones(size(f)),cfg);
est.rawRttM = feat.rawRttM;
est.rttM = feat.rawRttM-cal.rttBiasM;
est.rawPbrM = rawPbr;
est.pbrM = pbr;
est.pbrCoherence = coherence;
est.pbrAmbiguous = numel(candidates)>1;
est.aliasCandidatesM = candidates;
calibrationOK = ~isfield(cal,'phaseCalibrationValid') || cal.phaseCalibrationValid;
phaseQualityOK = ~isempty(candidates) && isfinite(coherence) && ...
    coherence>=option(cfg,'minPbrCoherence',0.65) && isfinite(pbr);
% PBR usability depends on its own CFO, calibration and phase quality, not
% on the synchronization channel needed by RTT. A finite search result by
% itself is not a usable phase measurement.
est.pbrValid = feat.cfoValid && calibrationOK && phaseQualityOK;
est.fusedM = est.rttM;
est.fusionValid = false;
est.innovationSigma = nan;
est.status = 'rtt_only';
est.pbrPeriodM = period;
est.phaseInformationScale = nan;
% Diagnostic only: phase curvature after removing the best affine frequency
% trend.  A low value does NOT prove LOS (unresolved echoes can look linear).
% Never use channel truth or scene labels in receiver decisions.
est.phaseCurvatureRad = phaseCurvature(phase, f);
est.phaseCurvatureFlag = est.phaseCurvatureRad > ...
    option(cfg,'phaseCurvatureThresholdRad',0.12);

sigmaR = cal.rttSigmaM;
if isfield(feat,'rttNoiseSigmaM') && isfinite(feat.rttNoiseSigmaM)
    sigmaR = sqrt(sigmaR^2+feat.rttNoiseSigmaM^2);
end
fc = f-sum(w.*f)/sum(w);
sigmaP = sqrt(1/max((4*pi/cfg.c)^2*sum(w.*fc.^2),realmin));
nominalPhaseVarianceDistance = sigmaP^2;
% CFO error is common across all frequencies.  Its gap-dependent slope is
% propagated as a correlated nuisance, not counted as independent per tone.
if isfield(feat,'exchangeGapS') && isfield(feat,'cfoUncertaintyHz')
    gc = feat.exchangeGapS(:)-sum(w.*feat.exchangeGapS(:))/sum(w);
    cfoDistanceSigma = cfg.c/2*feat.cfoUncertaintyHz* ...
        abs(sum(w.*fc.*gc)/max(sum(w.*fc.^2),realmin));
    sigmaP = sqrt(sigmaP^2+cfoDistanceSigma^2);
end
est.rttSigmaM = sigmaR;
est.pbrSigmaM = sigmaP;
if ~feat.cfoValid
    % Sync was derotated using the failed CFO acquisition. Its resulting
    % calibrated range is not a valid fallback measurement; raw IQ features
    % remain available to diagnose the acquisition failure.
    est.rttM = nan; est.fusedM = nan;
    est.status = 'invalid_cfo'; return;
end
if isfield(feat,'syncValid') && ~feat.syncValid
    est.rttM = nan; est.fusedM = nan;
    est.status = 'unreliable_sync'; return;
end
if ~isfinite(est.rttM) || ~isfinite(sigmaR) || sigmaR<=0
    est.rttM = nan; est.fusedM = nan;
    est.status = 'invalid_rtt'; return;
end
if isfield(cal,'phaseCalibrationValid') && ~cal.phaseCalibrationValid
    est.status = 'unstable_phase_calibration_rtt_only'; return;
end
if isempty(candidates) || ~isfinite(coherence) || ...
        coherence<option(cfg,'minPbrCoherence',0.65)
    est.status = 'low_phase_coherence_rtt_only'; return;
end
aliasScores = (candidates-est.rttM).^2/(sigmaR^2+sigmaP^2);
[sorted,index] = sort(aliasScores);
chosen = candidates(index(1));
est.innovationSigma = sqrt(sorted(1));
if est.innovationSigma>option(cfg,'maxFusionInnovationSigma',3)
    % Experimental safety mode for UNIQUE phase aliases only.  A coherent
    % single-branch phase estimate can survive a biased RTT clock; this is
    % NOT safe for hardware phase/calibration drift, and is opt-in.
    if option(cfg,'allowPbrOnlyOnDisagreement',false) && ...
            numel(candidates)==1 && est.pbrValid && ...
            ~est.phaseCurvatureFlag
        est.fusedM = chosen;
        est.status = 'pbr_only_on_disagreement_experimental';
        return;
    end
    est.status = 'range_phase_disagreement_rtt_only'; return;
end
% Reject near-equal aliases: a ten-to-one likelihood ratio is a declared
% conservative decision rule, not an empirically proven confidence interval.
if numel(sorted)>1 && sorted(2)-sorted(1)< ...
        2*log(option(cfg,'minAliasLikelihoodRatio',10))
    est.status = 'uncertain_alias_rtt_only'; return;
end
% A quarter of a long ambiguity period can contain many sidelobes: fminbnd
% must not be asked to search that entire interval as a unimodal function.
% Restrict refinement to a small neighborhood of the already fitted phase
% peak, using four nominal standard deviations or four grid steps. Its cost
% at the fitted peak is always retained as a candidate below.
localWidth = max(4*cfg.pbrStepM,4*sigmaP);
if isfinite(period), basin=min(period/4,localWidth); else, basin=localWidth; end
lo = max(range(1),chosen-basin); hi = min(range(2),chosen+basin);
fcLikelihood = f-mean(f);
z = exp(1i*phase);
phaseCost = @(d) 2*(sum(w)-abs(sum(w.*z.* ...
    exp(1i*4*pi*fcLikelihood*d/cfg.c))));
% Locally the nominal profiled phase cost is (d-d_P)^2/sigma_P,nom^2.
% Adding a common CFO-induced distance variance gives sigma_P,total^2;
% multiplying by sigma_P,nom^2/sigma_P,total^2 therefore reduces its local
% curvature to 1/sigma_P,total^2. This is a local variance approximation,
% not a claim that shared CFO errors are independent across frequencies.
phaseInformationScale = min(1,nominalPhaseVarianceDistance/ ...
    max(sigmaP^2,realmin));
est.phaseInformationScale = phaseInformationScale;
obj = @(d) phaseInformationScale*max(phaseCost(d),0)+ ...
    (d-est.rttM)^2/sigmaR^2;
est.fusedM = boundedMin(obj,lo,hi,1e-8,chosen);
est.fusionValid = true;
if est.pbrAmbiguous
    est.status = 'rtt_selected_phase_alias';
else
    est.status = 'single_alias_soft_fusion';
end
end

function [distance,candidates,coherence,period] = phaseFit(phase,w,cfg)
f = cfg.fHz(:); range=cfg.distanceRangeM(:).';
if numel(phase)~=numel(f) || any(~isfinite(phase)) || ...
        any(~isfinite(w)) || any(w<=0)
    distance=nan; candidates=[]; coherence=nan; period=nan; return;
end
spacing = diff(f);
if ~isempty(spacing) && spacing(1)>0 && ...
        max(abs(spacing-spacing(1)))<=max(1,abs(spacing(1))*1e-10)
    period = cfg.c/(2*spacing(1));
    fitRange = [0 min(period,range(2))];
else
    period = inf; fitRange=range;
end
if fitRange(2)<fitRange(1)
    distance=nan; candidates=[]; coherence=nan; return;
end
fc = f-mean(f); z=exp(1i*phase(:));
obj = @(d) -abs(sum(w.*z.*exp(1i*4*pi*fc*d/cfg.c)));
grid = fitRange(1):cfg.pbrStepM:fitRange(2);
grid = unique([grid fitRange(2)]);
values = abs((w.*z).'*exp(1i*4*pi*fc*grid/cfg.c));
[~,j] = max(values);
lo=max(fitRange(1),grid(j)-cfg.pbrStepM);
hi=min(fitRange(2),grid(j)+cfg.pbrStepM);
base = boundedMin(obj,lo,hi,1e-9);
coherence = -obj(base)/sum(w);
tol = 1e-6;
if isfinite(period)
    base = mod(base,period);
    if period-base<tol || base<tol, base=0; end
    first=ceil((range(1)-base-tol)/period);
    last=floor((range(2)-base+tol)/period);
    candidates=base+(first:last)*period;
else
    candidates=base;
end
candidates(abs(candidates-range(1))<tol)=range(1);
candidates(abs(candidates-range(2))<tol)=range(2);
candidates=candidates(candidates>=range(1) & candidates<=range(2));
candidates=unique(candidates);
if isempty(candidates), distance=nan; else, distance=candidates(1); end
end

function x = boundedMin(fun,lo,hi,tol,varargin)
if hi<=lo, x=lo; return; end
xmid=fminbnd(fun,lo,hi,optimset('Display','off','TolX',tol));
candidates=[lo xmid hi varargin{:}];
candidates=candidates(isfinite(candidates) & candidates>=lo & candidates<=hi);
values=arrayfun(fun,candidates);
[~,j]=min(values); x=candidates(j);
end

function value = option(cfg,name,fallback)
if isfield(cfg,name), value=cfg.(name); else, value=fallback; end
end

function curvature = phaseCurvature(phase,f)
% RMS of the second-order (non-affine) component of unwrapped phase.
% This is a diagnostic, not an unbiased multipath detector.  In particular,
% a short-band echo may introduce almost pure linear phase (range bias).
if numel(f)<3 || any(~isfinite(phase))
    curvature=nan; return;
end
x=(f(:)-mean(f(:)))/max(max(f)-min(f),realmin);
y=unwrap(phase(:));
A=[ones(numel(x),1),x];
residual=y-A*(A\y);
curvature=sqrt(mean(residual.^2));
end
