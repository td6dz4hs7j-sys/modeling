function E = evaluate_q2_route(D,legs,boxIdx,nodeOrder,typeIdx)
% Evaluate a route from box IDs, ordered unique service nodes and UAV type.
boxIdx=double(boxIdx(:)); nodeOrder=double(nodeOrder(:)');
assert(~isempty(boxIdx) && all(boxIdx>=1 & boxIdx<=height(D.boxes)) && numel(unique(boxIdx))==numel(boxIdx));
assert(~isempty(nodeOrder) && all(nodeOrder>=2 & nodeOrder<=height(D.nodes)) && numel(unique(nodeOrder))==numel(nodeOrder));
u=D.uav(typeIdx,:); stopCounts=zeros(size(nodeOrder));
for k=1:numel(nodeOrder)
 stopCounts(k)=sum(D.boxNodeIndex(boxIdx)==nodeOrder(k));
 assert(stopCounts(k)>0,'Route visits a node without boxes.');
end
assert(sum(stopCounts)==numel(boxIdx),'Route nodeOrder must cover every box destination exactly once.');
mass=sum(D.boxMass(boxIdx)); volume=sum(D.boxVolume(boxIdx));
% Optional scenario: preparation and loading overlap from the route start.
if isfield(D,'parallelPrepLoad') && D.parallelPrepLoad
    preflight=max(u.prep,numel(boxIdx)*u.load);
else
    preflight=u.prep+numel(boxIdx)*u.load;
end
remaining=mass; energy=0; flight=0; clock=preflight;
boxArrival=zeros(numel(boxIdx),1); legEnergy=zeros(numel(nodeOrder)+1,1); legFlight=legEnergy;
nodeSeq=[1,nodeOrder,1];
for h=1:numel(nodeSeq)-1
 a=nodeSeq(h); b=nodeSeq(h+1); P=q2_get_leg(legs,a,b);
 q=remaining;
 L=u.range0-(u.range0-u.rangeF)*(q/u.payload)^1.5;
 assert(q>=-D.tol.mass && q<=u.payload+D.tol.mass,'Payload outside type rating.');
 eh=u.energy*P.distance_m/L;
 eu=(u.mass+q)*D.g*P.up_m/(u.eta*3.6e6);
 legEnergy(h)=eh+eu; energy=energy+legEnergy(h);
 legFlight(h)=P.up_m/u.up+P.distance_m/u.speed+P.down_m/u.down;
 flight=flight+legFlight(h); clock=clock+legFlight(h);
 if b~=1
  at=find(nodeOrder==b,1); idx=boxIdx(D.boxNodeIndex(boxIdx)==b);
  clock=clock+u.handover+numel(idx)*u.boxhandover;
  boxArrival(ismember(boxIdx,idx))=clock;
  remaining=remaining-sum(D.boxMass(idx));
 end
end
 deadline=D.hardDeadline_s(boxIdx);
 maxSOC=1-energy/u.energy;
 bt=find(D.batteryInventory.type==u.id,1); assert(~isempty(bt),'Missing matching battery inventory.'); Tfull=D.batteryInventory.fullCharge_s(bt);
 if maxSOC<0.9, charge=Tfull*(0.65*(0.90-maxSOC)/0.90+0.35);
 else, charge=Tfull*0.35*(1-maxSOC)/0.10; end
E=struct('boxIdx',boxIdx,'nodeOrder',nodeOrder,'typeIdx',typeIdx,'mass_kg',mass,'volume_m3',volume,'energy_kWh',energy,'flight_s',flight,'operation_s',clock,'boxArrivalOffset_s',boxArrival,'returnOffset_s',clock,'returnSOC',maxSOC,'charge_s',charge,'hardDeadline_s',deadline,'safe',energy<=(1-u.reserve)*u.energy+D.tol.energy,'capacitySafe',mass<=u.payload+D.tol.mass && volume<=u.volume+D.tol.volume,'legEnergy_kWh',legEnergy,'legFlight_s',legFlight,'stopCounts',stopCounts);
end

function x=q2_get_leg(legs,a,b)
n=16; assert(a~=b && a>=1 && a<=n && b>=1 && b<=n,'Invalid leg index.');
ix=(a-1)*(n-1)+b-double(b>a); assert(ix<=numel(legs),'Missing leg %d -> %d',a,b); x=legs(ix);
end
