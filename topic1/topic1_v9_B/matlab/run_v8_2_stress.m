function trials = run_v8_2_stress(nTrials,seed,outDir)
%RUN_V8_2_STRESS Paired V8 stress study under combined channel impairments.
% Fast: trials=run_v8_2_stress(2,20271019);
% Full: trials=run_v8_2_stress(20,20271019);
% Important: V8 decision does not access scenario labels, truth, or SNR.
% All comparisons use identical receiver observations for baseline and V8.
if nargin<1 || isempty(nTrials),nTrials=2;end
if nargin<2 || isempty(seed),seed=20271019;end
validateattributes(nTrials,{'numeric'},{'scalar','integer','positive'});
validateattributes(seed,{'numeric'},{'scalar','integer','nonnegative','finite'});
root=fileparts(mfilename('fullpath'));
if nargin<3 || isempty(outDir),outDir=fullfile(root,'results','v8_2_stress');end
if ~exist(outDir,'dir'),mkdir(outDir);end
cfg=td1.defaultConfig();cfg.allowPbrOnlyOnDisagreement=false;
plans={struct('name','uniform_32MHz','MHz',0:2:32),...
       struct('name','uniform_64MHz','MHz',0:4:64)};
% Distinct calibration and measurement scenes model post-calibration drift.
% Combo conditions chosen prospectively, before viewing these test records.
conditions={...
 struct('name','strong_only','amp',.4,'delayNs',60,'phase',-.9,'driftNs',0,'clockDrift',0,'cfo',0,'randomHop',false,'phaseDrift',0),...
 struct('name','strong_delay_drift','amp',.4,'delayNs',60,'phase',-.9,'driftNs',16,'clockDrift',60,'cfo',0,'randomHop',false,'phaseDrift',0),...
 struct('name','strong_cfo_clock','amp',.4,'delayNs',60,'phase',-.9,'driftNs',0,'clockDrift',0,'cfo',12000,'randomHop',false,'phaseDrift',0),...
 struct('name','strong_random_hop','amp',.4,'delayNs',60,'phase',-.9,'driftNs',0,'clockDrift',0,'cfo',0,'randomHop',true,'phaseDrift',0),...
 struct('name','strong_phase_drift','amp',.4,'delayNs',60,'phase',-.9,'driftNs',0,'clockDrift',0,'cfo',0,'randomHop',false,'phaseDrift',.45),...
 struct('name','light_delay_drift','amp',.25,'delayNs',25,'phase',.7,'driftNs',16,'clockDrift',60,'cfo',0,'randomHop',false,'phaseDrift',0),...
 struct('name','los_delay_drift','amp',0,'delayNs',0,'phase',0,'driftNs',16,'clockDrift',60,'cfo',0,'randomHop',false,'phaseDrift',0)};
snrs=[0 15 30]; distances=[3 15];
N=numel(plans)*numel(conditions)*numel(snrs)*numel(distances)*nTrials;
row=struct('Plan','','Condition','','Distance_m',NaN,'SNR_dB',NaN,'Trial',NaN,'Seed',seed,...
 'EchoAmp',NaN,'EchoDelay_ns',NaN,'PostCalDelayDrift_ns',NaN,'PostCalPhaseDrift_rad',NaN,...
 'RTT_m',NaN,'PBR_m',NaN,'Original_m',NaN,'V8_m',NaN,...
 'RTTError_m',NaN,'PBRError_m',NaN,'OriginalError_m',NaN,'V8Error_m',NaN,...
 'OriginalStatus','','PBRValid',false,'PBRCoherence',NaN,'PBRAmbiguous',false,...
 'AliasCount',NaN,'InnovationSigma',NaN,'V8UsePbr',false,'V8Reason','');
rows=repmat(row,N,1);
oldRng=rng; restoreRng=onCleanup(@()rng(oldRng));
idx=0;
for pi=1:numel(plans)
 plan=plans{pi};
 for ci=1:numel(conditions)
  cond=conditions{ci};
  sceneCal=cfg.scenarios(1);
  sceneCal.name=cond.name;
  sceneCal.fHz=cfg.toneAnchorHz+plan.MHz(:)*1e6;
  sceneCal.phaseResidualRad=zeros(numel(sceneCal.fHz),1);
  sceneCal.echoAmplitude=cond.amp;
  sceneCal.echoDelayS=cond.delayNs*1e-9;
  sceneCal.echoPhaseRad=cond.phase;
  sceneCal.cfoHz=cond.cfo;
  sceneCal.clockAppm=30*(cond.clockDrift~=0);
  sceneCal.clockBppm=-30*(cond.clockDrift~=0);
  sceneCal.hwDelayS=16e-9*(cond.driftNs~=0);
  sceneCal.randomHopPhase=cond.randomHop;
  sceneTest=sceneCal;
  sceneTest.driftDelayS=cond.driftNs*1e-9;
  sceneTest.driftClockBppm=cond.clockDrift;
  % Calibrator uses the undrifted reference; phase changes afterwards.
  sceneTest.phaseResidualRad=sceneCal.phaseResidualRad + ...
      cond.phaseDrift*sin((1:numel(sceneCal.fHz))'*sqrt(2)+0.37);
  prep=td1.prepare(cfg,sceneCal);rx=td1.receiverConfig(prep);
  for si=1:numel(snrs)
   snr=snrs(si);
   rng(seed+100000*pi+10000*ci+100*si,'twister');
   for kk=1:cfg.calibrationTrials
    obs=td1.simulate(cfg.calibrationDistanceM,snr,sceneCal,prep,true);
    item=td1.observe(obs,rx);
    if kk==1,train=repmat(item,cfg.calibrationTrials,1);end
    train(kk)=item;
   end
   cal=td1.calibrate(train,repmat(cfg.calibrationDistanceM,cfg.calibrationTrials,1),rx);
   rng(seed+500000+100000*pi+10000*ci+100*si,'twister');
   for di=1:numel(distances)
    d=distances(di);
    for t=1:nTrials
     obs=td1.simulate(d,snr,sceneTest,prep,false);
     feat=td1.observe(obs,rx);
     base=td1.estimate(feat,cal,rx);
     v8=td1.selectConflictV8(base,struct());
     idx=idx+1;
     rows(idx).Plan=plan.name;rows(idx).Condition=cond.name;
     rows(idx).Distance_m=d;rows(idx).SNR_dB=snr;rows(idx).Trial=t;
     rows(idx).EchoAmp=cond.amp;rows(idx).EchoDelay_ns=cond.delayNs;
     rows(idx).PostCalDelayDrift_ns=cond.driftNs;
     rows(idx).PostCalPhaseDrift_rad=cond.phaseDrift;
     rows(idx).RTT_m=base.rttM;rows(idx).PBR_m=base.pbrM;
     rows(idx).Original_m=base.fusedM;rows(idx).V8_m=v8.selectedM;
     rows(idx).RTTError_m=base.rttM-d;rows(idx).PBRError_m=base.pbrM-d;
     rows(idx).OriginalError_m=base.fusedM-d;rows(idx).V8Error_m=v8.selectedM-d;
     rows(idx).OriginalStatus=base.status;rows(idx).PBRValid=base.pbrValid;
     rows(idx).PBRCoherence=base.pbrCoherence;
     rows(idx).PBRAmbiguous=base.pbrAmbiguous;
     rows(idx).AliasCount=numel(base.aliasCandidatesM);
     rows(idx).InnovationSigma=base.innovationSigma;
     rows(idx).V8UsePbr=v8.usePbr;rows(idx).V8Reason=v8.reason;
    end
   end
  end
  fprintf('V8_2 complete: %s / %s\n',plan.name,cond.name);
 end
end
trials=struct2table(rows);
writetable(trials,fullfile(outDir,'v8_2_trials.csv'));
summ=cell(numel(plans)*numel(conditions),15);k=0;
for pi=1:numel(plans)
 for ci=1:numel(conditions)
  x=trials(strcmp(trials.Plan,plans{pi}.name)&strcmp(trials.Condition,conditions{ci}.name),:);
  valid=isfinite(x.OriginalError_m)&isfinite(x.V8Error_m);
  changed=x.V8UsePbr&valid;
  k=k+1;
  summ(k,:)={plans{pi}.name,conditions{ci}.name,height(x),sum(valid),...
    localRmse(x.RTTError_m),localRmse(x.PBRError_m),...
    localRmse(x.OriginalError_m),localRmse(x.V8Error_m),...
    localP95(x.OriginalError_m),localP95(x.V8Error_m),...
    mean(abs(x.OriginalError_m(valid))>1),mean(abs(x.V8Error_m(valid))>1),...
    sum(changed),sum(abs(x.V8Error_m(changed))<abs(x.OriginalError_m(changed))),...
    sum(abs(x.V8Error_m(changed))>abs(x.OriginalError_m(changed)))};
 end
end
summary=cell2table(summ,'VariableNames',{'Plan','Condition','Count','PairedFiniteN',...
 'RTTRMSE_m','PBRRMSE_m','OriginalRMSE_m','V8RMSE_m',...
 'OriginalP95Abs_m','V8P95Abs_m','OriginalOver1mRate','V8Over1mRate',...
 'V8SwitchCount','SwitchBetterCount','SwitchWorseCount'});
writetable(summary,fullfile(outDir,'v8_2_summary.csv'));
fid=fopen(fullfile(outDir,'v8_2_notes.txt'),'w');
if fid>=0
 fprintf(fid,'Seed=%d; repeats=%d; total trials=%d.\n',seed,nTrials,height(trials));
 fprintf(fid,'Two tone spans 32/64 MHz; seven combined cases, 3 SNR, 2 distances.\n');
 fprintf(fid,'Original vs V8 share IQ and calibration samples, unchanged V8 selection rule.\n');
 fprintf(fid,'Calibration performed before post-cal drift; no hardware measurement.\n');
 fprintf(fid,'Simulation assumes ideal coherent retuning; phase-drift fixture is deterministic.\n');
 fprintf(fid,'SwitchBetterCount and SwitchWorseCount are offline evaluations ONLY.\n');
 fprintf(fid,'RMSE excludes NaN: compare PairedFiniteN; calibration is scene-specific.\n');
 fclose(fid);
end
fprintf('V8_2 finished: %d records -> %s\n',height(trials),outDir);
end
function val=localRmse(x)
x=x(isfinite(x));if isempty(x),val=NaN;else,val=sqrt(mean(x.^2));end
end
function val=localP95(x)
x=sort(abs(x(isfinite(x))));
if isempty(x),val=NaN;else,val=x(max(1,ceil(.95*numel(x))));end
end
