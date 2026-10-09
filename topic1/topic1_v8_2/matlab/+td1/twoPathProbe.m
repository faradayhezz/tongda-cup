function probe = twoPathProbe(feat,cal,cfg,baseline)
%TWOPATHPROBE Exploratory phase-only two-path estimation; NOT a BLE receiver.
% Fits exp(-j4*pi*f*d/c) * (1+a*exp(-j2*pi*(f-f0)*tau))^2.
% Unknown common phase is profiled out. The receiver does not access truth.
% This is deliberately diagnostic-only: short-band echoes can be unidentifiable.
probe=struct('candidateM',NaN,'excessDelayNs',NaN,'echoAmplitude',NaN, ...
    'echoPhaseRad',NaN,'singleCost',NaN,'twoPathCost',NaN, ...
    'relativeImprovement',NaN,'distanceShiftM',NaN, ...
    'eligible',false,'reason','not_evaluated');
if ~baseline.pbrValid || ~isfinite(baseline.fusedM) || ...
        numel(cfg.fHz)<8 || ~all(isfinite(feat.phaseRad(:)))
    probe.reason='unreliable_inputs';return;
end
f=cfg.fHz(:); f0=mean(f); x=f-f0;
z=exp(1i*(feat.phaseRad(:)-cal.phaseBiasRad(:)));
% Nominal phase variance weights; calibration uncertainty is per tone.
sigma=cal.phaseStdRad(:);
if numel(sigma)==1,sigma=repmat(sigma,numel(f),1);end
if isfield(feat,'phaseNoiseStdRad')
    sigma=sqrt(sigma.^2+feat.phaseNoiseStdRad(:).^2);
end
w=1./max(sigma.^2,1e-6);w=w/sum(w);
% Common complex phase is nuisance, so maximize correlation magnitude.
metric=@(model) max(0,2*(1-abs(sum(w.*z.*conj(model./max(abs(model),1e-9))))));
% Search locally around RTT-guided baseline. Bounds prevent unconstrained
% fits from claiming a remote alias as an echo-corrected range.
d0=baseline.fusedM;
lo=max(cfg.distanceRangeM(1),d0-3);
hi=min(cfg.distanceRangeM(2),d0+3);
if hi<=lo,probe.reason='distance_bounds';return;end
single=@(d) metric(exp(-1i*4*pi*x*d/cfg.c));
[~,probe.singleCost]=fminbnd(single,lo,hi,optimset('Display','off','TolX',1e-5));
% finite multistart; fit 4 physical parameters [d, tau_ns, amplitude, phase].
% For performance, first coarse search then refine only 2 best starts.
starts=[];scores=[];
for tau=[10 25 50 80]
    for amp=[0.15 0.35]
        for phi=[-pi 0 pi]
            p=[d0 tau amp phi];
            scores(end+1)=loss(p); %#ok<AGROW>
            starts(end+1,:)=p; %#ok<AGROW>
        end
    end
end
[~,idx]=sort(scores);
best=inf; pbest=[];
for j=1:min(3,numel(idx))
    p=fminsearch(@loss,starts(idx(j),:), ...
        optimset('Display','off','MaxFunEvals',350,'MaxIter',200,'TolX',1e-5));
    val=loss(p);
    if val<best,best=val;pbest=p;end
end
if isempty(pbest),probe.reason='optimization_failed';return;end
probe.candidateM=pbest(1);
probe.excessDelayNs=pbest(2);
probe.echoAmplitude=pbest(3);
probe.echoPhaseRad=atan2(sin(pbest(4)),cos(pbest(4)));
probe.twoPathCost=best;
probe.relativeImprovement=max(0,(probe.singleCost-best)/max(probe.singleCost,1e-10));
probe.distanceShiftM=probe.candidateM-d0;
% This flag means a plausible fitted model, NOT a verified resolved echo.
probe.eligible=(best<probe.singleCost) && pbest(2)>5 && pbest(2)<100 && ...
    pbest(3)>=0.02 && pbest(3)<0.7;
if probe.eligible
    probe.reason='candidate_diagnostic_only';
else
    probe.reason='weak_or_boundary_solution';
end
    function value=loss(p)
        d=p(1);tau=p(2)*1e-9;a=p(3)*exp(1i*p(4));
        if any(~isfinite(p)) || d<lo || d>hi || tau<5e-9 || ...
                tau>100e-9 || p(3)<0 || p(3)>0.7
            value=10+sum(abs(p(isfinite(p))));return;
        end
        h=1+a*exp(-1i*2*pi*x*tau);
        model=exp(-1i*4*pi*x*d/cfg.c).*h.^2;
        value=metric(model);
    end
end
