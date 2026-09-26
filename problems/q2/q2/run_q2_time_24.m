function run_q2_time_24(root)
% One extra sortie is allowed only when it improves makespan with all 80 on time.
x=load(fullfile(root,'results','q2_all_ontime','q2_final_solution.mat'),'D','legs');
a=load(fullfile(root,'results','q2_time_23_cap','warm_chain','q2_seed_20261102_checkpoint.mat'),'best');
D=x.D;legs=x.legs;S0=a.best;
v=validate_q2_solution(D,legs,S0,'RequireAllExpectedOnTime',true);
assert(strcmp(v.status,'PASS')&&S0.metrics.N==23,'23-sortie warm start invalid.');
out=fullfile(root,'results','q2_time_24');if ~isfolder(out),mkdir(out);end
R=optimize_q2(D,legs,S0,'MaxSeeds',2,'Seeds',[20261104 20261105], ...
 'MaxRounds',40,'CandidatesPerRound',200,'StagnationRounds',12,'MaxSorties',24, ...
 'Priority',[1 2 3 4],'Label','time_cap24','OutputDir',out);
best=R.best;V=validate_q2_solution(D,legs,best,'RequireAllExpectedOnTime',true);
assert(strcmp(V.status,'PASS')&&best.metrics.N<=24,'24-cap result fails strict audit.');
save(fullfile(out,'q2_time_cap24_final.mat'),'best','V','R','-v7.3');
fprintf('TIME CAP24 FINAL: N=%d Cmax=%.3f E=%.6f; below_7200=%d\n', ...
 best.metrics.N,best.metrics.Cmax_s,best.metrics.energy_kWh,best.metrics.Cmax_s<=7200+D.tol.time);
end
