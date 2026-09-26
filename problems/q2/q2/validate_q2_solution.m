function V = validate_q2_solution(D,legs,S,varargin)
% Independent route/energy/time/resource audit; it never calls the evaluator.
ip=inputParser;
addParameter(ip,'RequireAllExpectedOnTime',false,@(x)islogical(x)&&isscalar(x));
addParameter(ip,'AllowPrepBatteryOverlap',false,@(x)islogical(x)&&isscalar(x));
addParameter(ip,'AllowFixedPrepPrestage',false,@(x)islogical(x)&&isscalar(x));
parse(ip,varargin{:});
requireAllExpectedOnTime=ip.Results.RequireAllExpectedOnTime;
allowPrepBatteryOverlap=ip.Results.AllowPrepBatteryOverlap;
allowFixedPrepPrestage=ip.Results.AllowFixedPrepPrestage;
issues=strings(0,1); delivered=zeros(0,1); N=numel(S.routes); energyTotal=0; W=0; Cmax=0;
routeMetrics=repmat(struct('energy',0,'operation',0,'flight',0,'arrival',[],'soc',0,'charge',0),N,1);
try
 for p=1:N
  r=S.routes(p); ix=double(r.boxIdx(:)); seq=double(r.nodeOrder(:)'); k=double(r.typeIdx);
  if isempty(ix)||any(~isfinite(ix))||any(ix<1|ix>height(D.boxes))||any(mod(ix,1)~=0)||numel(unique(ix))~=numel(ix),issues(end+1)="bad route box index/repetition";continue;end %#ok<AGROW>
  if any(ismember(delivered,ix)),issues(end+1)="duplicate delivery";end %#ok<AGROW>
  delivered=[delivered;ix]; %#ok<AGROW>
  expectedNodes=unique(D.boxNodeIndex(ix));
  if any(~isfinite(seq))||any(mod(seq,1)~=0)||numel(unique(seq))~=numel(seq)||~isequal(sort(seq),sort(expectedNodes(:)')),issues(end+1)="route stops do not match assigned box destinations";end %#ok<AGROW>
  if ~isfinite(k)||mod(k,1)~=0||k<1||k>height(D.uav),issues(end+1)="invalid UAV type";continue;end %#ok<AGROW>
  u=D.uav(k,:); m=sum(D.boxMass(ix));v=sum(D.boxVolume(ix));
  if m>u.payload+D.tol.mass||v>u.volume+D.tol.volume,issues(end+1)="capacity violation";end %#ok<AGROW>
  [ee,ff,op,offs]=manual_route(D,legs,ix,seq,k,allowPrepBatteryOverlap||allowFixedPrepPrestage);
  soc=1-ee/u.energy; safe=ee<=(1-u.reserve)*u.energy+D.tol.energy;
  if ~safe,issues(end+1)="energy reserve violation";end %#ok<AGROW>
  if ~all(isfinite([ee,ff,op,soc,r.eval.energy_kWh,r.eval.operation_s,r.eval.flight_s,r.start_s,r.return_s,r.batteryReady_s]))||any(~isfinite(offs)),issues(end+1)="nonfinite route value";end %#ok<AGROW>
  if abs(ee-r.eval.energy_kWh)>D.tol.energy,issues(end+1)="reported energy mismatch";end %#ok<AGROW>
  if abs(op-r.eval.operation_s)>D.tol.time,issues(end+1)="reported operation time mismatch";end %#ok<AGROW>
  if max(abs(offs-r.eval.boxArrivalOffset_s))>D.tol.time,issues(end+1)="reported delivery offsets mismatch";end %#ok<AGROW>
  if abs(ee-r.eval.energy_kWh)>D.tol.energy || abs(op-r.eval.operation_s)>D.tol.time
      % A tampered route schedule is already invalid; still retain independent recomputation.
  end
  arr=r.start_s+offs; hard=D.hardDeadline_s(ix);
  if allowPrepBatteryOverlap && ~allowFixedPrepPrestage
   pre=max(u.prep,numel(ix)*u.load);
   if ~isfield(r,'prepStart_s')||~isfinite(r.prepStart_s)||r.prepStart_s<0||abs(r.start_s-(r.prepStart_s+pre))>D.tol.time
    issues(end+1)="prep/takeoff timing mismatch"; %#ok<AGROW>
   end
  end
  if allowFixedPrepPrestage
   if ~isfield(r,'prepStart_s')||~isfield(r,'loadStart_s')||~isfield(r,'takeoff_s')||~isfinite(r.prepStart_s)||~isfinite(r.loadStart_s)||r.prepStart_s<0||r.loadStart_s<0||r.prepStart_s+u.prep>r.start_s+D.tol.time||r.loadStart_s+numel(ix)*u.load>r.start_s+D.tol.time||abs(r.takeoff_s-r.start_s)>D.tol.time
    issues(end+1)="prestage fixed prep/load timing invalid"; %#ok<AGROW>
   end
  end
  late=arr>hard+D.tol.time;
  if any(late & D.isMedical(ix)),issues(end+1)="medical hard deadline missed";end %#ok<AGROW>
  if any(late & D.boxes.firstBatch(ix)),issues(end+1)="first-batch deadline missed";end %#ok<AGROW>
  if requireAllExpectedOnTime && any(arr>D.boxes.expected_s(ix)+D.tol.time)
   issues(end+1)="expected delivery time missed"; %#ok<AGROW>
  end
  if ~all(isfinite([r.start_s,r.return_s,r.batteryReady_s,arr(:)']))||r.start_s<0||abs(r.return_s-(r.start_s+op))>D.tol.time,issues(end+1)="invalid route time interval";end %#ok<AGROW>
  if ~ismember(r.uavID,D.uavInventory.id)||D.uavInventory.type(D.uavInventory.id==r.uavID)~=u.id,issues(end+1)="UAV ID/type mismatch";end %#ok<AGROW>
  allBatIds=strings(0,1);for z=1:height(D.batteryInventory),for q=1:D.batteryInventory.count(z),allBatIds(end+1,1)=D.batteryInventory.type(z)+"-B"+compose('%02d',q);end,end %#ok<AGROW>
  bt=extractBefore(string(r.batteryID),"-B"); bi=find(D.batteryInventory.type==bt,1);
  if ~ismember(string(r.batteryID),allBatIds)||isempty(bi)||bt~=u.id,issues(end+1)="battery ID/type mismatch";charge=Inf;else
   T=D.batteryInventory.fullCharge_s(bi);
   if soc<0||soc>1+1e-9,charge=Inf;elseif soc<.9,charge=T*(.65*(.90-soc)/.90+.35);else,charge=T*.35*(1-soc)/.10;end
   if abs(r.batteryReady_s-(r.return_s+charge))>D.tol.time,issues(end+1)="battery recharge-ready time mismatch";end %#ok<AGROW>
  end
  if numel(r.boxArrival_s)~=numel(offs)||any(~isfinite(r.boxArrival_s))||max(abs(r.start_s+offs-r.boxArrival_s))>D.tol.time,issues(end+1)="route arrival vector mismatch";end %#ok<AGROW>
  sid="Q2-"+compose('%03d',p); routeBoxes=join(D.boxes.id(ix),";");routeStops=join(D.nodes.id(seq),"→");
  sr=find(S.sorties.sortie_id==sid,1);
  if isempty(sr),issues(end+1)="missing sortie row";else
   st=S.sorties(sr,:);
   typeMismatch=st.uav_type~=u.id;
   if typeMismatch,issues(end+1)="sortie UAV type mismatch";end %#ok<AGROW>
   if typeMismatch||st.uav_id~=r.uavID||st.battery_id~=r.batteryID||st.box_ids~=routeBoxes||st.service_order~=routeStops||abs(st.mass_kg-m)>D.tol.mass||abs(st.volume_m3-v)>D.tol.volume||abs(st.energy_kWh-ee)>D.tol.energy||abs(st.flight_s-ff)>D.tol.time||abs(st.operation_s-op)>D.tol.time||abs(st.start_s-r.start_s)>D.tol.time||abs(st.return_s-r.return_s)>D.tol.time,issues(end+1)="sortie table mismatch";end %#ok<AGROW>
  end
  for b=1:numel(ix)
   br=find(S.boxDelivery.box_id==D.boxes.id(ix(b)),1);
   if isempty(br),issues(end+1)="missing box delivery row";else
    dr=S.boxDelivery(br,:);area=D.boxes.area(ix(b));cat=D.boxes.category(ix(b));due=D.boxes.expected_s(ix(b));hd=D.hardDeadline_s(ix(b));pr=D.boxes.priority(ix(b));
    if dr.area~=area||dr.category~=cat||dr.sortie_id~=sid||dr.uav_id~=r.uavID||dr.battery_id~=r.batteryID||~isfinite(dr.arrival_s)||abs(dr.arrival_s-arr(b))>D.tol.time||~isfinite(dr.expected_s)||abs(dr.expected_s-due)>D.tol.time||~sameval(dr.hard_deadline_s,hd,D.tol.time)||~isfinite(dr.priority)||abs(dr.priority-pr)>D.tol.time,issues(end+1)="box delivery table mismatch";end %#ok<AGROW>
   end
  end
  expected=D.boxes.expected_s(ix);pri=D.boxes.priority(ix);W=W+sum(pri.*max(0,arr-expected));
  energyTotal=energyTotal+ee;Cmax=max(Cmax,r.return_s);
  routeMetrics(p)=struct('energy',ee,'operation',op,'flight',ff,'arrival',arr,'soc',soc,'charge',charge);
 end
 if numel(delivered)~=height(D.boxes)||numel(unique(delivered))~=height(D.boxes),issues(end+1)="not all 80 boxes delivered exactly once";end %#ok<AGROW>
 if height(S.sorties)~=N||numel(unique(S.sorties.sortie_id))~=N,issues(end+1)="sortie table row count or ID uniqueness mismatch";end %#ok<AGROW>
 if height(S.boxDelivery)~=height(D.boxes)||numel(unique(S.boxDelivery.box_id))~=height(D.boxes),issues(end+1)="box delivery table does not contain 80 unique boxes";end %#ok<AGROW>
 % Resource intervals: legacy UAV/battery start together; overlap mode permits prep while charging.
 for i=1:N,for j=i+1:N
  if allowFixedPrepPrestage,ui=S.routes(i).loadStart_s;uj=S.routes(j).loadStart_s;elseif allowPrepBatteryOverlap,ui=S.routes(i).prepStart_s;uj=S.routes(j).prepStart_s;else,ui=S.routes(i).start_s;uj=S.routes(j).start_s;end
  if S.routes(i).uavID==S.routes(j).uavID && max(ui,uj)<min(S.routes(i).return_s,S.routes(j).return_s)-D.tol.time,issues(end+1)="UAV interval overlap";end %#ok<AGROW>
  if S.routes(i).batteryID==S.routes(j).batteryID && max(S.routes(i).start_s,S.routes(j).start_s)<min(S.routes(i).batteryReady_s,S.routes(j).batteryReady_s)-D.tol.time,issues(end+1)="battery/charging interval overlap";end %#ok<AGROW>
 end,end
 if allowFixedPrepPrestage
  ids=unique(string({S.routes.uavID}));
  for uix=1:numel(ids)
   same=find(string({S.routes.uavID})==ids(uix));[~,ord]=sort([S.routes(same).takeoff_s]);same=same(ord);
   for z=2:numel(same)
    prev=S.routes(same(z-1));cur=S.routes(same(z));ut=D.uav(cur.typeIdx,:);
    if cur.prepStart_s<prev.takeoff_s-D.tol.time,issues(end+1)="fixed prep began before prior takeoff";end %#ok<AGROW>
    if cur.prepStart_s+ut.prep>cur.start_s+D.tol.time,issues(end+1)="fixed prep incomplete at takeoff";end %#ok<AGROW>
    if cur.loadStart_s<prev.return_s-D.tol.time,issues(end+1)="load began before prior return";end %#ok<AGROW>
   end
  end
 end
 if ~all(isfinite([S.metrics.W,S.metrics.Cmax_s,S.metrics.energy_kWh,S.metrics.N]))||any([S.metrics.W,S.metrics.Cmax_s,S.metrics.energy_kWh,S.metrics.N]<0),issues(end+1)="nonfinite or negative solution metric";end %#ok<AGROW>
 if abs(W-S.metrics.W)>D.tol.time,issues(end+1)="reported weighted lateness mismatch";end %#ok<AGROW>
 if abs(Cmax-S.metrics.Cmax_s)>D.tol.time,issues(end+1)="reported completion mismatch";end %#ok<AGROW>
 if abs(energyTotal-S.metrics.energy_kWh)>D.tol.energy,issues(end+1)="reported total energy mismatch";end %#ok<AGROW>
 if S.metrics.N~=N,issues(end+1)="reported route count mismatch";end %#ok<AGROW>
catch ME
 issues(end+1)="validator exception: "+string(ME.message); %#ok<AGROW>
end
V=struct('status',ifelse(isempty(issues),'PASS','FAIL'),'issues',issues, ...
 'requireAllExpectedOnTime',requireAllExpectedOnTime, ...
 'deliveredBoxes',numel(unique(delivered)),'routeCount',N, ...
 'independentMetrics',struct('W',W,'Cmax_s',Cmax,'energy_kWh',energyTotal,'N',N), ...
 'routeMetrics',routeMetrics);
end

function [E,flight,operation,offsets]=manual_route(D,legs,idx,order,k,allowOverlap)
u=D.uav(k,:); left=sum(D.boxMass(idx)); E=0; flight=0;
if allowOverlap
 operation=0;
elseif isfield(D,'parallelPrepLoad') && D.parallelPrepLoad
 operation=max(u.prep,numel(idx)*u.load);
else
 operation=u.prep+numel(idx)*u.load;
end
offsets=zeros(numel(idx),1); seq=[1,order,1];
for t=1:numel(seq)-1
 a=seq(t);b=seq(t+1);n=height(D.nodes);g=(a-1)*(n-1)+b-double(b>a);P=legs(g);q=left;
 L=u.range0-(u.range0-u.rangeF)*(q/u.payload)^1.5;
 E=E+u.energy*P.distance_m/L+(u.mass+q)*D.g*P.up_m/(u.eta*3.6e6);
 ft=P.up_m/u.up+P.distance_m/u.speed+P.down_m/u.down;flight=flight+ft;operation=operation+ft;
 if b~=1
  B=idx(D.boxNodeIndex(idx)==b); operation=operation+u.handover+numel(B)*u.boxhandover;
  offsets(ismember(idx,B))=operation; left=left-sum(D.boxMass(B));
 end
end
end

function x=ifelse(tf,a,b)
if tf,x=a;else,x=b;end
end
function tf=sameval(a,b,tol)
tf=(isfinite(a)&&isfinite(b)&&abs(a-b)<=tol)||(isinf(a)&&isinf(b)&&sign(a)==sign(b));
end
