function verify_q2_github_bundle(root)
% Revalidate all four published schedules from fresh locally supplied inputs.
if nargin<1,root=fileparts(fileparts(mfilename('fullpath')));end
D=load_q2_data(root);D.parallelPrepLoad=true;
[legs,~]=build_q2_leg_cache(D,root,false);
keys=["sortie_priority","time_priority","energy_priority","balanced"];
rows=cell(4,6);
for i=1:numel(keys)
 p=fullfile(root,'results','q2_strategy_scenarios',keys(i)+"_best_pass.mat");
 x=load(p,'best');S=x.best;
 V=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true, ...
 'AllowPrepBatteryOverlap',true,'AllowFixedPrepPrestage',true);
 assert(strcmp(V.status,'PASS'),'%s: %s',keys(i),strjoin(cellstr(V.issues),'; '));
 rows(i,:)={keys(i),V.routeCount,V.independentMetrics.Cmax_s/60, ...
 V.independentMetrics.energy_kWh,V.deliveredBoxes,string(V.status)};
end
T=cell2table(rows,'VariableNames',{'strategy','sorties','Cmax_min','energy_kWh','boxes','validator'});
writetable(T,fullfile(root,'results','q2_strategy_scenarios','fresh_bundle_validation.csv'));
disp(T);
end
