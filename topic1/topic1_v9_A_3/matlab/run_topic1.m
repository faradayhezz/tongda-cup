function results = run_topic1(outDir, nTrials)
%RUN_TOPIC1 Reproducible waveform-level ranging benchmark. Simulation only.
%   results = run_topic1;
%   results = run_topic1(fullfile(pwd,'results','quick'), 3);
% Base MATLAB only. No Bluetooth/Communications/Statistics toolbox required.
% This is an inspired waveform and calibrated reciprocal-channel model,
% not an implementation of the Bluetooth Channel Sounding protocol.
baseDir = fileparts(mfilename('fullpath'));
if nargin < 1 || isempty(outDir)
    outDir = fullfile(baseDir, 'results', 'benchmark');
end
cfg = td1.defaultConfig();
if nargin >= 2 && ~isempty(nTrials)
    validateattributes(nTrials, {'numeric'}, {'scalar','integer','positive','finite'});
    cfg.nTrials = nTrials;
end
if isstring(outDir), outDir = char(outDir); end
validateattributes(outDir, {'char'}, {'row','nonempty'});
if ~exist(outDir,'dir'), mkdir(outDir); end
oldRng = rng; cleanup = onCleanup(@() rng(oldRng));
rows = numel(cfg.scenarios)*numel(cfg.distancesM)*numel(cfg.snrDb)*cfg.nTrials;
records = repmat(blankRecord(), rows, 1);
calibrations = cell(numel(cfg.scenarios), numel(cfg.snrDb));
row = 0; timerAll = tic;
for s = 1:numel(cfg.scenarios)
    scene = cfg.scenarios(s);
    prepared = td1.prepare(cfg, scene);
    receiver = td1.receiverConfig(prepared);
    for z = 1:numel(cfg.snrDb)
        snrDb = cfg.snrDb(z);
        % Calibration uses known reference distance, separate RNG and packets.
        rng(cfg.seed + s*1000 + z*10, 'twister');
        for k = 1:cfg.calibrationTrials
            obs = td1.simulate(cfg.calibrationDistanceM,snrDb,scene,prepared,true);
            feat = td1.observe(obs,receiver);
            if k == 1
                train = repmat(feat,cfg.calibrationTrials,1);
            end
            train(k) = feat;
        end
        cal = td1.calibrate(train, ...
            repmat(cfg.calibrationDistanceM,cfg.calibrationTrials,1),receiver);
        calibrations{s,z} = cal;
        rng(cfg.seed + 100000 + s*1000 + z*10, 'twister');
        for d = 1:numel(cfg.distancesM)
            truth = cfg.distancesM(d);
            for k = 1:cfg.nTrials
                % Only the simulator receives the truth. Estimator receives IQ
                % features, independently fitted calibration, and design cfg.
                obs = td1.simulate(truth,snrDb,scene,prepared,false);
                timerEstimate = tic;
                feat = td1.observe(obs,receiver);
                est = td1.estimate(feat,cal,receiver);
                elapsed = toc(timerEstimate);
                row = row + 1;
                record = blankRecord();
                record.Scenario = scene.name;
                record.TrueDistance_m = truth;
                record.SNR_dB = snrDb;
                record.Trial = k;
                record.Raw_RTT_m = est.rawRttM;
                record.Calibrated_RTT_m = est.rttM;
                record.Raw_PBR_m = est.rawPbrM;
                record.Calibrated_PBR_m = est.pbrM;
                record.Fused_m = est.fusedM;
                record.CFO_Hz = feat.cfoPairHz;
                record.PBR_Coherence = est.pbrCoherence;
                record.PBR_Ambiguous = est.pbrAmbiguous;
                record.PBR_Usable = est.pbrValid;
                record.FusionValid = est.fusionValid;
                record.Status = est.status;
                record.InnovationSigma = est.innovationSigma;
                record.PhaseCurvature_rad = est.phaseCurvatureRad;
                record.PhaseCurvatureFlag = est.phaseCurvatureFlag;
                record.EstimatorSeconds = elapsed;
                if est.pbrValid && isfinite(est.fusedM)
                    record.FusionWorseThanPBR = double( ...
                        abs(est.fusedM-truth)>abs(est.pbrM-truth)+1e-6);
                end
                candidates = est.aliasCandidatesM;
                if isempty(candidates) || ~est.pbrAmbiguous || ~est.fusionValid
                    record.AliasBranchWrong = NaN;
                else
                    [~,nearestTruth] = min(abs(candidates-truth));
                    [~,selected] = min(abs(candidates-est.fusedM));
                    record.AliasBranchWrong = double(selected~=nearestTruth);
                end
                records(row) = record;
            end
        end
    end
    fprintf('Completed %s (%d trials per distance/SNR).\n',scene.name,cfg.nTrials);
end
trials = struct2table(records);
summary = summarize(trials,cfg);
diagnostics = diagnosticSummary(trials,cfg);
results = struct('config',cfg,'calibrations',{calibrations},'trials',trials, ...
    'summary',summary,'diagnostics',diagnostics,'matlabVersion',version, ...
    'elapsedSeconds',toc(timerAll),'outputDirectory',outDir);
results.figures = {fullfile(outDir,'rmse.png'),fullfile(outDir,'robustness.png')};
writetable(trials,fullfile(outDir,'trials.csv'));
writetable(summary,fullfile(outDir,'summary.csv'));
writetable(diagnostics,fullfile(outDir,'diagnostics.csv'));
makeFigures(summary,diagnostics,cfg,results.figures);
save(fullfile(outDir,'results.mat'),'results');
fprintf('Simulation only: %d test packets, %d summary rows, %.1f s.\n', ...
    height(trials),height(summary),results.elapsedSeconds);
fprintf('Saved to %s\n',outDir);
end

function record = blankRecord()
record = struct('Scenario','','TrueDistance_m',0,'SNR_dB',0,'Trial',0, ...
    'Raw_RTT_m',NaN,'Calibrated_RTT_m',NaN,'Raw_PBR_m',NaN, ...
    'Calibrated_PBR_m',NaN,'Fused_m',NaN,'CFO_Hz',NaN, ...
    'PBR_Coherence',NaN,'PBR_Ambiguous',false,'PBR_Usable',false,'FusionValid',false, ...
    'Status','','InnovationSigma',NaN,'EstimatorSeconds',NaN, ...
    'FusionWorseThanPBR',NaN,'AliasBranchWrong',NaN, ...
    'PhaseCurvature_rad',NaN,'PhaseCurvatureFlag',false);
end

function summary = summarize(trials,cfg)
methods = {'Raw_RTT','Calibrated_RTT','Raw_PBR','Calibrated_PBR','Fused'};
template = struct('Scenario','','TrueDistance_m',0,'SNR_dB',0,'Method','', ...
    'N',0,'FiniteN',0,'UsableN',0,'MAE_m',NaN,'RMSE_m',NaN,'Bias_m',NaN, ...
    'P95AbsError_m',NaN,'AbsErrorOver1mRate',NaN);
n = numel(cfg.scenarios)*numel(cfg.distancesM)*numel(cfg.snrDb)*numel(methods);
records = repmat(template,n,1); row = 0;
for s=1:numel(cfg.scenarios)
    for d=1:numel(cfg.distancesM)
        for z=1:numel(cfg.snrDb)
            selected = strcmp(trials.Scenario,cfg.scenarios(s).name) & ...
                trials.TrueDistance_m==cfg.distancesM(d) & trials.SNR_dB==cfg.snrDb(z);
            for m=1:numel(methods)
                row=row+1; record=template;
                record.Scenario=cfg.scenarios(s).name;
                record.TrueDistance_m=cfg.distancesM(d);
                record.SNR_dB=cfg.snrDb(z); record.Method=methods{m};
                values=trials.([methods{m} '_m'])(selected);
                error=values-cfg.distancesM(d); valid=isfinite(error);
                record.N=numel(error); record.FiniteN=sum(valid);
                if strcmp(methods{m},'Calibrated_PBR')
                    record.UsableN=sum(valid & trials.PBR_Usable(selected));
                elseif strcmp(methods{m},'Raw_PBR') || strcmp(methods{m},'Raw_RTT')
                    % Raw methods are ablation diagnostics without calibration.
                    record.UsableN=NaN;
                else
                    record.UsableN=sum(valid);
                end
                error=error(valid);
                if ~isempty(error)
                    record.MAE_m=mean(abs(error));
                    record.RMSE_m=sqrt(mean(error.^2));
                    record.Bias_m=mean(error);
                    record.P95AbsError_m=percentile(abs(error),.95);
                    record.AbsErrorOver1mRate=mean(abs(error)>1);
                end
                records(row)=record;
            end
        end
    end
end
summary=struct2table(records);
end

function diagnostics = diagnosticSummary(trials,cfg)
template=struct('Scenario','','SNR_dB',0,'N',0,'FusionAcceptedRate',0, ...
    'RTTFallbackRate',0,'UnavailableRate',0,'PBRUsableRate',0, ...
    'ComparedN',0,'FusionWorseThanPBRRate',NaN,'AliasDecisionN',0,'AliasBranchWrongRate',NaN, ...
    'MedianEstimator_ms',0,'MeanPBRCoherence',0);
records=repmat(template,numel(cfg.scenarios)*numel(cfg.snrDb),1); row=0;
for s=1:numel(cfg.scenarios)
    for z=1:numel(cfg.snrDb)
        row=row+1;
        select=strcmp(trials.Scenario,cfg.scenarios(s).name) & trials.SNR_dB==cfg.snrDb(z);
        record=template; record.Scenario=cfg.scenarios(s).name;
        record.SNR_dB=cfg.snrDb(z); record.N=sum(select);
        record.FusionAcceptedRate=mean(trials.FusionValid(select));
        record.RTTFallbackRate=mean(~trials.FusionValid(select) & isfinite(trials.Fused_m(select)));
        record.UnavailableRate=mean(~isfinite(trials.Fused_m(select)));
        record.PBRUsableRate=mean(trials.PBR_Usable(select));
        compared=trials.FusionWorseThanPBR(select);compared=compared(isfinite(compared));
        record.ComparedN=numel(compared);
        if ~isempty(compared),record.FusionWorseThanPBRRate=mean(compared);end
        alias=trials.AliasBranchWrong(select); alias=alias(isfinite(alias));
        record.AliasDecisionN=numel(alias);
        if ~isempty(alias), record.AliasBranchWrongRate=mean(alias); end
        record.MedianEstimator_ms=1000*median(trials.EstimatorSeconds(select));
        record.MeanPBRCoherence=mean(trials.PBR_Coherence(select));
        records(row)=record;
    end
end
diagnostics=struct2table(records);
end

function value = percentile(data,p)
data=sort(data(:)); index=1+(numel(data)-1)*p;
lo=floor(index); hi=ceil(index);
value=data(lo)+(index-lo)*(data(hi)-data(lo));
end

function makeFigures(summary,diagnostics,cfg,paths)
methods={'Calibrated_RTT','Calibrated_PBR','Fused'};
labels={'RTT calibrated','PBR calibrated','Fusion'};
styles={'-o','-s','-^'}; colors=[.15 .40 .70;.83 .35 .12;.2 .6 .3];
fig=figure('Visible','off','Color','w','Position',[30 30 1600 1050]);
for s=1:numel(cfg.scenarios)
    for z=1:numel(cfg.snrDb)
        subplot(numel(cfg.scenarios),numel(cfg.snrDb),(s-1)*numel(cfg.snrDb)+z);
        hold on;
        for m=1:numel(methods)
            selected=strcmp(summary.Scenario,cfg.scenarios(s).name) & ...
                summary.SNR_dB==cfg.snrDb(z) & strcmp(summary.Method,methods{m});
            plot(summary.TrueDistance_m(selected),summary.RMSE_m(selected), ...
                styles{m},'Color',colors(m,:),'MarkerSize',3,'LineWidth',1);
        end
        grid on; xlim([0 21]); xlabel('Distance (m)'); ylabel('RMSE (m)');
        title(sprintf('%s | %g dB',cfg.scenarios(s).name,cfg.snrDb(z)), ...
            'Interpreter','none','FontSize',9);
        if s==1 && z==1, legend(labels,'Location','best','FontSize',7); end
    end
end
sgtitle('Simulation only | GFSK-inspired sync + bidirectional tones');
saveas(fig,paths{1}); close(fig);
fig=figure('Visible','off','Color','w','Position',[30 30 1300 650]);
for s=1:numel(cfg.scenarios)
    subplot(2,3,s); hold on;
    selected=strcmp(diagnostics.Scenario,cfg.scenarios(s).name);
    plot(diagnostics.SNR_dB(selected),diagnostics.RTTFallbackRate(selected),'-o');
    plot(diagnostics.SNR_dB(selected),diagnostics.FusionWorseThanPBRRate(selected),'-s');
    plot(diagnostics.SNR_dB(selected),diagnostics.AliasBranchWrongRate(selected),'-^');
    plot(diagnostics.SNR_dB(selected),diagnostics.UnavailableRate(selected),'--x');
    grid on; ylim([0 1]); xlabel('SNR (dB)'); ylabel('Fraction');
    title(cfg.scenarios(s).name,'Interpreter','none');
    if s==1,legend({'RTT fallback','Fusion worsens PBR','Wrong alias','Unavailable'},'Location','best');end
end
sgtitle('Simulation only | Failure and degradation diagnostics');
saveas(fig,paths{2});close(fig);
end
