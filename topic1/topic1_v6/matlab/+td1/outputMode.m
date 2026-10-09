function mode = outputMode(est)
%OUTPUTMODE Distinguish joint fusion, RTT fallback, PBR fallback and failure.
% A finite PBR-only experimental result is not an RTT fallback.
if ~isfinite(est.fusedM)
    mode='unavailable';
elseif est.fusionValid
    mode='joint_fusion';
elseif strcmp(est.status,'pbr_only_on_disagreement_experimental')
    mode='pbr_only';
else
    mode='rtt_only';
end
end
