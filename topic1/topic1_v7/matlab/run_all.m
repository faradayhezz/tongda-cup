function outputs = run_all(nTrials)
%RUN_ALL Run invariants, the full benchmark and parameter sensitivity.
% Open this code folder in MATLAB R2023a and run: outputs = run_all;
% A short integration run is available with: outputs = run_all(3);
if nargin<1 || isempty(nTrials),nTrials=50;end
validateattributes(nTrials,{'numeric'},{'scalar','integer','positive','finite'});
baseDir=fileparts(mfilename('fullpath'));testDir=fullfile(baseDir,'tests');
oldPath=path;cleanup=onCleanup(@() path(oldPath));
addpath(baseDir,testDir);
checkDir=fullfile(baseDir,'results','verification');
if ~exist(checkDir,'dir'),mkdir(checkDir);end
report=test_topic1();
writetable(report,fullfile(checkDir,'self_tests.csv'));
benchmark=run_topic1(fullfile(baseDir,'results','benchmark'),nTrials);
sensitivity=run_sensitivity(fullfile(baseDir,'results','sensitivity'),min(20,nTrials));
metadata=struct('MatlabVersion',version,'SimulationOnly',true, ...
    'SelfTests',height(report),'SelfTestsPassed',all(report.Pass), ...
    'TestPackets',height(benchmark.trials),'SummaryRows',height(benchmark.summary), ...
    'SensitivityPackets',height(sensitivity.trials), ...
    'TrialsPerDistanceSnr',nTrials,'Seed',benchmark.config.seed, ...
    'BenchmarkElapsedSeconds',benchmark.elapsedSeconds);
file=fopen(fullfile(checkDir,'verification.json'),'w','n','UTF-8');
if file<0,error('td1:WriteVerification','Cannot open verification.json.');end
closeFile=onCleanup(@() fclose(file));
fprintf(file,'%s\n',jsonencode(metadata));
outputs=struct('selfTests',report,'benchmark',benchmark,'sensitivity',sensitivity);
disp(metadata);
end
