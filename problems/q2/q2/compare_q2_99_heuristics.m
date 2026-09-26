function compare_q2_99_heuristics(root)
% Route-order baselines on exactly the same 23 tasks, types, boxes and decoder.
if nargin<1,root=fileparts(fileparts(mfilename('fullpath')));end
D=load_q2_data(root);D.parallelPrepLoad=true;[legs,~]=build_q2_leg_cache(D,root,false);
x=load(fullfile(root,'results','q2_99_review','final_best_pass.mat'),'best');best=x.best;
N=numel(best.routes);r=repmat(struct('boxIdx',[],'nodeOrder',[],'typeIdx',0),N,1);
due=zeros(N,1);duration=due;boxid=due;
for i=1:N
 a=best.routes(i);r(i)=struct('boxIdx',a.boxIdx(:),'nodeOrder',a.nodeOrder(:)','typeIdx',a.typeIdx);
 due(i)=min(D.boxes.expected_s(a.boxIdx));duration(i)=a.eval.operation_s;
 boxid(i)=min(a.boxIdx);
end
[~,ord1]=sortrows([due duration boxid],[1 2 3]);
[~,ord2]=sortrows([duration due boxid],[1 2 3]);
[~,ord3]=sortrows([boxid due duration],[1 2 3]);
names=["earliest_due_date";"shortest_route_first";"input_box_order";"optimized_route_order"];
orders={ord1,ord2,ord3,(1:N)'};rows=cell(4,8);
for j=1:4
 [S,st]=prestage_schedule_q2_routes(D,legs,r(orders{j}));
 V=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true, ...
 'AllowPrepBatteryOverlap',true,'AllowFixedPrepPrestage',true);
 count=sum(S.boxDelivery.arrival_s<=S.boxDelivery.expected_s+D.tol.time);
 if strcmp(V.status,'PASS')
  save(fullfile(root,'results','q2_99_review',names(j)+"_pass.mat"),'S','V','-v7.3');
 end
 rows(j,:)={names(j),numel(S.routes),V.independentMetrics.Cmax_s/60, ...
 V.independentMetrics.energy_kWh,count,strcmp(V.status,'PASS'), ...
 st.feasible,strjoin(V.issues,' | ')};
end
T=cell2table(rows,'VariableNames',{'route_order_rule','sorties','Cmax_min','energy_kWh', ...
 'boxes_on_time','strict_PASS','hard_deadline_feasible','validator_issues'});
writetable(T,fullfile(root,'results','q2_99_review','same_routes_order_baselines.csv'));
fprintf('Q2_99_ORDER_BASELINES completed: %d strict PASS\n',sum(T.strict_PASS));
end
