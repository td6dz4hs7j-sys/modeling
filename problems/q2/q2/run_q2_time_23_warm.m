function run_q2_time_23_warm(root)
% Continue makespan descent from a verified 23-sortie all-on-time checkpoint.
x=load(fullfile(root,'results','q2_all_ontime','q2_final_solution.mat'),'D','legs');
a=load(fullfile(root,'results','q2_time_23_cap','type_chain','q2_type_chain_final.mat'),'best');
D=x.D;legs=x.legs;S0=a.best;
v=validate_q2_solution(D,legs,S0,'RequireAllExpectedOnTime',true);
assert(strcmp(v.status,'PASS')&&S0.metrics.N<=23,'Time checkpoint fails strict audit.');
out=fullfile(root,'results','q2_time_23_cap','warm_chain');if ~isfolder(out),mkdir(out);end
R=optimize_q2(D,legs,S0,'MaxSeeds',2,'Seeds',[20261102 20261103], ...
 'MaxRounds',40,'CandidatesPerRound',200,'StagnationRounds',12,'MaxSorties',23, ...
 'Priority',[1 2 3 4],'Label','time_cap23_warm','OutputDir',out);
best=R.best;V=validate_q2_solution(D,legs,best,'RequireAllExpectedOnTime',true);
assert(strcmp(V.status,'PASS')&&best.metrics.N<=23,'Warm result fails strict audit.');
save(fullfile(out,'q2_time_cap23_warm_final.mat'),'best','V','R','-v7.3');
fprintf('TIME CAP23 WARM FINAL: N=%d Cmax=%.3f E=%.6f; below_7200=%d\n', ...
 best.metrics.N,best.metrics.Cmax_s,best.metrics.energy_kWh,best.metrics.Cmax_s<=7200+D.tol.time);
end
