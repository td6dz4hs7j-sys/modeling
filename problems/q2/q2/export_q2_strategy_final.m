function export_q2_strategy_final()
% Export the verified balanced Q2 strategy into the official result template.
root=fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root,'q2'),fullfile(root,'common'),fullfile(root,'utils'));
out=fullfile(root,'results','q2_strategy_scenarios');
source=fullfile(out,'balanced_best_pass.mat');
x=load(source);assert(isfield(x,'best'),'Balanced MAT has no best solution');S=x.best;
D=load_q2_data(root);D.parallelPrepLoad=true;
y=load(fullfile(root,'cache','leg_cache.mat'),'legs');legs=y.legs;
V=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true, ...
 'AllowPrepBatteryOverlap',true,'AllowFixedPrepPrestage',true);
assert(strcmp(V.status,'PASS'),'Q2 balanced solution failed strict validation');
assert(V.deliveredBoxes==80&&V.routeCount==23&&V.independentMetrics.W<=D.tol.time);
dest=fullfile(out,'Q2_综合均衡最终结果.xlsx');
copyfile(fullfile(root,'input','结果提交模板.xlsx'),dest,'f');
T=S.sorties;rows=cell(height(T),8);
for k=1:height(T)
 rows(k,:)={char(T.sortie_id(k)),char(T.uav_id(k)),char(T.uav_type(k)), ...
  char(T.battery_id(k)),T.start_s(k),char(T.service_order(k)), ...
  T.return_s(k),T.energy_kWh(k)};
end
writecell(rows,dest,'Sheet','Q2_运输架次','Range','A2');
T=S.boxDelivery;rows=cell(height(T),4);
for k=1:height(T)
 rows(k,:)={char(T.box_id(k)),char(T.sortie_id(k)),char(T.area(k)),T.arrival_s(k)};
end
writecell(rows,dest,'Sheet','Q2_逐箱交付','Range','A2');
summary=table(string('综合均衡'),V.routeCount,V.deliveredBoxes, ...
 V.independentMetrics.Cmax_s/60,V.independentMetrics.energy_kWh, ...
 V.independentMetrics.W,string(V.status), ...
 'VariableNames',{'scheme','sorties','boxes','makespan_min','energy_kWh','weighted_delay','validator'});
writetable(summary,fullfile(out,'Q2_综合均衡最终指标.csv'));
fprintf('Q2 BALANCED EXPORT PASS: %d sorties, %d boxes, %.9f min, %.9f kWh\n', ...
 V.routeCount,V.deliveredBoxes,V.independentMetrics.Cmax_s/60,V.independentMetrics.energy_kWh);
end
