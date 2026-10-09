function report = compare_v9_B_1_1(mode)
% Compare two paired search bounds. The runs MUST share seed/episodes/mode.
if nargin<1 || isempty(mode),mode='targeted';end
root=fileparts(mfilename('fullpath'));
f40=fullfile(root,'results',sprintf('v9_B_1_1_%s_40m',mode),'v9_B_1_1_trials.csv');
f20=fullfile(root,'results',sprintf('v9_B_1_1_%s_20m',mode),'v9_B_1_1_trials.csv');
assert(exist(f40,'file')==2 && exist(f20,'file')==2,'Run BOTH 40m and 20m versions first.');
a=readtable(f40); b=readtable(f20);
assert(height(a)==height(b),'Unequal row count');
if ismember('Seed',a.Properties.VariableNames) && ismember('Seed',b.Properties.VariableNames)
 assert(isequal(a.Seed,b.Seed),'Paired comparison requires identical random seeds.');
end
assert(all(abs(a.RawRtt_m-b.RawRtt_m)<1e-8),'Raw observations differ; these are not paired runs.');
assert(isequal(a.Plan,b.Plan) && isequal(a.Condition,b.Condition) && ...
 isequal(a.SNR_dB,b.SNR_dB) && isequal(a.Distance_m,b.Distance_m) && ...
 isequal(a.Episode,b.Episode) && isequal(a.TimeStep,b.TimeStep), ...
 'Pairing keys differ. Check seed and run settings.');
assert(all(isfinite(a.V8Error_m)) && all(isfinite(b.V8Error_m)) && ...
 all(isfinite(a.V9B1Error_m)) && all(isfinite(b.V9B1Error_m)), ...
 'Nonfinite values: do not compare RMSE without inspecting failures.');
names=unique(a.Plan,'stable'); conds=unique(a.Condition,'stable'); ds=unique(a.Distance_m);
r=cell(0,13);
for pi=1:numel(names)
 for ci=1:numel(conds)
  for di=1:numel(ds)
   ix=strcmp(a.Plan,names{pi}) & strcmp(a.Condition,conds{ci}) & a.Distance_m==ds(di);
   if ~any(ix),continue;end
   r(end+1,:)={names{pi},conds{ci},ds(di),sum(ix), ...
    sqrt(mean(a.V8Error_m(ix).^2)),sqrt(mean(b.V8Error_m(ix).^2)), ...
    sqrt(mean(a.V9B1Error_m(ix).^2)),sqrt(mean(b.V9B1Error_m(ix).^2)), ...
    sum(a.PbrAliasCount(ix)>1),sum(b.PbrAliasCount(ix)>1), ...
    sum(a.V8Switched(ix)),sum(b.V8Switched(ix)), ...
    sum(abs(b.V9B1Error_m(ix))>abs(a.V9B1Error_m(ix))+1e-10)}; %#ok<AGROW>
  end
 end
end
report=cell2table(r,'VariableNames',{'Plan','Condition','Distance_m','N', ...
 'V8RMSE_40m','V8RMSE_20m','V9B1RMSE_40m','V9B1RMSE_20m', ...
 'Aliases_40m','Aliases_20m','V8Switches_40m','V8Switches_20m','WorseRows_20m'});
out=fullfile(root,'results',['v9_B_1_1_compare_' mode '.csv']);
writetable(report,out);
fprintf('PASS paired boundary comparison: %d rows, %d groups -> %s\n',height(a),height(report),out);
fprintf('Overall V8 RMSE: 40m %.4f / 20m %.4f m\n',sqrt(mean(a.V8Error_m.^2)),sqrt(mean(b.V8Error_m.^2)));
fprintf('Overall V9B1 RMSE: 40m %.4f / 20m %.4f m\n',sqrt(mean(a.V9B1Error_m.^2)),sqrt(mean(b.V9B1Error_m.^2)));
end
