function run_q2_time_23_cap(root)
% Earliest all-on-time schedule with no more than 23 sorties.
x=load(fullfile(root,'results','q2_all_ontime','q2_final_solution.mat'),'D','legs');
a=load(fullfile(root,'results','q2_refinement','q2_time_refined.mat'),'Stime');
b=load(fullfile(root,'results','q2_more_search','q2_seed_20261009_checkpoint.mat'),'best');
D=x.D;legs=x.legs;out=fullfile(root,'results','q2_time_23_cap');
if ~isfolder(out),mkdir(out);end
starts={a.Stime,b.best};seeds={[20261026 20261027],[20261028 20261029]};
best=[];origin=0;
for run=1:2
 s=starts{run};v=validate_q2_solution(D,legs,s,'RequireAllExpectedOnTime',true);
 assert(strcmp(v.status,'PASS')&&s.metrics.N<=23,'Start %d fails strict or sortie cap.',run);
 R=optimize_q2(D,legs,s,'MaxSeeds',2,'Seeds',seeds{run}, ...
  'MaxRounds',40,'CandidatesPerRound',200,'StagnationRounds',20, ...
  'MaxSorties',23,'Priority',[1 2 3 4], ...
  'Label',sprintf('time_cap23_%d',run),'OutputDir',fullfile(out,sprintf('start_%d',run)));
 candidate=R.best;V=validate_q2_solution(D,legs,candidate,'RequireAllExpectedOnTime',true);
 assert(strcmp(V.status,'PASS')&&candidate.metrics.N<=23,'Constrained search failed audit.');
 save(fullfile(out,sprintf('q2_start_%d_final.mat',run)),'candidate','V','R','-v7.3');
 if isempty(best)||candidate.metrics.Cmax_s<best.metrics.Cmax_s-D.tol.time
  best=candidate;origin=run;
 end
 fprintf('TIME CAP23 START %d: N=%d Cmax=%.3f E=%.6f\n', ...
  run,candidate.metrics.N,candidate.metrics.Cmax_s,candidate.metrics.energy_kWh);
end
V=validate_q2_solution(D,legs,best,'RequireAllExpectedOnTime',true);
save(fullfile(out,'q2_time_cap23_final.mat'),'best','V','origin','-v7.3');
fprintf('TIME CAP23 FINAL: N=%d Cmax=%.3f E=%.6f; target_5400_reached=%d\n', ...
 best.metrics.N,best.metrics.Cmax_s,best.metrics.energy_kWh,best.metrics.Cmax_s<=5400+D.tol.time);
end
