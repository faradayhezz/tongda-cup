function result = run_v9_A_1_sanity(seed)
% Minimal controlled calibration test: no echo, high SNR, two target ranges.
% Reference distance is known; target distance is used ONLY for scoring.
if nargin<1,seed=20271119;end
oldRng=rng;restore=onCleanup(@()rng(oldRng)); %#ok<NASGU>
rng(seed,'twister');
cfg=td1.defaultConfig();
scene=cfg.scenarios(1);scene.name='LOS_calibration_unit_test';
scene.fHz=cfg.toneAnchorHz+(0:2:32)'*1e6;
scene.phaseResidualRad=zeros(numel(scene.fHz),1);
scene.echoAmplitude=0;scene.echoDelayS=0;scene.randomHopPhase=false;
scene.phaseNoiseRad=0;scene.cfoHz=0;
scene.hwDelayS=16e-9;scene.clockAppm=0;scene.clockBppm=0;
scene.driftClockBppm=0;scene.driftDelayS=0;
prep=td1.prepare(cfg,scene);rx=td1.receiverConfig(prep);
refDist=cfg.calibrationDistanceM;refN=8;snrDb=60;
% t=0 baseline, t=end 16ns delay drift. Compare legacy vs shared-hardware.
scene.referenceTracksDrift=true;
calInitial=makeReference(scene);
scene.driftDelayS=16e-9;
calUpdated=makeReference(scene);
scene.referenceTracksDrift=false;
calLegacy=makeReference(scene);
rows=struct('Distance_m',{},'FixedError_m',{},'UpdatedError_m',{},...
 'LegacyError_m',{},'FixedRttError_m',{},'UpdatedRttError_m',{},...
 'FixedPbrError_m',{},'UpdatedPbrError_m',{});
for d=[3,15]
    obs=td1.observe(td1.simulate(d,snrDb,scene,prep,false),rx);
    fixed=td1.estimate(obs,calInitial,rx);
    updated=td1.estimate(obs,calUpdated,rx);
    legacy=td1.estimate(obs,calLegacy,rx);
    rows(end+1)=struct('Distance_m',d,...
      'FixedError_m',fixed.fusedM-d,'UpdatedError_m',updated.fusedM-d,...
      'LegacyError_m',legacy.fusedM-d,...
      'FixedRttError_m',fixed.rttM-d,'UpdatedRttError_m',updated.rttM-d,...
      'FixedPbrError_m',fixed.pbrM-d,'UpdatedPbrError_m',updated.pbrM-d); %#ok<AGROW>
end
result=struct2table(rows);
root=fileparts(mfilename('fullpath'));
out=fullfile(root,'results','v9_A_1_sanity');
if ~exist(out,'dir'),mkdir(out);end
writetable(result,fullfile(out,'v9_A_1_sanity.csv'));
fprintf('V9_A_1 sanity check (high SNR, LOS, 16ns drift):\n');disp(result);
fprintf('Calibration RTT bias initial %.4f, updated %.4f, legacy %.4f m\n',...
 calInitial.rttBiasM,calUpdated.rttBiasM,calLegacy.rttBiasM);
if any(~isfinite([result.FixedError_m;result.UpdatedError_m;result.LegacyError_m]))
 error('V9_A_1:Nonfinite','Sanity test produced nonfinite estimates.');
end
if abs(calUpdated.rttBiasM-calInitial.rttBiasM)<0.1
 warning('V9_A_1:CalibrationBlind','Updated reference did not visibly track delay drift.');
end
    function cal=makeReference(sceneReference)
        features=[];
        for k=1:refN
            raw=td1.simulate(refDist,snrDb,sceneReference,prep,true);
            one=td1.observe(raw,rx);
            if k==1,features=repmat(one,refN,1);end
            features(k)=one;
        end
        cal=td1.calibrate(features,repmat(refDist,refN,1),rx);
    end
end
