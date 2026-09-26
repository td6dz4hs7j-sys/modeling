function [S,status]=overlap_schedule_q2_routes(D,legs,routes)
% Scenario assumption: UAV preparation/loading can begin after its prior return
% while an external shared battery is still charging. Battery is needed at takeoff.
status=struct('feasible',false,'reason','');
uavAvail=zeros(height(D.uavInventory),1); uids=D.uavInventory.id;
bids=strings(0,1); btypes=strings(0,1); bav=zeros(0,1);
for k=1:height(D.batteryInventory)
 for j=1:D.batteryInventory.count(k)
  bids(end+1,1)=D.batteryInventory.type(k)+"-B"+compose('%02d',j); %#ok<AGROW>
  btypes(end+1,1)=D.batteryInventory.type(k); bav(end+1,1)=0; %#ok<AGROW>
 end
end
n=numel(routes); out=repmat(struct('boxIdx',[],'nodeOrder',[],'typeIdx',0,'eval',[],'uavID','','batteryID','','prepStart_s',0,'takeoff_s',0,'start_s',0,'return_s',0,'batteryReady_s',0,'boxArrival_s',[]),n,1);
sr=cell(n,13); br=cell(0,10); W=0; E=0; C=0; hard=[];
for p=1:n
 r=routes(p); ev=evaluate_q2_route(D,legs,r.boxIdx,r.nodeOrder,r.typeIdx);
 if ~ev.safe||~ev.capacitySafe,status.reason='route unsafe/capacity';S=struct('routes',out(1:p-1));return;end
 typ=D.uav.id(r.typeIdx); ui=find(D.uavInventory.type==typ); bi=find(btypes==typ); u=D.uav(r.typeIdx,:);
 pre=max(u.prep,numel(r.boxIdx)*u.load); % scenario assumption: prep and loading run concurrently
 pairs=[];
 for a=ui(:)',for b=bi(:)',pairs(end+1,:)=[max(uavAvail(a)+pre,bav(b)),a,b];end,end %#ok<AGROW>
 pairs=sortrows(pairs,[1 2 3]); take=pairs(1,1); a=pairs(1,2); b=pairs(1,3); ps=max(uavAvail(a),take-pre);
 flyop=ev.operation_s-pre; ret=take+flyop; ready=ret+ev.charge_s;
 arr=take+(ev.boxArrivalOffset_s-pre);
 uavAvail(a)=ret;bav(b)=ready;
 late=arr>ev.hardDeadline_s+D.tol.time;if any(late),hard=[hard;ev.boxIdx(late)];end %#ok<AGROW>
 due=D.boxes.expected_s(ev.boxIdx);pri=D.boxes.priority(ev.boxIdx);W=W+sum(pri.*max(0,arr-due)); E=E+ev.energy_kWh;C=max(C,ret);
 ev2=ev;ev2.operation_s=flyop;ev2.returnOffset_s=flyop;ev2.boxArrivalOffset_s=ev.boxArrivalOffset_s-pre;
 out(p)=struct('boxIdx',r.boxIdx(:),'nodeOrder',r.nodeOrder(:)','typeIdx',r.typeIdx,'eval',ev2,'uavID',uids(a),'batteryID',bids(b),'prepStart_s',ps,'takeoff_s',take,'start_s',take,'return_s',ret,'batteryReady_s',ready,'boxArrival_s',arr);
 id="Q2-"+compose('%03d',p);sr(p,:)={id,typ,uids(a),bids(b),join(D.boxes.id(ev.boxIdx),";"),join(D.nodes.id(ev.nodeOrder),"→"),ev.mass_kg,ev.volume_m3,ev.energy_kWh,ev.flight_s,flyop,take,ret};
 for q=1:numel(ev.boxIdx),ix=ev.boxIdx(q);br(end+1,:)={D.boxes.id(ix),D.boxes.area(ix),D.boxes.category(ix),id,uids(a),bids(b),arr(q),D.boxes.expected_s(ix),ev.hardDeadline_s(q),D.boxes.priority(ix)};end %#ok<AGROW>
end
S=struct('routes',out,'sorties',cell2table(sr,'VariableNames',{'sortie_id','uav_type','uav_id','battery_id','box_ids','service_order','mass_kg','volume_m3','energy_kWh','flight_s','operation_s','start_s','return_s'}),'boxDelivery',cell2table(br,'VariableNames',{'box_id','area','category','sortie_id','uav_id','battery_id','arrival_s','expected_s','hard_deadline_s','priority'}),'metrics',struct('W',W,'Cmax_s',C,'energy_kWh',E,'N',n));
status.feasible=isempty(hard)&&height(S.boxDelivery)==height(D.boxes)&&numel(unique(S.boxDelivery.box_id))==height(D.boxes);
if status.feasible,status.reason='PASS';else,status.reason='hard deadline or delivery coverage failure';end
end
