function result = run_v8_regression(nTrials, seed, outDir)
%RUN_V8_REGRESSION Six-scene paired regression test for experimental V8.
%   run_v8_regression(3,20271009)   % smoke test
%   run_v8_regression(50,20271009)  % 7200 paired packets
%   Reuses original six scenes, distances, SNR values, and calibration.
%   Both algorithms receive the *same* estimated features and calibration.
%   Ground truth is used only to score results, never for decisions.
if nargin<1 || isempty(nTrials), nTrials=3; end
if nargin<2 || isempty(seed), seed=20271009; end
validateattributes(nTrials,{'numeric'},{'scalar','integer','positive','finite'});
validateattributes(seed,{'numeric'},{'scalar','integer','nonnegative','finite'});
root=fileparts(mfilename('fullpath'));
if nargin<3 || isempty(outDir), outDir=fullfile(root,'results','v8_regression'); end
if ~exist(outDir,'dir'),mkdir(outDir);end
cfg=td1.defaultConfig();
cfg.allowPbrOnlyOnDisagreement=false;
n=numel(cfg.scenarios)*numel(cfg.distancesM)*numel(cfg.snrDb)*nTrials;
template=struct('Scenario','','Distance_m',NaN,'SNR_dB',NaN,'Trial',NaN,...
 'RTT_m',NaN,'PBR_m',NaN,'Baseline_m',NaN,'V8_m',NaN,...
 'BaselineError_m',NaN,'V8Error_m',NaN,'PBRError_m',NaN,...
 'BaselineStatus','','V8Reason','','V8Switched',false,...
 'PBRValid',false,'PBRAmbiguous',false,'AliasCount',NaN,...
 'PBRCoherence',NaN,'InnovationSigma',NaN,...
 'FusionValid',false);
records=repmat(template,n,1);
old=rng; clean=onCleanup(@()rng(old)); %#ok<NASGU>
ix=0;
for s=1:numel(cfg.scenarios)
 scene=cfg.scenarios(s);
 prep=td1.prepare(cfg,scene);
 rx=td1.receiverConfig(prep);
 for z=1:numel(cfg.snrDb)
  snr=cfg.snrDb(z);
  rng(seed+s*1000+z*10,'twister');
  for j=1:cfg.calibrationTrials
   ob=td1.simulate(cfg.calibrationDistanceM,snr,scene,prep,true);
   f=td1.observe(ob,rx);
   if j==1,train=repmat(f,cfg.calibrationTrials,1);end
   train(j)=f;
  end
  cal=td1.calibrate(train,repmat(cfg.calibrationDistanceM,cfg.calibrationTrials,1),rx);
  rng(seed+100000+s*1000+z*10,'twister');
  for di=1:numel(cfg.distancesM)
   d=cfg.distancesM(di);
   for t=1:nTrials
    ob=td1.simulate(d,snr,scene,prep,false);
    f=td1.observe(ob,rx);
    base=td1.estimate(f,cal,rx);
    v8=td1.selectConflictV8(base,struct());
    ix=ix+1; r=template;
    r.Scenario=scene.name;r.Distance_m=d;r.SNR_dB=snr;r.Trial=t;
    r.RTT_m=base.rttM;r.PBR_m=base.pbrM;
    r.Baseline_m=base.fusedM;r.V8_m=v8.selectedM;
    r.BaselineError_m=base.fusedM-d;r.V8Error_m=v8.selectedM-d;
    r.PBRError_m=base.pbrM-d;
    r.BaselineStatus=base.status;r.V8Reason=v8.reason;
    r.V8Switched=v8.usePbr;r.PBRValid=base.pbrValid;
    r.PBRAmbiguous=base.pbrAmbiguous;
    r.AliasCount=numel(base.aliasCandidatesM);
    r.PBRCoherence=base.pbrCoherence;
    r.InnovationSigma=base.innovationSigma;
    r.FusionValid=base.fusionValid;
    records(ix)=r;
   end
  end
 end
 fprintf('Completed %s: %d paired records.\n',scene.name,numel(cfg.distancesM)*numel(cfg.snrDb)*nTrials);
end
trials=struct2table(records);
writetable(trials,fullfile(outDir,'v8_regression_trials.csv'));
summary=repmat(struct('Scenario','','Count',0,'BaselineFiniteN',0,'V8FiniteN',0,...
 'BaselineRMSE_m',NaN,'V8RMSE_m',NaN,'BaselineMAE_m',NaN,'V8MAE_m',NaN,...
 'BaselineBias_m',NaN,'V8Bias_m',NaN,'BaselineP95_m',NaN,'V8P95_m',NaN,...
 'BaselineOver1mRate',NaN,'V8Over1mRate',NaN,'SwitchCount',0,...
 'SwitchImproved',0,'SwitchWorsened',0,'SwitchTied',0,'SwitchReasons',''),numel(cfg.scenarios),1);
for s=1:numel(cfg.scenarios)
 mask=strcmp(trials.Scenario,cfg.scenarios(s).name);
 x=trials(mask,:);a=x.BaselineError_m;b=x.V8Error_m;
 summary(s).Scenario=cfg.scenarios(s).name;summary(s).Count=height(x);
 summary(s).BaselineFiniteN=sum(isfinite(a));summary(s).V8FiniteN=sum(isfinite(b));
 [summary(s).BaselineRMSE_m,summary(s).BaselineMAE_m,summary(s).BaselineBias_m,summary(s).BaselineP95_m,summary(s).BaselineOver1mRate]=stats(a);
 [summary(s).V8RMSE_m,summary(s).V8MAE_m,summary(s).V8Bias_m,summary(s).V8P95_m,summary(s).V8Over1mRate]=stats(b);
 switched=x.V8Switched;summary(s).SwitchCount=sum(switched);
 aa=abs(a(switched));bb=abs(b(switched));valid=isfinite(aa)&isfinite(bb);
 summary(s).SwitchImproved=sum(bb(valid)<aa(valid)-1e-9);
 summary(s).SwitchWorsened=sum(bb(valid)>aa(valid)+1e-9);
 summary(s).SwitchTied=sum(abs(bb(valid)-aa(valid))<=1e-9);
 fprintf('%-21s base RMSE %.4f | V8 %.4f m | switched %d (better %d, worse %d)\n',...
  summary(s).Scenario,summary(s).BaselineRMSE_m,summary(s).V8RMSE_m,summary(s).SwitchCount,summary(s).SwitchImproved,summary(s).SwitchWorsened);
end
summary=struct2table(summary);writetable(summary,fullfile(outDir,'v8_regression_summary.csv'));
fid=fopen(fullfile(outDir,'v8_regression_notes.txt'),'w');
if fid>0
 fprintf(fid,'Experimental six-scene regression; seed %d, repeats %d, observations %d.\n',seed,nTrials,height(trials));
 fprintf(fid,'Same simulated IQ/features for original estimator and V8 switch.\n');
 fprintf(fid,'SNR per scene calibration assumes known reference distance; no hardware validation.\n');
 fprintf(fid,'V8 switch uses only receiver estimates, never scenario label or true distance.\n');
 fprintf(fid,'Check Calibration_drift, Sparse_alias, Random_hop_phase first.\n');
 fprintf(fid,'RMSE excludes nonfinite values; inspect FiniteN before comparing.\n');
 fclose(fid);
end
result=struct('trials',trials,'summary',summary,'outputDirectory',outDir);
fprintf('Done: %d records -> %s\n',height(trials),outDir);
end
function [rmse,mae,bias,p95,over1]=stats(e)
e=e(isfinite(e));
if isempty(e),rmse=NaN;mae=NaN;bias=NaN;p95=NaN;over1=NaN;return;end
rmse=sqrt(mean(e.^2));mae=mean(abs(e));bias=mean(e);over1=mean(abs(e)>1);
v=sort(abs(e));p=1+0.95*(numel(v)-1);lo=floor(p);hi=ceil(p);
p95=v(lo)+(p-lo)*(v(hi)-v(lo));
end
