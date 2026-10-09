function report=report_v9_B_1_2_final_scan(seeds)
% CSV aggregation and plots; errors are reported for V9_B_1_2 only.
if nargin<1 || isempty(seeds), seeds=[20281219 20290107 20290211];end
root=fileparts(mfilename('fullpath'));
out=fullfile(root,'results','v9_B_1_2_final_scan_report');
if ~exist(out,'dir'),mkdir(out);end
trials=table(); sumRows=cell(numel(seeds),6);
for k=1:numel(seeds)
 file=fullfile(root,'results',sprintf('v9_B_1_2_scan_seed_%d',seeds(k)),'distance_scan_trials.csv');
 assert(exist(file,'file')==2,['Missing output: ' file]);
 t=readtable(file);t.Seed=repmat(seeds(k),height(t),1);
 assert(height(t)==4800,'Expected exactly 4800 rows per seed');
 assert(all(ismember(1:20,unique(t.Distance_m)')),'Missing scan distance');
 assert(all(isfinite(t.V9B1Error_m)),'Nonfinite V9B1 outputs');
 e=t.V9B1Error_m;
 sumRows(k,:)={seeds(k),height(t),sqrt(mean(e.^2)),mean(abs(e)),localP95(abs(e)),mean(abs(e)>1)};
 trials=[trials;t]; %#ok<AGROW>
end
perSeed=cell2table(sumRows,'VariableNames',{'Seed','N','RMSE_m','MAE_m','P95_m','Over1m'});
writetable(perSeed,fullfile(out,'seed_summary.csv'));
assert(height(trials)==numel(seeds)*4800,'Wrong total number of samples');
plans=unique(trials.Plan);conds=unique(trials.Condition);snrs=unique(trials.SNR_dB);
rows=cell(0,9);
for ip=1:numel(plans)
 for ic=1:numel(conds)
  for d=1:20
   for is=1:numel(snrs)
    ix=strcmp(trials.Plan,plans{ip})&strcmp(trials.Condition,conds{ic})& ...
       trials.Distance_m==d & trials.SNR_dB==snrs(is);
    e=trials.V9B1Error_m(ix);
    rows(end+1,:)={plans{ip},conds{ic},d,snrs(is),numel(e), ...
       sqrt(mean(e.^2)),mean(abs(e)),localP95(abs(e)),mean(abs(e)>1)}; %#ok<AGROW>
   end
  end
 end
end
byDistanceSnr=cell2table(rows,'VariableNames',{'Plan','Condition','Distance_m','SNR_dB','N','RMSE_m','MAE_m','P95_m','Over1m'});
writetable(byDistanceSnr,fullfile(out,'scan_by_distance_snr.csv'));
rows=cell(0,8);
for ip=1:numel(plans)
 for ic=1:numel(conds)
  for d=1:20
   ix=strcmp(trials.Plan,plans{ip})&strcmp(trials.Condition,conds{ic})&trials.Distance_m==d;
   e=trials.V9B1Error_m(ix);
   rows(end+1,:)={plans{ip},conds{ic},d,numel(e),sqrt(mean(e.^2)),mean(abs(e)),localP95(abs(e)),mean(abs(e)>1)}; %#ok<AGROW>
  end
 end
end
byDistance=cell2table(rows,'VariableNames',{'Plan','Condition','Distance_m','N','RMSE_m','MAE_m','P95_m','Over1m'});
writetable(byDistance,fullfile(out,'scan_by_distance.csv'));
% Plot RMSE vs true distance; curves are grouped by radio span and channel.
try
 fig=figure('Visible','off','Color','w');hold on;
 labels=cell(numel(plans)*numel(conds),1);ii=0;
 for ip=1:numel(plans)
  for ic=1:numel(conds)
   ii=ii+1; ix=strcmp(byDistance.Plan,plans{ip})&strcmp(byDistance.Condition,conds{ic});
   plot(byDistance.Distance_m(ix),byDistance.RMSE_m(ix),'-o','LineWidth',1.3,'MarkerSize',3);
   labels{ii}=[plans{ip} ' / ' conds{ic}];
  end
 end
 xlabel('True distance (m)');ylabel('RMSE (m)');
 title('V9 B 1 2: range RMSE vs true distance (0-22 m search)');
 legend(labels,'Location','best');grid on;xlim([1 20]);
 saveas(fig,fullfile(out,'scan_rmse_by_distance.png'));close(fig);
catch ME
 warning('Plot unavailable: %s',ME.message);
end
report=struct('perSeed',perSeed,'byDistance',byDistance,'byDistanceSnr',byDistanceSnr,'output',out);
fprintf('PASS final scan: %d seeds, %d total finite target records. Output: %s\n',numel(seeds),height(trials),out);
end
function p=localP95(e)
e=sort(e);p=e(max(1,ceil(.95*numel(e))));
end
