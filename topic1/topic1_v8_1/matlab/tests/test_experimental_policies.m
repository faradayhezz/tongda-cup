function report = test_experimental_policies()
%TEST_EXPERIMENTAL_POLICIES Decision guards and independent physics checks.
% These tests expose known limits; passing does not prove NLOS robustness.
records=struct('Name',{},'Pass',{},'Detail',{});
base=struct('fusedM',10,'pbrM',9.8,'pbrValid',true, ...
    'pbrAmbiguous',false,'aliasCandidatesM',9.8, ...
    'innovationSigma',4,'pbrCoherence',.85, ...
    'status','range_phase_disagreement_rtt_only','fusionValid',false);
choice=td1.selectConflictV8(base);
assert(choice.usePbr && choice.selectedM==base.pbrM);
records(end+1)=pass('Eligible conflict','Unique valid phase candidate accepted');
bad=base;bad.pbrValid=false;assert(~td1.selectConflictV8(bad).usePbr);
bad=base;bad.pbrAmbiguous=true;bad.aliasCandidatesM=[9.8 28.5];
assert(~td1.selectConflictV8(bad).usePbr);
bad=base;bad.innovationSigma=2;assert(~td1.selectConflictV8(bad).usePbr);
bad=base;bad.fusedM=NaN;assert(~td1.selectConflictV8(bad).usePbr);
bad=base;bad.status='unreliable_sync';assert(~td1.selectConflictV8(bad).usePbr);
records(end+1)=pass('Conflict safety guards','Invalid, ambiguous, small, unavailable and wrong status rejected');
for coherence=[.69 .97 .999]
    bad=base;bad.pbrCoherence=coherence;
    assert(~td1.selectConflictV8(bad).usePbr);
end
records(end+1)=pass('Conflict coherence boundaries','Experimental interval is restricted');

fit=struct('eligible',true,'candidateM',9.5,'relativeImprovement',.9, ...
    'echoAmplitude',.3,'excessDelayNs',25,'singleCost',.1,'twoPathCost',.01);
gate=td1.selectTwoPathV3(base,fit);assert(gate.useTwoPath);
badFit=fit;badFit.candidateM=14;
gate=td1.selectTwoPathV3(base,badFit);assert(~gate.useTwoPath);
assert(strcmp(gate.reason,'excessive_shift'));
records(end+1)=pass('Two path correction bound','Large correction rejected by V3');
badFit=fit;badFit.candidateM=14;badFit.excessDelayNs=60;
badFit.echoAmplitude=.4;badFit.relativeImprovement=.995;badFit.twoPathCost=.0005;
gate=td1.selectTwoPathV3(base,badFit);
rescue=td1.selectTwoPathV7(base,badFit,gate,struct(),17);
assert(rescue.useTwoPath && rescue.rescue);
badFit.echoAmplitude=.68;
assert(~td1.selectTwoPathV7(base,badFit,gate,struct(),17).useTwoPath);
records(end+1)=pass('Rescue restrictions','V7 rescue and rejected high amplitude');

oldRng=rng;cleanup=onCleanup(@() rng(oldRng));
rng(202610095,'twister');cfg=td1.defaultConfig();scene=cfg.scenarios(1);
scene.phaseNoiseRad=0;scene.clockAppm=0;scene.clockBppm=0;
scene.cfoHz=0;scene.hwDelayS=0;scene.phaseResidualRad=zeros(17,1);
prep=td1.prepare(cfg,scene);rx=td1.receiverConfig(prep);
cal=calibrateClean(scene,prep,rx,cfg.calibrationDistanceM);
scene.driftClockBppm=300;
feat=td1.observe(td1.simulate(10,Inf,scene,prep,false),rx);
ordinary=td1.estimate(feat,cal,rx);
rx.allowPbrOnlyOnDisagreement=true;
experimental=td1.estimate(feat,cal,rx);
assert(abs(ordinary.fusedM-10)>2 && abs(experimental.fusedM-10)<.005);
assert(strcmp(td1.outputMode(ordinary),'rtt_only'));
assert(strcmp(td1.outputMode(experimental),'pbr_only'));
assert(~experimental.fusionValid);
records(end+1)=pass('Clock drift opt in and accounting','Physical PBR-only fallback is separate from RTT');

scene.driftClockBppm=0;scene.driftDelayS=16e-9;
shared=td1.estimate(td1.observe(td1.simulate(10,Inf,scene,prep,false),rx),cal,rx);
assert(abs(shared.fusedM-10)>2 && shared.innovationSigma<3);
records(end+1)=pass('Shared delay negative control','Expected limitation: both methods share hidden range bias');

% A valid single-path candidate inside the fit window must be retained as
% an available reference. A broad fminbnd search alone can miss that peak.
plans={0:16,0:2:32,0:4:64,[0 1 2 4 6 8 10 12 14 16 18 20 22 26 29 31 32]};
amp=[0 .15 .25 .4];delayNs=[0 15 25 60];echoPhase=[0 .7 .7 -.9];
checked=0;
for p=1:numel(plans)
    clean=cfg.scenarios(1);clean.phaseNoiseRad=0;
    clean.fHz=cfg.toneAnchorHz+plans{p}(:)*1e6;
    clean.phaseResidualRad=zeros(numel(clean.fHz),1);
    prep=td1.prepare(cfg,clean);rx=td1.receiverConfig(prep);
    cal=calibrateClean(clean,prep,rx,cfg.calibrationDistanceM);
    for e=1:numel(amp)
        channel=clean;channel.echoAmplitude=amp(e);
        channel.echoDelayS=delayNs(e)*1e-9;channel.echoPhaseRad=echoPhase(e);
        for distance=[3 15]
            feat=td1.observe(td1.simulate(distance,Inf,channel,prep,false),rx);
            ordinary=td1.estimate(feat,cal,rx);
            probe=td1.twoPathProbe(feat,cal,rx,ordinary);
            assert(probe.coarseStartCount==24 && probe.validCoarseStartCount==24, ...
                'Nested optimizer corrupted physical coarse starts.');
            candidates=ordinary.aliasCandidatesM;
            [~,idx]=min(abs(candidates-ordinary.fusedM));candidate=candidates(idx);
            lo=max(rx.distanceRangeM(1),ordinary.fusedM-3);
            hi=min(rx.distanceRangeM(2),ordinary.fusedM+3);
            if candidate>=lo && candidate<=hi
                sigma=sqrt(cal.phaseStdRad.^2+feat.phaseNoiseStdRad.^2);
                w=1./max(sigma.^2,1e-6);w=w/sum(w);
                z=exp(1i*(feat.phaseRad-cal.phaseBiasRad));x=rx.fHz-mean(rx.fHz);
                model=exp(-1i*4*pi*x*candidate/rx.c);
                knownCost=max(0,2*(1-abs(sum(w.*z.*conj(model)))));
                assert(probe.singleCost<=knownCost+1e-7, ...
                    'Single-path cost missed known phase candidate: plan %d echo %d d %.0f.',p,e,distance);
                checked=checked+1;
            end
        end
    end
end
records(end+1)=pass('Single path optimizer reference',sprintf('%d independent candidate comparisons',checked));
report=struct2table(records);disp(report);
fprintf('PASS: %d experimental policy tests.\n',height(report));
end

function cal=calibrateClean(scene,prep,rx,distance)
for k=1:8
    feat=td1.observe(td1.simulate(distance,Inf,scene,prep,true),rx);
    if k==1,features=repmat(feat,8,1);end
    features(k)=feat;
end
cal=td1.calibrate(features,repmat(distance,8,1),rx);
end

function record=pass(name,detail)
record=struct('Name',name,'Pass',true,'Detail',detail);
end
