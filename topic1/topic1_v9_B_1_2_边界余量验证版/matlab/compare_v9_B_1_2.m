function report=compare_v9_B_1_2(mode)
%COMPARE_V9_B_1_2 Compare 0-40, 0-20, 0-22 m search bounds.
% Run all with same seed/episodes/mode. Only paired finite rows included.
if nargin<1 || isempty(mode),mode='targeted';end
root=fileparts(mfilename('fullpath'));
bounds=[40 20 22]; T=cell(1,3);
for k=1:3
 p=fullfile(root,'results',sprintf('v9_B_1_2_%s_%dm',mode,bounds(k)),'v9_B_1_2_trials.csv');
 assert(exist(p,'file')==2,'Run all three ranges before comparison. Missing: %s',p);
 T{k}=readtable(p);
end
ref=T{1};
for k=2:3
 q=T{k};
 assert(height(ref)==height(q),'Different sample sizes');
 assert(isequal(ref.Plan,q.Plan) && isequal(ref.Condition,q.Condition) && ...
  isequal(ref.SNR_dB,q.SNR_dB) && isequal(ref.Distance_m,q.Distance_m) && ...
  isequal(ref.Episode,q.Episode) && isequal(ref.TimeStep,q.TimeStep), ...
  'Paired keys differ: check seeds and test settings');
end
plans=unique(ref.Plan,'stable');conds=unique(ref.Condition,'stable'); ds=unique(ref.Distance_m);
rows=cell(0,20);
for pi=1:numel(plans)
 for ci=1:numel(conds)
  for di=1:numel(ds)
   mask=strcmp(ref.Plan,plans{pi}) & strcmp(ref.Condition,conds{ci}) & ref.Distance_m==ds(di);
   if ~any(mask),continue;end
   n=sum(mask);rm=zeros(1,3);p95=zeros(1,3);sw=zeros(1,3);alias=zeros(1,3);edges=zeros(1,3);
   finite=true(n,1);
   for k=1:3
    q=T{k};x=q.V9B1Error_m(mask);finite=finite & isfinite(x);
    sw(k)=sum(q.V8Switched(mask));alias(k)=sum(q.PbrAliasCount(mask)>1);
    edges(k)=sum(q.PbrNearUpperEdge(mask));
   end
   for k=1:3
    q=T{k};x=q.V9B1Error_m(mask);x=x(finite);
    if isempty(x),rm(k)=NaN;p95(k)=NaN;
    else
     rm(k)=sqrt(mean(x.^2));z=sort(abs(x));p95(k)=z(max(1,ceil(.95*numel(z))));
    end
   end
   rows(end+1,:)={plans{pi},conds{ci},ds(di),n,sum(finite), ...
    rm(1),rm(2),rm(3),p95(1),p95(2),p95(3), ...
    alias(1),alias(2),alias(3),sw(1),sw(2),sw(3),edges(2),edges(3), ...
    sum(abs(T{3}.V9B1Error_m(mask))>abs(T{2}.V9B1Error_m(mask))+1e-10)}; %#ok<AGROW>
  end
 end
end
report=cell2table(rows,'VariableNames',{'Plan','Condition','Distance_m','N','PairedFiniteN', ...
 'RMSE_40m','RMSE_20m','RMSE_22m','P95_40m','P95_20m','P95_22m', ...
 'Alias_40m','Alias_20m','Alias_22m','V8Switch_40m','V8Switch_20m','V8Switch_22m', ...
 'NearUpper_20m','NearUpper_22m','WorseRows_22vs20'});
out=fullfile(root,'results',['v9_B_1_2_compare_' mode '.csv']);
writetable(report,out);
fprintf('PASS V9_B_1_2 paired comparison: %d rows per search range; output %s\n',height(ref),out);
for k=1:3
 q=T{k};v=q.V9B1Error_m;
 fprintf('0-%d m: valid %d/%d, RMSE %.4f m, aliases %d, V8 switched %d\n',bounds(k), ...
 sum(isfinite(v)),height(q),sqrt(mean(v(isfinite(v)).^2)),sum(q.PbrAliasCount>1),sum(q.V8Switched));
end
end
