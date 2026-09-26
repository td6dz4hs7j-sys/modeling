function probe_q2_s005_hyg(root)
% Exact-scheduler probe for transferring S005-HYG-01 into the S007/S003 trip.
if nargin<1,root=fileparts(fileparts(mfilename('fullpath')));end
addpath(fullfile(root,'q2'),fullfile(root,'common'),fullfile(root,'utils'));
D=load_q2_data(root);[legs,~]=build_q2_leg_cache(D,root,false);
A=load(fullfile(root,'results','q2_after_audit','q2_after_audit.mat'),'best');S0=A.best;
routes=strip(S0.routes);b=find(D.boxes.id=="S005-HYG-01",1);assert(~isempty(b));
src=find(arrayfun(@(r)any(r.boxIdx==b),routes),1);n3=D.nodeIndex('S003');n7=D.nodeIndex('S007');
dst=find(arrayfun(@(r)all(ismember([n3 n7],r.nodeOrder)),routes),1);
fprintf('SOURCE_ROUTE=%d TARGET_ROUTE=%d BOX=%s\n',src,dst,D.boxes.id(b));
assert(~isempty(src)&&~isempty(dst));
remaining=setdiff(routes(src).boxIdx(:),b,'stable');srcNodes=order_nodes(D,remaining,routes(src).nodeOrder);
[srcRoute,ok]=best_route(D,legs,remaining,srcNodes);assert(ok);
targetBoxes=[routes(dst).boxIdx(:);b];nodes=unique(D.boxNodeIndex(targetBoxes),'stable')';orders=perms(nodes);
rows=cell(0,10);trial=0;best=[];bestC=Inf;
for o=1:size(orders,1)
 for k=1:height(D.uav)
  try,ev=evaluate_q2_route(D,legs,targetBoxes,orders(o,:),k);catch ME
   rows(end+1,:)={orders(o,1),orders(o,2),orders(o,3),k,false,NaN,NaN,NaN,"ROUTE_ERROR",string(ME.message)};continue %#ok<AGROW>
  end
  if ~(ev.capacitySafe&&ev.safe)
   why="route infeasible";if ~ev.capacitySafe,why="capacity/volume infeasible";elseif ~ev.safe,why="energy reserve infeasible";end
   rows(end+1,:)={orders(o,1),orders(o,2),orders(o,3),k,false,NaN,ev.energy_kWh,NaN,why,""};continue %#ok<AGROW>
  end
  target=struct('boxIdx',targetBoxes,'nodeOrder',orders(o,:),'typeIdx',k);
  cand=routes;cand(src)=srcRoute;cand(dst)=target;
  key=zeros(numel(cand),3);for p=1:numel(cand),bb=cand(p).boxIdx;key(p,:)=[min(D.hardDeadline_s(bb)),min(D.boxes.expected_s(bb)),p];end
  [~,ix]=sortrows(key,[1 2 3]);cand=cand(ix);
  [T,st]=schedule_q2_routes(D,legs,cand);trial=trial+1;
  if ~st.feasible
   rows(end+1,:)={orders(o,1),orders(o,2),orders(o,3),k,false,NaN,ev.energy_kWh,NaN,"SCHEDULE_REJECT",string(st.reason)}; %#ok<AGROW>
   continue
  end
  V=validate_q2_solution(D,legs,T,'RequireAllExpectedOnTime',true);
  rows(end+1,:)={orders(o,1),orders(o,2),orders(o,3),k,true,T.metrics.Cmax_s,T.metrics.energy_kWh,T.metrics.W,string(V.status),string(strjoin(V.issues,' | '))}; %#ok<AGROW>
  if strcmp(V.status,'PASS')&&T.metrics.Cmax_s<bestC,best=T;bestC=T.metrics.Cmax_s;end
 end
end
out=fullfile(root,'results','q2_critical_optimized');if ~isfolder(out),mkdir(out);end
T=cell2table(rows,'VariableNames',{'stop1','stop2','stop3','typeIdx','scheduleFeasible','makespan_s','energy_kWh','delay','validatorStatus','validatorIssues'});
writetable(T,fullfile(out,'s005_hyg_exact_probe.csv'));if ~isempty(best),V=validate_q2_solution(D,legs,best,'RequireAllExpectedOnTime',true);save(fullfile(out,'s005_hyg_exact_probe_best.mat'),'best','V','-v7.3');end
disp(T);fprintf('PROBE_TRIALS=%d ROUTES_TESTED=%d PASS_EXPECTED=%d BEST_CMAX=%.9f\n',trial,height(T),sum(T.validatorStatus=="PASS"),bestC);
end
function [r,ok]=best_route(D,legs,b,nodes)
ok=false;r=struct('boxIdx',b(:),'nodeOrder',nodes(:)','typeIdx',1);best=[Inf Inf Inf];
for k=1:height(D.uav)
 try,ev=evaluate_q2_route(D,legs,b,nodes,k);catch,continue;end
 if ~(ev.capacitySafe&&ev.safe&&all(ev.boxArrivalOffset_s<=ev.hardDeadline_s+D.tol.time)),continue;end
 key=[ev.operation_s,ev.energy_kWh,k];if lex(key,best),best=key;r.typeIdx=k;ok=true;end
end
end
function n=order_nodes(D,b,old)
x=unique(D.boxNodeIndex(b),'stable')';n=[old(ismember(old,x)),x(~ismember(x,old))];
end
function r=strip(x)
r=repmat(struct('boxIdx',[],'nodeOrder',[],'typeIdx',0),numel(x),1);for p=1:numel(x),r(p)=struct('boxIdx',x(p).boxIdx(:),'nodeOrder',x(p).nodeOrder(:)','typeIdx',x(p).typeIdx);end
end
function tf=lex(a,b)
tf=false;for i=1:numel(a),if a(i)<b(i)-1e-8,tf=true;return;elseif a(i)>b(i)+1e-8,return;end,end
end
