function choice=combineV9B(base,v8,v3,v7)
%COMBINEV9B Transparent priority logic, diagnostic experiment only.
% No scenario name, SNR truth or actual distance are used.
choice=struct('selectedM',base.fusedM,'usePbr',false, ...
 'useTwoPath',false,'reason','periodic_baseline');
if v8.usePbr && isfinite(v8.selectedM)
 choice.selectedM=v8.selectedM;
 choice.usePbr=true;
 choice.reason='v8_pbr_conflict';
elseif v7.useTwoPath && isfinite(v7.selectedM)
 choice.selectedM=v7.selectedM;
 choice.useTwoPath=true;
 choice.reason=['v7_' v7.reason];
elseif v3.useTwoPath && isfinite(v3.selectedM)
 choice.selectedM=v3.selectedM;
 choice.useTwoPath=true;
 choice.reason='v3_two_path';
end
end
