function run_q2_parallel_forms(root)
% Bounded neighborhood search under parallel prep/load timing.
if nargin<1,root=fileparts(fileparts(mfilename('fullpath')));end
out=fullfile(root,'results','q2_parallel_forms');if ~isfolder(out),mkdir(out);end
D=load_q2_data(root);D.parallelPrepLoad=true;[legs,~]=build_q2_leg_cache(D,root,false);
cp=fullfile(out,'best_pass.mat');if isfile(cp),x=load(cp,'best','bestV');base=x.best;else,x=load(fullfile(root,'results','q2_parallel_prep_load','parallel_solution.mat'),'S');base=x.S;end
V=validate_q2_solution(D,legs,base,'RequireAllExpectedOnTime',true);assert(strcmp(V.status,'PASS'));
best=base;bestV=V;save(fullfile(out,'best_pass.mat'),'D','legs','best','bestV','-v7.3');
logFile=fullfile(out,'search_log.csv');fid=fopen(logFile,'w');fprintf(fid,'form,tested,accepted,bestN,bestCmax_min,bestE_kWh,elapsed_s\n');fclose(fid);
t0=tic;budget=150;tested=0;accepted=0;forms=[0 0 0];
routes=strip(base.routes);n=numel(routes);best22=[];best22V=[];best22C=Inf;mergeTested=0;mergeFeasible=0;
% Form 1: all single route swaps and relocations; test alternate compatible vehicle types too.
for mode=1:2
 for i=1:n
  if mode==1,js=i+1:n;else,js=1:n;end
  for j=js
   if toc(t0)>budget,break;end
   if i==j,continue;end
   q=routes;if mode==1,q([i j])=q([j i]);else,item=q(i);q(i)=[];q=[q(1:j-1);item;q(j:end)];end
   tryCandidate(q,'route_order');
  end
  if toc(t0)>budget,break;end
 end
 if toc(t0)>budget,break;end
end
% Form 2: route type substitutions and one-stop-order reversals on original groupings.
for i=1:n
 if toc(t0)>budget,break;end
 for k=1:height(D.uav)
  if k==routes(i).typeIdx,continue;end
  q=routes;q(i).typeIdx=k;tryCandidate(q,'type_swap');if toc(t0)>budget,break;end
 end
 no=routes(i).nodeOrder;
 if numel(no)>1
  for a=1:numel(no)-1
   for b=a+1:numel(no)
    q=routes;q(i).nodeOrder(a:b)=q(i).nodeOrder(b:-1:a);tryCandidate(q,'stop_reverse');
    if toc(t0)>budget,break;end
   end
   if toc(t0)>budget,break;end
  end
 end
end
% Form 3: mutate one route's stop order, then revisit a reduced order neighborhood.
if toc(t0)<budget
 for i=1:n
  if toc(t0)>budget,break;end
  no=routes(i).nodeOrder;
  for a=1:numel(no)-1
   for b=a+1:numel(no)
    q=routes;q(i).nodeOrder([a b])=q(i).nodeOrder([b a]);
    tryCandidate(q,'stop_swap');if toc(t0)>budget,break;end
   end
   if toc(t0)>budget,break;end
  end
 end
end
% Form 4: bounded single-box transfers across routes (at most 60 attempts).
if toc(t0)<budget
 tried=0;
 for i=1:n
  for b=1:numel(routes(i).boxIdx)
   if toc(t0)>budget||tried>=60,break;end
   bx=routes(i).boxIdx(b);nd=D.boxNodeIndex(bx);
   for j=1:n
    if j==i||tried>=60||toc(t0)>budget,continue;end
    q=routes; q(i).boxIdx(b)=[];q(j).boxIdx(end+1)=bx;
    if ~any(D.boxNodeIndex(q(i).boxIdx)==nd),q(i).nodeOrder(q(i).nodeOrder==nd)=[];end
    if ~any(q(j).nodeOrder==nd),q(j).nodeOrder(end+1)=nd;end
    tried=tried+1;tryCandidate(q,'box_transfer');
   end
  end
  if toc(t0)>budget||tried>=60,break;end
 end
end
% Form 5: evaluate up to 40 capacity-screened route merges; retain best 22 separately.
pairCount=0;
for i=1:n-1
 for j=i+1:n
  if pairCount>=40||toc(t0)>budget,break;end
  pairCount=pairCount+1; boxUnion=[routes(i).boxIdx(:);routes(j).boxIdx(:)];
  mass=sum(D.boxMass(boxUnion));vol=sum(D.boxVolume(boxUnion));
  stopUnion=unique([routes(i).nodeOrder(:)' routes(j).nodeOrder(:)'],'stable');
  for k=1:height(D.uav)
   if toc(t0)>budget,break;end
   u=D.uav(k,:);if mass>u.payload+D.tol.mass||vol>u.volume+D.tol.volume,continue;end
   q=routes;q(i)=struct('boxIdx',boxUnion,'nodeOrder',stopUnion,'typeIdx',k);q(j)=[];mergeTested=mergeTested+1;
   try,[F,st]=schedule_q2_routes(D,legs,q);catch,continue;end
   if ~st.feasible||numel(F.routes)~=22,continue;end
   W=validate_q2_solution(D,legs,F,'RequireAllExpectedOnTime',true);
   if ~strcmp(W.status,'PASS'),continue;end
   mergeFeasible=mergeFeasible+1;
   if W.independentMetrics.Cmax_s<best22C
    best22=F;best22V=W;best22C=W.independentMetrics.Cmax_s;
    save(fullfile(out,'best_22_pass.mat'),'D','legs','best22','best22V','-v7.3');
   end
  end
 end
 if pairCount>=40||toc(t0)>budget,break;end
end
fid=fopen(fullfile(out,'run_summary.txt'),'w');fprintf(fid,'budget_s=%g\nelapsed_s=%.3f\ntested=%d\naccepted=%d\nmergePairs=%d\nmergeTested=%d\nmergeStrictPass=%d\nN=%d\nCmax_min=%.12f\nE_kWh=%.12f\nstatus=%s\n',budget,toc(t0),tested,accepted,pairCount,mergeTested,mergeFeasible,bestV.routeCount,bestV.independentMetrics.Cmax_s/60,bestV.independentMetrics.energy_kWh,bestV.status);fclose(fid);
fprintf('FORMS PASS tested=%d accepted=%d elapsed=%.2fs N=%d Cmax=%.9f min E=%.9f kWh\n',tested,accepted,toc(t0),bestV.routeCount,bestV.independentMetrics.Cmax_s/60,bestV.independentMetrics.energy_kWh);
 function tryCandidate(q,form)
  if toc(t0)>budget,return;end
  tested=tested+1;
  try,[F,st]=schedule_q2_routes(D,legs,q);catch,return;end
  if ~st.feasible||F.metrics.Cmax_s>=bestV.independentMetrics.Cmax_s-D.tol.time,return;end
  W=validate_q2_solution(D,legs,F,'RequireAllExpectedOnTime',true);
  if ~strcmp(W.status,'PASS'),return;end
  best=F;bestV=W;accepted=accepted+1;forms(strcmp(form,{'route_order','type_swap','stop_reverse','stop_swap'}))=1; %#ok<AGROW>
  save(fullfile(out,'best_pass.mat'),'D','legs','best','bestV','-v7.3');
  fid=fopen(logFile,'a');fprintf(fid,'%s,%d,%d,%d,%.9f,%.9f,%.3f\n',form,tested,accepted,bestV.routeCount,bestV.independentMetrics.Cmax_s/60,bestV.independentMetrics.energy_kWh,toc(t0));fclose(fid);
  fprintf('IMPROVE %s test=%d N=%d Cmax=%.6f E=%.6f\n',form,tested,bestV.routeCount,bestV.independentMetrics.Cmax_s/60,bestV.independentMetrics.energy_kWh);
 end
end
function r=strip(a)
r=repmat(struct('boxIdx',[],'nodeOrder',[],'typeIdx',[]),numel(a),1);
for z=1:numel(a),r(z)=struct('boxIdx',a(z).boxIdx(:),'nodeOrder',a(z).nodeOrder(:)','typeIdx',a(z).typeIdx);end
end





