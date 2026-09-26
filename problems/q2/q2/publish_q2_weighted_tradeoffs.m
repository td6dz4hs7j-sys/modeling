function publish_q2_weighted_tradeoffs(root)
out=fullfile(root,'results','q2_weighted_verified');x=load(fullfile(out,'q2_weighted_final.mat'));
D=x.D;legs=x.legs;archive=x.archive;
extra=fullfile(out,'balanced_refine','q2_weighted_final.mat');
if isfile(extra)
 b=load(extra,'archive','D');assert(abs(b.D.g-D.g)<1e-12);
 archive=[archive(:);b.archive(:)];
end
t=cellfun(@(s)s.metrics.Cmax_s,archive);e=cellfun(@(s)s.metrics.energy_kWh,archive);
writetable(table(t(:)/60,e(:),'VariableNames',{'makespan_min','energy_kWh'}),fullfile(out,'pareto_front.csv'));
[~,order]=sortrows([t(:),e(:)],[1 2]);fast=order(1);eligible=find(t<=7200+D.tol.time);[~,p]=min(e(eligible));balanced=eligible(p);
eligible=find(e<=67.14+D.tol.energy);if isempty(eligible),[~,energy]=min(e);else,[~,p]=min(t(eligible));energy=eligible(p);end
[~,compromise]=min(.55*t/5640+.45*e/67.14);
ids=[fast compromise balanced energy];names={'fastest','balanced','within120','energy6714'};rows=cell(4,8);
for k=1:4
 S=archive{ids(k)};V=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true);assert(strcmp(V.status,'PASS'));
 branch=fullfile(out,names{k});if ~isfolder(branch),mkdir(branch);end
 tests=test_q2_mutations(D,legs,S,'RequireAllExpectedOnTime',true);assert(all(tests.rejected));
 writetable(tests,fullfile(branch,'q2_strict_mutation_tests.csv'));
 write_q2_validation(V,fullfile(branch,'q2_final_validation.json'));
 save(fullfile(branch,'solution.mat'),'S','V','-v7.3');
 export_q2_results(D,legs,S,x.S,struct('summary',table(),'trace',table()),branch);
 rows(k,:)={names{k},23,t(ids(k))/60,e(ids(k)),sum(S.sorties.operation_s)/3600,80,D.g,string(V.status)};
end
writetable(cell2table(rows,'VariableNames',{'choice','sorties','makespan_min','energy_kWh','cumulative_operation_h','on_time_boxes','g','validator'}),fullfile(out,'recommended_tradeoffs.csv'));
disp(cell2table(rows));
end
