function review_q2_overlap_independent(root)
% Reload all sources and verify both timing interpretations and saved solutions.
if nargin<1,root=fileparts(fileparts(mfilename('fullpath')));end
D=load_q2_data(root);D.parallelPrepLoad=true;
[legs,~]=build_q2_leg_cache(D,root,false);
folder=fullfile(root,'results','q2_overlap');
z23=load(fullfile(folder,'best_23_pass.mat'),'best');
z22=load(fullfile(folder,'best_22_pass.mat'),'best22');
plans={z23.best,z22.best22};
rows=cell(2,6);
for i=1:2
 S=plans{i};
 V=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true,'AllowPrepBatteryOverlap',true);
 assert(strcmp(V.status,'PASS'),strjoin(cellstr(V.issues),'; '));
 assert(V.routeCount==24-i && V.deliveredBoxes==80);
 routes=repmat(struct('boxIdx',[],'nodeOrder',[],'typeIdx',0),numel(S.routes),1);
 for j=1:numel(S.routes)
  routes(j)=struct('boxIdx',S.routes(j).boxIdx,'nodeOrder',S.routes(j).nodeOrder,'typeIdx',S.routes(j).typeIdx);
 end
 [old,st]=schedule_q2_routes(D,legs,routes);
 assert(st.feasible);
 V0=validate_q2_solution(D,legs,old,'RequireAllExpectedOnTime',true);
 assert(strcmp(V0.status,'PASS'),strjoin(cellstr(V0.issues),'; '));
 rows(i,:)={V.routeCount,V.independentMetrics.Cmax_s/60,V0.independentMetrics.Cmax_s/60, ...
  (V0.independentMetrics.Cmax_s-V.independentMetrics.Cmax_s)/60,V.independentMetrics.energy_kWh,V.deliveredBoxes};
 fprintf('OVERLAP_INDEPENDENT PASS N=%d new=%.9f min same_routes_old=%.9f min E=%.9f boxes=%d\n', ...
  V.routeCount,V.independentMetrics.Cmax_s/60,V0.independentMetrics.Cmax_s/60,V.independentMetrics.energy_kWh,V.deliveredBoxes);
end
T=cell2table(rows,'VariableNames',{'sorties','overlap_completion_min','prior_timing_same_routes_min','reduction_min','energy_kWh','boxes_on_time'});
writetable(T,fullfile(folder,'independent_comparison.csv'));
end
