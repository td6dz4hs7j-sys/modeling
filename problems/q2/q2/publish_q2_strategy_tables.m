function publish_q2_strategy_tables(root)
% Publish only full schedules freshly revalidated under one Q2 scenario.
if nargin<1,root=fileparts(fileparts(mfilename('fullpath')));end
out=fullfile(root,'results','q2_strategy_scenarios');
D=load_q2_data(root);D.parallelPrepLoad=true;[legs,~]=build_q2_leg_cache(D,root,false);
caseNames=["到期时间贪心排序";"22架次时间优先搜索";"多区路线拆分构造";"路线与时刻局部精修";"任务分配与能耗精修";"加权邻域联合搜索"];
algorithms=["最早期望期限排序+资源解码";"架次压缩+时间搜索";"多服务区路线拆分+资源解码";"任务顺序/机型/箱分配局部搜索";"箱转移/交换/机型变更";"模拟退火式多邻域联合搜索"];
priorities=["期限→时间";"先定22架次，再优化时间";"先拆分路线，再优化时间";"时间优先局部搜索";"能耗优先，时间设上限";"能耗权重最高"];
source=["derived EDD from frozen 23-route set";"q2_prestage/recovered_101027_pass.mat"; ...
 "q2_prestage_split23/best_23_pass.mat";"q2_prestage_23_refine/best_pass.mat"; ...
 "q2_99_review/final_best_pass.mat";"q2_strategy_scenarios/energy_priority_best_pass.mat"];
cases=cell(6,1);
base=load(fullfile(root,'results','q2_99_review','final_best_pass.mat'),'best');
r=strip(base.best.routes);due=zeros(numel(r),1);duration=due;bid=due;
for i=1:numel(r)
 due(i)=min(D.boxes.expected_s(r(i).boxIdx));duration(i)=base.best.routes(i).eval.operation_s;bid(i)=min(r(i).boxIdx);
end
[~,order]=sortrows([due duration bid],[1 2 3]);[cases{1},~]=prestage_schedule_q2_routes(D,legs,r(order));
z=load(fullfile(root,'results','q2_prestage','recovered_101027_pass.mat'),'best');cases{2}=z.best;
z=load(fullfile(root,'results','q2_prestage_split23','best_23_pass.mat'),'best23');cases{3}=z.best23;
z=load(fullfile(root,'results','q2_prestage_23_refine','best_pass.mat'),'best');cases{4}=z.best;
cases{5}=base.best;
z=load(fullfile(out,'energy_priority_best_pass.mat'),'best');cases{6}=z.best;
rows=cell(6,14);
for i=1:6
 S=cases{i};V=strict(S);assert(strcmp(V.status,'PASS'),'%s: %s',caseNames(i),strjoin(cellstr(V.issues),'; '));
 rows(i,:)={caseNames(i),algorithms(i),priorities(i),V.routeCount, ...
  V.independentMetrics.Cmax_s/60,V.independentMetrics.energy_kWh, ...
  sum(S.sorties.operation_s)/3600,V.independentMetrics.W,V.deliveredBoxes, ...
  sum(arrayfun(@(x)numel(x.nodeOrder)>1,S.routes)),string(V.status),source(i), ...
  min(S.boxDelivery.expected_s-S.boxDelivery.arrival_s)/60, ...
  min(arrayfun(@(r)(1-D.uav.reserve(r.typeIdx))*D.uav.energy(r.typeIdx)-r.eval.energy_kWh,S.routes))};
 if i==1,save(fullfile(out,'due_date_greedy_pass.mat'),'S','V','-v7.3');end
end
A=cell2table(rows,'VariableNames',{'scheme','algorithm','objective_priority','sorties', ...
 'Cmax_min','energy_kWh','cumulative_flight_delivery_h','weighted_lateness_priority_s', ...
 'boxes_on_time','multi_area_sorties','validator','source','minimum_expected_margin_min','minimum_energy_reserve_margin_kWh'});
writetable(A,fullfile(out,'algorithm_strategy_comparison.csv'));
strategyNames=["架次优先";"时间优先";"能耗优先";"综合均衡"];
strategyKeys=["sortie_priority";"time_priority";"energy_priority";"balanced"];
priority=["架次权重最高";"时间权重最高";"能耗权重最高";"三目标等权"];
wr=cell(4,16);
for i=1:4
 z=load(fullfile(out,strategyKeys(i)+"_best_pass.mat"),'best','w');S=z.best;V=strict(S);
 assert(strcmp(V.status,'PASS'));
 wr(i,:)={strategyNames(i),"共享种子+多邻域随机搜索",priority(i),z.w(1),z.w(2),z.w(3), ...
  V.routeCount,V.independentMetrics.Cmax_s/60,V.independentMetrics.energy_kWh, ...
  sum(S.sorties.operation_s)/3600,V.independentMetrics.W,V.deliveredBoxes, ...
  sum(arrayfun(@(x)numel(x.nodeOrder)>1,S.routes)),string(V.status), ...
  min(S.boxDelivery.expected_s-S.boxDelivery.arrival_s)/60, ...
  min(arrayfun(@(r)(1-D.uav.reserve(r.typeIdx))*D.uav.energy(r.typeIdx)-r.eval.energy_kWh,S.routes))};
end
W=cell2table(wr,'VariableNames',{'scheme','algorithm','objective_priority','sortie_weight', ...
 'time_weight','energy_weight','sorties','Cmax_min','energy_kWh', ...
 'cumulative_flight_delivery_h','weighted_lateness_priority_s','boxes_on_time', ...
 'multi_area_sorties','validator','minimum_expected_margin_min','minimum_energy_reserve_margin_kWh'});
writetable(W,fullfile(out,'weighted_scheme_comparison.csv'));
fprintf('Q2_STRATEGY_TABLES PASS algorithms=%d weighted=%d\n',height(A),height(W));
 function V=strict(S)
  V=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true, ...
   'AllowPrepBatteryOverlap',true,'AllowFixedPrepPrestage',true);
 end
end
function q=strip(a)
q=repmat(struct('boxIdx',[],'nodeOrder',[],'typeIdx',0),numel(a),1);
for i=1:numel(a),q(i)=struct('boxIdx',a(i).boxIdx(:),'nodeOrder',a(i).nodeOrder(:)','typeIdx',a(i).typeIdx);end
end
