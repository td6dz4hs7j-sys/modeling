function run_q2_more(root)
% Additional fixed-budget search from the frozen, strictly valid 24-sortie solution.
src=fullfile(root,'results','q2_all_ontime','q2_final_solution.mat');
x=load(src,'D','legs','S'); D=x.D;legs=x.legs;S0=x.S;
v0=validate_q2_solution(D,legs,S0,'RequireAllExpectedOnTime',true);
assert(strcmp(v0.status,'PASS'),'Frozen input did not pass strict audit.');
out=fullfile(root,'results','q2_more_search');if ~isfolder(out),mkdir(out);end
R=optimize_q2(D,legs,S0,'MaxSeeds',4, ...
 'Seeds',[20261008 20261009 20261010 20261011], ...
 'MaxRounds',40,'CandidatesPerRound',200,'StagnationRounds',20, ...
 'Priority',[1 4 2 3],'Label','q2_more','OutputDir',out);
S=R.best;V=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true);
assert(strcmp(V.status,'PASS'),'Additional search failed strict validator.');
save(fullfile(out,'q2_more_final.mat'),'S','R','V','-v7.3');
writetable(R.summary,fullfile(out,'q2_more_summary.csv'));
writetable(R.trace,fullfile(out,'q2_more_trace.csv'));
fprintf('MORE SEARCH FINAL: N=%d W=%.6f Cmax=%.3f E=%.6f\n', ...
 S.metrics.N,S.metrics.W,S.metrics.Cmax_s,S.metrics.energy_kWh);
end
