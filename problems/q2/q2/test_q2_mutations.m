function T=test_q2_mutations(D,legs,S,varargin)
% Adversarial mutations: every corrupted schedule must be rejected.
ip=inputParser;addParameter(ip,'RequireAllExpectedOnTime',false,@(x)islogical(x)&&isscalar(x));
parse(ip,varargin{:});requireAllExpectedOnTime=ip.Results.RequireAllExpectedOnTime;
names=["duplicate_box","missing_box","duplicate_sortie_row","over_capacity","incorrect_energy","over_energy","wrong_delivery","medical_late","first_batch_late","uav_conflict","battery_reused_while_charging","cross_type_battery","reported_uav_type_tamper"];
if requireAllExpectedOnTime,names(end+1)="expected_late";end
rows=cell(numel(names),3);
for c=1:numel(names)
 M=S;expected="";
 switch names(c)
  case "duplicate_box"
   M.routes(1).boxIdx=[M.routes(1).boxIdx(:);M.routes(1).boxIdx(1)];
  case "missing_box"
   M.routes(1).boxIdx(end)=[];
  case "duplicate_sortie_row"
   M.sorties=[M.sorties;M.sorties(1,:)];expected="sortie table row count or ID uniqueness mismatch";
  case "over_capacity"
   ids=find(D.boxes.area=="S001" & D.boxes.category=="饮用水");
   M.routes(1).boxIdx=ids(1:min(4,numel(ids)));M.routes(1).nodeOrder=D.nodeIndex('S001');M.routes(1).typeIdx=1;
  case "incorrect_energy"
   M.routes(1).eval.energy_kWh=M.routes(1).eval.energy_kWh+10;
  case "over_energy"
   [idx,order,k,ev]=find_overenergy_fixture(D,legs);
   r=M.routes(1);r.boxIdx=idx(:);r.nodeOrder=order(:)';r.typeIdx=k;r.eval=ev;
   r.uavID=D.uavInventory.id(find(D.uavInventory.type==D.uav.id(k),1));
   bi=find(D.batteryInventory.type==D.uav.id(k),1);r.batteryID=D.batteryInventory.type(bi)+"-B01";
   r.start_s=0;r.return_s=ev.operation_s;r.batteryReady_s=r.return_s+ev.charge_s;r.boxArrival_s=ev.boxArrivalOffset_s;
   M.routes(1)=r;expected="energy reserve violation";
  case "wrong_delivery"
   M.routes(1).boxArrival_s(1)=M.routes(1).boxArrival_s(1)+1000;
  case "medical_late"
   p=find(D.isMedical,1);M=replace_route_with_box(M,D,legs,1,p,D.hardDeadline_s(p)+10000);expected="medical hard deadline missed";
  case "first_batch_late"
   p=find(D.boxes.firstBatch & ~D.isMedical,1);assert(~isempty(p),'No non-medical first-batch box available for isolated mutation.');
   M=replace_route_with_box(M,D,legs,1,p,D.hardDeadline_s(p)+10000);expected="first-batch deadline missed";
  case "expected_late"
   p=find(~D.isHard,1);assert(~isempty(p),'No soft-only box available for expected-time mutation.');
   M=replace_route_with_box(M,D,legs,1,p,D.boxes.expected_s(p)+10000);expected="expected delivery time missed";
  case "uav_conflict"
   [i,j]=same_type_pair(M);t=min(M.routes(i).start_s,M.routes(j).start_s);M.routes(j).uavID=M.routes(i).uavID;M=shift_to(M,i,t,D);M=shift_to(M,j,t,D);expected="UAV interval overlap";
  case "battery_reused_while_charging"
   [i,j]=same_type_pair(M);M.routes(j).batteryID=M.routes(i).batteryID;
   t=min(M.routes(i).start_s,M.routes(j).start_s);M=shift_to(M,i,t,D);M=shift_to(M,j,t,D);expected="battery/charging interval overlap";
  case "cross_type_battery"
   p=1; other=find(D.batteryInventory.type~=D.uav.id(M.routes(p).typeIdx),1);
   M.routes(p).batteryID=D.batteryInventory.type(other)+"-B01";
  case "reported_uav_type_tamper"
   wrongType=D.uav.id(1); if wrongType==M.sorties.uav_type(1),wrongType=D.uav.id(2);end
   M.sorties.uav_type(1)=wrongType; expected="sortie UAV type mismatch";
 end
 V=validate_q2_solution(D,legs,M,'RequireAllExpectedOnTime',requireAllExpectedOnTime); rejected=~strcmp(V.status,'PASS');
 rows(c,:)={names(c),rejected,strjoin(V.issues(1:min(4,numel(V.issues)))," | ")};
 assert(rejected,'Mutation was accepted: %s',names(c));
 if strlength(expected)>0,assert(any(contains(V.issues,expected)),'Mutation %s did not trigger expected diagnostic "%s". Issues: %s',names(c),expected,strjoin(V.issues,' | '));end
end

T=cell2table(rows,'VariableNames',{'mutation','rejected','evidence'});
end

function S=replace_route_with_box(S,D,legs,p,b,arrivalTarget)
node=D.boxNodeIndex(b);chosen=0;ev=[];
for k=1:height(D.uav)
 trial=evaluate_q2_route(D,legs,b,node,k);
 if trial.capacitySafe&&trial.safe,chosen=k;ev=trial;break;end
end
assert(chosen>0,'No feasible type for deadline mutation fixture.');
r=S.routes(p);typ=D.uav.id(chosen);r.boxIdx=b;r.nodeOrder=node;r.typeIdx=chosen;r.eval=ev;
r.uavID=D.uavInventory.id(find(D.uavInventory.type==typ,1));bi=find(D.batteryInventory.type==typ,1);r.batteryID=typ+"-B01";
r.start_s=max(0,arrivalTarget-ev.boxArrivalOffset_s);r.return_s=r.start_s+ev.operation_s;r.batteryReady_s=r.return_s+ev.charge_s;r.boxArrival_s=r.start_s+ev.boxArrivalOffset_s;S.routes(p)=r;
end

function [idx,order,k,ev]=find_overenergy_fixture(D,legs)
% Find an actual capacity-legal but reserve-violating two-stop payload.
k=find(D.uav.id=="C",1);assert(~isempty(k),'No type C UAV available.');n=height(D.boxes);
for a=1:n-1
 for b=a+1:n
  cand=[a,b];nodes=unique(D.boxNodeIndex(cand),'stable');
  if numel(nodes)<2||sum(D.boxMass(cand))>D.uav.payload(k)+D.tol.mass||sum(D.boxVolume(cand))>D.uav.volume(k)+D.tol.volume,continue;end
  ord=perms(nodes(:)');
  for z=1:size(ord,1)
   trial=evaluate_q2_route(D,legs,cand,ord(z,:),k);
   if trial.capacitySafe&&~trial.safe,idx=cand;order=ord(z,:);ev=trial;return;end
  end
 end
end
error('Q2:NoOverEnergyFixture','No pair of boxes yields a capacity-legal reserve-violating route.');
end

function [i,j]=same_type_pair(S)
i=0;j=0;
for a=1:numel(S.routes),for b=a+1:numel(S.routes)
 if S.routes(a).typeIdx==S.routes(b).typeIdx,i=a;j=b;return;end
end,end
assert(i>0,'Need two routes of one type for resource mutation tests.');
end

function S=shift_route(S,p,delta,D)
S=shift_to(S,p,S.routes(p).start_s+delta,D);
end

function S=shift_to(S,p,newStart,D)
r=S.routes(p);r.start_s=newStart;r.return_s=newStart+r.eval.operation_s;r.batteryReady_s=r.return_s+r.eval.charge_s;r.boxArrival_s=newStart+r.eval.boxArrivalOffset_s;S.routes(p)=r;
sid="Q2-"+compose('%03d',p);row=find(S.sorties.sortie_id==sid,1);S.sorties.start_s(row)=r.start_s;S.sorties.return_s(row)=r.return_s;S.sorties.uav_id(row)=r.uavID;S.sorties.battery_id(row)=r.batteryID;
for b=1:numel(r.boxIdx),br=find(S.boxDelivery.box_id==D.boxes.id(r.boxIdx(b)),1);S.boxDelivery.arrival_s(br)=r.boxArrival_s(b);S.boxDelivery.uav_id(br)=r.uavID;S.boxDelivery.battery_id(br)=r.batteryID;end
S.metrics.Cmax_s=max([S.routes.return_s]);
late=max(0,S.boxDelivery.arrival_s-S.boxDelivery.expected_s);S.metrics.W=sum(S.boxDelivery.priority.*late);
end
