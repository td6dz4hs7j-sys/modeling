function [S,routes,construction] = construct_q2_minimal(D,legs,varargin)
% Deterministic initial construction: urgent direct routes, then local residual routes.
candidateOnly=nargin>=3&&strcmpi(string(varargin{1}),'CandidateOnly');
routes=struct('boxIdx',{},'nodeOrder',{},'typeIdx',{}); construction=struct('status','IN_PROGRESS','urgentRoutes',0,'residualRoutes',0,'message','');
if candidateOnly && nargin>=4
 % Count-only entry: use the already verified seed routes and skip all route
 % construction, scheduling, and validator work.
 routes=varargin{2};
 [pool,counts,poolStats]=q2_multistop_pool(D,legs,routes);
 construction=poolStats;construction.status='COUNT_ONLY';construction.urgentRoutes=0;
 construction.residualRoutes=0;construction.message='Candidate generation only; no schedule or optimization run.';
 construction.multistopCandidates=pool;construction.dualCandidates=counts(2);
 construction.tripleCandidates=counts(3);construction.multistopSeedFeasible=0;
 construction.multistopSeedApplied=false;construction.multistopSeedReason='CountOnly';
 construction.candidateGeneration_s=poolStats.totalGeneration_s;
 S=[];return
end
areas=2:height(D.nodes); urg=cell(numel(areas),1);
% Harder/farther urgent service zones are allocated first.
priority=zeros(numel(areas),3);
for a=1:numel(areas)
 n=areas(a); urg{a}=find(D.boxNodeIndex==n & D.isHard);
 if isempty(urg{a}), error('Q2:MissingUrgent','No hard-deadline box at %s.',D.nodes.id(n)); end
 d=q2leg(legs,1,n).distance_m; due=min(D.hardDeadline_s(urg{a}));
 priority(a,:)=[due,-d,-sum(D.boxMass(urg{a}))];
end
[~,order]=sortrows(priority,[1 2 3]);
% For each zone, test every UAV type against the hard deadline and retain the
% candidate with lexicographically smallest currently scheduled (W,C,E,N).
for a=order(:)'
 n=areas(a); ids=urg{a}; cand=cell(0,4);
 for k=1:height(D.uav)
  r=struct('boxIdx',ids(:),'nodeOrder',n,'typeIdx',k);
  try, ev=evaluate_q2_route(D,legs,r.boxIdx,r.nodeOrder,r.typeIdx); catch, continue; end
  if ~(ev.capacitySafe&&ev.safe),continue;end
  trial=[routes,r]; [St,st]=schedule_q2_routes(D,legs,trial);
  if st.feasible || (numel(st.hardLateBoxes)==0 && numel(St.routes)==numel(trial))
   m=St.metrics; cand(end+1,:)={r,[m.W,m.Cmax_s,m.energy_kWh,m.N],trial,st}; %#ok<AGROW>
  end
 end
 if isempty(cand)
  construction.status='HARD_DEADLINE_CONSTRUCTION_FAILED'; construction.message=sprintf('No fixed-type schedule can append urgent route for %s without hard deadline failure.',D.nodes.id(n));
  S=struct('routes',routes,'sorties',table(),'boxDelivery',table(),'metrics',struct('W',Inf,'Cmax_s',Inf,'energy_kWh',Inf,'N',numel(routes)));
  return
 end
 key=vertcat(cand{:,2}); [~,ix]=sortrows(key,[1 2 3 4]); routes=cand{ix(1),3};
end
construction.urgentRoutes=numel(routes);
% Fill one-zone residual routes. The current urgent routes remain fixed; each
% remaining box is inserted by deadline/priority order into the largest safe
% same-zone batch, then the batch type is chosen by energy/time/ready pair.
assigned=false(height(D.boxes),1); for p=1:numel(routes),assigned(routes(p).boxIdx)=true;end
for n=areas
 rem=find(D.boxNodeIndex==n & ~assigned);
 while ~isempty(rem)
  % Earliest expectation, then largest priority and mass, deterministic IDs last.
  [~,ix]=sortrows([D.boxes.expected_s(rem),-D.boxes.priority(rem),-D.boxMass(rem),rem],[1 2 3 4]); rem=rem(ix);
  group=rem(1); rem(1)=[];
  for j=1:numel(rem)
   test=[group;rem(j)]; if q2_any_direct_feasible(D,legs,test,n),group=test;end
  end
  rem=rem(~ismember(rem,group));
  candidate=cell(0,3);
  gm=sum(D.boxMass(group));gv=sum(D.boxVolume(group));
  for k=1:height(D.uav)
   if gm>D.uav.payload(k)+D.tol.mass||gv>D.uav.volume(k)+D.tol.volume,continue;end
   ev=evaluate_q2_route(D,legs,group,n,k);
   if ev.capacitySafe&&ev.safe, candidate(end+1,:)={k,[ev.energy_kWh,ev.operation_s,k],ev};end %#ok<AGROW>
  end
  if isempty(candidate)
   construction.status='RESIDUAL_ROUTE_UNBUILDABLE'; construction.message=sprintf('No feasible direct route can carry residual box group at %s.',D.nodes.id(n));
   [S,~]=schedule_q2_routes(D,legs,routes);return
  end
  key=vertcat(candidate{:,2});[~,ix]=sortrows(key,[1 2 3]); k=candidate{ix(1),1};
  routes(end+1)=struct('boxIdx',group(:),'nodeOrder',n,'typeIdx',k); %#ok<AGROW>
  assigned(group)=true;
 end
end
construction.residualRoutes=numel(routes)-construction.urgentRoutes;
% Prioritize hard work already sorted first; residual routes then follow by
% earliest expectation and area, preserving a stable, reproducible order.
if numel(routes)>construction.urgentRoutes
 u=routes(1:construction.urgentRoutes); v=routes(construction.urgentRoutes+1:end); vk=zeros(numel(v),3);
 for j=1:numel(v), vk(j,:)=[min(D.boxes.expected_s(v(j).boxIdx)),min(v(j).nodeOrder),j];end
 [~,ix]=sortrows(vk,[1 2 3]);routes=[u,v(ix)];
end
[S,status]=schedule_q2_routes(D,legs,routes); construction.status='BUILT'; construction.message=status.reason;
construction.dualCandidates=0; construction.tripleCandidates=0;
construction.multistopSeedFeasible=0; construction.multistopSeedApplied=false;
construction.candidateGeneration_s=0;
construction.multistopSeedReason='No multi-stop candidate improved a feasible full schedule.';
construction.multistopCandidates=struct('boxIdx',{},'nodeOrder',{},'typeIdx',{},'stopCount',{},'sourceTrips',{},'energy_kWh',{},'operation_s',{});
if status.feasible
 % Build route-level candidates from individual boxes across all current trips.
 % Candidate counts include only capacity, energy, and solo hard-deadline-safe
 % routes; the full schedule is checked again before a candidate becomes a seed.
  tc=tic; [pool,counts,poolStats]=q2_multistop_pool(D,legs,routes); construction.candidateGeneration_s=toc(tc);
  construction.multistopMaxNeighborDegree=poolStats.maxNeighborDegree;
  construction.dualRoughGenerated=poolStats.dualRoughGenerated;
  construction.tripleRoughGenerated=poolStats.tripleRoughGenerated;
 construction.multistopCandidates=pool;
 construction.dualCandidates=counts(2); construction.tripleCandidates=counts(3);
 % Apply the best feasible box-level regrouping found. Boxes may be pulled from
 % different trips; each source trip is rebuilt from its remaining boxes.
  applied=false;nok=0;
  if ~candidateOnly
  [S,routes,applied,nok]=q2_apply_multistop_seed(D,legs,S,routes,pool);
  construction.multistopSeedFeasible=nok; construction.multistopSeedApplied=applied;
 end
 if applied,construction.multistopSeedReason='Applied best feasible box-level cross-trip regrouping.';end
 construction.message=sprintf('%s; dual=%d triple=%d feasible-seed-trials=%d applied=%d', ...
  construction.message,counts(2),counts(3),nok,applied);
end
if ~status.feasible,construction.status='RESOURCE_OR_DEADLINE_SCHEDULE_FAILED';end
end

function P=q2leg(legs,a,b)
ix=(a-1)*15+b-double(b>a);P=legs(ix);
end
function ok=q2_any_direct_feasible(D,legs,boxes,node)
ok=false; m=sum(D.boxMass(boxes));v=sum(D.boxVolume(boxes));
for k=1:height(D.uav)
 if m>D.uav.payload(k)+D.tol.mass || v>D.uav.volume(k)+D.tol.volume,continue;end
 ev=evaluate_q2_route(D,legs,boxes,node,k);if ev.capacitySafe&&ev.safe,ok=true;return;end
end
end

function [pool,counts,stats]=q2_multistop_pool(D,legs,routes)
% Bounded candidate generation: nearby zone pairs first, then extend only
% high-quality dual stops to a few nearby third zones. Never materialize the
% full Cartesian product of all boxes and all zones.
template=struct('boxIdx',[],'nodeOrder',[],'typeIdx',0,'stopCount',0,'sourceTrips',[], ...
 'energy_kWh',0,'operation_s',0);
pool=repmat(template,0,1);counts=zeros(1,3);areas=unique(D.boxNodeIndex(:))';
src=zeros(height(D.boxes),1);for p=1:numel(routes),src(routes(p).boxIdx)=p;end
nA=numel(areas); dist=inf(nA); 
for i=1:nA,for j=1:nA,if i~=j,dist(i,j)=q2leg(legs,areas(i),areas(j)).distance_m;end,end,end
% Keep each service area at five undirected neighbors, using shortest edges.
edges=zeros(nA*(nA-1)/2,3);e=0;
for i=1:nA-1,for j=i+1:nA,e=e+1;edges(e,:)=[dist(i,j),i,j];end,end
[~,eo]=sort(edges(:,1));edges=edges(eo,:);adj=false(nA);degree=zeros(nA,1);neighborCount=min(5,max(0,nA-1));
% First satisfy the 4-neighbor floor, then use remaining capacity toward five.
for e=1:size(edges,1)
 i=edges(e,2);j=edges(e,3);
 if degree(i)<4&&degree(j)<4
  adj(i,j)=true;adj(j,i)=true;degree(i)=degree(i)+1;degree(j)=degree(j)+1;
 end
end
for e=1:size(edges,1)
 i=edges(e,2);j=edges(e,3);
 if (degree(i)<4||degree(j)<4)&&degree(i)<6&&degree(j)<6&&~adj(i,j)
  adj(i,j)=true;adj(j,i)=true;degree(i)=degree(i)+1;degree(j)=degree(j)+1;
 end
end
for e=1:size(edges,1)
 i=edges(e,2);j=edges(e,3);
 if degree(i)<neighborCount&&degree(j)<neighborCount&&~adj(i,j)
  adj(i,j)=true;adj(j,i)=true;degree(i)=degree(i)+1;degree(j)=degree(j)+1;
 end
end
stats=struct('neighborCountPerArea',neighborCount,'maxNeighborDegree',max(degree),'minNeighborDegree',min(degree), ...
 'dualRoughGenerated',0,'tripleRoughGenerated',0,'dualFullEvaluated',0, ...
 'tripleFullEvaluated',0,'dualRetained',0,'tripleRetained',0, ...
 'dualGeneration_s',0,'tripleGeneration_s',0,'totalGeneration_s',0);
assert(min(degree)>=min(4,nA-1)&&max(degree)<=6,'Q2:NeighborDegree', ...
 'Bounded dual-neighbor graph must have actual degree 4-6 per area when enough areas exist.');
pairMask=adj; rough=repmat(template,0,1); roughScore=zeros(0,3); dualTimer=tic;
for i=1:nA-1
 for j=i+1:nA
  if ~pairMask(i,j),continue;end
  A=find(D.boxNodeIndex==areas(i));B=find(D.boxNodeIndex==areas(j));
  boxPair=zeros(0,4);boxPairIx=zeros(0,2);
  for a=A(:)'
   for b=B(:)'
    pair=[a;b];
    if ~q2_group_capacity_feasible(D,pair),continue;end
    row=[D.hardDeadline_s(a)+D.hardDeadline_s(b), ...
      -(D.boxes.priority(a)+D.boxes.priority(b)),D.boxMass(a)+D.boxMass(b),a*height(D.boxes)+b];
    boxPair(end+1,:)=row;boxPairIx(end+1,:)=[a,b]; %#ok<AGROW>
    if size(boxPair,1)>8
     [~,keep]=sortrows(boxPair,[1 2 3 4]);keep=keep(1:8);
     boxPair=boxPair(keep,:);boxPairIx=boxPairIx(keep,:);
    end
   end
  end
  [~,bp]=sortrows(boxPair,[1 2 3 4]);boxPairIx=boxPairIx(bp,:);
  for q=1:size(boxPairIx,1)
   a=boxPairIx(q,1);b=boxPairIx(q,2);
    boxes=[a;b];
    visitOrders=[areas(i),areas(j);areas(j),areas(i)];
    for oi=1:2
     order=visitOrders(oi,:);
     for k=1:height(D.uav)
      if sum(D.boxMass(boxes))>D.uav.payload(k)+D.tol.mass || sum(D.boxVolume(boxes))>D.uav.volume(k)+D.tol.volume,continue;end
      [ok,lbTime,lbEnergy]=q2_multistop_fastcheck(D,legs,boxes,order,k);if ~ok,continue;end
      rough(end+1)=struct('boxIdx',boxes,'nodeOrder',order,'typeIdx',k,'stopCount',2, ...
       'sourceTrips',unique(src(boxes))','energy_kWh',lbEnergy,'operation_s',lbTime); %#ok<AGROW>
      roughScore(end+1,:)=[lbTime,lbEnergy,k]; %#ok<AGROW>
    end
  end
 end
end
end
stats.dualRoughGenerated=numel(rough);
[dual,nDualEval]=q2_evaluate_limited(D,legs,rough,roughScore,800,25,4000);
stats.dualGeneration_s=toc(dualTimer);stats.dualFullEvaluated=nDualEval;
stats.dualRetained=numel(dual);
counts(2)=numel(dual);pool=[pool;dual(:)];
% Extend at most 30 distinct high-quality box pairs, with up to three third zones.
if ~isempty(dual)
 qscore=[[dual.operation_s]',[dual.energy_kWh]',[dual.typeIdx]'];[~,ord]=sortrows(qscore,[1 2 3]);
 seeds=repmat(template,0,1);seen=strings(0,1);
 for id=ord(:)'
  c=dual(id);sig=string(sprintf('%d,',sort(c.boxIdx)));
  if any(seen==sig),continue;end
  seen(end+1,1)=sig;seeds(end+1)=c; %#ok<AGROW>
  if numel(seeds)>=30,break;end
 end
 rough3=repmat(template,0,1);score3=zeros(0,3);tripleTimer=tic;
 for s=1:numel(seeds)
  c=seeds(s);nodes=unique(D.boxNodeIndex(c.boxIdx),'stable')';
  ix=arrayfun(@(n)find(areas==n,1),nodes);
  third=setdiff(areas,nodes);rank=zeros(numel(third),1);
  for z=1:numel(third)
   rank(z)=min(dist(ix(1),areas==third(z)))+min(dist(ix(2),areas==third(z)));
  end
  [~,zord]=sort(rank);third=third(zord(1:min(3,numel(zord))));
  for n3=third
   allAt=find(D.boxNodeIndex==n3);boxesAt=zeros(0,1);boxScore=zeros(0,3);
   % Select the best two third boxes only after checking capacity with the seed.
   for b=allAt(:)'
    test=[c.boxIdx(:);b];if ~q2_group_capacity_feasible(D,test),continue;end
    row=[D.hardDeadline_s(b),-D.boxes.priority(b),b];
    boxScore(end+1,:)=row;boxesAt(end+1,1)=b; %#ok<AGROW>
    if numel(boxesAt)>2
     [~,keep]=sortrows(boxScore,[1 2 3]);keep=keep(1:2);
     boxScore=boxScore(keep,:);boxesAt=boxesAt(keep);
    end
   end
   for b=boxesAt(:)'
    boxes=[c.boxIdx(:);b];nodes3=unique(D.boxNodeIndex(boxes),'stable')'; orders=perms(nodes3)';
    for o=1:size(orders,2)
     order=orders(:,o)';
     for k=1:height(D.uav)
      if sum(D.boxMass(boxes))>D.uav.payload(k)+D.tol.mass || sum(D.boxVolume(boxes))>D.uav.volume(k)+D.tol.volume,continue;end
      [ok,lbTime,lbEnergy]=q2_multistop_fastcheck(D,legs,boxes,order,k);if ~ok,continue;end
      rough3(end+1)=struct('boxIdx',boxes,'nodeOrder',order,'typeIdx',k,'stopCount',3, ...
       'sourceTrips',unique(src(boxes))','energy_kWh',lbEnergy,'operation_s',lbTime); %#ok<AGROW>
      score3(end+1,:)=[lbTime,lbEnergy,k]; %#ok<AGROW>
     end
    end
   end
  end
 end
 [triple,nTripleEval]=q2_evaluate_limited(D,legs,rough3,score3,800,10,4000);
 stats.tripleRoughGenerated=numel(rough3);stats.tripleFullEvaluated=nTripleEval;
 stats.tripleRetained=numel(triple);stats.tripleGeneration_s=toc(tripleTimer);
 counts(3)=numel(triple);pool=[pool;triple(:)];
end
stats.totalGeneration_s=stats.dualGeneration_s+stats.tripleGeneration_s;
end

function ok=q2_group_capacity_feasible(D,boxes)
mass=sum(D.boxMass(boxes));volume=sum(D.boxVolume(boxes));
ok=any(mass<=D.uav.payload+D.tol.mass & volume<=D.uav.volume+D.tol.volume);
end

function [candidates,nEvaluated]=q2_evaluate_limited(D,legs,rough,score,limit,perZoneLimit,maxEvaluations)
candidates=repmat(struct('boxIdx',[],'nodeOrder',[],'typeIdx',0,'stopCount',0,'sourceTrips',[], ...
 'energy_kWh',0,'operation_s',0),0,1);
 nEvaluated=0;if isempty(rough),return;end
[~,ord]=sortrows(score,[1 2 3]);zoneKeys=strings(0,1);zoneCounts=zeros(0,1);
for ix=ord(:)'
 c=rough(ix);zones=sort(unique(D.boxNodeIndex(c.boxIdx)));
 key=join(string(zones),',');bucket=find(zoneKeys==key,1);
 if isempty(bucket),zoneKeys(end+1,1)=key;zoneCounts(end+1,1)=0;bucket=numel(zoneKeys);end
 if zoneCounts(bucket)>=perZoneLimit,continue;end
 if nEvaluated>=maxEvaluations,break;end
 nEvaluated=nEvaluated+1;ev=evaluate_q2_route(D,legs,c.boxIdx,c.nodeOrder,c.typeIdx);
 if ~(ev.capacitySafe&&ev.safe)||any(ev.boxArrivalOffset_s>ev.hardDeadline_s+D.tol.time),continue;end
 c.energy_kWh=ev.energy_kWh;c.operation_s=ev.operation_s;candidates(end+1)=c; %#ok<AGROW>
 zoneCounts(bucket)=zoneCounts(bucket)+1;
 if numel(candidates)>=limit,break;end
end
end

function [ok,lbTime,lbEnergy]=q2_multistop_fastcheck(D,legs,boxes,order,k)
u=D.uav(k,:);n=numel(order);ok=true;lbTime=Inf;lbEnergy=Inf;
% Optimistic battery-energy bound: full rated range and empty-airframe climb.
totalDistance=0;totalUp=0;clock=u.prep+numel(boxes)*u.load;lbEnergy=0;
prev=1;
for z=1:n
 P=q2leg(legs,prev,order(z));totalDistance=totalDistance+P.distance_m;totalUp=totalUp+P.up_m;
 clock=clock+P.up_m/u.up+P.distance_m/u.speed+P.down_m/u.down;
 ix=boxes(D.boxNodeIndex(boxes)==order(z));clock=clock+u.handover+numel(ix)*u.boxhandover;
 if any(clock>D.hardDeadline_s(ix)+D.tol.time),ok=false;return;end
 prev=order(z);
end
P=q2leg(legs,prev,1);totalDistance=totalDistance+P.distance_m;totalUp=totalUp+P.up_m;
clock=clock+P.up_m/u.up+P.distance_m/u.speed+P.down_m/u.down;lbTime=clock;
lbEnergy=u.energy*totalDistance/u.range0+u.mass*D.g*totalUp/(u.eta*3.6e6);
if lbEnergy>(1-u.reserve)*u.energy+D.tol.energy,ok=false;end
end

function [S,bestRoutes,applied,nok]=q2_apply_multistop_seed(D,legs,S0,routes0,pool)
S=S0;bestRoutes=routes0;applied=false;nok=0;
if isempty(pool),return;end
% Prioritize candidates that can empty more source trips, then short and low-energy routes.
key=zeros(numel(pool),4);
for j=1:numel(pool)
 key(j,:)=[-numel(pool(j).sourceTrips),pool(j).operation_s,pool(j).energy_kWh,j];
end
[~,ix]=sortrows(key,[1 2 3 4]); ix=ix(1:min(30,numel(ix)));
best=[S0.metrics.N,S0.metrics.Cmax_s,S0.metrics.energy_kWh];
for jj=ix(:)'
 c=pool(jj); if numel(c.sourceTrips)<2,continue;end
 cand=repmat(struct('boxIdx',[],'nodeOrder',[],'typeIdx',0),0,1); valid=true;
 for p=1:numel(routes0)
  remain=setdiff(routes0(p).boxIdx(:),c.boxIdx(:),'stable');
  if isempty(remain),continue;end
  nodes=unique(D.boxNodeIndex(remain),'stable')';
  types=find(sum(D.boxMass(remain))<=D.uav.payload+D.tol.mass & sum(D.boxVolume(remain))<=D.uav.volume+D.tol.volume);
  opts=cell(0,3);
  for k=types(:)'
   ev=evaluate_q2_route(D,legs,remain,nodes,k);
   if ev.capacitySafe&&ev.safe&&all(ev.boxArrivalOffset_s<=ev.hardDeadline_s+D.tol.time)
    opts(end+1,:)={k,[ev.operation_s,ev.energy_kWh,k],ev}; %#ok<AGROW>
   end
  end
  if isempty(opts),valid=false;break;end
  mat=vertcat(opts{:,2});[~,q]=sortrows(mat,[1 2 3]);k=opts{q(1),1};
  cand(end+1)=struct('boxIdx',remain,'nodeOrder',nodes,'typeIdx',k); %#ok<AGROW>
 end
 if ~valid,continue;end
 evRoute=struct('boxIdx',c.boxIdx(:),'nodeOrder',c.nodeOrder(:)','typeIdx',c.typeIdx);
 cand(end+1)=evRoute;
 % Put rebuilt trips back in hard-deadline order before scheduling.
 orderKey=zeros(numel(cand),3);
 for z=1:numel(cand)
  b=cand(z).boxIdx(:); orderKey(z,:)=[min(D.hardDeadline_s(b)),min(D.boxes.expected_s(b)),z];
 end
 [~,ord]=sortrows(orderKey,[1 2 3]);cand=cand(ord);
 [trial,st]=schedule_q2_routes(D,legs,cand);
 if ~st.feasible,continue;end
 nok=nok+1;m=trial.metrics;score=[m.N,m.Cmax_s,m.energy_kWh];
 if score(1)<best(1) || (score(1)==best(1)&&(score(2)<best(2)-1e-8 || ...
   (abs(score(2)-best(2))<=1e-8&&score(3)<best(3)-1e-9)))
  S=trial;bestRoutes=cand;best=score;applied=true;
 end
end
end
