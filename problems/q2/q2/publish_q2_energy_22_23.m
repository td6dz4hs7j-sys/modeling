function publish_q2_energy_22_23(root)
% Export both strictly validated fixed-sortie energy schedules.
x=load(fullfile(root,'results','q2_all_ontime','q2_final_solution.mat'),'D','legs','baseline');
D=x.D;legs=x.legs;baseline=x.baseline;
src={fullfile(root,'results','q2_energy_22_23','n22_warm','q2_energy_best.mat'), ...
 fullfile(root,'results','q2_energy_22_23','n23_warm','q2_energy_best.mat')};
rows=cell(2,8);
for k=1:2
 a=load(src{k},'S','R');S=a.S;R=a.R;
 target=21+k;assert(S.metrics.N==target);
 V=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true);
 assert(strcmp(V.status,'PASS'),'Energy solution failed strict audit.');
 out=fullfile(root,'results','q2_energy_22_23',sprintf('published_n%d',target));
 if ~isfolder(out),mkdir(out);end
 tests=test_q2_mutations(D,legs,S,'RequireAllExpectedOnTime',true);
 assert(height(tests)==13&&all(tests.rejected));
 writetable(tests,fullfile(out,'q2_strict_mutation_tests.csv'));
 save(fullfile(out,'q2_energy_solution.mat'),'S','V','R','-v7.3');
 write_q2_validation(V,fullfile(out,'q2_final_validation.json'));
 export_q2_results(D,legs,S,baseline,R,out);
 rows(k,:)={target,S.metrics.energy_kWh,S.metrics.Cmax_s,S.metrics.Cmax_s/60, ...
  sum(S.sorties.operation_s)/3600,height(S.boxDelivery), ...
  sum(S.boxDelivery.arrival_s<=S.boxDelivery.expected_s+D.tol.time),string(V.status)};
end
comparison=cell2table(rows,'VariableNames',{'sorties','energy_kWh','makespan_s', ...
 'makespan_min','cumulative_operation_h','delivered_boxes','on_time_boxes','validator'});
writetable(comparison,fullfile(root,'results','q2_energy_22_23','final_energy_comparison.csv'));
disp(comparison);
end
