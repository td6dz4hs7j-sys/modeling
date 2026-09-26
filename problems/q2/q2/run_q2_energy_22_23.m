function run_q2_energy_22_23(root)
% Fixed-sortie energy search, with 80 expected-time deadlines enforced.
x=load(fullfile(root,'results','q2_all_ontime','q2_final_solution.mat'),'D','legs','S');
D=x.D;legs=x.legs;
out=fullfile(root,'results','q2_energy_22_23');if ~isfolder(out),mkdir(out);end
a=load(fullfile(root,'results','q2_refinement','q2_energy_refined.mat'),'Senergy');
b=load(fullfile(root,'results','q2_current','q2_current_solution.mat'),'S');
starts22={x.S,a.Senergy};starts23={b.S};
starts={starts22,starts23};targets=[22 23];seeds=[20261106 20261107];
rows=cell(2,7);
for k=1:2
 target=targets(k);candidates=starts{k};S0=[];
 for j=1:numel(candidates)
  q=candidates{j};v=validate_q2_solution(D,legs,q,'RequireAllExpectedOnTime',true);
  if strcmp(v.status,'PASS')&&q.metrics.N==target&& ...
    (isempty(S0)||q.metrics.energy_kWh<S0.metrics.energy_kWh)
   S0=q;
  end
 end
 assert(~isempty(S0),'No valid start for %d sorties.',target);
 branch=fullfile(out,sprintf('n%d',target));if ~isfolder(branch),mkdir(branch);end
 fprintf('ENERGY N%d START: Cmax=%.3f E=%.6f\n',target,S0.metrics.Cmax_s,S0.metrics.energy_kWh);
 R=optimize_q2(D,legs,S0,'MaxSeeds',1,'Seeds',seeds(k), ...
  'MaxRounds',40,'CandidatesPerRound',200,'StagnationRounds',12, ...
  'MinSorties',target,'MaxSorties',target,'Priority',[1 3 2 4], ...
  'Label',sprintf('energy_n%d',target),'OutputDir',branch);
 S=R.best;V=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true);
 assert(strcmp(V.status,'PASS')&&S.metrics.N==target,'N%d result fails strict audit.',target);
 save(fullfile(branch,'q2_energy_best.mat'),'S','V','R','S0','-v7.3');
 rows(k,:)={target,S0.metrics.energy_kWh,S.metrics.energy_kWh,S.metrics.Cmax_s, ...
  sum(S.sorties.operation_s),sum(S.boxDelivery.arrival_s<=S.boxDelivery.expected_s+D.tol.time),string(V.status)};
 fprintf('ENERGY N%d FINAL: Cmax=%.3f E=%.6f W=%.6f\n', ...
  target,S.metrics.Cmax_s,S.metrics.energy_kWh,S.metrics.W);
end
comparison=cell2table(rows,'VariableNames',{'sorties','initial_energy_kWh', ...
 'best_energy_kWh','makespan_s','cumulative_operation_s','on_time_boxes','validator'});
writetable(comparison,fullfile(out,'q2_energy_22_23_comparison.csv'));
disp(comparison);
end
