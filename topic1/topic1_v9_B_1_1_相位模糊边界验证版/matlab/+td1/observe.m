function feat = observe(obs,cfg)
%OBSERVE Estimate features from IQ and declared scheduling metadata only.
% This is a simulation receiver, not BLE interoperability or Pluto timing.
% LO CFO correction does NOT correct an independent sampling/turnaround clock.
% exchangeGapS is a declared equivalent scheduling interval.  Derotating each
% block at its own first sample alone cannot remove the phase across this gap.

f = cfg.fHz(:); nTone = numel(cfg.toneRef);
validateattributes(obs.replyDelayS,{'numeric'}, ...
    {'real','finite','scalar','nonnegative'});
if size(obs.forwardTone,1)~=nTone || size(obs.reverseTone,1)~=nTone || ...
        size(obs.forwardTone,2)~=numel(f) || ...
        size(obs.reverseTone,2)~=numel(f)
    error('td1:BadToneShape','Tone IQ shape must match toneRef and fHz.');
end
gap = obs.exchangeGapS(:);
if numel(gap)~=numel(f) || any(~isfinite(gap)) || any(gap<0)
    error('td1:BadGap','exchangeGapS must contain a finite gap per frequency.');
end
qf = bsxfun(@times,obs.forwardTone,conj(cfg.toneRef(:)));
qr = bsxfun(@times,obs.reverseTone,conj(cfg.toneRef(:)));
[cf,af,cof,sf,nvf,okf] = toneCfo(qf,cfg);
[cr,ar,cor,sr,nvr,okr] = toneCfo(qr,cfg);
cp = (cf-cr)/2;
pairTolerance = option(cfg,'cfoPairToleranceHz',max(2000,cfg.fs/nTone/8));
feat.cfoForwardHz = cf;
feat.cfoReverseHz = cr;
feat.cfoPairHz = cp;
feat.cfoUncertaintyHz = sqrt(sf^2+sr^2)/2;
feat.toneCoherenceForward = cof;
feat.toneCoherenceReverse = cor;
feat.cfoValid = okf && okr && abs(cf+cr)<=pairTolerance;
feat.rawPhaseRad = angle(mean(qf,1).*mean(qr,1)).';
feat.phaseRad = angle(af.*ar).'+2*pi*cp*gap;
feat.phaseRad = angle(exp(1i*feat.phaseRad));
% Nominal phase noise variance from the IQ residual, not a test truth error.
afPower = max(abs(af(:)).^2,realmin);
arPower = max(abs(ar(:)).^2,realmin);
feat.phaseNoiseStdRad = sqrt(nvf./(2*nTone*afPower)+ ...
    nvr./(2*nTone*arPower));
feat.exchangeGapS = gap;

y = obs.syncIq(:);
if numel(y)~=numel(cfg.knownSync) || any(~isfinite(y))
    error('td1:BadSync','syncIq must be finite and match knownSync.');
end
t = (0:numel(y)-1).'/cfg.fs;
y = y.*exp(-1i*2*pi*cf*t);
crossSpectrum = fft(y,cfg.fftLength).*conj(cfg.syncSpectrum(:));
lagBounds = obs.replyDelayS*cfg.fs+ ...
    2*cfg.rttSearchRangeM(:).'*cfg.fs/cfg.c;
if isfield(cfg,'rttBasisReplyDelayS') && ...
        isequal(obs.replyDelayS,cfg.rttBasisReplyDelayS) && ...
        isfield(cfg,'rttBasis') && isequal(lagBounds,cfg.rttLagBounds)
    lagGrid=cfg.rttLagGrid; basis=cfg.rttBasis;
else
    lagGrid=lagBounds(1):cfg.rttCoarseStepSamples:lagBounds(2);
    lagGrid=unique([lagGrid lagBounds(2)]);
    basis=exp(1i*cfg.binRad(:)*lagGrid);
end
scores = abs(crossSpectrum.'*basis).^2;
[~,best] = max(scores);
lo = max(lagBounds(1),lagGrid(best)-cfg.rttCoarseStepSamples);
hi = min(lagBounds(2),lagGrid(best)+cfg.rttCoarseStepSamples);
obj = @(lag) -abs(sum(crossSpectrum.* ...
    exp(1i*cfg.binRad(:)*lag))).^2;
lag = boundedMin(obj,lo,hi,1e-9);
correlation = sum(crossSpectrum.*exp(1i*cfg.binRad(:)*lag))/cfg.fftLength;
syncEnergy = sum(abs(cfg.knownSync(:)).^2);
rxEnergy = sum(abs(y).^2);
feat.rawRttM = (lag/cfg.fs-obs.replyDelayS)*cfg.c/2;
feat.syncQuality = abs(correlation)^2/max(syncEnergy*rxEnergy,realmin);
atBoundary = lag<=lagBounds(1)+1e-6 || lag>=lagBounds(2)-1e-6;
feat.syncValid = isfinite(feat.rawRttM) && ~atBoundary && ...
    feat.syncQuality>=option(cfg,'minSyncQuality',0.003);

% A local AWGN timing variance estimate after profiling unknown complex gain.
% It is a nominal random-noise estimate, not an NLOS/hardware bias bound.
noiseVariance = max((rxEnergy-abs(correlation)^2/max(syncEnergy,realmin))/ ...
    max(numel(y)-1,1),realmin);
powerSpectrum = abs(cfg.syncSpectrum(:)).^2;
angularHz = cfg.binRad(:)*cfg.fs;
derivativeEnergy = sum(powerSpectrum.*angularHz.^2)/cfg.fftLength;
crossDerivative = sum(powerSpectrum.*(-1i*angularHz))/cfg.fftLength;
derivativeEnergy = max(derivativeEnergy- ...
    abs(crossDerivative)^2/max(syncEnergy,realmin),realmin);
gainPower = abs(correlation)^2/max(syncEnergy^2,realmin);
feat.rttNoiseSigmaM = cfg.c/2*sqrt(noiseVariance/ ...
    max(2*gainPower*derivativeEnergy,realmin));
end

function [cfo,amplitude,coherence,sigmaHz,noiseVariance,valid] = toneCfo(q,cfg)
n = size(q,1); k = size(q,2); lag = min(64,floor(n/2));
if lag<1 || any(~isfinite(q(:)))
    error('td1:BadTone','Tone IQ must contain finite samples.');
end
lagProduct = q(1+lag:end,:).*conj(q(1:end-lag,:));
coarse = cfg.fs/(2*pi*lag)*angle(sum(lagProduct(:)));
capture = cfg.cfoCaptureHz;
initialValid = abs(coarse)<capture;
% Pooled lag correlation seeds a local coherent-energy optimization.  Each
% frequency has its own unknown complex amplitude; phases are never pooled
% directly across frequencies during CFO acquisition.
span = cfg.fs/(2*n);
lo = max(-capture,coarse-span); hi = min(capture,coarse+span);
if hi<=lo
    lo = -capture; hi = capture;
end
obj = @(nu) -sum(abs(sum(bsxfun(@times,q, ...
    exp(-1i*2*pi*nu*cfg.toneTimeS(:))),1)).^2);
cfo = boundedMin(obj,lo,hi,1e-5);
derotated = bsxfun(@times,q,exp(-1i*2*pi*cfo*cfg.toneTimeS(:)));
amplitude = mean(derotated,1);
total = sum(abs(q(:)).^2);
coherent = n*sum(abs(amplitude).^2);
coherence = coherent/max(total,realmin);
residual = bsxfun(@minus,derotated,amplitude);
noiseVariance = max(sum(abs(residual(:)).^2)/max(k*(n-1),1),realmin);
centeredTime = cfg.toneTimeS(:)-mean(cfg.toneTimeS(:));
information = 2*(2*pi)^2*sum(abs(amplitude).^2)*sum(centeredTime.^2);
sigmaHz = sqrt(noiseVariance/max(information,realmin));
valid = initialValid && isfinite(cfo) && isfinite(sigmaHz) && ...
    abs(cfo)<capture-1 && coherence>=option(cfg,'minToneCoherence',0.08);
end

function x = boundedMin(fun,lo,hi,tol)
if hi<=lo, x=lo; return; end
xmid = fminbnd(fun,lo,hi,optimset('Display','off','TolX',tol));
candidates = [lo xmid hi];
values = arrayfun(fun,candidates);
[~,j] = min(values); x = candidates(j);
end

function value = option(cfg,name,fallback)
if isfield(cfg,name), value=cfg.(name); else, value=fallback; end
end
