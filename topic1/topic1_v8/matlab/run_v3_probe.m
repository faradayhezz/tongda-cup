function comparison = run_v3_probe(nTrials,seed,outDir)
%RUN_V3_PROBE Paired independent-seed comparison: baseline, V2, gated V3.
% run_v3_probe(3,20261109) -> smoke test
% run_v3_probe(50,20261109) -> validation (2 scenes, 2400 packets)
if nargin<1 || isempty(nTrials),nTrials=3;end
if nargin<2 || isempty(seed),seed=20261109;end
validateattributes(nTrials,{'numeric'},{'scalar','integer','positive'});
validateattributes(seed,{'numeric'},{'scalar','integer','nonnegative','finite'});
root=fileparts(mfilename('fullpath'));
if nargin<3 || isempty(outDir),outDir=fullfile(root,'results','v3_probe');end
if ~exist(outDir,'dir'),mkdir(outDir);end
cfg=td1.defaultConfig();cfg.allowPbrOnlyOnDisagreement=false;
keep=[1 3];
row=0;
rows=repmat(struct('Scenario','','Distance_m',NaN,'SNR_dB',NaN, ...
    'Trial',NaN,'Seed',seed,'Baseline_m',NaN,'Candidate_m',NaN, ...
    'V3_m',NaN,'BaselineError_m',NaN,'CandidateError_m',NaN, ...
    'V3Error_m',NaN,'SelectedTwoPath',false,'GateReason','', ...
    'RelativeImprovement',NaN,'EstimatedEchoAmplitude',NaN, ...
    'ExcessDelay_ns',NaN,'SingleCost',NaN,'TwoPathCost',NaN), ...
    numel(keep)*numel(cfg.distancesM)*numel(cfg.snrDb)*nTrials,1);
oldRng=rng;cleanup=onCleanup(@()rng(oldRng));
for si=keep
    scene=cfg.scenarios(si);prep=td1.prepare(cfg,scene);
    rx=td1.receiverConfig(prep);
    for zi=1:numel(cfg.snrDb)
        snr=cfg.snrDb(zi);
        rng(seed+si*1000+zi*10,'twister');
        for j=1:cfg.calibrationTrials
            ob=td1.simulate(cfg.calibrationDistanceM,snr,scene,prep,true);
            ft=td1.observe(ob,rx);
            if j==1,train=repmat(ft,cfg.calibrationTrials,1);end
            train(j)=ft;
        end
        cal=td1.calibrate(train,repmat(cfg.calibrationDistanceM,cfg.calibrationTrials,1),rx);
        rng(seed+100000+si*1000+zi*10,'twister');
        for di=1:numel(cfg.distancesM)
            dist=cfg.distancesM(di);
            for t=1:nTrials
                ob=td1.simulate(dist,snr,scene,prep,false);
                ft=td1.observe(ob,rx);
                base=td1.estimate(ft,cal,rx);
                fit=td1.twoPathProbe(ft,cal,rx,base);
                gate=td1.selectTwoPathV3(base,fit);
                row=row+1;
                rows(row).Scenario=scene.name;
                rows(row).Distance_m=dist;
                rows(row).SNR_dB=snr;
                rows(row).Trial=t;
                rows(row).Baseline_m=base.fusedM;
                rows(row).Candidate_m=fit.candidateM;
                rows(row).V3_m=gate.selectedM;
                rows(row).BaselineError_m=base.fusedM-dist;
                rows(row).CandidateError_m=fit.candidateM-dist;
                rows(row).V3Error_m=gate.selectedM-dist;
                rows(row).SelectedTwoPath=gate.useTwoPath;
                rows(row).GateReason=gate.reason;
                rows(row).RelativeImprovement=fit.relativeImprovement;
                rows(row).EstimatedEchoAmplitude=fit.echoAmplitude;
                rows(row).ExcessDelay_ns=fit.excessDelayNs;
                rows(row).SingleCost=fit.singleCost;
                rows(row).TwoPathCost=fit.twoPathCost;
            end
        end
    end
    fprintf('V3: completed %s.\n',scene.name);
end
comparison=struct2table(rows);
writetable(comparison,fullfile(outDir,'v3_trials.csv'));
scenarios=cell(numel(keep),1);baselines=zeros(numel(keep),1);
candidates=baselines;v3=baselines;rates=baselines;
for j=1:numel(keep)
    scenario=cfg.scenarios(keep(j)).name;
    mask=strcmp(comparison.Scenario,scenario);
    scenarios{j}=scenario;
    baselines(j)=rmse(comparison.BaselineError_m(mask));
    candidates(j)=rmse(comparison.CandidateError_m(mask));
    v3(j)=rmse(comparison.V3Error_m(mask));
    rates(j)=mean(comparison.SelectedTwoPath(mask));
    fprintf('%s: baseline %.4f m | V2 %.4f m | V3 %.4f m | selected %d/%d\n', ...
        scenario,baselines(j),candidates(j),v3(j), ...
        sum(comparison.SelectedTwoPath(mask)),sum(mask));
end
summary=table(scenarios,baselines,candidates,v3,rates, ...
    'VariableNames',{'Scenario','BaselineRMSE_m','V2RMSE_m','V3RMSE_m','V3SelectRate'});
writetable(summary,fullfile(outDir,'v3_summary.csv'));
fprintf('Validation seed: %d; no true distances used in selection.\n',seed);
fprintf('Experimental only: existing run_all and td1.estimate are unchanged.\n');
end
function r=rmse(x)
x=x(isfinite(x));
if isempty(x),r=NaN;else,r=sqrt(mean(x.^2));end
end
