function publish_q2_current(root)
% Freeze and publish the current all-on-time makespan-focused Q2 result.
x=load(fullfile(root,'results','q2_all_ontime','q2_final_solution.mat'),'D','legs','baseline');
a=load(fullfile(root,'results','q2_time_23_cap','warm_chain','q2_seed_20261102_checkpoint.mat'),'best','T');
D=x.D;legs=x.legs;S=a.best;baseline=x.baseline;
V=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true);
assert(strcmp(V.status,'PASS')&&S.metrics.N<=23,'Current solution failed strict audit.');
out=fullfile(root,'results','q2_current');if ~isfolder(out),mkdir(out);end
R=struct('seeds',20261102,'trace',a.T,'summary',table(),'statistics',struct());
mutationTests=test_q2_mutations(D,legs,S,'RequireAllExpectedOnTime',true);
assert(height(mutationTests)==13&&all(mutationTests.rejected),'Validator mutation tests failed.');
writetable(mutationTests,fullfile(out,'q2_strict_mutation_tests.csv'));
save(fullfile(out,'q2_current_solution.mat'),'D','legs','S','baseline','V','R','-v7.3');
write_q2_validation(V,fullfile(out,'q2_final_validation.json'));
export_q2_results(D,legs,S,baseline,R,out);
plot_q2_results(D,legs,S,baseline,R,fullfile(root,'figures','q2_current'));
paths={ ...
 fullfile(root,'results','q2_refinement','n21','q2_time_refined.mat'), ...
 fullfile(root,'results','q2_all_ontime','q2_final_solution.mat'), ...
 fullfile(root,'results','q2_time_23_cap','type_chain','q2_type_chain_final.mat'), ...
 fullfile(root,'results','q2_time_24','q2_seed_20261104_checkpoint.mat')};
names={'21架次时间方案';'22架次历史方案';'23架次换机型方案';'24架次探索方案'};
rows=cell(5,7);rows(1,:)={'当前23架次方案',S.metrics.N,S.metrics.Cmax_s,S.metrics.energy_kWh, ...
 sum(S.sorties.operation_s),sum(S.boxDelivery.arrival_s<=S.boxDelivery.expected_s+D.tol.time),string(V.status)};
for i=1:4
 if i==1,z=load(paths{i},'Stime');Q=z.Stime;
 elseif i==2,z=load(paths{i},'S');Q=z.S;
 else,z=load(paths{i},'best');Q=z.best;end
 qv=validate_q2_solution(D,legs,Q,'RequireAllExpectedOnTime',true);
 rows(i+1,:)={names{i},Q.metrics.N,Q.metrics.Cmax_s,Q.metrics.energy_kWh, ...
  sum(Q.sorties.operation_s),sum(Q.boxDelivery.arrival_s<=Q.boxDelivery.expected_s+D.tol.time),string(qv.status)};
end
comparison=cell2table(rows,'VariableNames',{'scenario','sorties','makespan_s','energy_kWh', ...
 'cumulative_operation_s','on_time_boxes','validator'});
writetable(comparison,fullfile(out,'q2_current_comparison.csv'));
disp(comparison);
fprintf('CURRENT FINAL: N=%d Cmax=%.3f E=%.6f W=%.6f PASS=%d\n', ...
 S.metrics.N,S.metrics.Cmax_s,S.metrics.energy_kWh,S.metrics.W,strcmp(V.status,'PASS'));
end
