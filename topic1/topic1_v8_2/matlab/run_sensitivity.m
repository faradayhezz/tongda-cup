function results = run_sensitivity(outDir,nTrials)
%RUN_SENSITIVITY Separate sweeps of CFO, phase noise, multipath and drift.
% Independent LOS calibration at 20 dB is reused across the stress sweep.
% Truth is used solely by the simulator and by final evaluation.
baseDir=fileparts(mfilename('fullpath'));
if nargin<1 || isempty(outDir),outDir=fullfile(baseDir,'results','sensitivity');end
if nargin<2 || isempty(nTrials),nTrials=20;end
validateattributes(nTrials,{'numeric'},{'scalar','integer','positive','finite'});
if ~exist(outDir,'dir'),mkdir(outDir);end
oldRng=rng; cleanup=onCleanup(@() rng(oldRng));
cfg=td1.defaultConfig();base=cfg.scenarios(1);p=td1.prepare(cfg,base);
receiver=td1.receiverConfig(p);
rng(cfg.seed+700000,'twister');
for k=1:cfg.calibrationTrials
    feat=td1.observe(td1.simulate(cfg.calibrationDistanceM,20,base,p,true),receiver);
    if k==1,train=repmat(feat,cfg.calibrationTrials,1);end
    train(k)=feat;
end
cal=td1.calibrate(train,repmat(cfg.calibrationDistanceM,cfg.calibrationTrials,1),receiver);
groups={'CFO_Hz','PhaseNoise_rad','EchoAmplitude','ClockB_Drift_ppm','DelayDrift_ns'};
values={[-120e3 -40e3 0 12e3 40e3 120e3],[0 .05 .15 .35 .7], ...
    [0 .1 .25 .5 .8],[0 10 30 60 150 300],[0 4 8 16 32]};
template=struct('Parameter','','Value',0,'Trial',0,'TrueDistance_m',10, ...
    'RTT_m',NaN,'PBR_m',NaN,'Fused_m',NaN,'CFOEstimate_Hz',NaN, ...
    'PBR_Usable',false,'FusionValid',false,'Status','','OutputMode','');
count=sum(cellfun(@numel,values))*nTrials;records=repmat(template,count,1);row=0;
for g=1:numel(groups)
    for v=1:numel(values{g})
        scene=base;value=values{g}(v);
        switch groups{g}
            case 'CFO_Hz',scene.cfoHz=value;
            case 'PhaseNoise_rad',scene.phaseNoiseRad=value;
            case 'EchoAmplitude'
                scene.echoAmplitude=value;scene.echoDelayS=25e-9;scene.echoPhaseRad=.7;
            case 'ClockB_Drift_ppm',scene.driftClockBppm=value;
            case 'DelayDrift_ns',scene.driftDelayS=value*1e-9;
        end
        prepared=td1.prepare(cfg,scene);
        receiver=td1.receiverConfig(prepared);
        rng(cfg.seed+800000+g*1000+v,'twister');
        for k=1:nTrials
            obs=td1.simulate(10,20,scene,prepared,false);
            feat=td1.observe(obs,receiver);est=td1.estimate(feat,cal,receiver);
            row=row+1;r=template;r.Parameter=groups{g};r.Value=value;r.Trial=k;
            r.RTT_m=est.rttM;r.PBR_m=est.pbrM;r.Fused_m=est.fusedM;
            r.CFOEstimate_Hz=feat.cfoPairHz;r.PBR_Usable=est.pbrValid;
            r.FusionValid=est.fusionValid;r.Status=est.status;r.OutputMode=td1.outputMode(est);
            records(row)=r;
        end
    end
    fprintf('Completed sensitivity: %s.\n',groups{g});
end
trials=struct2table(records);
prototype=struct('Parameter','','Value',0,'N',0,'FiniteN',0,'PBRUsableN',0, ...
    'RTT_RMSE_m',NaN,'PBR_RMSE_m',NaN,'Fused_RMSE_m',NaN, ...
    'FusionAcceptedRate',0,'RTTFallbackRate',0,'PBRFallbackRate',0,'UnavailableRate',0);
summaryRecords=repmat(prototype,sum(cellfun(@numel,values)),1);row=0;
for g=1:numel(groups)
    for v=1:numel(values{g})
        row=row+1;s=prototype;s.Parameter=groups{g};s.Value=values{g}(v);
        selected=strcmp(trials.Parameter,groups{g}) & trials.Value==values{g}(v);
        s.N=sum(selected);s.FiniteN=sum(isfinite(trials.Fused_m(selected)));
        s.PBRUsableN=sum(trials.PBR_Usable(selected));
        s.RTT_RMSE_m=finiteRmse(trials.RTT_m(selected)-10);
        s.PBR_RMSE_m=finiteRmse(trials.PBR_m(selected)-10);
        s.Fused_RMSE_m=finiteRmse(trials.Fused_m(selected)-10);
        s.FusionAcceptedRate=mean(trials.FusionValid(selected));
        s.RTTFallbackRate=mean(strcmp(trials.OutputMode(selected),'rtt_only'));
        s.PBRFallbackRate=mean(strcmp(trials.OutputMode(selected),'pbr_only'));
        s.UnavailableRate=mean(~isfinite(trials.Fused_m(selected)));summaryRecords(row)=s;
    end
end
summary=struct2table(summaryRecords);
writetable(trials,fullfile(outDir,'trials.csv'));
writetable(summary,fullfile(outDir,'summary.csv'));
fig=figure('Visible','off','Color','w','Position',[30 30 1400 760]);
for g=1:numel(groups)
    subplot(2,3,g);selected=strcmp(summary.Parameter,groups{g});
    x=summary.Value(selected);
    plot(x,summary.RTT_RMSE_m(selected),'-o',x,summary.PBR_RMSE_m(selected), ...
        '-s',x,summary.Fused_RMSE_m(selected),'-^');
    grid on;xlabel(groups{g},'Interpreter','none');ylabel('RMSE (m)');
    if g==1,legend({'RTT','PBR','Fusion'},'Location','best');end
end
subplot(2,3,6);hold on;
for g=1:numel(groups)
    selected=strcmp(summary.Parameter,groups{g});
    plot(1:sum(selected),1-summary.FusionAcceptedRate(selected),'-o');
end
grid on;ylim([0 1]);xlabel('Parameter setting index');ylabel('Fusion rejection fraction');
legend(groups,'Interpreter','none','Location','best','FontSize',8);
sgtitle('Simulation only | 10 m, 20 dB | Fixed independent reference calibration');
figurePath=fullfile(outDir,'sensitivity.png');saveas(fig,figurePath);close(fig);
results=struct('config',cfg,'calibration',cal,'trials',trials,'summary',summary, ...
    'figure',figurePath,'matlabVersion',version);
save(fullfile(outDir,'results.mat'),'results');
fprintf('Simulation only: %d sensitivity packets.\n',height(trials));
end

function value=finiteRmse(error)
error=error(isfinite(error));
if isempty(error),value=NaN;else,value=sqrt(mean(error.^2));end
end
