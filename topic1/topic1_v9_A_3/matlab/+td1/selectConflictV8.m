function choice = selectConflictV8(base, policy)
%SELECTCONFLICTV8 Experimental independent RTT/PBR conflict decision.
% Uses receiver features only; never sees true distance, scene or simulated SNR.
% A coherent but non-perfect phase response can arise from multipath;
% this is only a heuristic, NOT a certified RTT bias detector.
if nargin < 2 || isempty(policy), policy=struct(); end
choice=struct('selectedM',base.fusedM,'usePbr',false, ...
    'reason','retain_original','phaseQuality',base.pbrCoherence);
if ~isfinite(base.fusedM) || ~isfinite(base.pbrM)
    choice.reason='invalid_measurement'; return;
end
if ~strcmp(base.status,'range_phase_disagreement_rtt_only')
    choice.reason='no_eligible_disagreement'; return;
end
if ~base.pbrValid || base.pbrAmbiguous || numel(base.aliasCandidatesM)~=1
    choice.reason='invalid_or_ambiguous_pbr'; return;
end
if ~isfinite(base.innovationSigma) || base.innovationSigma<=3
    choice.reason='small_innovation'; return;
end
coh=base.pbrCoherence;
if ~(isfinite(coh) && coh>=getOpt(policy,'minCoherence',0.70) && ...
        coh<getOpt(policy,'maxCoherence',0.97))
    choice.reason='phase_quality_not_multipath_like'; return;
end
% Never use the phase estimate outside the declared range; the estimate
% itself already checks CFO/phase calibration validity.
if ~isfinite(base.pbrM) || base.pbrM<0 || base.pbrM>40
    choice.reason='out_of_range'; return;
end
choice.selectedM=base.pbrM;
choice.usePbr=true;
choice.reason='unique_pbr_conflict_candidate_experimental';
end
function v=getOpt(s,key,default)
if isfield(s,key),v=s.(key);else,v=default;end
end
