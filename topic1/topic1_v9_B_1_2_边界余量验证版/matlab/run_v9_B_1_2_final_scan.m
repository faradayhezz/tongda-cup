function report = run_v9_B_1_2_final_scan()
% Final frozen-algorithm scan: 20 distances x 4 SNR x 2 spans x 3 scenes x 10 steps.
% Three independent random seeds, each 4800 target records. MATLAB R2018b compatible.
root=fileparts(mfilename('fullpath'));
seeds=[20281219 20290107 20290211];
for k=1:numel(seeds)
 fprintf('\n=== Continuous scan %d/%d: seed %d ===\n',k,numel(seeds),seeds(k));
 run_v9_B_1_2_distance_scan(1,seeds(k));
end
report=report_v9_B_1_2_final_scan(seeds);
end
