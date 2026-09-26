function report = check_q1_inheritance(D,legs)
% Compare Q2 single-area route calculations with the established Q1 models.
% This is a numerical inheritance check only; it does not alter either model.
nNodes=height(D.nodes); nArea=nNodes-1; tolE=D.tol.energy; tolT=D.tol.time;
eMax=0; tMax=0; eCases=0; tCases=0; routeCases=0; asymMax=0;
for a=2:nNodes
 area=D.nodes.id(a); i=D.nodeIndex(char(area)); Pout=getleg(legs,1,i,nNodes); Pret=getleg(legs,i,1,nNodes);
 P=struct('distance',Pout.distance_m,'outUp',Pout.up_m,'backUp',Pret.up_m);
 asymMax=max(asymMax,abs(Pout.distance_m-Pret.distance_m));
 if abs(Pout.distance_m-Pret.distance_m)>1e-6
  error('Q1 inheritance distance asymmetry exceeds tolerance for %s.',area);
 end
 for k=1:height(D.uav)
  u=D.uav(k,:); qvals=[0,0.5*u.payload,u.payload];
  for q=qvals
   L=u.range0-(u.range0-u.rangeF)*(q/u.payload)^1.5;
   Emanual=u.energy*(P.distance/L+P.distance/u.range0)+ ...
    D.g*((u.mass+q)*P.outUp+u.mass*P.backUp)/(u.eta*3.6e6);
   Ecommon=flight_energy_model(u,P,q,D.g);
   eMax=max(eMax,abs(Emanual-Ecommon)); eCases=eCases+1;
  end
  % The first real box at this area supplies a Q2 one-stop route case.
  b=find(D.boxes.area==area,1,'first'); assert(~isempty(b),'Area %s has no boxes.',area);
  Ebox=flight_energy_model(u,P,D.boxMass(b),D.g);
  Teval=evaluate_q2_route(D,legs,b,a,k);
  [Tcommon,Tflight]=flight_time_model(u,P,1);
  eMax=max(eMax,abs(Ebox-Teval.energy_kWh));
  tMax=max(tMax,abs(Tcommon-Teval.operation_s));
  tMax=max(tMax,abs(Tflight-Teval.flight_s));
  eCases=eCases+1; tCases=tCases+2; routeCases=routeCases+1;
 end
end
assert(eMax<=tolE,'Q1/Q2 energy inheritance mismatch: %.12g kWh > %.12g.',eMax,tolE);
assert(tMax<=tolT,'Q1/Q2 time inheritance mismatch: %.12g s > %.12g.',tMax,tolT);
report=struct('maxEnergyError_kWh',eMax,'maxTimeError_s',tMax, ...
 'energyCaseCount',eCases,'timeCaseCount',tCases,'singleBoxRouteCount',routeCases, ...
 'maxDirectionalDistanceDifference_m',asymMax,'energyTolerance_kWh',tolE,'timeTolerance_s',tolT, ...
 'status','PASS');
end

function P=getleg(legs,a,b,n)
ix=(a-1)*(n-1)+b-double(b>a); assert(ix>=1&&ix<=numel(legs),'Missing leg %d -> %d.',a,b); P=legs(ix);
end
