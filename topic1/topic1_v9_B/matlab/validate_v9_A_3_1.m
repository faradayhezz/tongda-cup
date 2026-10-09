function validate_v9_A_3_1(csvPath)
% Validate exported jump labels and simulated drift; MATLAB R2018b+.
% Diagnostics only: no change to ranging estimators or signal generation.
root = fileparts(mfilename('fullpath'));
if nargin < 1 || isempty(csvPath)
    csvPath = fullfile(root,'results','v9_A_3_1_diagnostic','v9_A_3_1_trials.csv');
end
assert(exist(csvPath,'file') == 2, 'Trials CSV not found: %s', csvPath);
T = readtable(csvPath);
required = {'Condition','TrueJump','TrueJumpActive','TrueDriftDelay_ns', ...
    'TrueDriftClock_ppm','TimeStep','JumpTime','Plan','UpdatePeriod', ...
    'SNR_dB','Distance_m','Episode'};
assert(all(ismember(required,T.Properties.VariableNames)), ...
    'Some necessary diagnostic columns are missing.');
% readtable() may deserialize CSV 0/1 into double, not logical.
assert(all(ismember(T.TrueJump,[0;1])) && all(ismember(T.TrueJumpActive,[0;1])), ...
    'Jump labels must be numeric/logical 0/1.');
onset = logical(T.TrueJump);
active = logical(T.TrueJumpActive);
mask = strcmp(cellstr(T.Condition),'sudden_jump');
assert(any(mask), 'No sudden_jump trials.');
jump = T(mask,:);
jumpOnset = onset(mask);
jumpActive = active(mask);
assert(all(jumpOnset == (jump.TimeStep == jump.JumpTime)), ...
    'TrueJump does not match JumpTime');
assert(all(jumpActive == (jump.TimeStep >= jump.JumpTime)), ...
    'TrueJumpActive mismatch');
assert(all(abs(jump.TrueDriftDelay_ns(~jumpActive)) < 1e-8), ...
    'Nonzero delay before jump');
assert(all(abs(jump.TrueDriftDelay_ns(jumpActive)-16) < 1e-8), ...
    'Wrong delay after jump');
assert(all(abs(jump.TrueDriftClock_ppm(~jumpActive)) < 1e-8), ...
    'Nonzero clock drift before jump');
assert(all(abs(jump.TrueDriftClock_ppm(jumpActive)-60) < 1e-8), ...
    'Wrong clock drift after jump');
assert(~any(onset(~mask)) && ~any(active(~mask)), ...
    'Jump labels set on other conditions');
% Every group contains two distances at every time step; group by distance too.
G = findgroups(jump.Plan,jump.UpdatePeriod,jump.SNR_dB, ...
    jump.Distance_m,jump.Episode);
counts = splitapply(@sum,double(jumpOnset),G);
assert(all(counts == 1),'Not exactly one jump onset per replicate');
assert(numel(unique(jump.JumpTime)) > 1,'Jump onset not randomized');
fprintf('PASS V9_A_3_1: %d rows; %d jump groups; labels and drift consistent.\n', ...
    height(T),numel(counts));
end
