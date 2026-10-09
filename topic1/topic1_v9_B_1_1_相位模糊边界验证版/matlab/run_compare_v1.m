function results = run_compare_v1(nTrials)
%RUN_COMPARE_V1 Paired default/opt-in runs without editing shared config files.
% Same deterministic IQ/calibration seeds; PBR-only can fail on phase drift.
if nargin<1 || isempty(nTrials), nTrials=50; end
validateattributes(nTrials,{'numeric'},{'scalar','integer','positive','finite'});
base=fileparts(mfilename('fullpath'));
results.baseline=run_topic1(fullfile(base,'results','v1_baseline'),nTrials);
results.experimental=run_topic1(fullfile(base,'results','v1_experimental'), ...
    nTrials,struct('allowPbrOnlyOnDisagreement',true));
results.note='Opt-in PBR-only fallback is experimental; shared phase drift remains confounded with range.';
fprintf('%s\n',results.note);
end
