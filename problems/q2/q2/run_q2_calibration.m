function run_q2_calibration
root=fileparts(fileparts(mfilename('fullpath')));
x=load(fullfile(root,'results/q2/q2_solution.mat'),'D','legs','S');
audit_q2_fast_decoder(x.D,x.legs,x.S);
R=optimize_q2(x.D,x.legs,x.S,'MaxSeeds',1,'MaxRounds',1,'CandidatesPerRound',20,'Label','calibration');
disp(R.summary);disp(R.trace);
end
