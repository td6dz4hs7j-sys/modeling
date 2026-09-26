function review_q2_parallel_forms(root)
% Independent fresh-source audit of both saved parallel-timing schedules.
if nargin < 1, root=fileparts(fileparts(mfilename('fullpath'))); end
D=load_q2_data(root); D.parallelPrepLoad=true;
[legs,~]=build_q2_leg_cache(D,root,false);
folder=fullfile(root,'results','q2_parallel_forms');
a=load(fullfile(folder,'best_pass.mat'),'best');
b=load(fullfile(folder,'best_22_pass.mat'),'best22');
plans={a.best,b.best22}; names={"fastest_23","fewer_sorties_22"};
rows=cell(2,5);
for i=1:2
 S=plans{i}; V=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true);
 assert(strcmp(V.status,'PASS'),strjoin(cellstr(V.issues),'; '));
 assert(V.deliveredBoxes==80 && V.routeCount==24-i);
 assert(all(S.boxDelivery.arrival_s<=S.boxDelivery.expected_s+D.tol.time));
 rows(i,:)={names{i},V.routeCount,V.independentMetrics.Cmax_s/60, ...
   V.independentMetrics.energy_kWh,V.deliveredBoxes};
 fprintf('INDEPENDENT_FORMS PASS %s N=%d Cmax_min=%.9f E_kWh=%.9f boxes=%d\n', ...
  names{i},V.routeCount,V.independentMetrics.Cmax_s/60, ...
  V.independentMetrics.energy_kWh,V.deliveredBoxes);
end
T=cell2table(rows,'VariableNames',{'scenario','sorties','completion_min','energy_kWh','boxes_on_time'});
writetable(T,fullfile(folder,'independent_comparison.csv'));
end
