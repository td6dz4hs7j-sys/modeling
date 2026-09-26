function publish_q2_more(root)
% Promote only a strictly valid improvement from the additional search.
out=fullfile(root,'results','q2_all_ontime');
previousPath=fullfile(out,'q2_final_solution.mat');
old=load(previousPath);
deepPath=fullfile(root,'results','q2_deeper_search','q2_deeper_final.mat');
if isfile(deepPath)
 more=load(deepPath,'S','R');S=more.S;R=more.R;
else
 more=load(fullfile(root,'results','q2_more_search','q2_seed_20261008_best.mat'),'best');
 S=more.best;R=struct('seeds',20261008,'summary',table(),'trace',table());
end
newFiles={fullfile(root,'results','q2_refinement','q2_time_refined.mat'), ...
 fullfile(root,'results','q2_refinement','q2_energy_refined.mat'), ...
 fullfile(root,'results','q2_refinement','n21','q2_time_refined.mat'), ...
 fullfile(root,'results','q2_refinement','n21','q2_energy_refined.mat')};
for k=1:numel(newFiles)
 if ~isfile(newFiles{k}),continue;end
 a=load(newFiles{k});if isfield(a,'Stime'),candidate=a.Stime;candidateR=a.Rt;
 else,candidate=a.Senergy;candidateR=a.Re;end
 key=[candidate.metrics.W,candidate.metrics.N,candidate.metrics.Cmax_s,candidate.metrics.energy_kWh];
 bestKey=[S.metrics.W,S.metrics.N,S.metrics.Cmax_s,S.metrics.energy_kWh];
 if lexLess(key,bestKey),S=candidate;R=candidateR;end
end
D=old.D;legs=old.legs;
V=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true);
assert(strcmp(V.status,'PASS'),'New solution failed strict validator.');
improved=S.metrics.N<old.S.metrics.N || ...
 (S.metrics.N==old.S.metrics.N && ...
  (S.metrics.Cmax_s<old.S.metrics.Cmax_s-D.tol.time || ...
   (abs(S.metrics.Cmax_s-old.S.metrics.Cmax_s)<=D.tol.time && ...
    S.metrics.energy_kWh<old.S.metrics.energy_kWh-D.tol.energy)));
same=S.metrics.N==old.S.metrics.N && ...
 abs(S.metrics.Cmax_s-old.S.metrics.Cmax_s)<=D.tol.time && ...
 abs(S.metrics.energy_kWh-old.S.metrics.energy_kWh)<=D.tol.energy;
assert(improved||same,'Additional search did not improve or reproduce the final solution.');
if improved
 backup=fullfile(out,sprintf('q2_previous_%d_solution.mat',old.S.metrics.N));
 if ~isfile(backup),copyfile(previousPath,backup,'f');end
end

baseline=old.baseline;cacheMeta=old.cacheMeta;construction=old.construction;
inheritance=old.inheritance;environment=old.environment;
mutationTests=test_q2_mutations(D,legs,S,'RequireAllExpectedOnTime',true);
assert(all(mutationTests.rejected),'Strict mutation battery has a missed case.');
writetable(mutationTests,fullfile(out,'q2_strict_mutation_tests.csv'));
save(previousPath,'D','legs','S','baseline','R','V','cacheMeta', ...
 'construction','inheritance','environment','-v7.3');
write_q2_validation(V,fullfile(out,'q2_final_validation.json'));
export_q2_results(D,legs,S,baseline,R,out);
plot_q2_results(D,legs,S,baseline,R,fullfile(root,'figures','q2_all_ontime'));
fprintf('FINAL STRICT PASS: N=%d W=%.6f Cmax=%.3f E=%.6f\n', ...
 S.metrics.N,S.metrics.W,S.metrics.Cmax_s,S.metrics.energy_kWh);
end

function tf=lexLess(a,b)
tf=false;
for i=1:numel(a)
 if a(i)<b(i)-1e-9,tf=true;return;
 elseif a(i)>b(i)+1e-9,return;end
end
end
