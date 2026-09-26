function [F,ctx] = q2_fast_schedule(D,legs,routes,ctx)
% Table-free implementation of schedule_q2_routes with the same decoder rules.
% Route evaluations are cached only for an exact model fingerprint, box set,
% ordered stop list, UAV type, and evaluator version.
if nargin<4||isempty(ctx),ctx=q2_fast_context(D,legs);end
ticFast=tic; nr=numel(routes); nBoxes=height(D.boxes);
F=struct('feasible',false,'reason','','metrics',struct('W',Inf,'Cmax_s',Inf,'energy_kWh',Inf,'N',nr), ...
 'routeEvalSeconds',0,'decodeSeconds',0,'cacheHits',0,'cacheMisses',0,'modelFingerprint',ctx.modelFingerprint);
if nr==0,F.reason='No routes.';return;end
allBoxes=[];
for p=1:nr
 b=double(routes(p).boxIdx(:)); typ=double(routes(p).typeIdx); nodes=double(routes(p).nodeOrder(:)');
 if isempty(b)||any(~isfinite(b))||any(mod(b,1)~=0)||any(b<1|b>nBoxes)||numel(unique(b))~=numel(b)
  F.reason=sprintf('route %d has invalid or repeated box indices',p);return
 end
 if isempty(nodes)||any(~isfinite(nodes))||any(mod(nodes,1)~=0)||any(nodes<2|nodes>height(D.nodes))||numel(unique(nodes))~=numel(nodes)
  F.reason=sprintf('route %d has invalid stop order',p);return
 end
 if typ<1||typ>height(D.uav)||mod(typ,1)~=0
  F.reason=sprintf('route %d has invalid UAV type',p);return
 end
 allBoxes=[allBoxes;b]; %#ok<AGROW>
 dest=unique(D.boxNodeIndex(b),'stable');
 if ~isequal(sort(dest(:)),sort(nodes(:)))
  F.reason=sprintf('route %d stops do not match box destinations',p);return
 end
 u=D.uav(typ,:);
 if sum(D.boxMass(b))>u.payload+D.tol.mass||sum(D.boxVolume(b))>u.volume+D.tol.volume
  F.reason=sprintf('route %d exceeds mass/volume rating',p);return
 end
end
if numel(allBoxes)~=nBoxes||~isequal(sort(allBoxes),(1:nBoxes)')
 F.reason='Route set does not deliver every box exactly once';return
end

routeEvalSeconds=0; cacheHits=0;cacheMisses=0;evals=cell(nr,1);
for p=1:nr
 b=double(routes(p).boxIdx(:));nodes=double(routes(p).nodeOrder(:)');typ=double(routes(p).typeIdx);
 key=q2_fast_route_key(ctx.modelFingerprint,b,nodes,typ);
 if isKey(ctx.routeCache,key)
  evCanonical=ctx.routeCache(key);cacheHits=cacheHits+1;
 else
  % Canonical box order makes the cached result independent of storage order.
  sortedBox=sort(b);t=tic;
  try,evCanonical=evaluate_q2_route(D,legs,sortedBox,nodes,typ);catch ME
   F.reason=sprintf('route %d evaluation failed: %s',p,ME.message);return
  end
  routeEvalSeconds=routeEvalSeconds+toc(t);cacheMisses=cacheMisses+1;ctx.routeCache(key)=evCanonical;
 end
 ev=evCanonical; ev.boxIdx=b;
 [~,map]=ismember(b,evCanonical.boxIdx);
 ev.boxArrivalOffset_s=evCanonical.boxArrivalOffset_s(map);
 ev.hardDeadline_s=evCanonical.hardDeadline_s(map);
 if ~ev.safe,F.reason=sprintf('route %d violates return-energy reserve',p);return;end
 evals{p}=ev;
end

% Preserve inventory order and the decoder's [availability, UAV row, battery row] tie break.
uavAvailable=zeros(height(D.uavInventory),1); uavType=D.uavInventory.type;
batteryIds=strings(0,1);batteryTypes=strings(0,1);batteryAvailable=zeros(0,1);
for k=1:height(D.batteryInventory)
 for j=1:D.batteryInventory.count(k)
  batteryIds(end+1,1)=D.batteryInventory.type(k)+"-B"+compose('%02d',j); %#ok<AGROW>
  batteryTypes(end+1,1)=D.batteryInventory.type(k);batteryAvailable(end+1,1)=0; %#ok<AGROW>
 end
end
W=0;Cmax=0;Etotal=0;
for p=1:nr
 ev=evals{p};typ=D.uav.id(ev.typeIdx);ui=find(uavType==typ);bi=find(batteryTypes==typ);
 if isempty(ui)||isempty(bi),F.reason=sprintf('route %d type %s lacks resources',p,typ);return;end
 pairs=zeros(numel(ui)*numel(bi),3);z=0;
 for a=1:numel(ui),for b=1:numel(bi),z=z+1;pairs(z,:)=[max(uavAvailable(ui(a)),batteryAvailable(bi(b))),ui(a),bi(b)];end,end
 pairs=sortrows(pairs,[1 2 3]); start=pairs(1,1);uix=pairs(1,2);bix=pairs(1,3);
 ret=start+ev.returnOffset_s;ready=ret+ev.charge_s;
 uavAvailable(uix)=ret;batteryAvailable(bix)=ready;
 arrivals=start+ev.boxArrivalOffset_s;
 if any(arrivals>ev.hardDeadline_s+D.tol.time),F.reason='One or more medical/first-batch hard deadlines are late';return;end
 ix=ev.boxIdx;W=W+sum(D.boxes.priority(ix).*max(0,arrivals-D.boxes.expected_s(ix)));
 Cmax=max(Cmax,ret);Etotal=Etotal+ev.energy_kWh;
end
F.feasible=true;F.reason='PASS';F.metrics=struct('W',W,'Cmax_s',Cmax,'energy_kWh',Etotal,'N',nr);
F.routeEvalSeconds=routeEvalSeconds;F.decodeSeconds=toc(ticFast)-routeEvalSeconds;F.elapsedSeconds=toc(ticFast);
F.cacheHits=cacheHits;F.cacheMisses=cacheMisses;
end

function key=q2_fast_route_key(fp,boxes,nodes,typ)
key=sprintf('%s|%s|b=%s|n=%s|t=%d',fp,'q2-fast-route-v1',sprintf('%d,',sort(boxes)),sprintf('%d,',nodes),typ);
end
