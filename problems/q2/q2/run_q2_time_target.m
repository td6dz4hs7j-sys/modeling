function run_q2_time_target(root)
% Search solely for earliest all-on-time makespan, allowing extra sorties.
x=load(fullfile(root,'results','q2_all_ontime','q2_final_solution.mat'),'D','legs');
a=load(fullfile(root,'results','q2_all_ontime','q2_validated_alternatives.mat'),'Stime');
b=load(fullfile(root,'results','q2_opt_main','q2_seed_20260927_best.mat'),'best');
D=x.D;legs=x.legs;out=fullfile(root,'results','q2_time_target');
if ~isfolder(out),mkdir(out);end
starts={a.Stime,b.best};seeds={[20261022 20261023],[20261024 20261025]};
results=cell(2,1);best=[];origin=0;
for run=1:2
 v=validate_q2_solution(D,legs,starts{run},'RequireAllExpectedOnTime',true);
 assert(strcmp(v.status,'PASS'),'Time search start %d failed strict validation.',run);
 R=optimize_q2(D,legs,starts{run},'MaxSeeds',2,'Seeds',seeds{run}, ...
  'MaxRounds',40,'CandidatesPerRound',200,'StagnationRounds',20, ...
  'Priority',[1 2 3 4],'Label',sprintf('time_target_%d',run), ...
  'OutputDir',fullfile(out,sprintf('start_%d',run)));
 results{run}=R;
 c=R.best;v=validate_q2_solution(D,legs,c,'RequireAllExpectedOnTime',true);
 assert(strcmp(v.status,'PASS'),'Time search result %d failed strict validation.',run);
 if isempty(best)||c.metrics.Cmax_s<best.metrics.Cmax_s-D.tol.time
  best=c;origin=run;
 end
 save(fullfile(out,sprintf('q2_start_%d_final.mat',run)),'R','c','v','-v7.3');
 fprintf('TIME TARGET START %d: N=%d Cmax=%.3f E=%.6f\n', ...
  run,c.metrics.N,c.metrics.Cmax_s,c.metrics.energy_kWh);
end
V=validate_q2_solution(D,legs,best,'RequireAllExpectedOnTime',true);
save(fullfile(out,'q2_time_target_final.mat'),'best','V','origin','results','-v7.3');
fprintf('TIME TARGET FINAL: N=%d Cmax=%.3f E=%.6f; target_5400_reached=%d\n', ...
 best.metrics.N,best.metrics.Cmax_s,best.metrics.energy_kWh,best.metrics.Cmax_s<=5400+D.tol.time);
end
