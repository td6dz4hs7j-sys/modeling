function run_q2_after_audit(root)
% Bounded deterministic schedule and route refinement from the audited balanced Q2 seed.
% The schedule stage keeps groups/stops/types fixed; the route stage checks a finite set.
if nargin<1,root=fileparts(fileparts(mfilename('fullpath')));end
addpath(fullfile(root,'q2'),fullfile(root,'common'),fullfile(root,'utils'));
source=fullfile(root,'results','q2_weighted_verified','balanced','solution.mat');
A=load(source,'S');
assert(isfield(A,'S')&&isfield(A.S,'routes'),'Balanced solution MAT must contain S.routes.');
D=load_q2_data(root);
[legs,cacheMeta]=build_q2_leg_cache(D,root,false); %#ok<NASGU>

% Rebuild the frozen seed through the current full scheduler and independent validator.
routes=strip_routes(A.S.routes);
[seed,status]=schedule_q2_routes(D,legs,routes);
assert(status.feasible,'Frozen seed is infeasible: %s',status.reason);
Vseed=validate_q2_solution(D,legs,seed,'RequireAllExpectedOnTime',true);
assert(strcmp(Vseed.status,'PASS'),'Frozen seed failed validator: %s',strjoin(Vseed.issues,' | '));
assert(seed.metrics.N==23&&height(seed.boxDelivery)==80&&seed.metrics.W<=D.tol.time, ...
 'Frozen seed does not satisfy the 23-sortie/80-box/all-expected-time contract.');

% Deterministic finite neighborhood: swaps, insertions, and reversals of route precedence.
% The helper validates every accepted candidate using the full scheduler and validator.
[best,T]=refine_q2_schedule(D,legs,seed,2);
[best,status]=schedule_q2_routes(D,legs,strip_routes(best.routes));
assert(status.feasible,'Refined solution is infeasible: %s',status.reason);
V=validate_q2_solution(D,legs,best,'RequireAllExpectedOnTime',true);
assert(strcmp(V.status,'PASS'),'Refined solution failed validator: %s',strjoin(V.issues,' | '));
assert(best.metrics.N==23&&height(best.boxDelivery)==80&&best.metrics.W<=D.tol.time, ...
 'Refined solution violates the 23-sortie/80-box/all-expected-time contract.');

% Fixed bounded route neighborhood: reverse every multi-point stop order, then
% inspect at most 40 evenly spaced one-box transfers between frozen routes.
[routeBest,Troute]=refine_route_neighbors(D,legs,best);
if routeBest.metrics.Cmax_s<best.metrics.Cmax_s-D.tol.time || ...
 routeBest.metrics.energy_kWh<best.metrics.energy_kWh-D.tol.energy
 best=routeBest;
 V=validate_q2_solution(D,legs,best,'RequireAllExpectedOnTime',true);
 assert(strcmp(V.status,'PASS'),'Selected route neighbor failed validator: %s',strjoin(V.issues,' | '));
end

out=fullfile(root,'results','q2_after_audit');
if ~isfolder(out),mkdir(out);end
summary=table( ...
 ["balanced_seed";"after_bounded_schedule_refine"], ...
 [seed.metrics.N;best.metrics.N], ...
 [seed.metrics.W;best.metrics.W], ...
 [seed.metrics.Cmax_s;best.metrics.Cmax_s], ...
 [seed.metrics.energy_kWh;best.metrics.energy_kWh], ...
 [string(Vseed.status);string(V.status)], ...
 'VariableNames',{'solution','sorties','weighted_lateness','makespan_s','energy_kWh','validator'});
improved=(best.metrics.Cmax_s<seed.metrics.Cmax_s-D.tol.time)|| ...
 (best.metrics.energy_kWh<seed.metrics.energy_kWh-D.tol.energy);
result=struct('source',source,'search','deterministic schedule precedence neighborhood', ...
 'maxPasses',2,'improved',improved,'seedMetrics',seed.metrics, ...
 'finalMetrics',best.metrics,'validator',V,'cacheMeta',cacheMeta);

% Persist only after the current full scheduler and strict independent validator pass.
save(fullfile(out,'q2_after_audit.mat'),'best','V','T','Troute','summary','result','-v7.3');
writetable(summary,fullfile(out,'metrics_comparison.csv'));
writetable(T,fullfile(out,'schedule_refinement_trace.csv'));
writetable(Troute,fullfile(out,'route_neighbor_trace.csv'));
writetable(best.sorties,fullfile(out,'sorties.csv'));
writetable(best.boxDelivery,fullfile(out,'box_delivery.csv'));
write_q2_validation(V,fullfile(out,'validation.json'));
fprintf('SOURCE=%s\n',source);
fprintf('SEED N=%d W=%.12g Cmax_s=%.9f E=%.12f validator=%s\n', ...
 seed.metrics.N,seed.metrics.W,seed.metrics.Cmax_s,seed.metrics.energy_kWh,Vseed.status);
fprintf('FINAL N=%d W=%.12g Cmax_s=%.9f E=%.12f validator=%s improved=%d\n', ...
 best.metrics.N,best.metrics.W,best.metrics.Cmax_s,best.metrics.energy_kWh,V.status,improved);
fprintf('OUTPUT=%s\n',out);
end

function routes=strip_routes(r)
routes=repmat(struct('boxIdx',[],'nodeOrder',[],'typeIdx',[]),numel(r),1);
for p=1:numel(r)
 routes(p)=struct('boxIdx',r(p).boxIdx(:),'nodeOrder',r(p).nodeOrder(:)','typeIdx',r(p).typeIdx);
end
end

function [best,T]=refine_route_neighbors(D,legs,seed)
base=seed.metrics;best=seed;routes=strip_routes(seed.routes);candidates={};labels=strings(0,1);
for i=1:numel(routes)
 if numel(routes(i).nodeOrder)>1
  x=routes;x(i).nodeOrder=fliplr(x(i).nodeOrder);
  candidates{end+1,1}=x;labels(end+1,1)="reverse-stop-order:"+i; %#ok<AGROW>
 end
end
moveCandidates={};moveLabels=strings(0,1);n=numel(routes);
for i=1:n
 if numel(routes(i).boxIdx)<2,continue;end
 for j=1:n
  if i==j,continue;end
  for b=sort(routes(i).boxIdx(:))'
   x=routes; x(i).boxIdx(x(i).boxIdx==b)=[]; x(j).boxIdx(end+1)=b;
   x(i).nodeOrder=route_order(D,x(i).boxIdx,x(i).nodeOrder);
   x(j).nodeOrder=route_order(D,x(j).boxIdx,x(j).nodeOrder);
   moveCandidates{end+1,1}=x;moveLabels(end+1,1)="move-box:"+b+":"+i+"->"+j; %#ok<AGROW>
  end
 end
end
if numel(moveCandidates)>40
 take=unique(round(linspace(1,numel(moveCandidates),40)));
 moveCandidates=moveCandidates(take);moveLabels=moveLabels(take);
end
candidates=[candidates;moveCandidates];labels=[labels;moveLabels];
ctx=q2_fast_context(D,legs);rows=cell(numel(candidates),7);bestKey=[base.Cmax_s,base.energy_kWh];
for k=1:numel(candidates)
 [F,ctx]=q2_fast_schedule(D,legs,candidates{k},ctx);
 accepted=false;statusText="FAST_REJECT";m=F.metrics;
 if F.feasible&&m.N==base.N&&m.W<=D.tol.time
  strictPareto=(m.Cmax_s<base.Cmax_s-D.tol.time&&m.energy_kWh<=base.energy_kWh+D.tol.energy)|| ...
   (m.energy_kWh<base.energy_kWh-D.tol.energy&&m.Cmax_s<=base.Cmax_s+D.tol.time);
  statusText="FEASIBLE_NO_PARETO_GAIN";
  if strictPareto
   [S,st]=schedule_q2_routes(D,legs,candidates{k});
   if st.feasible
    assert(abs(S.metrics.W-m.W)<=D.tol.time&&abs(S.metrics.Cmax_s-m.Cmax_s)<=D.tol.time&& ...
     abs(S.metrics.energy_kWh-m.energy_kWh)<=D.tol.energy, ...
     'Fast/full route-neighbor metrics differ.');
    V=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true);
    if strcmp(V.status,'PASS')&&S.metrics.N==23&&S.metrics.W<=D.tol.time&& ...
      ((S.metrics.Cmax_s<base.Cmax_s-D.tol.time&&S.metrics.energy_kWh<=base.energy_kWh+D.tol.energy)|| ...
       (S.metrics.energy_kWh<base.energy_kWh-D.tol.energy&&S.metrics.Cmax_s<=base.Cmax_s+D.tol.time))
     key=[S.metrics.Cmax_s,S.metrics.energy_kWh];accepted=true;statusText="VALIDATOR_PASS_PARETO_GAIN";
     if lex_less(key,bestKey),best=S;bestKey=key;end
    else,statusText="FULL_REJECT_VALIDATOR";end
   else,statusText="FULL_REJECT_SCHEDULE";end
  end
 end
 rows(k,:)={k,char(labels(k)),F.feasible,m.W,m.Cmax_s,m.energy_kWh,statusText}; %#ok<AGROW>
end
T=cell2table(rows,'VariableNames',{'candidate','neighborhood','fast_feasible','W','Cmax_s','energy_kWh','decision'});
found=(best.metrics.Cmax_s<base.Cmax_s-D.tol.time)|| ...
 (best.metrics.energy_kWh<base.energy_kWh-D.tol.energy);
fprintf('ROUTE NEIGHBORHOOD: %d candidates (%d stop reversals, %d box moves), strict Pareto candidate found=%d\n', ...
 numel(candidates),numel(labels)-numel(moveLabels),numel(moveLabels),found);
end

function order=route_order(D,boxes,oldOrder)
nodes=unique(D.boxNodeIndex(boxes),'stable')';
order=[oldOrder(ismember(oldOrder,nodes)),nodes(~ismember(nodes,oldOrder))];
end

function tf=lex_less(a,b)
tf=a(1)<b(1)-1e-6||(abs(a(1)-b(1))<=1e-6&&a(2)<b(2)-1e-8);
end
