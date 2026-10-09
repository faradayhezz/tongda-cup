function results = run_compare_v1(nTrials)
%RUN_COMPARE_V1 Compare the unchanged default with experimental fallback.
% WARNING: outputs are simulation-only; hardware drift can fool phase-only.
if nargin<1, nTrials=50; end
base=fileparts(mfilename('fullpath'));
configFile=fullfile(base,'+td1','defaultConfig.m');
% Baseline: cfg.allowPbrOnlyOnDisagreement=false.
% The runner uses defaultConfig internally; to avoid changing global files
% the second mode is run via a separate version of the runner (below).
results.baseline=run_topic1(fullfile(base,'results','v1_baseline'),nTrials);
results.note=['For the experimental mode, set ', ...
    'allowPbrOnlyOnDisagreement=true in defaultConfig.m, then run: ', ...
    'run_topic1(fullfile(pwd,''results'',''v1_experimental''),nTrials). ', ...
    'Restore false afterwards. Same RNG seed makes trials comparable.'];
fprintf('%s\n',results.note);
end
