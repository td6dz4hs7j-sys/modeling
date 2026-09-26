function [S,status]=prestage_schedule_q2_routes(D,legs,routes)
% Assumption: fixed preparation may start at the prior takeoff; loading waits
% for the prior return. Loading and fixed prep run concurrently.
status=struct('feasible',false,'reason','');uavAvail=zeros(height(D.uavInventory),1);lastTake=zeros(height(D.uavInventory),1);uids=D.uavInventory.id;
bids=strings(0,1);btypes=strings(0,1);bav=[];
for k=1:height(D.batteryInventory),for j=1:D.batteryInventory.count(k),bids(end+1)=D.batteryInventory.type(k)+"-B"+compose('%02d',j);btypes(end+1)=D.batteryInventory.type(k);bav(end+1)=0;end,end
n=numel(routes);out=repmat(struct('boxIdx',[],'nodeOrder',[],'typeIdx',0,'eval',[],'uavID','','batteryID','','prepStart_s',0,'loadStart_s',0,'takeoff_s',0,'start_s',0,'return_s',0,'batteryReady_s',0,'boxArrival_s',[]),n,1);sr=cell(n,13);br=cell(0,10);W=0;E=0;C=0;hard=[];
for p=1:n
 r=routes(p);ev=evaluate_q2_route(D,legs,r.boxIdx,r.nodeOrder,r.typeIdx);if ~ev.safe||~ev.capacitySafe,status.reason='unsafe route';S=struct('routes',out(1:p-1));return;end
 typ=D.uav.id(r.typeIdx);ui=find(D.uavInventory.type==typ);bi=find(btypes==typ);u=D.uav(r.typeIdx,:);pre=u.prep;load=numel(r.boxIdx)*u.load;
 pairs=[];for a=ui(:)',for b=bi(:)',ps=lastTake(a);ls=uavAvail(a);take=max([ps+pre,ls+load,bav(b)]);pairs(end+1,:)=[take,a,b,ps,ls];end,end %#ok<AGROW>
 pairs=sortrows(pairs,[1 2 3]);take=pairs(1,1);a=pairs(1,2);b=pairs(1,3);ps=pairs(1,4);ls=pairs(1,5);ret=take+ev.operation_s-max(pre,load);ready=ret+ev.charge_s;arr=take+ev.boxArrivalOffset_s-max(pre,load);
 uavAvail(a)=ret;lastTake(a)=take;bav(b)=ready;late=arr>ev.hardDeadline_s+D.tol.time;if any(late),hard=[hard;ev.boxIdx(late)];end
 W=W+sum(D.boxes.priority(ev.boxIdx).*max(0,arr-D.boxes.expected_s(ev.boxIdx)));E=E+ev.energy_kWh;C=max(C,ret);ev2=ev;ev2.operation_s=ev.operation_s-max(pre,load);ev2.returnOffset_s=ev2.operation_s;ev2.boxArrivalOffset_s=ev.boxArrivalOffset_s-max(pre,load);
 out(p)=struct('boxIdx',r.boxIdx(:),'nodeOrder',r.nodeOrder(:)','typeIdx',r.typeIdx,'eval',ev2,'uavID',uids(a),'batteryID',bids(b),'prepStart_s',ps,'loadStart_s',ls,'takeoff_s',take,'start_s',take,'return_s',ret,'batteryReady_s',ready,'boxArrival_s',arr);
 id="Q2-"+compose('%03d',p);sr(p,:)={id,typ,uids(a),bids(b),join(D.boxes.id(ev.boxIdx),";"),join(D.nodes.id(ev.nodeOrder),"→"),ev.mass_kg,ev.volume_m3,ev.energy_kWh,ev.flight_s,ev2.operation_s,take,ret};for q=1:numel(ev.boxIdx),ix=ev.boxIdx(q);br(end+1,:)={D.boxes.id(ix),D.boxes.area(ix),D.boxes.category(ix),id,uids(a),bids(b),arr(q),D.boxes.expected_s(ix),ev.hardDeadline_s(q),D.boxes.priority(ix)};end
end
S=struct('routes',out,'sorties',cell2table(sr,'VariableNames',{'sortie_id','uav_type','uav_id','battery_id','box_ids','service_order','mass_kg','volume_m3','energy_kWh','flight_s','operation_s','start_s','return_s'}),'boxDelivery',cell2table(br,'VariableNames',{'box_id','area','category','sortie_id','uav_id','battery_id','arrival_s','expected_s','hard_deadline_s','priority'}),'metrics',struct('W',W,'Cmax_s',C,'energy_kWh',E,'N',n));status.feasible=isempty(hard)&&height(S.boxDelivery)==height(D.boxes);status.reason='PASS';
end
