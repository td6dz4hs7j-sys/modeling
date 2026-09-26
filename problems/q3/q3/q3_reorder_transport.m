function S=q3_reorder_transport(D,S0,targetStart_s,batteryOverrides)
% Retiming with an explicitly chosen physical UAV order and same-type batteries.
S=S0;n=numel(S.routes);assert(numel(targetStart_s)==n);
if nargin<4,batteryOverrides=containers.Map('KeyType','double','ValueType','char');end
for p=1:n
 if isKey(batteryOverrides,p)
  id=string(batteryOverrides(p));
  S.routes(p).batteryID=id;S.sorties.battery_id(p)=id;
  ix=S.routes(p).boxIdx(:);
  for b=1:numel(ix)
   k=find(S.boxDelivery.box_id==D.boxes.id(ix(b)),1);
   S.boxDelivery.battery_id(k)=id;
  end
 end
end
original=reshape([S0.routes.start_s],[],1);
[~,order]=sortrows([targetStart_s(:),(1:n)']);
for z=1:n
 p=order(z);r=S.routes(p);t=max(0,targetStart_s(p));
 priorUav=[];
 for h=order(1:z-1)'
  q=S.routes(h);
  if q.uavID==r.uavID
   t=max(t,q.return_s);priorUav(end+1)=h; %#ok<AGROW>
  end
  if q.batteryID==r.batteryID,t=max(t,q.batteryReady_s);end
 end
 if isfield(r,'takeoff_s')
  u=D.uav(r.typeIdx,:);prep=r.prepStart_s;load=r.loadStart_s;
  if ~isempty(priorUav)
   prev=priorUav(end);prep=max(prep,S.routes(prev).takeoff_s);
   load=max(load,S.routes(prev).return_s);
  end
  t=max([t,prep+u.prep,load+numel(r.boxIdx)*u.load]);
  S.routes(p).prepStart_s=prep;S.routes(p).loadStart_s=load;
  S.routes(p).takeoff_s=t;
 end
 delta=t-original(p);
 S.routes(p).start_s=t;
 S.routes(p).return_s=S0.routes(p).return_s+delta;
 S.routes(p).batteryReady_s=S0.routes(p).batteryReady_s+delta;
 S.routes(p).boxArrival_s=S0.routes(p).boxArrival_s+delta;
 sid="Q2-"+compose('%03d',p);sr=find(S.sorties.sortie_id==sid,1);
 S.sorties.start_s(sr)=t;S.sorties.return_s(sr)=S.routes(p).return_s;
 ids=D.boxes.id(r.boxIdx(:));
 for b=1:numel(ids)
  br=find(S.boxDelivery.box_id==ids(b),1);
  S.boxDelivery.arrival_s(br)=S0.boxDelivery.arrival_s(br)+delta;
 end
end
S.metrics.Cmax_s=max([S.routes.return_s]);
S.metrics.N=n;S.metrics.energy_kWh=sum(arrayfun(@(r)r.eval.energy_kWh,S.routes));
arr=zeros(height(D.boxes),1);
for b=1:height(D.boxes)
 k=find(S.boxDelivery.box_id==D.boxes.id(b),1);arr(b)=S.boxDelivery.arrival_s(k);
end
S.metrics.W=sum(D.boxes.priority.*max(0,arr-D.boxes.expected_s));
end
