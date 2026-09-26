function overlap_fast_search(root,budget)
% Bounded route-order/type/local box neighborhood for fastest strict overlap plan.
if nargin<1,root=fileparts(fileparts(mfilename('fullpath')));end
if nargin<2,budget=180;end
out=fullfile(root,'results','q2_overlap_fast');if ~isfolder(out),mkdir(out);end
logf=fopen(fullfile(out,'search.log'),'w');cleanup=onCleanup(@()fclose(logf));
D=load_q2_data(root);D.parallelPrepLoad=true;[legs,~]=build_q2_leg_cache(D,root,false);
f22=load(fullfile(root,'results','q2_overlap','best_22_pass.mat'),'best22');
f23=load(fullfile(root,'results','q2_overlap','best_23_pass.mat'),'best');
seeds={f22.best22,f23.best};
ownfile=fullfile(out,'best_pass.mat');if isfile(ownfile),own=load(ownfile,'best');seeds{end+1}=own.best;end
for s=1:2
 V=validate_q2_solution(D,legs,seeds{s},'RequireAllExpectedOnTime',true,'AllowPrepBatteryOverlap',true);assert(strcmp(V.status,'PASS'));
end
best=seeds{1};bestV=validate_q2_solution(D,legs,best,'RequireAllExpectedOnTime',true,'AllowPrepBatteryOverlap',true);
save(fullfile(out,'best_pass.mat'),'D','legs','best','bestV','-v7.3');
tic;tested=0;strict=0;accepted=0;pruned=0;rng(260926,'twister');
% Seed with the best Cmax across the 22/23-route incumbents.
for s=2:numel(seeds)
 if lexless(key(seeds{s}),key(best)),best=seeds{s};bestV=validate_q2_solution(D,legs,best,'RequireAllExpectedOnTime',true,'AllowPrepBatteryOverlap',true);save(fullfile(out,'best_pass.mat'),'D','legs','best','bestV','-v7.3');end
end
inc=best;
while toc<budget
 rr=strip(inc.routes);n=numel(rr);cand={};
 % All execution-order relocations, then random paired swaps.
 for i=1:n
  for j=1:n
   if i==j,continue;end
   q=rr;x=q(i);q(i)=[];j2=min(j,numel(q)+1);q=[q(1:j2-1);x;q(j2:end)];cand{end+1}=q; %#ok<AGROW>
  end
 end
 % Due-date and operation-time priority orderings steer resource allocation.
 due=zeros(n,1);work=zeros(n,1);for i=1:n,ix=rr(i).boxIdx;due(i)=min(D.boxes.expected_s(ix));work(i)=inc.routes(i).eval.operation_s;end
 [~,a]=sort(due);cand{end+1}=rr(a);[~,a]=sort(work,'descend');cand{end+1}=rr(a);[~,a]=sort(due-work);cand{end+1}=rr(a);
 % Up to 100 informed random neighborhood moves: box exchanges within same/different routes.
 for z=1:100
  q=rr;
  if n>1 && rand<.55
   i=randi(n);j=randi(n);if i==j,continue;end
   if isempty(q(i).boxIdx)||isempty(q(j).boxIdx),continue;end
   ai=randi(numel(q(i).boxIdx));aj=randi(numel(q(j).boxIdx));tmp=q(i).boxIdx(ai);q(i).boxIdx(ai)=q(j).boxIdx(aj);q(j).boxIdx(aj)=tmp;
   q(i).nodeOrder=unique(D.boxNodeIndex(q(i).boxIdx),'stable')';q(j).nodeOrder=unique(D.boxNodeIndex(q(j).boxIdx),'stable')';
  else
   i=randi(n);q(i).typeIdx=randi(height(D.uav));
  end
  cand{end+1}=q; %#ok<AGROW>
 end
 % Evaluate candidates ordered to favor likely critical-path reductions.
 order=randperm(numel(cand));
 for z=order
  if toc>=budget,break;end
  q=cand{z};tested=tested+1;
  try,[S,st]=overlap_schedule_q2_routes(D,legs,q);catch,pruned=pruned+1;continue;end
  if ~st.feasible||S.metrics.N>23,pruned=pruned+1;continue;end
  if ~better(S,best),continue;end
  V=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true,'AllowPrepBatteryOverlap',true);
  if ~strcmp(V.status,'PASS'),pruned=pruned+1;continue;end
  strict=strict+1;accepted=accepted+1;best=S;bestV=V;inc=S;
  save(fullfile(out,'best_pass.mat'),'D','legs','best','bestV','-v7.3');
  fprintf(logf,'checkpoint t=%.1f n=%d cmax_min=%.9f energy=%.9f tested=%d\n',toc,bestV.routeCount,bestV.independentMetrics.Cmax_s/60,bestV.independentMetrics.energy_kWh,tested);fclose(logf);logf=fopen(fullfile(out,'search.log'),'a');
 end
 % If a complete pass found no improvement, restart the neighborhood from best with shuffled route order.
 if isequal(inc,best),inc=best;else,inc=best;end
end
best=validateFresh(best);bestV=validate_q2_solution(D,legs,best,'RequireAllExpectedOnTime',true,'AllowPrepBatteryOverlap',true);assert(strcmp(bestV.status,'PASS'));
save(fullfile(out,'best_pass.mat'),'D','legs','best','bestV','-v7.3');
fprintf(logf,'DONE budget_s=%g elapsed_s=%.2f tested=%d pruned=%d strict=%d accepted=%d n=%d cmax_min=%.12f energy=%.12f\n',budget,toc,tested,pruned,strict,accepted,bestV.routeCount,bestV.independentMetrics.Cmax_s/60,bestV.independentMetrics.energy_kWh);
fprintf('OVERLAP_FAST PASS N=%d Cmax=%.9f min E=%.9f kWh tested=%d pruned=%d\n',bestV.routeCount,bestV.independentMetrics.Cmax_s/60,bestV.independentMetrics.energy_kWh,tested,pruned);
 function S=validateFresh(S),Df=load_q2_data(root);Df.parallelPrepLoad=true;[Lf,~]=build_q2_leg_cache(Df,root,false);Vf=validate_q2_solution(Df,Lf,S,'RequireAllExpectedOnTime',true,'AllowPrepBatteryOverlap',true);assert(strcmp(Vf.status,'PASS'));D=Df;legs=Lf;end
end
function tf=better(a,b),tf=a.metrics.Cmax_s<b.metrics.Cmax_s-1e-6 || (abs(a.metrics.Cmax_s-b.metrics.Cmax_s)<=1e-6 && a.metrics.energy_kWh<b.metrics.energy_kWh-1e-8);end
function k=key(S),k=[S.metrics.Cmax_s,S.metrics.energy_kWh];end
function tf=lexless(a,b),tf=a(1)<b(1)-1e-6 || (abs(a(1)-b(1))<=1e-6 && a(2)<b(2)-1e-8);end
function r=strip(a),r=repmat(struct('boxIdx',[],'nodeOrder',[],'typeIdx',0),numel(a),1);for z=1:numel(a),r(z)=struct('boxIdx',a(z).boxIdx(:),'nodeOrder',a(z).nodeOrder(:)','typeIdx',a(z).typeIdx);end,end
