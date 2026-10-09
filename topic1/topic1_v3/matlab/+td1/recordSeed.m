function value = recordSeed(seed,plan,condition,snrIndex,episode,timeStep,stream,sample)
%RECORDSEED Deterministic context mixing, independent of update/search policy.
% Avoid additive episode/time aliases. Audit tests check uniqueness across
% the actual experiment grid. This is a seed mixer, not a hardware clock.
keys=[seed plan condition snrIndex episode timeStep stream sample];
validateattributes(keys,{'numeric'},{'real','finite','integer','nonnegative','<=',2^32-1});
value=mod(seed,2^32);
for k=2:numel(keys)
    % Products stay below 2^53, so double integer arithmetic is exact.
    value=mod(value*1664525+keys(k)+1013904223,2^32);
end
end
