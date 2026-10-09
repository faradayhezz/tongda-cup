function results = run_v7_diagnostic(nTrials, seed, outDir)
%RUN_V7_FREQUENCY_STUDY Controlled frequency-span/echo identifiability study.
% results = run_v7_diagnostic(2,20270309); % quick smoke test
% results = run_v7_diagnostic(20,20270309); % Monte Carlo follow-up
% Does NOT modify td1.estimate or claim actual PlutoSDR hopping capability.
% SNR and true range are used ONLY to simulate data and evaluate afterwards.
if nargin<1 || isempty(nTrials),nTrials=2;end
if nargin<2 || isempty(seed),seed=20270309;end
validateattributes(nTrials,{'numeric'},{'scalar','integer','positive'});
validateattributes(seed,{'numeric'},{'scalar','integer','nonnegative','finite'});
root=fileparts(mfilename('fullpath'));
if nargin<3 || isempty(outDir),outDir=fullfile(root,'results','v7_diagnostic');end
if ~exist(outDir,'dir'),mkdir(outDir);end
cfg=td1.defaultConfig();cfg.allowPbrOnlyOnDisagreement=false;
% Keep number of tones constant so the main comparison targets span/layout.
% Nonuniform 32 MHz: integer MHz offsets, deterministic for reproducibility.
plans={... 
    struct('name','uniform_16MHz','offsetsMHz',0:16), ...
    struct('name','uniform_32MHz','offsetsMHz',0:2:32), ...
    struct('name','uniform_64MHz','offsetsMHz',0:4:64), ...
    struct('name','nonuniform_32MHz','offsetsMHz',[0 1 2 4 6 8 10 12 14 16 18 20 22 26 29 31 32])};
% One LOS and three contrasting multipath geometries. Independent of truth labels.
echos={... 
    struct('name','LOS','amp',0,'delayNs',0,'phaseRad',0), ...
    struct('name','weak_close','amp',0.15,'delayNs',15,'phaseRad',0.7), ...
    struct('name','original_echo','amp',0.25,'delayNs',25,'phaseRad',0.7), ...
    struct('name','strong_late','amp',0.4,'delayNs',60,'phaseRad',-0.9)};
snrs=[0 15 30]; distances=[3 15];
N=numel(plans)*numel(echos)*numel(snrs)*numel(distances)*nTrials;
rows=repmat(struct('Plan','','Echo','','Bandwidth_MHz',NaN,'ToneCount',NaN,...
    'ExcessDelay_ns',NaN,'EchoAmplitude',NaN,'Btau',NaN,...
    'Distance_m',NaN,'SNR_dB',NaN,'Trial',NaN,'Seed',seed,...
    'Baseline_m',NaN,'V2_m',NaN,'V3_m',NaN,'BaselineError_m',NaN,...
    'V2Error_m',NaN,'V3Error_m',NaN,'V3Selected',false,'RTT_m',NaN,'PBR_m',NaN,'BaselineStatus','',...
    'PBRValid',false,'PBRCoherence',NaN,'PBRPeriod_m',NaN,'AliasCount',NaN,...
    'RttSigma_m',NaN,'PbrSigma_m',NaN,'InnovationSigma',NaN,...
    'V3Reason','','V7_m',NaN,'V7Error_m',NaN,'V7Selected',false,...
    'V7Reason','','V7BicGain',NaN,'V7Rescue',false,...
    'RelativeImprovement',NaN,'FitEchoAmplitude',NaN,...
    'FitDelay_ns',NaN,'FitSingleCost',NaN,'FitTwoPathCost',NaN,...
    'FitEligible',false,'FitReason',''),N,1);
oldRng=rng; restoreRng=onCleanup(@()rng(oldRng)); %#ok<NASGU>
idx=0;
for pi=1:numel(plans)
    plan=plans{pi};
    for ei=1:numel(echos)
        ec=echos{ei};
        scene=cfg.scenarios(1);
        scene.name=ec.name;
        scene.fHz=cfg.toneAnchorHz+plan.offsetsMHz(:)*1e6;
        scene.phaseResidualRad=zeros(numel(scene.fHz),1);
        scene.echoAmplitude=ec.amp;
        scene.echoDelayS=ec.delayNs*1e-9;
        scene.echoPhaseRad=ec.phaseRad;
        prep=td1.prepare(cfg,scene);
        rx=td1.receiverConfig(prep);
        bwMHz=(max(scene.fHz)-min(scene.fHz))/1e6;
        for si=1:numel(snrs)
            snr=snrs(si);
            % Calibration uses known LOS distance for every frequency plan.
            rng(seed+100000*pi+10000*ei+100*si,'twister');
            for k=1:cfg.calibrationTrials
                ob=td1.simulate(cfg.calibrationDistanceM,snr,scene,prep,true);
                f=td1.observe(ob,rx);
                if k==1,train=repmat(f,cfg.calibrationTrials,1);end
                train(k)=f;
            end
            cal=td1.calibrate(train,repmat(cfg.calibrationDistanceM,cfg.calibrationTrials,1),rx);
            rng(seed+200000+100000*pi+10000*ei+100*si,'twister');
            for di=1:numel(distances)
                d=distances(di);
                for t=1:nTrials
                    ob=td1.simulate(d,snr,scene,prep,false);
                    f=td1.observe(ob,rx);
                    base=td1.estimate(f,cal,rx);
                    fit=td1.twoPathProbe(f,cal,rx,base);
                    gate=td1.selectTwoPathV3(base,fit);
                    v7=td1.selectTwoPathV7(base,fit,gate,struct(),numel(scene.fHz));
                    idx=idx+1;
                    rows(idx).Plan=plan.name;
                    rows(idx).Echo=ec.name;
                    rows(idx).Bandwidth_MHz=bwMHz;
                    rows(idx).ToneCount=numel(scene.fHz);
                    rows(idx).ExcessDelay_ns=ec.delayNs;
                    rows(idx).EchoAmplitude=ec.amp;
                    rows(idx).Btau=bwMHz*1e6*ec.delayNs*1e-9;
                    rows(idx).Distance_m=d;
                    rows(idx).SNR_dB=snr;
                    rows(idx).Trial=t;
                    rows(idx).Baseline_m=base.fusedM;
                    rows(idx).V2_m=fit.candidateM;
                    rows(idx).V3_m=gate.selectedM;
                    rows(idx).BaselineError_m=base.fusedM-d;
                    rows(idx).V2Error_m=fit.candidateM-d;
                    rows(idx).V3Error_m=gate.selectedM-d;
                    rows(idx).V3Selected=gate.useTwoPath;
                    rows(idx).RTT_m=base.rttM;
                    rows(idx).PBR_m=base.pbrM;
                    rows(idx).BaselineStatus=base.status;
                    rows(idx).PBRValid=base.pbrValid;
                    rows(idx).PBRCoherence=base.pbrCoherence;
                    rows(idx).PBRPeriod_m=base.pbrPeriodM;
                    rows(idx).AliasCount=numel(base.aliasCandidatesM);
                    rows(idx).RttSigma_m=base.rttSigmaM;
                    rows(idx).PbrSigma_m=base.pbrSigmaM;
                    rows(idx).InnovationSigma=base.innovationSigma;
                    rows(idx).V3Reason=gate.reason;
                    rows(idx).V7_m=v7.selectedM;
                    rows(idx).V7Error_m=v7.selectedM-d;
                    rows(idx).V7Selected=v7.useTwoPath;
                    rows(idx).V7Reason=v7.reason;
                    rows(idx).V7BicGain=v7.bicGain;
                    rows(idx).V7Rescue=v7.rescue;
                    rows(idx).RelativeImprovement=fit.relativeImprovement;
                    rows(idx).FitEchoAmplitude=fit.echoAmplitude;
                    rows(idx).FitDelay_ns=fit.excessDelayNs;
                    rows(idx).FitSingleCost=fit.singleCost;
                    rows(idx).FitTwoPathCost=fit.twoPathCost;
                    rows(idx).FitEligible=fit.eligible;
                    rows(idx).FitReason=fit.reason;
                end
            end
        end
        fprintf('V7: %s / %s complete.\n',plan.name,ec.name);
    end
end
results=struct2table(rows);
writetable(results,fullfile(outDir,'v7_trials.csv'));
summary=cell(numel(plans)*numel(echos),15);
k=0;
for pi=1:numel(plans)
    for ei=1:numel(echos)
        k=k+1;
        mask=strcmp(results.Plan,plans{pi}.name) & strcmp(results.Echo,echos{ei}.name);
        x=results(mask,:);
        summary(k,:)={plans{pi}.name,echos{ei}.name,height(x),...
            plans{pi}.offsetsMHz(end)-plans{pi}.offsetsMHz(1),...
            echos{ei}.delayNs,echos{ei}.amp,...
            localRmse(x.BaselineError_m),localRmse(x.V2Error_m),...
            localRmse(x.V3Error_m),mean(x.V3Selected),...
            localRmse(x.V7Error_m),mean(x.V7Selected),sum(x.V7Rescue),...
            localRmse(x.RTT_m-x.Distance_m),localRmse(x.PBR_m-x.Distance_m)};
        fprintf('%s / %s : base %.3f | V2 %.3f | V3 %.3f | V7 %.3f m ; rescue %d\n',...
            plans{pi}.name,echos{ei}.name,summary{k,7},summary{k,8},...
            summary{k,9},summary{k,11},summary{k,13});
    end
end
summary=cell2table(summary,'VariableNames',{'Plan','Echo','Count','Bandwidth_MHz',...
    'ExcessDelay_ns','EchoAmplitude','BaselineRMSE_m','V2RMSE_m',...
    'V3RMSE_m','V3SelectRate','V7RMSE_m','V7SelectRate',...
    'V7RescueCount','RTTRMSE_m','PBRRMSE_m'});
writetable(summary,fullfile(outDir,'v7_summary.csv'));
fid=fopen(fullfile(outDir,'v7_experiment_notes.txt'),'w');
if fid>0
    fprintf(fid,'Seed %d, repeats %d, records %d.\n',seed,nTrials,height(results));
    fprintf(fid,'All plans 17 tones; RF retuning/phase calibration assumed idealized by simulator.\n');
    fprintf(fid,'V3 thresholds reused as-is, NOT optimized for new frequency patterns.\n');
    fprintf(fid,'NaN candidate estimates are excluded by localRmse; count finite values before interpreting.\n');
    fprintf(fid,'B*tau is only a dimensionless sensitivity indicator, NOT an identifiability guarantee.\n');
    fprintf(fid,'V7 is EXPERIMENTAL; fit-based rescue can worsen LOS or other channels.\n');
    fprintf(fid,'Per-scene calibration is simulated; hardware drift is not validated.\n');
    fclose(fid);
end
fprintf('V7 finished: %d observations; output %s\n',height(results),outDir);
end
function r=localRmse(x)
x=x(isfinite(x));
if isempty(x),r=NaN;else,r=sqrt(mean(x.^2));end
end
