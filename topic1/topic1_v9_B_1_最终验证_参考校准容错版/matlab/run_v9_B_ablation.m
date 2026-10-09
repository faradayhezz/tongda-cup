function trials = run_v9_B_ablation(nEpisodes,seed,outDir)
%RUN_V9_A_CALIBRATION Prospective dynamic-reference calibration ablation.
% Quick: run_v9_A_3_1_stress(1,20271109);
% Full:  run_v9_A_3_1_stress(5,20271109);
% Reference acquisitions use a KNOWN range; target truth never enters any
% calibration, prediction, estimator or V8 decision. No actual hardware.
if nargin<1 || isempty(nEpisodes),nEpisodes=1;end
if nargin<2 || isempty(seed),seed=20280109;end
validateattributes(nEpisodes,{'numeric'},{'scalar','integer','positive'});
validateattributes(seed,{'numeric'},{'scalar','integer','nonnegative'});
root=fileparts(mfilename('fullpath'));
if nargin<3 || isempty(outDir),outDir=fullfile(root,'results','v9_B_ablation');end

if ~exist(outDir,'dir'),mkdir(outDir);end
cfg=td1.defaultConfig();cfg.allowPbrOnlyOnDisagreement=false;
plans={struct('name','uniform_32MHz','MHz',0:2:32), ...
       struct('name','uniform_64MHz','MHz',0:4:64)};
conditions={ ...
 struct('name','linear_drift','amp',0,'delayNs',0,'phase',0,'driftNs',16,'clockPpm',60,'shape','linear','referenceSnrPenalty',0), ...
 struct('name','quadratic_drift','amp',0,'delayNs',0,'phase',0,'driftNs',16,'clockPpm',60,'shape','quadratic','referenceSnrPenalty',0), ...
 struct('name','sudden_jump','amp',0,'delayNs',0,'phase',0,'driftNs',16,'clockPpm',60,'shape','jump','referenceSnrPenalty',0), ...
 struct('name','noisy_reference','amp',0,'delayNs',0,'phase',0,'driftNs',16,'clockPpm',60,'shape','linear','referenceSnrPenalty',20), ...
 struct('name','strong_stable','amp',.4,'delayNs',60,'phase',-.9,'driftNs',0,'clockPpm',0,'shape','stable','referenceSnrPenalty',0), ...
 struct('name','strong_drift','amp',.4,'delayNs',60,'phase',-.9,'driftNs',16,'clockPpm',60,'shape','linear','referenceSnrPenalty',0), ...
 struct('name','light_drift','amp',.25,'delayNs',25,'phase',.7,'driftNs',16,'clockPpm',60,'shape','linear','referenceSnrPenalty',0)};
snrs=[10 30];distances=[3 15];timeSteps=20;
updatePeriods=5; referenceCount=8;
N=numel(plans)*numel(conditions)*numel(updatePeriods)*numel(snrs)*numel(distances)*nEpisodes*timeSteps;
proto=struct('Plan','','Condition','','SNR_dB',NaN,'Distance_m',NaN,...
 'Episode',NaN,'TimeStep',NaN,'CalibrationAge',NaN,'ReferenceUpdated',false,...
 'UpdatePeriod',NaN,'ReferenceSNR_dB',NaN,'DriftProfile','','TrueJump',false,'TrueJumpActive',false,...
 'Fixed_m',NaN,'Periodic_m',NaN,'Predicted_m',NaN,'Adaptive_m',NaN,...
 'FixedError_m',NaN,'PeriodicError_m',NaN,'PredictedError_m',NaN,'AdaptiveError_m',NaN,...
 'FixedStatus','','PeriodicStatus','','PredictedStatus','','AdaptiveStatus','',...
 'FixedUsePbr',false,'PeriodicUsePbr',false,'PredictedUsePbr',false,'AdaptiveUsePbr',false,...
 'PeriodicCalibrationValid',false,'PredictedCalibrationValid',false,'AdaptiveCalibrationValid',false, ...
 'TrueDriftDelay_ns',NaN,'TrueDriftClock_ppm',NaN,'JumpTime',NaN,'JumpDetected',false,'AdaptiveWeight',NaN,'InnovationScore',NaN, ...
 'FixedCalRttBias_m',NaN,'PeriodicCalRttBias_m',NaN,'PredictedCalRttBias_m',NaN,'AdaptiveCalRttBias_m',NaN, ...
 'FixedCalPhaseSlope_m',NaN,'PeriodicCalPhaseSlope_m',NaN,'PredictedCalPhaseSlope_m',NaN,'AdaptiveCalPhaseSlope_m',NaN, ...
 'RawRtt_m',NaN,'FixedRtt_m',NaN,'PeriodicRtt_m',NaN,'PredictedRtt_m',NaN,'AdaptiveRtt_m',NaN, ...
 'FixedPbr_m',NaN,'PeriodicPbr_m',NaN,'PredictedPbr_m',NaN,'AdaptivePbr_m',NaN, ...
 'FixedBase_m',NaN,'PeriodicBase_m',NaN,'PredictedBase_m',NaN,'AdaptiveBase_m',NaN, ...
 'ReferenceTracksDrift',false, ...
 'V8_m',NaN,'V3_m',NaN,'V7_m',NaN,'V9B_m',NaN, ...
 'V8Error_m',NaN,'V3Error_m',NaN,'V7Error_m',NaN,'V9BError_m',NaN, ...
 'V8Reason','','V3Reason','','V7Reason','','V9BReason','', ...
 'V8Switched',false,'V3Switched',false,'V7Switched',false,'V9BSwitched',false, ...
 'TwoPathCandidate_m',NaN,'TwoPathGain',NaN,'TwoPathEcho',NaN,'TwoPathDelay_ns',NaN);
rows=repmat(proto,N,1);ix=0;
oldRng=rng;clean=onCleanup(@()rng(oldRng));
for pi=1:numel(plans)
 plan=plans{pi};
 for ci=1:numel(conditions)
  cond=conditions{ci};
  scene0=cfg.scenarios(1);scene0.name=cond.name;
  scene0.referenceTracksDrift=true;
  scene0.fHz=cfg.toneAnchorHz+plan.MHz(:)*1e6;
  scene0.phaseResidualRad=zeros(numel(scene0.fHz),1);
  scene0.echoAmplitude=cond.amp;scene0.echoDelayS=cond.delayNs*1e-9;
  scene0.echoPhaseRad=cond.phase;
  scene0.hwDelayS=16e-9;scene0.clockAppm=30;scene0.clockBppm=-30;
  scene0.cfoHz=12000;
  prep=td1.prepare(cfg,scene0);rx=td1.receiverConfig(prep);
  for ui=1:numel(updatePeriods)
   updateEvery=updatePeriods(ui);
  for si=1:numel(snrs)
   snr=snrs(si);
   for ep=1:nEpisodes
    % Independent replicates; keep the same target observation across estimators.
    rng(td1.recordSeed(seed,pi,ci,si,ep,0,3,0),'twister');
    fixed=[];latest=[];previous=[];lastUpdate=0;prevTrend=[];adaptiveGate=1;innovation=NaN;jumpDetected=false;
    % Jump is strictly inside the timeline and is deliberately offset from updates.
    jumpTime=8+mod(seed+pi*7+ci*5+si*3+ep*11,8);
    if all(mod(jumpTime-1,updatePeriods)==0),jumpTime=jumpTime+1;end
    for t=1:timeSteps
     % Time-varying simulator truth is confined to the signal generator.
     progress=(t-1)/(timeSteps-1);
     switch cond.shape
      case 'linear',driftFraction=progress;
      case 'quadratic',driftFraction=progress^2;
      case 'jump',driftFraction=double(t>=jumpTime);
      otherwise,driftFraction=0;
     end
     currentScene=scene0;
     currentScene.driftDelayS=cond.driftNs*1e-9*driftFraction;
     currentScene.driftClockBppm=cond.clockPpm*driftFraction;
     updated=mod(t-1,updateEvery)==0;
     % Reset the stream for target IQ by scenario/episode/time/distance, NOT update period.
     % Reference IQ is separately seeded by update time; no ground truth enters estimation.
     jumpDetected=false;
     if updated
      ref=[];
      for k=1:referenceCount
       rng(td1.recordSeed(seed,pi,ci,si,ep,t,0,k),'twister');
       raw=td1.simulate(cfg.calibrationDistanceM,snr-cond.referenceSnrPenalty,currentScene,prep,true);
       observed=td1.observe(raw,rx);
       if k==1,ref=repmat(observed,referenceCount,1);end
       ref(k)=observed;
      end
      fresh=td1.calibrate(ref,repmat(cfg.calibrationDistanceM,referenceCount,1),rx);
      if isempty(fixed),fixed=fresh;end
      previous=latest;latest=fresh;lastUpdate=t;
      [adaptiveGate,innovation,jumpDetected,prevTrend]=td1.calibrationGateV9A3(latest,previous,prevTrend,updateEvery);
     end
     age=t-lastUpdate;
     pred=td1.predictCalibrationV9(latest,previous,age,updateEvery,0.5);
     adapt=td1.predictCalibrationV9(latest,previous,age,updateEvery,0.5*adaptiveGate);
     for di=1:numel(distances)
      d=distances(di);
      rng(td1.recordSeed(seed,pi,ci,si,ep,t,1,di),'twister');
      signal=td1.simulate(d,snr,currentScene,prep,false);
      feat=td1.observe(signal,rx);
      a0=td1.estimate(feat,fixed,rx);a=td1.selectConflictV8(a0,struct());
      b0=td1.estimate(feat,latest,rx);b=td1.selectConflictV8(b0,struct());
      c0=td1.estimate(feat,pred,rx);c=td1.selectConflictV8(c0,struct());
      e0=td1.estimate(feat,adapt,rx);e=td1.selectConflictV8(e0,struct());
      % Same IQ and dynamic calibration; staged ablation never reads truth.
      base=b0;v8=b;
      probe=td1.twoPathProbe(feat,latest,rx,base);
      gate3=td1.selectTwoPathV3(base,probe,struct());
      gate7=td1.selectTwoPathV7(base,probe,gate3,struct(),numel(rx.fHz));
      % V9_B: protect V8's strong-echo conflict choice; otherwise permit
      % V3 correction followed by V7's selective rescue.
      unified=td1.combineV9B(base,v8,gate3,gate7);
      ix=ix+1;
      rows(ix).Plan=plan.name;rows(ix).Condition=cond.name;
      rows(ix).SNR_dB=snr;rows(ix).Distance_m=d;
      rows(ix).Episode=ep;rows(ix).TimeStep=t;
      rows(ix).UpdatePeriod=updateEvery;
      rows(ix).ReferenceSNR_dB=snr-cond.referenceSnrPenalty;
      rows(ix).DriftProfile=cond.shape;
      rows(ix).TrueJump=strcmp(cond.shape,'jump') && t==jumpTime;
      rows(ix).TrueJumpActive=strcmp(cond.shape,'jump') && t>=jumpTime;
      rows(ix).CalibrationAge=age;rows(ix).ReferenceUpdated=updated;
      rows(ix).Fixed_m=a.selectedM;rows(ix).Periodic_m=b.selectedM;
      rows(ix).Predicted_m=c.selectedM;rows(ix).Adaptive_m=e.selectedM;
      rows(ix).FixedError_m=a.selectedM-d;
      rows(ix).PeriodicError_m=b.selectedM-d;
      rows(ix).PredictedError_m=c.selectedM-d;rows(ix).AdaptiveError_m=e.selectedM-d;
      rows(ix).FixedStatus=a.reason;rows(ix).PeriodicStatus=b.reason;
      rows(ix).PredictedStatus=c.reason;rows(ix).AdaptiveStatus=e.reason;
      rows(ix).FixedUsePbr=a.usePbr;rows(ix).PeriodicUsePbr=b.usePbr;
      rows(ix).PredictedUsePbr=c.usePbr;rows(ix).AdaptiveUsePbr=e.usePbr;
      rows(ix).PeriodicCalibrationValid=latest.phaseCalibrationValid;
      rows(ix).PredictedCalibrationValid=pred.phaseCalibrationValid;rows(ix).AdaptiveCalibrationValid=adapt.phaseCalibrationValid;
      % Diagnostic ground truth BELOW: recorded to CSV only, never passed to
      % estimate(), predictCalibrationV9(), selectConflictV8() or calibrate().
      rows(ix).TrueDriftDelay_ns=currentScene.driftDelayS*1e9;
      rows(ix).TrueDriftClock_ppm=currentScene.driftClockBppm;
      rows(ix).JumpTime=jumpTime;rows(ix).JumpDetected=jumpDetected;
      rows(ix).AdaptiveWeight=adaptiveGate;rows(ix).InnovationScore=innovation;
      rows(ix).ReferenceTracksDrift=true;
      rows(ix).V8_m=v8.selectedM;rows(ix).V3_m=gate3.selectedM;
      rows(ix).V7_m=gate7.selectedM;rows(ix).V9B_m=unified.selectedM;
      rows(ix).V8Error_m=v8.selectedM-d;rows(ix).V3Error_m=gate3.selectedM-d;
      rows(ix).V7Error_m=gate7.selectedM-d;rows(ix).V9BError_m=unified.selectedM-d;
      rows(ix).V8Reason=v8.reason;rows(ix).V3Reason=gate3.reason;
      rows(ix).V7Reason=gate7.reason;rows(ix).V9BReason=unified.reason;
      rows(ix).V8Switched=v8.usePbr;rows(ix).V3Switched=gate3.useTwoPath;
      rows(ix).V7Switched=gate7.useTwoPath;rows(ix).V9BSwitched=unified.useTwoPath || unified.usePbr;
      rows(ix).TwoPathCandidate_m=probe.candidateM;
      rows(ix).TwoPathGain=probe.relativeImprovement;
      rows(ix).TwoPathEcho=probe.echoAmplitude;
      rows(ix).TwoPathDelay_ns=probe.excessDelayNs;
      rows(ix).FixedCalRttBias_m=fixed.rttBiasM;
      rows(ix).PeriodicCalRttBias_m=latest.rttBiasM;
      rows(ix).PredictedCalRttBias_m=pred.rttBiasM;rows(ix).AdaptiveCalRttBias_m=adapt.rttBiasM;
      rows(ix).FixedCalPhaseSlope_m=localPhaseSlopeDistance(fixed.phaseBiasRad,rx.fHz,cfg.c);
      rows(ix).PeriodicCalPhaseSlope_m=localPhaseSlopeDistance(latest.phaseBiasRad,rx.fHz,cfg.c);
      rows(ix).PredictedCalPhaseSlope_m=localPhaseSlopeDistance(pred.phaseBiasRad,rx.fHz,cfg.c);
      rows(ix).AdaptiveCalPhaseSlope_m=localPhaseSlopeDistance(adapt.phaseBiasRad,rx.fHz,cfg.c);
      rows(ix).RawRtt_m=feat.rawRttM;
      rows(ix).FixedRtt_m=a0.rttM;
      rows(ix).PeriodicRtt_m=b0.rttM;
      rows(ix).PredictedRtt_m=c0.rttM;rows(ix).AdaptiveRtt_m=e0.rttM;
      rows(ix).FixedPbr_m=a0.pbrM;
      rows(ix).PeriodicPbr_m=b0.pbrM;
      rows(ix).PredictedPbr_m=c0.pbrM;rows(ix).AdaptivePbr_m=e0.pbrM;
      rows(ix).FixedBase_m=a0.fusedM;
      rows(ix).PeriodicBase_m=b0.fusedM;
      rows(ix).PredictedBase_m=c0.fusedM;rows(ix).AdaptiveBase_m=e0.fusedM;
     end
    end
   end
  end
  fprintf('V9_A_3_1 complete: %s / %s\n',plan.name,cond.name);
 end
 end
end
trials=struct2table(rows);
writetable(trials,fullfile(outDir,'v9_B_trials.csv'));
summaryRows={};
for pi=1:numel(plans)
 for ci=1:numel(conditions)
  idx=strcmp(trials.Plan,plans{pi}.name)&strcmp(trials.Condition,conditions{ci}.name);
  group=trials(idx,:);
  paired=isfinite(group.FixedError_m)&isfinite(group.PeriodicError_m)& ...
    isfinite(group.V8Error_m)&isfinite(group.V3Error_m)& ...
    isfinite(group.V7Error_m)&isfinite(group.V9BError_m);
  x=group(paired,:);
  summaryRows(end+1,:)={plans{pi}.name,conditions{ci}.name,height(group),height(x), ...
    localRmse(x.FixedError_m),localRmse(x.PeriodicError_m), ...
    localRmse(x.V8Error_m),localRmse(x.V3Error_m), ...
    localRmse(x.V7Error_m),localRmse(x.V9BError_m), ...
    localP95(x.V8Error_m),localP95(x.V9BError_m), ...
    localOver1(x.V8Error_m),localOver1(x.V9BError_m), ...
    sum(x.V8Switched),sum(x.V3Switched),sum(x.V7Switched),sum(x.V9BSwitched)}; %#ok<AGROW>
 end
end
summary=cell2table(summaryRows,'VariableNames',{'Plan','Condition','Count','PairedFiniteN', ...
 'FixedRMSE_m','PeriodicRMSE_m','V8RMSE_m','V3RMSE_m','V7RMSE_m','V9BRMSE_m', ...
 'V8P95_m','V9BP95_m','V8Over1m','V9BOver1m', ...
 'V8Switches','V3Switches','V7Switches','V9BSwitches'});
writetable(summary,fullfile(outDir,'v9_B_summary.csv'));
notes=fopen(fullfile(outDir,'v9_B_notes.txt'),'w');
if notes>=0
 fprintf(notes,'V9_B experimental ablation; seed %d; episodes %d; observations %d.\n',seed,nEpisodes,height(trials));
 fprintf(notes,'Strategies: Fixed reference; Periodic calibration; V8; V3; V7; combined V9_B.\n');
 fprintf(notes,'V3/V7 use the same periodic calibration as V8; ALL share target IQ.\n');
 fprintf(notes,'V9_B first preserves accepted V8 PBR conflict switch; otherwise tries V7, V3, baseline.\n');
 fprintf(notes,'V9_B is not yet a proven optimal joint fusion method; no truth in online decision.\n');
 fprintf(notes,'Known reference for calibration; ideal coherent retuning; no PlutoSDR tests.\n');
 fprintf(notes,'PairedFiniteN counts rows with finite errors across six comparison outputs.\n');
 fclose(notes);
end

fprintf('V9_B finished: %d target records -> %s\n',height(trials),outDir);
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
