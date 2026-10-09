function report = test_topic1()
%TEST_TOPIC1 Physics invariants and failure paths, base MATLAB only.
% Run from code folder: addpath('tests'); report=test_topic1;
cfg=td1.defaultConfig();
oldRng=rng; cleanup=onCleanup(@() rng(oldRng));
rng(20261009,'twister');
records=struct('Name',{},'Pass',{},'Detail',{});
clean=cfg.scenarios(1);
clean.clockAppm=0; clean.clockBppm=0; clean.cfoHz=0;
clean.hwDelayS=0; clean.phaseResidualRad=zeros(numel(clean.fHz),1);
clean.echoAmplitude=0; clean.phaseNoiseRad=0;
clean.driftDelayS=0; clean.driftClockBppm=0; clean.randomHopPhase=false;
p=td1.prepare(cfg,clean);
cal=fitClean(clean,p,cfg.calibrationDistanceM);
for truth=[0 1 2.718 19.234 40]
    feat=td1.observe(td1.simulate(truth,Inf,clean,p,false),p);
    est=td1.estimate(feat,cal,p);
    assert(abs(est.rttM-truth)<.05,'RTT sign/fractional delay failed.');
    assert(abs(est.pbrM-truth)<.005,'PBR round-trip scale failed.');
    assert(abs(est.fusedM-truth)<.05,'Fusion noiseless range failed.');
end
records(end+1)=pass('Noiseless fractional range','0, 1, 2.718, 19.234, 40 m including boundaries');

truth=8.432;
feat=td1.observe(td1.simulate(truth,Inf,clean,p,false),p);
est1=td1.estimate(feat,cal,p);
shifted=feat; shifted.phaseRad=feat.phaseRad+1.234567;
shifted.rawPhaseRad=feat.rawPhaseRad+1.234567;
est2=td1.estimate(shifted,cal,p);
assert(abs(est1.pbrM-est2.pbrM)<1e-5,'Common phase affected PBR.');
assert(abs(est1.fusedM-est2.fusedM)<1e-5,'Common phase affected fusion.');
records(end+1)=pass('Unknown common phase invariance','PBR/fusion unaffected');

slope=td1.phaseSlope(feat.phaseRad-cal.phaseBiasRad,p.fHz,p.c);
assert(abs(slope.distanceM-truth)<.005,'Independent phase slope disagrees.');
assert(abs(slope.distanceM-est1.pbrM)<.005,'Slope/search cross-check failed.');
records(end+1)=pass('Independent unwrap regression','Cross-check coherent search');

impaired=clean; impaired.clockAppm=30; impaired.clockBppm=-30;
impaired.hwDelayS=16e-9; impaired.cfoHz=12000;
impaired.phaseResidualRad=.2*sin((1:numel(clean.fHz)).');
p2=td1.prepare(cfg,impaired);
cal2=fitClean(impaired,p2,cfg.calibrationDistanceM);
feat2=td1.observe(td1.simulate(12.345,Inf,impaired,p2,false),p2);
est=td1.estimate(feat2,cal2,p2);
assert(abs(feat2.cfoPairHz-12000)<10,'IQ CFO recovery failed.');
assert(abs(est.rttM-12.345)<.06,'Known-range RTT calibration failed.');
assert(abs(est.pbrM-12.345)<.005,'CFO/phase calibration failed.');
expected=p2.c/2*((1+30e-6)/(1-30e-6)-1)*p2.replyDelayS ...
    +p2.c*impaired.hwDelayS/2+30e-6*12.345;
assert(abs(feat2.rawRttM-12.345-expected)<.05,'Clock/reply bias formula failed.');
records(end+1)=pass('CFO clock and reference calibration','Independent IQ CFO and known range');

sparse=clean; sparse.fHz=(2.4e9+(0:4)*8e6).';
sparse.phaseResidualRad=zeros(numel(sparse.fHz),1);
p3=td1.prepare(cfg,sparse); cal3=fitClean(sparse,p3,cfg.calibrationDistanceM);
truth=19.234; feat3=td1.observe(td1.simulate(truth,Inf,sparse,p3,false),p3);
est=td1.estimate(feat3,cal3,p3); period=p3.c/(2*8e6);
assert(est.pbrAmbiguous && numel(est.aliasCandidatesM)>=2,'Missing PBR aliases.');
assert(abs(est.pbrM-mod(truth,period))<.005,'PBR fundamental alias mismatch.');
assert(abs(est.fusedM-truth)<.05,'RTT did not select correct alias.');
records(end+1)=pass('Sparse phase ambiguity','18.737 m period; RTT selects true branch');

% A misleading RTT with underestimated uncertainty should not be marketed as
% successful fusion. Either reject it or show that it selects the wrong alias.
bad=feat3; bad.rawRttM=truth-period;
badEst=td1.estimate(bad,cal3,p3);
assert(~badEst.fusionValid || abs(badEst.fusedM-truth)>period/2, ...
    'Biased RTT failure was not exposed.');
records(end+1)=pass('Biased RTT negative control','Wrong alias or explicit fallback');

bad=feat; bad.phaseRad=(0:numel(p.fHz)-1).'.^2*.71;
badCal=cal; badCal.phaseStdRad=ones(numel(p.fHz),1)*.03;
badEst=td1.estimate(bad,badCal,p);
assert(~badEst.fusionValid,'Inconsistent frequency phases not rejected.');
records(end+1)=pass('Inconsistent phase rejection','Quality failure is explicit');

obs=td1.simulate(truth,Inf,clean,p,false);
obs.syncIq=zeros(size(obs.syncIq));
badFeat=td1.observe(obs,p); badEst=td1.estimate(badFeat,cal,p);
assert(~badEst.fusionValid && ~badFeat.syncValid && isnan(badEst.fusedM), ...
    'Missing sync not flagged.');
records(end+1)=pass('Missing sync rejection','No high confidence range without sync');

outside=clean; outside.cfoHz=120e3; p4=td1.prepare(cfg,outside);
outFeat=td1.observe(td1.simulate(10,Inf,outside,p4,false),p4);
assert(~outFeat.cfoValid,'Out-of-range CFO not rejected.');
records(end+1)=pass('CFO capture limit','120 kHz exceeds configured 80 kHz');

receiver=td1.receiverConfig(p2);
assert(~isfield(receiver,'scenarios') && ~isfield(receiver,'cfoHz') && ...
    ~isfield(receiver,'hwDelayS'),'Channel truths crossed receiver boundary.');
featWhitelisted=td1.observe(td1.simulate(12.345,Inf,impaired,p2,false),receiver);
estWhitelisted=td1.estimate(featWhitelisted,cal2,receiver);
assert(abs(estWhitelisted.pbrM-12.345)<.005,'Whitelisted receiver differs.');
records(end+1)=pass('Receiver truth isolation','Only design fields cross the interface');

report=struct2table(records); disp(report);
fprintf('PASS: %d meaningful tests.\n',height(report));
end

function cal=fitClean(scene,p,knownDistance)
for k=1:8
    feat=td1.observe(td1.simulate(knownDistance,Inf,scene,p,true),p);
    if k==1,features=repmat(feat,8,1);end
    features(k)=feat;
end
cal=td1.calibrate(features,repmat(knownDistance,8,1),p);
end

function record=pass(name,detail)
record=struct('Name',name,'Pass',true,'Detail',detail);
end
