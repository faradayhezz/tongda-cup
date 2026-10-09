function comparison = run_v2_probe(nTrials,outDir)
%RUN_V2_PROBE Paired exploratory comparison; original estimator unchanged.
% Example: comparison=run_v2_probe(3);
if nargin<1 || isempty(nTrials),nTrials=3;end
validateattributes(nTrials,{'numeric'},{'scalar','integer','positive'});
root=fileparts(mfilename('fullpath'));
if nargin<2 || isempty(outDir),outDir=fullfile(root,'results','v2_probe');end
if ~exist(outDir,'dir'),mkdir(outDir);end
cfg=td1.defaultConfig();
keep=[1 3]; % LOS vs light multipath; additional scenarios after validation
row=0;rows=repmat(struct('Scenario','','Distance_m',NaN,'SNR_dB',NaN, ...
    'Trial',NaN,'Baseline_m',NaN,'Candidate_m',NaN,'BaselineError_m',NaN, ...
    'CandidateError_m',NaN,'SingleCost',NaN,'TwoPathCost',NaN, ...
    'RelativeImprovement',NaN,'ExcessDelay_ns',NaN, ...
    'EstimatedEchoAmplitude',NaN,'Reason',''), ...
    2*numel(cfg.distancesM)*numel(cfg.snrDb)*nTrials,1);
oldRng=rng;cleanup=onCleanup(@()rng(oldRng));
for si=keep
    scene=cfg.scenarios(si);prep=td1.prepare(cfg,scene);
    rx=td1.receiverConfig(prep);
    for zi=1:numel(cfg.snrDb)
        snr=cfg.snrDb(zi);
        rng(cfg.seed+si*1000+zi*10,'twister');
        for j=1:cfg.calibrationTrials
            ob=td1.simulate(cfg.calibrationDistanceM,snr,scene,prep,true);
            ft=td1.observe(ob,rx);
            if j==1,train=repmat(ft,cfg.calibrationTrials,1);end
            train(j)=ft;
        end
        cal=td1.calibrate(train,repmat(cfg.calibrationDistanceM,cfg.calibrationTrials,1),rx);
        rng(cfg.seed+100000+si*1000+zi*10,'twister');
        for di=1:numel(cfg.distancesM)
            dist=cfg.distancesM(di);
            for t=1:nTrials
                ob=td1.simulate(dist,snr,scene,prep,false);
                ft=td1.observe(ob,rx);base=td1.estimate(ft,cal,rx);
                fit=td1.twoPathProbe(ft,cal,rx,base);
                row=row+1;
                rows(row).Scenario=scene.name;
                rows(row).Distance_m=dist;
                rows(row).SNR_dB=snr;
                rows(row).Trial=t;
                rows(row).Baseline_m=base.fusedM;
                rows(row).Candidate_m=fit.candidateM;
                rows(row).BaselineError_m=base.fusedM-dist;
                rows(row).CandidateError_m=fit.candidateM-dist;
                rows(row).SingleCost=fit.singleCost;
                rows(row).TwoPathCost=fit.twoPathCost;
                rows(row).RelativeImprovement=fit.relativeImprovement;
                rows(row).ExcessDelay_ns=fit.excessDelayNs;
                rows(row).EstimatedEchoAmplitude=fit.echoAmplitude;
                rows(row).Reason=fit.reason;
            end
        end
    end
    fprintf('V2 probe: completed %s.\n',scene.name);
end
comparison=struct2table(rows);
writetable(comparison,fullfile(outDir,'v2_probe_trials.csv'));
for si=keep
    selected=strcmp(comparison.Scenario,cfg.scenarios(si).name);
    a=comparison.BaselineError_m(selected);
    b=comparison.CandidateError_m(selected);
    fprintf('%s: baseline RMSE %.4f m, candidate RMSE %.4f m (finite %d/%d)\n', ...
        cfg.scenarios(si).name,sqrt(mean(a(isfinite(a)).^2)), ...
        sqrt(mean(b(isfinite(b)).^2)),sum(isfinite(b)),numel(b));
end
fprintf('Diagnostic only: candidate estimates DO NOT replace fused output.\n');
end
