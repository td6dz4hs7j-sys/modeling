function run_q2_critical_optimized(root,countOnly)
% Deterministic bounded regrouping and critical UAV schedule search.
if nargin<1,root=fileparts(fileparts(mfilename('fullpath')));end
if nargin<2,countOnly=false;end
addpath(fullfile(root,'q2'),fullfile(root,'common'),fullfile(root,'utils'));
D=load_q2_data(root);[legs,meta]=build_q2_leg_cache(D,root,false); %#ok<NASGU>
source=fullfile(root,'results','q2_after_audit','q2_after_audit.mat');
if isfile(source)
 A=load(source,'best');seed0=A.best;
else
 source=fullfile(root,'results','q2_weighted_verified','balanced','solution.mat');A=load(source,'S');seed0=A.S;
end
base=strip(seed0.routes);
if countOnly
 candidateTimer=tic;[~,~,construction]=construct_q2_minimal(D,legs,'CandidateOnly',base);candidateElapsed=toc(candidateTimer);pool=construction.multistopCandidates;
else
 [seed,st]=schedule_q2_routes(D,legs,base);assert(st.feasible);
 V=validate_q2_solution(D,legs,seed,'RequireAllExpectedOnTime',true);assert(strcmp(V.status,'PASS'));
 candidateTimer=tic;[~,~,construction]=construct_q2_minimal(D,legs,'CandidateOnly',base);candidateElapsed=toc(candidateTimer);pool=construction.multistopCandidates;
end
fprintf('MULTISTOP_CANDIDATES dual=%d triple=%d retained=%d\n',construction.dualCandidates,construction.tripleCandidates,numel(pool));
if countOnly
 out=fullfile(root,'results','q2_candidate_throttle','count_only');if ~isfolder(out),mkdir(out);end
 T=table(construction.neighborCountPerArea,construction.minNeighborDegree,construction.maxNeighborDegree, ...
  construction.dualRoughGenerated,construction.dualFullEvaluated,construction.dualRetained,construction.dualGeneration_s, ...
  construction.tripleRoughGenerated,construction.tripleFullEvaluated,construction.tripleRetained,construction.tripleGeneration_s, ...
  numel(pool),candidateElapsed, ...
  'VariableNames',{'neighborsPerArea','minNeighbors','maxNeighbors','dualRough','dualFullEvaluated','dualRetained','dualElapsed_s', ...
  'tripleRough','tripleFullEvaluated','tripleRetained','tripleElapsed_s','totalRetained','elapsed_s'});
 writetable(T,fullfile(out,'candidate_count_smoke.csv'));save(fullfile(out,'candidate_count_smoke.mat'),'construction','T','source','-v7.3');
 fprintf('COUNT_ONLY neighbors=%d-%d dual=rough:%d/full:%d/kept:%d triple=rough:%d/full:%d/kept:%d retained=%d elapsed_s=%.3f\n', ...
  construction.minNeighborDegree,construction.maxNeighborDegree,construction.dualRoughGenerated,construction.dualFullEvaluated,construction.dualRetained, ...
  construction.tripleRoughGenerated,construction.tripleFullEvaluated,construction.tripleRetained,numel(pool),candidateElapsed);return
end
best=seed;bestKey=key_schedule(best);ctx=q2_fast_context(D,legs,fullfile(root,'cache','route_cache.mat'));
trace=cell(0,8);tested=0;rejectCount=zeros(1,7);
if ~isempty(pool)
 u7=find(seed.sorties.uav_id=="U07");if ~isempty(u7),[~,uord]=sort(seed.sorties.return_s(u7));u7=u7(uord(max(1,numel(uord)-3):end));end
 criticalBoxes=[];for w=u7(:)',p=str2double(extractAfter(seed.sorties.sortie_id(w),"Q2-"));if p<=numel(base),criticalBoxes=[criticalBoxes;base(p).boxIdx(:)];end,end %#ok<AGROW>
 score=zeros(numel(pool),5);
 for q=1:numel(pool)
  actualSources=sum(arrayfun(@(r)any(ismember(r.boxIdx,pool(q).boxIdx)),base));
  hits=sum(ismember(pool(q).boxIdx,criticalBoxes));score(q,:)=[-hits,-actualSources,pool(q).operation_s,pool(q).energy_kWh,q];
 end
 [~,ord]=sortrows(score,[1 2 3 4 5]);ord=ord(1:min(100,numel(ord)));
 for z=1:numel(ord)
  q=ord(z);c=pool(q);actualSources=sum(arrayfun(@(r)any(ismember(r.boxIdx,c.boxIdx)),base));if actualSources<2,rejectCount(1)=rejectCount(1)+1;continue;end
  [cand,ok]=consume(D,legs,base,c);if ~ok,rejectCount(2)=rejectCount(2)+1;continue;end
  [F,ctx]=q2_fast_schedule(D,legs,cand,ctx);if ~F.feasible,rejectCount(3)=rejectCount(3)+1;continue;elseif F.metrics.W>D.tol.time,rejectCount(4)=rejectCount(4)+1;continue;end
  [T,ts]=schedule_q2_routes(D,legs,cand);if ~ts.feasible,rejectCount(5)=rejectCount(5)+1;continue;end
  VV=validate_q2_solution(D,legs,T,'RequireAllExpectedOnTime',true);if ~strcmp(VV.status,'PASS'),rejectCount(6)=rejectCount(6)+1;continue;end
  rejectCount(7)=rejectCount(7)+1;tested=tested+1;key=key_schedule(T);trace(end+1,:)={q,c.stopCount,actualSources,T.metrics.N,T.metrics.Cmax_s,T.metrics.energy_kWh,key(2),"pool"}; %#ok<AGROW>
  if less(key,bestKey),best=T;bestKey=key;end
 end
end
% One bounded targeted transfer: move the S005 hygiene box from the U07 tail
% route into the existing S007/S003 C-type multi-stop route, testing all orders.
[target,best,ctx]=targeted_s005_hyg(D,legs,best,ctx);trace=[trace;target];
% Ten deterministic cross-trip box swaps; pair combinations are never enumerated.
[swapRows,best,ctx]=bounded_cross_trip_swaps(D,legs,best,ctx,10);trace=[trace;swapRows];
best=order_search(D,legs,best,ctx,1);best=type_search(D,legs,best,ctx);best=order_search(D,legs,best,ctx,1);
V=validate_q2_solution(D,legs,best,'RequireAllExpectedOnTime',true);assert(strcmp(V.status,'PASS'));
assert(height(best.boxDelivery)==80&&best.metrics.W<=D.tol.time&&best.metrics.N<=seed.metrics.N);
out=fullfile(root,'results','q2_candidate_throttle','formal');if ~isfolder(out),mkdir(out);end
summary=table(construction.dualCandidates,construction.tripleCandidates,numel(pool),tested,best.metrics.N,best.metrics.Cmax_s,best.metrics.energy_kWh,best.metrics.W,string(V.status), ...
 'VariableNames',{'dualCandidates','tripleCandidates','retainedCandidates','regroupCandidatesScheduled','trips','makespan_s','energy_kWh','delay','validator'});
save(fullfile(out,'q2_critical_optimized.mat'),'best','V','construction','trace','summary','source','-v7.3');
writetable(summary,fullfile(out,'summary.csv'));writetable(array2table(rejectCount,'VariableNames',{'oneSource','residualRouteFail','fastInfeasible','weightedDelay','fullScheduleFail','validatorFail','validatorPass'}),fullfile(out,'neighborhood_diagnostics.csv'));if ~isempty(trace),writetable(cell2table(trace,'VariableNames',{'candidate','stops','sourceTrips','trips','makespan_s','energy_kWh','secondChain_s','source'}),fullfile(out,'regroup_trace.csv'));end
writetable(best.sorties,fullfile(out,'sorties.csv'));write_q2_validation(V,fullfile(out,'validation.json'));
write_candidate_report(out,source,seed,construction,candidateElapsed,tested,best,V);
fprintf('FINAL trips=%d Cmax_s=%.9f E=%.12f W=%.12g validator=%s multistop=%d\n',best.metrics.N,best.metrics.Cmax_s,best.metrics.energy_kWh,best.metrics.W,V.status,sum(arrayfun(@(r)numel(r.nodeOrder)>1,best.routes)));
fprintf('CRITICAL_TAIL\n');
for u=1:height(D.uavInventory)
 ix=find(best.sorties.uav_id==D.uavInventory.id(u));if isempty(ix),continue;end
 [~,o]=sort(best.sorties.return_s(ix));ix=ix(o(max(1,numel(o)-3):end));disp(best.sorties(ix,{'sortie_id','uav_id','battery_id','start_s','return_s','service_order'}));
end
fprintf('OUTPUT=%s\n',out);
end
function [cand,ok]=consume(D,legs,base,c)
cand=repmat(struct('boxIdx',[],'nodeOrder',[],'typeIdx',0),0,1);ok=false;claimed=c.boxIdx(:);
for p=1:numel(base)
 remain=setdiff(base(p).boxIdx(:),claimed,'stable');if isempty(remain),continue;end
 nodes=route_order(D,remain,base(p).nodeOrder);[r,good]=best_route(D,legs,remain,nodes);if ~good,return;end;cand(end+1)=r; %#ok<AGROW>
end
cand(end+1)=struct('boxIdx',claimed,'nodeOrder',c.nodeOrder(:)','typeIdx',c.typeIdx);
key=zeros(numel(cand),3);for p=1:numel(cand),b=cand(p).boxIdx;key(p,:)=[min(D.hardDeadline_s(b)),min(D.boxes.expected_s(b)),p];end
[~,ix]=sortrows(key,[1 2 3]);cand=cand(ix);ok=true;
end
function [rows,S,ctx]=bounded_cross_trip_swaps(D,legs,S,ctx,limit)
rows=cell(0,8);base=strip(S.routes);pairs=zeros(0,4);
for i=1:numel(base)-1
 for j=i+1:numel(base)
  if isempty(base(i).boxIdx)||isempty(base(j).boxIdx),continue;end
  pairs(end+1,:)=[i,j,base(i).boxIdx(1),base(j).boxIdx(1)]; %#ok<AGROW>
 end
end
if isempty(pairs),return;end
pairs=pairs(1:min(limit,size(pairs,1)),:);bestKey=key_schedule(S);
for z=1:size(pairs,1)
 i=pairs(z,1);j=pairs(z,2);x=base;a=pairs(z,3);b=pairs(z,4);
 x(i).boxIdx(x(i).boxIdx==a)=b;x(j).boxIdx(x(j).boxIdx==b)=a;
 [x(i),ok1]=best_route(D,legs,x(i).boxIdx,route_order(D,x(i).boxIdx,x(i).nodeOrder));
 [x(j),ok2]=best_route(D,legs,x(j).boxIdx,route_order(D,x(j).boxIdx,x(j).nodeOrder));
 if ~ok1||~ok2,continue;end
 ordKey=zeros(numel(x),3);for q=1:numel(x),bb=x(q).boxIdx;ordKey(q,:)=[min(D.hardDeadline_s(bb)),min(D.boxes.expected_s(bb)),q];end
 [~,qord]=sortrows(ordKey,[1 2 3]);x=x(qord);
 [F,ctx]=q2_fast_schedule(D,legs,x,ctx);if ~F.feasible||F.metrics.W>D.tol.time,continue;end
 [T,st]=schedule_q2_routes(D,legs,x);if ~st.feasible,continue;end
 V=validate_q2_solution(D,legs,T,'RequireAllExpectedOnTime',true);if ~strcmp(V.status,'PASS'),continue;end
 key=key_schedule(T);rows(end+1,:)={z,2,2,T.metrics.N,T.metrics.Cmax_s,T.metrics.energy_kWh,key(2),"swap"}; %#ok<AGROW>
 if less(key,bestKey),S=T;bestKey=key;end
end
end
function write_candidate_report(out,source,seed,C,elapsed,tested,best,V)
f=fopen(fullfile(out,'candidate_throttle_report.md'),'w');c=onCleanup(@()fclose(f));
fprintf(f,['# Q2 候选限流与一次有界求解\n\n' ...
 '输入路线：%s。候选统计独立运行 status 0；每区无向邻居 %d–%d。\n\n' ...
 '双站 rough/full evaluator/保留：%d/%d/%d；三站：%d/%d/%d；池合计 %d，生成耗时 %.3f s。\n\n' ...
 '跨Trip重组最多评估 top100 pool partial-merge、1 个定向 box move、10 个固定 swap；未枚举所有箱对。候选 pool 的 schedule+validator 通过数 %d。\n\n' ...
 '源解 fresh strict validator PASS。基线 N=%d、Cmax=%.6f s、E=%.9f kWh；结果 N=%d、Cmax=%.6f s、E=%.9f kWh、W=%.12g，validator=%s。\n' ...
 '相对该源解变化：Cmax=%+.6f s，能耗=%+.9f kWh。\n'], ...
 source,C.minNeighborDegree,C.maxNeighborDegree,C.dualRoughGenerated,C.dualFullEvaluated,C.dualRetained, ...
 C.tripleRoughGenerated,C.tripleFullEvaluated,C.tripleRetained,C.dualRetained+C.tripleRetained,elapsed, ...
 tested,seed.metrics.N,seed.metrics.Cmax_s,seed.metrics.energy_kWh,best.metrics.N,best.metrics.Cmax_s, ...
 best.metrics.energy_kWh,best.metrics.W,V.status,best.metrics.Cmax_s-seed.metrics.Cmax_s, ...
 best.metrics.energy_kWh-seed.metrics.energy_kWh);
end
function [r,ok]=best_route(D,legs,b,nodes)
ok=false;r=struct('boxIdx',b(:),'nodeOrder',nodes(:)','typeIdx',1);best=[Inf Inf Inf];
for k=1:height(D.uav)
 try,ev=evaluate_q2_route(D,legs,b,nodes,k);catch,continue;end
 if ~(ev.capacitySafe&&ev.safe&&all(ev.boxArrivalOffset_s<=ev.hardDeadline_s+D.tol.time)),continue;end
 key=[ev.operation_s ev.energy_kWh k];if less(key,best),best=key;r.typeIdx=k;ok=true;end
end
end
function S=order_search(D,legs,S,ctx,passes)
for pass=1:passes
 current=strip(S.routes);bk=key_schedule(S);n=numel(current);best=S;bestKey=bk;tested=0;
 for i=1:n,for j=1:n
  if i==j,continue;end;x=current;item=x(i);x(i)=[];x=[x(1:j-1);item;x(j:end)];
  tested=tested+1;if tested>20,break;end
  [F,ctx]=q2_fast_schedule(D,legs,x,ctx);if ~F.feasible||F.metrics.W>D.tol.time,continue;end
  [T,st]=schedule_q2_routes(D,legs,x);if ~st.feasible,continue;end;k=key_schedule(T);
  if less(k,bestKey),vv=validate_q2_solution(D,legs,T,'RequireAllExpectedOnTime',true);if strcmp(vv.status,'PASS'),best=T;bestKey=k;end,end
 end;if tested>=20,break;end,end
 if less(bestKey,bk),S=best;fprintf('ORDER pass=%d Cmax=%.3f second=%.3f E=%.6f\n',pass,bestKey(1),bestKey(2),bestKey(3));else,break;end
end
end
function S=type_search(D,legs,S,ctx)
routes=strip(S.routes);best=S;bestKey=key_schedule(S);ids=unique(S.sorties.uav_id,'stable');dur=zeros(numel(ids),1);
for a=1:numel(ids),ix0=find(S.sorties.uav_id==ids(a));dur(a)=max(S.sorties.return_s(ix0));end
[~,chainOrder]=sort(dur,'descend');targets=ids(chainOrder(1:min(2,numel(chainOrder))));ix=[];
for u=targets(:)',ix=[ix;find(S.sorties.uav_id==u)];end %#ok<AGROW>
for q=unique(ix(:))'
 ridx=str2double(extractAfter(S.sorties.sortie_id(q),"Q2-"));if ridx>numel(routes),continue;end
 for k=1:height(D.uav)
  if k==routes(ridx).typeIdx,continue;end;x=routes;x(ridx).typeIdx=k;
  [F,ctx]=q2_fast_schedule(D,legs,x,ctx);if ~F.feasible||F.metrics.W>D.tol.time,continue;end
  [T,st]=schedule_q2_routes(D,legs,x);if ~st.feasible,continue;end;key=key_schedule(T);
  if less(key,bestKey),vv=validate_q2_solution(D,legs,T,'RequireAllExpectedOnTime',true);if strcmp(vv.status,'PASS'),best=T;bestKey=key;end,end
 end
end
S=best;
end
function [rows,S,ctx]=targeted_s005_hyg(D,legs,S,ctx)
rows=cell(0,8);routes=strip(S.routes);b=find(D.boxes.id=="S005-HYG-01",1);if isempty(b),return;end
src=find(arrayfun(@(r)any(r.boxIdx==b),routes),1);if isempty(src),return;end
n3=D.nodeIndex('S003');n7=D.nodeIndex('S007');dst=[];
for p=1:numel(routes),if p~=src&&all(ismember([n3 n7],routes(p).nodeOrder)),dst(end+1)=p;end,end %#ok<AGROW>
if isempty(dst),return;end
bestKey=key_schedule(S);
for j=dst
 rem=setdiff(routes(src).boxIdx(:),b,'stable');srcNodes=route_order(D,rem,routes(src).nodeOrder);[srcRoute,ok]=best_route(D,legs,rem,srcNodes);if ~ok,continue;end
 targetBoxes=[routes(j).boxIdx(:);b];nodes=unique(D.boxNodeIndex(targetBoxes),'stable')';if numel(nodes)~=3,continue;end
 orders=perms(nodes);
 for o=1:size(orders,1)
  for k=1:height(D.uav)
   [dstRoute,ok]=best_route(D,legs,targetBoxes,orders(o,:));if ~ok||dstRoute.typeIdx~=k,continue;end
   x=routes;x(src)=srcRoute;x(j)=dstRoute;
   key0=zeros(numel(x),3);for q=1:numel(x),bb=x(q).boxIdx;key0(q,:)=[min(D.hardDeadline_s(bb)),min(D.boxes.expected_s(bb)),q];end
   [~,ord0]=sortrows(key0,[1 2 3]);x=x(ord0);
   [F,ctx]=q2_fast_schedule(D,legs,x,ctx);if ~F.feasible||F.metrics.W>D.tol.time,continue;end
   [T,st]=schedule_q2_routes(D,legs,x);if ~st.feasible,continue;end
   V=validate_q2_solution(D,legs,T,'RequireAllExpectedOnTime',true);if ~strcmp(V.status,'PASS'),continue;end
   key=key_schedule(T);rows(end+1,:)={"S005-HYG-01",3,2,T.metrics.N,T.metrics.Cmax_s,T.metrics.energy_kWh,key(2),"targeted"}; %#ok<AGROW>
   if less(key,bestKey),S=T;bestKey=key;end
  end
 end
end
end
function k=key_schedule(S)
c=chains(S);second=0;if size(c,1)>=2,second=c(2,1);elseif ~isempty(c),second=c(1,1);end;k=[S.metrics.Cmax_s,second,S.metrics.energy_kWh,S.metrics.N];
end
function c=chains(S)
ids=unique(S.sorties.uav_id,'stable');c=zeros(numel(ids),2);for i=1:numel(ids),ix=find(S.sorties.uav_id==ids(i));c(i,:)=[max(S.sorties.return_s(ix)),i];end;c=sortrows(c,[-1 2]);
end
function tf=less(a,b)
tf=false;for i=1:min(numel(a),numel(b)),if a(i)<b(i)-1e-7,tf=true;return;elseif a(i)>b(i)+1e-7,return;end,end
end
function o=route_order(D,b,old)
n=unique(D.boxNodeIndex(b),'stable')';o=[old(ismember(old,n)),n(~ismember(n,old))];
end
function r=strip(x)
r=repmat(struct('boxIdx',[],'nodeOrder',[],'typeIdx',0),numel(x),1);for p=1:numel(x),r(p)=struct('boxIdx',x(p).boxIdx(:),'nodeOrder',x(p).nodeOrder(:)','typeIdx',x(p).typeIdx);end
end
