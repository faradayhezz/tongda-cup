function trials = run_v9_A_1_diagnostic(nEpisodes,seed,outDir,trackReferenceDrift)
%RUN_V9_A_CALIBRATION Prospective dynamic-reference calibration ablation.
% Quick: run_v9_A_1_diagnostic(1,20271109);
% Full:  run_v9_A_1_diagnostic(5,20271109);
% Reference acquisitions use a KNOWN range; target truth never enters any
% calibration, prediction, estimator or V8 decision. No actual hardware.
if nargin<1 || isempty(nEpisodes),nEpisodes=1;end
if nargin<2 || isempty(seed),seed=20271109;end
validateattributes(nEpisodes,{'numeric'},{'scalar','integer','positive'});
validateattributes(seed,{'numeric'},{'scalar','integer','nonnegative'});
root=fileparts(mfilename('fullpath'));
if nargin<3 || isempty(outDir),outDir=fullfile(root,'results','v9_A_1_diagnostic');end
if nargin<4 || isempty(trackReferenceDrift),trackReferenceDrift=true;end
if ~exist(outDir,'dir'),mkdir(outDir);end
cfg=td1.defaultConfig();cfg.allowPbrOnlyOnDisagreement=false;
plans={struct('name','uniform_32MHz','MHz',0:2:32), ...
       struct('name','uniform_64MHz','MHz',0:4:64)};
conditions={ ...
 struct('name','LOS_drift','amp',0,'delayNs',0,'phase',0,'driftNs',16,'clockPpm',60), ...
 struct('name','light_drift','amp',.25,'delayNs',25,'phase',.7,'driftNs',16,'clockPpm',60), ...
 struct('name','strong_drift','amp',.4,'delayNs',60,'phase',-.9,'driftNs',16,'clockPpm',60), ...
 struct('name','strong_stable','amp',.4,'delayNs',60,'phase',-.9,'driftNs',0,'clockPpm',0)};
snrs=[0 15 30];distances=[3 15];timeSteps=20;updateEvery=5;
referenceCount=8; % Independent known-range IQ acquisitions per update.
N=numel(plans)*numel(conditions)*numel(snrs)*numel(distances)*nEpisodes*timeSteps;
proto=struct('Plan','','Condition','','SNR_dB',NaN,'Distance_m',NaN,...
 'Episode',NaN,'TimeStep',NaN,'CalibrationAge',NaN,'ReferenceUpdated',false,...
 'Fixed_m',NaN,'Periodic_m',NaN,'Predicted_m',NaN,...
 'FixedError_m',NaN,'PeriodicError_m',NaN,'PredictedError_m',NaN,...
 'FixedStatus','','PeriodicStatus','','PredictedStatus','',...
 'FixedUsePbr',false,'PeriodicUsePbr',false,'PredictedUsePbr',false,...
 'PeriodicCalibrationValid',false,'PredictedCalibrationValid',false, ...
 'TrueDriftDelay_ns',NaN,'TrueDriftClock_ppm',NaN, ...
 'FixedCalRttBias_m',NaN,'PeriodicCalRttBias_m',NaN,'PredictedCalRttBias_m',NaN, ...
 'FixedCalPhaseSlope_m',NaN,'PeriodicCalPhaseSlope_m',NaN,'PredictedCalPhaseSlope_m',NaN, ...
 'RawRtt_m',NaN,'FixedRtt_m',NaN,'PeriodicRtt_m',NaN,'PredictedRtt_m',NaN, ...
 'FixedPbr_m',NaN,'PeriodicPbr_m',NaN,'PredictedPbr_m',NaN, ...
 'FixedBase_m',NaN,'PeriodicBase_m',NaN,'PredictedBase_m',NaN, ...
 'ReferenceTracksDrift',false);
rows=repmat(proto,N,1);ix=0;
oldRng=rng;clean=onCleanup(@()rng(oldRng)); %#ok<NASGU>
for pi=1:numel(plans)
 plan=plans{pi};
 for ci=1:numel(conditions)
  cond=conditions{ci};
  scene0=cfg.scenarios(1);scene0.name=cond.name;
  scene0.referenceTracksDrift=logical(trackReferenceDrift);
  scene0.fHz=cfg.toneAnchorHz+plan.MHz(:)*1e6;
  scene0.phaseResidualRad=zeros(numel(scene0.fHz),1);
  scene0.echoAmplitude=cond.amp;scene0.echoDelayS=cond.delayNs*1e-9;
  scene0.echoPhaseRad=cond.phase;
  scene0.hwDelayS=16e-9;scene0.clockAppm=30;scene0.clockBppm=-30;
  scene0.cfoHz=12000;
  prep=td1.prepare(cfg,scene0);rx=td1.receiverConfig(prep);
  for si=1:numel(snrs)
   snr=snrs(si);
   for ep=1:nEpisodes
    % Independent replicates; keep the same target observation across estimators.
    rng(seed+pi*1000000+ci*100000+si*10000+ep*100,'twister');
    fixed=[];latest=[];previous=[];lastUpdate=0;
    for t=1:timeSteps
     % Time-varying simulator truth is confined to the signal generator.
     driftFraction=(t-1)/(timeSteps-1);
     currentScene=scene0;
     currentScene.driftDelayS=cond.driftNs*1e-9*driftFraction;
     currentScene.driftClockBppm=cond.clockPpm*driftFraction;
     updated=mod(t-1,updateEvery)==0;
     if updated
      ref=[];
      for k=1:referenceCount
       raw=td1.simulate(cfg.calibrationDistanceM,snr,currentScene,prep,true);
       observed=td1.observe(raw,rx);
       if k==1,ref=repmat(observed,referenceCount,1);end
       ref(k)=observed;
      end
      fresh=td1.calibrate(ref,repmat(cfg.calibrationDistanceM,referenceCount,1),rx);
      if isempty(fixed),fixed=fresh;end
      previous=latest;latest=fresh;lastUpdate=t;
     end
     age=t-lastUpdate;
     pred=td1.predictCalibrationV9(latest,previous,age,updateEvery,0.5);
     for di=1:numel(distances)
      d=distances(di);
      signal=td1.simulate(d,snr,currentScene,prep,false);
      feat=td1.observe(signal,rx);
      a0=td1.estimate(feat,fixed,rx);a=td1.selectConflictV8(a0,struct());
      b0=td1.estimate(feat,latest,rx);b=td1.selectConflictV8(b0,struct());
      c0=td1.estimate(feat,pred,rx);c=td1.selectConflictV8(c0,struct());
      ix=ix+1;
      rows(ix).Plan=plan.name;rows(ix).Condition=cond.name;
      rows(ix).SNR_dB=snr;rows(ix).Distance_m=d;
      rows(ix).Episode=ep;rows(ix).TimeStep=t;
      rows(ix).CalibrationAge=age;rows(ix).ReferenceUpdated=updated;
      rows(ix).Fixed_m=a.selectedM;rows(ix).Periodic_m=b.selectedM;
      rows(ix).Predicted_m=c.selectedM;
      rows(ix).FixedError_m=a.selectedM-d;
      rows(ix).PeriodicError_m=b.selectedM-d;
      rows(ix).PredictedError_m=c.selectedM-d;
      rows(ix).FixedStatus=a.reason;rows(ix).PeriodicStatus=b.reason;
      rows(ix).PredictedStatus=c.reason;
      rows(ix).FixedUsePbr=a.usePbr;rows(ix).PeriodicUsePbr=b.usePbr;
      rows(ix).PredictedUsePbr=c.usePbr;
      rows(ix).PeriodicCalibrationValid=latest.phaseCalibrationValid;
      rows(ix).PredictedCalibrationValid=pred.phaseCalibrationValid;
      % Diagnostic ground truth BELOW: recorded to CSV only, never passed to
      % estimate(), predictCalibrationV9(), selectConflictV8() or calibrate().
      rows(ix).TrueDriftDelay_ns=currentScene.driftDelayS*1e9;
      rows(ix).TrueDriftClock_ppm=currentScene.driftClockBppm;
      rows(ix).ReferenceTracksDrift=logical(trackReferenceDrift);
      rows(ix).FixedCalRttBias_m=fixed.rttBiasM;
      rows(ix).PeriodicCalRttBias_m=latest.rttBiasM;
      rows(ix).PredictedCalRttBias_m=pred.rttBiasM;
      rows(ix).FixedCalPhaseSlope_m=localPhaseSlopeDistance(fixed.phaseBiasRad,rx.fHz,cfg.c);
      rows(ix).PeriodicCalPhaseSlope_m=localPhaseSlopeDistance(latest.phaseBiasRad,rx.fHz,cfg.c);
      rows(ix).PredictedCalPhaseSlope_m=localPhaseSlopeDistance(pred.phaseBiasRad,rx.fHz,cfg.c);
      rows(ix).RawRtt_m=feat.rawRttM;
      rows(ix).FixedRtt_m=a0.rttM;
      rows(ix).PeriodicRtt_m=b0.rttM;
      rows(ix).PredictedRtt_m=c0.rttM;
      rows(ix).FixedPbr_m=a0.pbrM;
      rows(ix).PeriodicPbr_m=b0.pbrM;
      rows(ix).PredictedPbr_m=c0.pbrM;
      rows(ix).FixedBase_m=a0.fusedM;
      rows(ix).PeriodicBase_m=b0.fusedM;
      rows(ix).PredictedBase_m=c0.fusedM;
     end
    end
   end
  end
  fprintf('V9_A_1 complete: %s / %s\n',plan.name,cond.name);
 end
end
trials=struct2table(rows);
writetable(trials,fullfile(outDir,'v9_A_1_trials.csv'));
summary=cell(numel(plans)*numel(conditions),14);j=0;
for pi=1:numel(plans)
 for ci=1:numel(conditions)
  select=strcmp(trials.Plan,plans{pi}.name)&strcmp(trials.Condition,conditions{ci}.name);
  x=trials(select,:);j=j+1;
  finite=isfinite(x.FixedError_m)&isfinite(x.PeriodicError_m)&isfinite(x.PredictedError_m);
  summary(j,:)={plans{pi}.name,conditions{ci}.name,height(x),sum(finite),...
   localRmse(x.FixedError_m(finite)),localRmse(x.PeriodicError_m(finite)),...
   localRmse(x.PredictedError_m(finite)),...
   localP95(x.FixedError_m(finite)),localP95(x.PeriodicError_m(finite)),...
   localP95(x.PredictedError_m(finite)),...
   localOver1(x.FixedError_m(finite)),localOver1(x.PeriodicError_m(finite)),...
   localOver1(x.PredictedError_m(finite)),sum(x.ReferenceUpdated)};
 end
end
s=cell2table(summary,'VariableNames',{'Plan','Condition','Count','PairedFiniteN',...
 'FixedRMSE_m','PeriodicRMSE_m','PredictedRMSE_m',...
 'FixedP95_m','PeriodicP95_m','PredictedP95_m',...
 'FixedOver1m','PeriodicOver1m','PredictedOver1m','ReferenceUpdateRows'});
writetable(s,fullfile(outDir,'v9_A_1_summary.csv'));
fid=fopen(fullfile(outDir,'v9_A_1_notes.txt'),'w');
if fid>=0
 fprintf(fid,'Seed=%d, episodes=%d, target records=%d.\n',seed,nEpisodes,height(trials));
 fprintf(fid,'Known-reference updates every %d time steps with %d independent IQ captures.\n',updateEvery,referenceCount);
 fprintf(fid,'Fixed = t1 reference; Periodic = latest reference; Predicted = reference-history extrapolation.\n');
 fprintf(fid,'Drift is linear within episode; prediction may be favored by this fixture.\n');
 fprintf(fid,'Drift amplitudes only configure simulator, NEVER estimator, predictor, or selector.\n');
 fprintf(fid,'Shared target IQ across methods; reference overhead excluded from RMSE.\n');
 fprintf(fid,'Ideal coherent frequency retuning, software simulation, not PlutoSDR validation.\n');
 fprintf(fid,'NaN errors excluded from paired metrics: check PairedFiniteN.\n');
 fclose(fid);
end
fprintf('V9_A_1 finished: %d target records -> %s\n',height(trials),outDir);
end
function v=localRmse(x)
if isempty(x),v=NaN;else,v=sqrt(mean(x.^2));end
end
function v=localP95(x)
x=sort(abs(x));if isempty(x),v=NaN;else,v=x(max(1,ceil(.95*numel(x))));end
end
function v=localOver1(x)
if isempty(x),v=NaN;else,v=mean(abs(x)>1);end
end

function d=localPhaseSlopeDistance(ph,f,c)
% Unwrapped phase bias slope, relative diagnostic, not absolute truth.
x=f(:)-mean(f(:));y=unwrap(ph(:));
d=-c/(4*pi)*(x.'*(y-mean(y)))/max(x.'*x,realmin);
end
