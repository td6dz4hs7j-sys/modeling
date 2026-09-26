function [S,status] = schedule_q2_routes(D,legs,routes)
% Earliest-pair same-type UAV/battery schedule; input order is route precedence.
status=struct('feasible',false,'reason','','hardLateBoxes',strings(0,1));
S=struct('routes',routes,'sorties',table(),'boxDelivery',table(),'metrics',struct('W',Inf,'Cmax_s',Inf,'energy_kWh',Inf,'N',numel(routes)));
if isempty(routes),status.reason='No routes.';return;end
uavAvail=zeros(height(D.uavInventory),1); uavIds=D.uavInventory.id;
batteryIds=strings(0,1); batteryTypes=strings(0,1); battFull=zeros(0,1); battAvail=zeros(0,1);
for k=1:height(D.batteryInventory)
 for j=1:D.batteryInventory.count(k)
  batteryIds(end+1,1)=D.batteryInventory.type(k)+"-B"+compose('%02d',j); %#ok<AGROW>
  batteryTypes(end+1,1)=D.batteryInventory.type(k); battFull(end+1,1)=D.batteryInventory.fullCharge_s(k); battAvail(end+1,1)=0; %#ok<AGROW>
 end
end
nr=numel(routes); out=repmat(struct('boxIdx',[],'nodeOrder',[],'typeIdx',[],'eval',[],'uavID','','batteryID','','start_s',NaN,'return_s',NaN,'batteryReady_s',NaN,'boxArrival_s',[]),nr,1);
sortRows=cell(nr,13); boxRows=cell(0,10); hardLate=[]; Etotal=0;W=0;Cmax=0;
for p=1:nr
 r=routes(p); assert(isfield(r,'boxIdx')&&isfield(r,'nodeOrder')&&isfield(r,'typeIdx'));
 ev=evaluate_q2_route(D,legs,r.boxIdx,r.nodeOrder,r.typeIdx);
 if ~ev.capacitySafe, status.reason=sprintf('route %d exceeds mass/volume rating',p); S.routes=out(1:p-1); return; end
 if ~ev.safe, status.reason=sprintf('route %d violates return-energy reserve',p); S.routes=out(1:p-1); return; end
 typ=D.uav.id(r.typeIdx); ui=find(D.uavInventory.type==typ); bi=find(batteryTypes==typ);
 if isempty(ui)||isempty(bi),status.reason=sprintf('route %d type %s lacks resources',p,typ);S.routes=out(1:p-1);return;end
 pairs=zeros(numel(ui)*numel(bi),3);a=0;
 for x=1:numel(ui),for y=1:numel(bi),a=a+1;pairs(a,:)=[max(uavAvail(ui(x)),battAvail(bi(y))),ui(x),bi(y)];end,end
 pairs=sortrows(pairs,[1 2 3]); start=pairs(1,1); uix=pairs(1,2); bix=pairs(1,3);
 ret=start+ev.returnOffset_s; ready=ret+ev.charge_s;
 uavAvail(uix)=ret; battAvail(bix)=ready;
 arrivals=start+ev.boxArrivalOffset_s;
 deadlines=ev.hardDeadline_s; late=arrivals>deadlines+D.tol.time; if any(late),hardLate=[hardLate;ev.boxIdx(late)];end %#ok<AGROW>
 due=D.boxes.expected_s(ev.boxIdx); priority=D.boxes.priority(ev.boxIdx); W=W+sum(priority.*max(0,arrivals-due));
 Etotal=Etotal+ev.energy_kWh;Cmax=max(Cmax,ret);
 out(p)=struct('boxIdx',r.boxIdx(:),'nodeOrder',r.nodeOrder(:)','typeIdx',r.typeIdx,'eval',ev,'uavID',uavIds(uix),'batteryID',batteryIds(bix),'start_s',start,'return_s',ret,'batteryReady_s',ready,'boxArrival_s',arrivals);
 id="Q2-"+compose('%03d',p); nodeNames=join(D.nodes.id(ev.nodeOrder),"→"); boxNames=join(D.boxes.id(ev.boxIdx),";");
 sortRows(p,:)={id,typ,uavIds(uix),batteryIds(bix),boxNames,nodeNames,ev.mass_kg,ev.volume_m3,ev.energy_kWh,ev.flight_s,ev.operation_s,start,ret};
 for b=1:numel(ev.boxIdx)
  ix=ev.boxIdx(b); boxRows(end+1,:)={D.boxes.id(ix),D.boxes.area(ix),D.boxes.category(ix),id,uavIds(uix),batteryIds(bix),arrivals(b),D.boxes.expected_s(ix),ev.hardDeadline_s(b),D.boxes.priority(ix)}; %#ok<AGROW>
 end
end
S.routes=out; S.sorties=cell2table(sortRows,'VariableNames',{'sortie_id','uav_type','uav_id','battery_id','box_ids','service_order','mass_kg','volume_m3','energy_kWh','flight_s','operation_s','start_s','return_s'});
S.boxDelivery=cell2table(boxRows,'VariableNames',{'box_id','area','category','sortie_id','uav_id','battery_id','arrival_s','expected_s','hard_deadline_s','priority'});
S.metrics=struct('W',W,'Cmax_s',Cmax,'energy_kWh',Etotal,'N',nr);
status.hardLateBoxes=D.boxes.id(unique(hardLate)); status.feasible=isempty(hardLate)&&height(S.boxDelivery)==height(D.boxes)&&numel(unique(S.boxDelivery.box_id))==height(D.boxes);
if ~isempty(hardLate),status.reason='One or more medical/first-batch hard deadlines are late.';
elseif height(S.boxDelivery)~=height(D.boxes)||numel(unique(S.boxDelivery.box_id))~=height(D.boxes),status.reason='Route set does not deliver every box exactly once.';
else,status.reason='PASS';end
end
