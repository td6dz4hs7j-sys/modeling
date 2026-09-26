function run_q2_deeper(root)
% Further bounded search from the best strictly on-time result of q2_more.
x=load(fullfile(root,'results','q2_all_ontime','q2_final_solution.mat'),'D','legs');
a=load(fullfile(root,'results','q2_more_search','q2_seed_20261008_best.mat'),'best');
D=x.D;legs=x.legs;S0=a.best;
v=validate_q2_solution(D,legs,S0,'RequireAllExpectedOnTime',true);
assert(strcmp(v.status,'PASS'),'Input to deeper search is not strictly feasible.');
out=fullfile(root,'results','q2_deeper_search');if ~isfolder(out),mkdir(out);end
R=optimize_q2(D,legs,S0,'MaxSeeds',2,'Seeds',[20261012 20261013], ...
 'MaxRounds',40,'CandidatesPerRound',200,'StagnationRounds',20, ...
 'Priority',[1 4 2 3],'Label','q2_deeper','OutputDir',out);
S=R.best;V=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true);
assert(strcmp(V.status,'PASS'),'Deeper search candidate failed strict validator.');
save(fullfile(out,'q2_deeper_final.mat'),'S','R','V','-v7.3');
writetable(R.summary,fullfile(out,'q2_deeper_summary.csv'));
writetable(R.trace,fullfile(out,'q2_deeper_trace.csv'));
fprintf('DEEPER SEARCH FINAL: N=%d W=%.6f Cmax=%.3f E=%.6f\n', ...
 S.metrics.N,S.metrics.W,S.metrics.Cmax_s,S.metrics.energy_kWh);
end
