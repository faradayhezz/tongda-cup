function validate_v9_B_1_final()
root=fileparts(mfilename('fullpath'));
file=fullfile(root,'results','v9_B_1_final_verify','v9_B_1_final_trials.csv');
assert(exist(file,'file')==2,'Please run run_v9_B_1_final_verify first.');
T=readtable(file);
assert(height(T)>0,'Empty results.');
assert(all(ismember([1 3 5 10 15 20],unique(T.Distance_m)')),'Missing distances.');
assert(all(ismember([0 10 20 30],unique(T.SNR_dB)')),'Missing SNR values.');
assert(numel(unique(T.Condition))==9,'Expected 9 scenarios.');
assert(numel(unique(T.Plan))==2,'Expected 2 tone spans.');
assert(all(isfinite(T.V8Error_m)&isfinite(T.V9B1Error_m)),'Nonfinite final output: inspect trials.');
assert(all(abs(T.V9B1Error_m-(T.V9B1_m-T.Distance_m))<1e-6), 'V9_B_1 error column mismatch.');
assert(all(abs(T.V8Error_m-(T.V8_m-T.Distance_m))<1e-6), 'V8 error column mismatch.');
fprintf('Reference update failed/held: %d; powered bootstraps: %d.\n', ...
 sum(strcmp(T.ReferenceCalStatus,'update_failed_hold_previous')), ...
 sum(strcmp(T.ReferenceCalStatus,'bootstrap_20dB')));
fprintf('PASS V9_B_1 final: %d records, 9 scenarios, 2 spans, 6 distances, 4 SNRs.\n',height(T));
fprintf('V8 RMSE %.4f m; V9_B_1 RMSE %.4f m.\n',sqrt(mean(T.V8Error_m.^2)),sqrt(mean(T.V9B1Error_m.^2)));
end
