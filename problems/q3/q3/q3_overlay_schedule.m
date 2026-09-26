function q3_overlay_schedule(uavSwap)
% Q2 transport solution + concurrent relay overlay, entirely in MATLAB.
root=fileparts(fileparts(mfilename('fullpath')));addpath(fullfile(root,'q3'),fullfile(root,'q2'),fullfile(root,'common'));
out=fullfile(root,'results','q3_overlay');D=load_q3_data(root);
assert(isempty(intersect(D.relayIDs,D.uavInventory.id)),'Relay and transport UAV pools must remain distinct');
z=load(fullfile(out,'source_overlay.mat'),'S');S0=z.S;
if nargin<1,uavSwap=[];end
flex=ischar(uavSwap)&&strcmp(uavSwap,'flex');
fixed=isstruct(uavSwap);
sourceS0=S0;
if fixed
 T=uavSwap.transport;
 for p=1:numel(S0.routes)
  id=T.uav_id(p);bid=T.battery_id(p);S0.routes(p).uavID=id;S0.routes(p).batteryID=bid;
  S0.routes(p).prepStart_s=0;S0.routes(p).loadStart_s=0;
  S0.sorties.uav_id(p)=id;S0.sorties.battery_id(p)=bid;
  for box=S0.routes(p).boxIdx(:)'
   ix=S0.boxDelivery.box_id==D.boxes.id(box);S0.boxDelivery.uav_id(ix)=id;S0.boxDelivery.battery_id(ix)=bid;
  end
 end
elseif ~isempty(uavSwap)&&~flex
 assert(numel(uavSwap)==2&&S0.routes(uavSwap(1)).typeIdx==S0.routes(uavSwap(2)).typeIdx);
 ids=string({S0.routes(uavSwap).uavID});
 for k=1:2
  p=uavSwap(k);id=ids(3-k);S0.routes(p).uavID=id;S0.sorties.uav_id(p)=id;
  for box=S0.routes(p).boxIdx(:)'
   ix=S0.boxDelivery.box_id==D.boxes.id(box);S0.boxDelivery.uav_id(ix)=id;
  end
 end
end
P=readtable(fullfile(out,'selected_site_physics.csv'));W=readtable(fullfile(out,'continuous_demand_groups.csv'));
n=numel(S0.routes);m=height(P);H=15000;M=20000;
lb=[];ub=[];intcon=[];ri=[];co=[];vv=[];b=[];nv=0;
t=zeros(n,1);s=zeros(m,1);e=s;
original=[S0.routes.takeoff_s]';
orderTime=original;if fixed,orderTime=uavSwap.transport.takeoff_s;end
for p=1:n
 r=S0.routes(p);deadline=min(min(D.boxes.expected_s(r.boxIdx),D.hardDeadline_s(r.boxIdx))-r.boxArrival_s(:));
 lower=original(p);if flex||fixed,v=D.uav(r.typeIdx,:);lower=max(v.prep,numel(r.boxIdx)*v.load);end
 t(p)=var(lower,original(p)+deadline-.0001,false);
end
C=var(0,H,false);travel=D.relay.prep_s+D.relay.link_s+P.outbound_s;
for j=1:m
 s(j)=var(travel(j),H,false);e(j)=var(travel(j),H,false);
 add([e(j),s(j)],[1,-1],P.max_service_s(j)-.001);add([s(j),e(j)],[1,-1],-1);
 add([e(j),C],[1,-1],-P.return_s(j));
end
for p=1:n,add([t(p),C],[1,-1],-(S0.routes(p).return_s-original(p)));end
% Original physical transport assignments and order are retained.
if flex
 U=zeros(n,height(D.uavInventory));batteryIDs=strings(0,1);batteryTypes=zeros(0,1);
 for type=1:height(D.uav)
  for k=1:D.batteryInventory.count(type)
   batteryIDs(end+1,1)=D.uav.id(type)+"-B"+compose('%02d',k);batteryTypes(end+1,1)=type;
  end
 end
 B=zeros(n,numel(batteryIDs));
 for p=1:n
  type=S0.routes(p).typeIdx;
  for k=find(D.uavInventory.type==D.uav.id(type))',U(p,k)=var(0,1,true);end
  for k=find(batteryTypes==type)',B(p,k)=var(0,1,true);end
  ix=U(p,U(p,:)>0);eq(ix,ones(size(ix)),1);ix=B(p,B(p,:)>0);eq(ix,ones(size(ix)),1);
 end
 % All same-type aircraft and initially full batteries are interchangeable.
 % Fix labels on one route per type to remove redundant permutations.
 for type=1:height(D.uav)
  p=find([S0.routes.typeIdx]==type,1);k=find(U(p,:)>0,1);lb(U(p,k))=1;
  k=find(B(p,:)>0,1);lb(B(p,k))=1;
 end
 for a=1:n,for d=a+1:n
  if S0.routes(a).typeIdx~=S0.routes(d).typeIdx,continue;end
  before=var(0,1,true);v=D.uav(S0.routes(a).typeIdx,:);
  fa=S0.routes(a).return_s-original(a);fd=S0.routes(d).return_s-original(d);
  la=numel(S0.routes(a).boxIdx)*v.load;ld=numel(S0.routes(d).boxIdx)*v.load;
  for k=find(U(a,:)>0)
   add([t(a),t(d),U(a,k),U(d,k),before],[1,-1,M,M,M],3*M-max(fa+ld,v.prep));
   add([t(d),t(a),U(a,k),U(d,k),before],[1,-1,M,M,-M],2*M-max(fd+la,v.prep));
  end
  for k=find(B(a,:)>0)
   add([t(a),t(d),B(a,k),B(d,k),before],[1,-1,M,M,M],3*M-(S0.routes(a).batteryReady_s-original(a)));
   add([t(d),t(a),B(a,k),B(d,k),before],[1,-1,M,M,-M],2*M-(S0.routes(d).batteryReady_s-original(d)));
  end
 end,end
else
ids=unique(string({S0.routes.uavID}));
for id=ids
 ix=find(string({S0.routes.uavID})==id);[~,o]=sort(orderTime(ix));ix=ix(o);
 for k=2:numel(ix)
  a=ix(k-1);d=ix(k);u=D.uav(S0.routes(d).typeIdx,:);
  add([t(a),t(d)],[1,-1],-(S0.routes(a).return_s-original(a)+numel(S0.routes(d).boxIdx)*u.load));
  add([t(a),t(d)],[1,-1],-u.prep);
 end
end
for id=unique(string({S0.routes.batteryID}))
 ix=find(string({S0.routes.batteryID})==id);[~,o]=sort(orderTime(ix));ix=ix(o);
 for k=2:numel(ix)
  a=ix(k-1);d=ix(k);add([t(a),t(d)],[1,-1],-(S0.routes(a).batteryReady_s-original(a)));
 end
end
end
allocate=zeros(m,2);
beforeIndex=zeros(m,m);choiceIndex=zeros(height(W),m);
for j=1:m,for u=1:2,allocate(j,u)=var(0,1,true);end,eq(allocate(j,:),[1 1],1);end
for i=1:m,for j=i+1:m
 before=var(0,1,true);
 beforeIndex(i,j)=before;
 for u=1:2
  add([e(i),s(j),allocate(i,u),allocate(j,u),before],[1,-1,M,M,M],3*M-P.return_s(i)-D.relay.turn_s-travel(j));
  add([e(j),s(i),allocate(i,u),allocate(j,u),before],[1,-1,M,M,-M],2*M-P.return_s(j)-D.relay.turn_s-travel(i));
 end
end,end
for k=1:height(W)
 p=W.route(k);choices=[];
 for j=find(bitget(uint32(W.site_mask(k)),1:m))
  z=var(0,1,true);choices(end+1)=z; %#ok<AGROW>
  choiceIndex(k,j)=z;
  add([s(j),t(p),z],[1,-1,M],M+W.start_offset_s(k)-.002);
  add([t(p),e(j),z],[1,-1,M],M-W.end_offset_s(k)-.002);
 end
 eq(choices,ones(size(choices)),1);
end
A=sparse(ri,co,vv,numel(b),nv);f=zeros(nv,1);f(C)=1;
opts=optimoptions('intlinprog','Display','iter','MaxTime',90);
x0=[];
if fixed
 R=uavSwap.relays;x0=zeros(nv,1);x0(t)=uavSwap.transport.takeoff_s;
 x0(s)=R.serviceStart_s;x0(e)=R.serviceEnd_s;
 x0(C)=max([x0(t)+[S0.routes.return_s]'-original;x0(e)+P.return_s]);
 for j=1:m,u=find(D.relayIDs==R.uav(j));x0(allocate(j,u))=1;end
 for i=1:m,for j=i+1:m,x0(beforeIndex(i,j))=x0(s(i))<x0(s(j));end,end
 for k=1:height(W)
  p=W.route(k);eligible=find(choiceIndex(k,:)>0);
  ok=eligible(x0(s(eligible))<=x0(t(p))+W.start_offset_s(k)-.002+1e-7 & x0(e(eligible))>=x0(t(p))+W.end_offset_s(k)+.002-1e-7);
  assert(~isempty(ok),'Candidate has no provider for continuous demand group %d',k);x0(choiceIndex(k,ok(1)))=1;
 end
 violation=A*x0-b;[bad,row]=max(violation);
 assert(bad<=1e-6&&all(x0>=lb-1e-7)&&all(x0<=ub+1e-7),'Candidate violates MATLAB model row %d by %.9f',row,bad);
 fprintf('Conservative candidate independently satisfies every MATLAB inequality.\n');
end
fixedUpper=ub;fixedUpper(t)=original;
if flex||fixed,fixedUpper=ub;fprintf('Use existing same-type transport aircraft/batteries; route content remains fixed.\n');else,fprintf('First: retain all Q2 takeoff times exactly.\n');end
if isempty(x0),[x,val,flag,info]=intlinprog(f,intcon,A,b,[],[],lb,fixedUpper,opts);else,[x,val,flag,info]=intlinprog(f,intcon,A,b,[],[],lb,fixedUpper,x0,opts);end
mode='unchanged Q2 times';
if flex,mode='Q2 fixed routes; same-type resource and timing overlay';end
if fixed,mode='Q2 fixed routes; MATLAB timing refinement of candidate resource order';end
if isempty(x)
 fprintf('Next: use Q2 idle windows and expected-time slack; assignments unchanged.\n');
 opts.MaxTime=180;[x,val,flag,info]=intlinprog(f,intcon,A,b,[],[],lb,ub,opts);mode='Q2 slack retiming';
end
stats=struct('backend','MATLAB intlinprog','transport_mode',mode,'exitflag',flag,'output',info,'relay_sorties',m,'source_transport_sorties',n, ...
 'Q2_takeoff_lower_bound',lb(t),'inherit_Q2_prestage',true,'transport_assignments_frozen',isempty(uavSwap),'candidate_input',uavSwap);
stats.candidate_times_refined_in_MATLAB=fixed;
stats.authoritative_final_files={'transport_sorties.csv','relay_sorties.csv','Q3_结果提交.xlsx'};
fid=fopen(fullfile(out,'solver_stats.json'),'w');fprintf(fid,'%s',jsonencode(stats));fclose(fid);
if isempty(x),error('No incumbent for this selected-site overlay; expand sites/time model, not a full-problem infeasibility claim');end
ub(C)=val+1e-6;f=zeros(nv,1);f(s)=-1.1/3600;f(e)=1.1/3600;opts.MaxTime=30;opts.Display='off';
[y,~,~,~]=intlinprog(f,intcon,A,b,[],[],lb,ub,x,opts);if ~isempty(y),x=y;end
overrides=containers.Map('KeyType','double','ValueType','char');
if flex
 for p=1:n
  [~,k]=max(x(U(p,U(p,:)>0)));eligible=find(U(p,:)>0);id=D.uavInventory.id(eligible(k));
  S0.routes(p).uavID=id;S0.sorties.uav_id(p)=id;
  S0.routes(p).prepStart_s=0;S0.routes(p).loadStart_s=0;
  for box=S0.routes(p).boxIdx(:)',ix=S0.boxDelivery.box_id==D.boxes.id(box);S0.boxDelivery.uav_id(ix)=id;end
  eligible=find(B(p,:)>0);[~,k]=max(x(B(p,eligible)));overrides(p)=char(batteryIDs(eligible(k)));
 end
end
S=q3_reorder_transport(D,S0,x(t),overrides);
plan=struct('uav',{},'loc',{},'serviceStart_s',{},'serviceEnd_s',{},'name',{});
for j=1:m
 [~,u]=max(x(allocate(j,:)));plan(j)=struct('uav',u,'loc',P{j,{'lon','lat','alt_m'}}, ...
 'serviceStart_s',x(s(j)),'serviceEnd_s',x(e(j)),'name',sprintf('Q2_overlay_site%d',j));
end
[~,sequence]=sort([plan.serviceStart_s]);plan=plan(sequence);
dem=load_dem(root);relays=q3_build_relays(D,dem,plan);
assert(numel(unique(string({relays.componentID})))==m,'Reserve one initially full distinct component for each relay sortie');
assert(isempty(intersect(string({relays.componentID}),string({S0.routes.batteryID}))),'Relay components cannot borrow transport batteries');
z=load(fullfile(root,'cache','leg_cache.mat'),'legs');legs=z.legs;
V=validate_q3_solution(D,dem,legs,S,relays,'InheritQ2Prestage',true);
if ~strcmp(V.status,'PASS'),disp(V.issues);error('Overlay candidate failed independent validator');end
for p=1:n
 assert(isequal(S.routes(p).boxIdx,S0.routes(p).boxIdx)&&isequal(S.routes(p).nodeOrder,S0.routes(p).nodeOrder));
 assert(S.routes(p).uavID==S0.routes(p).uavID);if ~flex,assert(S.routes(p).batteryID==S0.routes(p).batteryID);end
end
proof=q3_audit_continuous_certificate(D,dem,legs,S,relays,V);
S0=sourceS0;
save(fullfile(out,'overlay_validated.mat'),'S','S0','relays','V','proof','-v7.3');
q3_export_results(root,D,dem,legs,S,relays,V,'q3_overlay');
q3_export_submission_workbook(root,D,legs,S,relays,struct2table(V.continuousCertificate),out, ...
 fullfile(root,'results','q2_strategy_scenarios','Q2_综合均衡最终结果.xlsx'));
q3_overlay_report(root,D,S0,S,relays,V,proof);
q3_overlay_figures(root,D,S0,S);
fprintf('Q2 OVERLAY PASS: %d transport + %d relay, C %.6f min, energy %.9f kWh, W %.6f.\n',n,m,V.makespan_s/60,V.jointEnergy_kWh,S.metrics.W);
function index=var(low,high,integer)
 nv=nv+1;index=nv;lb(index,1)=low;ub(index,1)=high;if integer,intcon(end+1)=index;end
end
function add(indices,values,rhs)
 row=numel(b)+1;ri=[ri,repmat(row,1,numel(indices))];co=[co,indices];vv=[vv,values];b(row,1)=rhs;
end
function eq(indices,values,rhs)
 add(indices,values,rhs);add(indices,-values,-rhs);
end
end
