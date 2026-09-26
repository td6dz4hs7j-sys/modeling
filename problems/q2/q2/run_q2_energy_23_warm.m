function run_q2_energy_23_warm(root)
x=load(fullfile(root,'results','q2_all_ontime','q2_final_solution.mat'),'D','legs');
a=load(fullfile(root,'results','q2_energy_22_23','split_search','q2_split_energy_23.mat'),'best');
D=x.D;legs=x.legs;S0=a.best;
v=validate_q2_solution(D,legs,S0,'RequireAllExpectedOnTime',true);
assert(strcmp(v.status,'PASS')&&S0.metrics.N==23);
out=fullfile(root,'results','q2_energy_22_23','n23_warm');if ~isfolder(out),mkdir(out);end
R=optimize_q2(D,legs,S0,'MaxSeeds',1,'Seeds',20261108, ...
 'MaxRounds',25,'CandidatesPerRound',200,'StagnationRounds',10, ...
 'MinSorties',23,'MaxSorties',23,'Priority',[1 3 2 4], ...
 'Label','energy_n23_warm','OutputDir',out);
S=R.best;V=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true);
assert(strcmp(V.status,'PASS')&&S.metrics.N==23);
save(fullfile(out,'q2_energy_best.mat'),'S','V','R','S0','-v7.3');
fprintf('ENERGY N23 WARM FINAL: E=%.6f Cmax=%.3f\n',S.metrics.energy_kWh,S.metrics.Cmax_s);
end
