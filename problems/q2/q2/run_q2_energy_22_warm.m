function run_q2_energy_22_warm(root)
x=load(fullfile(root,'results','q2_all_ontime','q2_final_solution.mat'),'D','legs');
a=load(fullfile(root,'results','q2_energy_22_23','n22','q2_energy_best.mat'),'S');
D=x.D;legs=x.legs;S0=a.S;
v=validate_q2_solution(D,legs,S0,'RequireAllExpectedOnTime',true);
assert(strcmp(v.status,'PASS')&&S0.metrics.N==22);
out=fullfile(root,'results','q2_energy_22_23','n22_warm');if ~isfolder(out),mkdir(out);end
R=optimize_q2(D,legs,S0,'MaxSeeds',1,'Seeds',20261109, ...
 'MaxRounds',25,'CandidatesPerRound',200,'StagnationRounds',10, ...
 'MinSorties',22,'MaxSorties',22,'Priority',[1 3 2 4], ...
 'Label','energy_n22_warm','OutputDir',out);
S=R.best;V=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true);
assert(strcmp(V.status,'PASS')&&S.metrics.N==22);
save(fullfile(out,'q2_energy_best.mat'),'S','V','R','S0','-v7.3');
fprintf('ENERGY N22 WARM FINAL: E=%.6f Cmax=%.3f\n',S.metrics.energy_kWh,S.metrics.Cmax_s);
end
