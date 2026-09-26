function rebuild_q2_solution(root)
% Fresh Q2 constructor: deadline-seeded multi-area routes, then strict audit.
% The old Q2 optimizer and route pool are not used.
if nargin<1, root=fileparts(fileparts(mfilename('fullpath'))); end
out=fullfile(root,'results','q2_rebuild_fresh'); if ~isfolder(out),mkdir(out);end
rng(20260926,'twister');
D=load_q2_data(root); [legs,~]=build_q2_leg_cache(D,root,false);
left=true(height(D.boxes),1); routes=repmat(struct('boxIdx',[],'nodeOrder',[],'typeIdx',[]),0,1);
freshFailure="";
% Start each trip from the most urgent unassigned box. Grow the route across
% nearby areas directly, inserting the next area while testing every type.
try
while any(left)
    rem=find(left); scarcity=zeros(numel(rem),1);
    for qi=1:numel(rem),scarcity(qi)=numel(box_feasible_types(D,legs,rem(qi)));end
    [~,ordSeed]=sortrows([D.boxes.expected_s(rem),scarcity]); seed=rem(ordSeed(1));
    routeBoxes=seed; routeNodes=D.boxNodeIndex(seed); left(seed)=false;
    changed=true;
    seedTypes=box_feasible_types(D,legs,seed);
    seedCOnlyFirstHour=D.boxes.expected_s(seed)<=3600 && numel(seedTypes)==1 && D.uav.id(seedTypes(1))=="C";
    seedFirstHour=D.boxes.expected_s(seed)<=3600;
    while changed
        changed=false; best=[]; bestScore=Inf;
        if numel(routeNodes)>=3,break;end
        candidates=find(left);
        if isempty(candidates),break;end
        present=unique(D.boxNodeIndex(candidates));
        if seedFirstHour,present=routeNodes(1);end
        for node=present(:)'
            ix=candidates(D.boxNodeIndex(candidates)==node);
            if isempty(ix),continue;end
            [~,ord]=sortrows([D.boxes.expected_s(ix),-D.boxes.priority(ix)]); ix=ix(ord);
            % Insert boxes for one new stop as a bundle, with a shared due window.
            take=ix(1); due=D.boxes.expected_s(take);
            for jj=2:numel(ix)
                b=ix(jj);
                if D.boxes.expected_s(b)<=due+900 && ...
                   sum(D.boxMass([routeBoxes(:);take(:);b]))<=max(D.uav.payload)+D.tol.mass && ...
                   sum(D.boxVolume([routeBoxes(:);take(:);b]))<=max(D.uav.volume)+D.tol.volume
                    take(end+1)=b; %#ok<AGROW>
                end
            end
            trial=[routeBoxes;take(:)]; nodes=unique([routeNodes,node],'stable');
            for k=1:height(D.uav)
                if sum(D.boxMass(trial))>D.uav.payload(k)+D.tol.mass || sum(D.boxVolume(trial))>D.uav.volume(k)+D.tol.volume,continue;end
                [seq,ev]=best_order(D,legs,trial,nodes,k);
                if ~ev.safe,continue;end
                latest=min(D.boxes.expected_s(trial)); if ev.boxArrivalOffset_s(find(trial==seed,1))>D.boxes.expected_s(seed),continue;end
                % Prefer geographic savings, then more urgent compatible boxes.
                sc=ev.energy_kWh + .0002*ev.operation_s + .000001*latest - .00001*numel(take);
                if sc<bestScore,bestScore=sc;best=struct('take',take,'seq',seq,'ev',ev,'k',k,'node',node);end
            end
        end
        if ~isempty(best)
            routeBoxes=[routeBoxes;best.take(:)]; routeNodes=best.seq; left(best.take)=false; changed=true;
        end
    end
    % Re-select a feasible type for this completed route.
    chosen=[]; chosenScore=Inf;
    for k=1:height(D.uav)
        if sum(D.boxMass(routeBoxes))>D.uav.payload(k)+D.tol.mass || sum(D.boxVolume(routeBoxes))>D.uav.volume(k)+D.tol.volume,continue;end
        [seq,ev]=best_order(D,legs,routeBoxes,routeNodes,k);
        if ev.safe && max(ev.boxArrivalOffset_s-D.boxes.expected_s(routeBoxes))<=0
            sc=ev.energy_kWh+.0002*ev.operation_s;
            if sc<chosenScore,chosenScore=sc;chosen=struct('seq',seq,'ev',ev,'k',k);end
        end
    end
    if isempty(chosen)
        % A singleton seed is always attempted under all three type ratings;
        % leave assignment to fallback only if raw data has no feasible type.
        error('Fresh constructor cannot form a return-safe route at box %s.',D.boxes.id(seed));
    end
    routes(end+1)=struct('boxIdx',routeBoxes(:),'nodeOrder',chosen.seq(:)','typeIdx',chosen.k); %#ok<AGROW>
end
catch ME
    freshFailure=string(getReport(ME,'extended','hyperlinks','off'));
end
% Schedule most urgent routes first against explicit aircraft and battery IDs.
if strlength(freshFailure)==0 && ~isempty(routes)
    for repair=0:4
        [S,ok,why,badRoute,blockingRoute]=decode_fresh(D,legs,routes);
        if ok || badRoute<1 || repair==4,break;end
        target=badRoute;if blockingRoute>0,target=blockingRoute;end
        [routes,changed]=split_urgent_stop(D,routes,target);
        if ~changed,break;end
    end
else,S=struct;ok=false;why=char(freshFailure);end
if ok
    V=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true);
else
    V=struct('status','FAIL','issues',string(why),'deliveredBoxes',0,'routeCount',numel(routes));
end
freshS=S; freshV=V; freshMetrics=struct('N',NaN,'Cmax_s',NaN,'energy_kWh',NaN);
if isfield(freshS,'metrics'),freshMetrics=freshS.metrics;end
method="fresh deadline-seeded multi-area insertion"; initialMulti=sum(arrayfun(@(r)numel(r.nodeOrder)>1,routes));
% Existing strict incumbent is only an emergency comparison checkpoint.
if ~strcmp(V.status,'PASS')
    x=load(fullfile(root,'results','q2_after_audit','q2_after_audit.mat'),'best');
    incumbent=x.best; Vf=validate_q2_solution(D,legs,incumbent,'RequireAllExpectedOnTime',true);
    assert(strcmp(Vf.status,'PASS'),'Both fresh constructor and incumbent failed strict validation.');
    S=incumbent; V=Vf; method="fresh construction failed; strict comparison checkpoint used";
end
save(fullfile(out,'q2_rebuild_solution.mat'),'D','legs','routes','S','V','method','initialMulti','freshS','freshV','freshMetrics','-v7.3');
write_q2_validation(V,fullfile(out,'q2_rebuild_validation.json'));
fid=fopen(fullfile(out,'q2_rebuild_method.txt'),'w'); c=onCleanup(@()fclose(fid));
fprintf(fid,'method=%s\nfresh_initial_routes=%d\nfresh_initial_multi_area_routes=%d\nfresh_decode=%d\n',method,numel(routes),initialMulti,ok);
if strlength(freshFailure)>0,fprintf(fid,'fresh_constructor_failure=%s\n',freshFailure);end
fprintf(fid,'fresh_validation=%s fresh_N=%g fresh_Cmax_s=%.6f fresh_energy_kWh=%.9f\n',freshV.status,freshMetrics.N,freshMetrics.Cmax_s,freshMetrics.energy_kWh);
if isfield(freshV,'issues'),for zi=1:numel(freshV.issues),fprintf(fid,'fresh_issue=%s\n',freshV.issues(zi));end,end
if ok, fprintf(fid,'fresh_N=%d fresh_Cmax_s=%.6f fresh_energy_kWh=%.9f\n',S.metrics.N,S.metrics.Cmax_s,S.metrics.energy_kWh); else, fprintf(fid,'fresh_failure=%s\n',why); end
fprintf(fid,'strict_status=%s delivered=%d routes=%d all_expected_on_time=%d\n',V.status,V.deliveredBoxes,V.routeCount,V.requireAllExpectedOnTime);
fprintf('Q2 REBUILD: method=%s initialN=%d initialMulti=%d strict=%s N=%d E=%.6f Cmax=%.3f\n',method,numel(routes),initialMulti,V.status,S.metrics.N,S.metrics.energy_kWh,S.metrics.Cmax_s);
end

function [seq,best]=best_order(D,legs,ix,nodes,k)
perms0=perms(nodes); best=[]; score=Inf; seq=nodes;
for j=1:size(perms0,1)
    q=perms0(j,:); e=evaluate_q2_route(D,legs,ix,q,k);
    if e.safe && e.capacitySafe
        % Order by expected-time margin, then flight energy.
        margin=max(e.boxArrivalOffset_s-D.boxes.expected_s(ix)); s=1000*max(0,margin)+e.energy_kWh+.0001*e.operation_s;
        if s<score,score=s;seq=q;best=e;end
    end
end
if isempty(best),best=evaluate_q2_route(D,legs,ix,nodes,k);end
end

function types=box_feasible_types(D,legs,b)
types=[];node=D.boxNodeIndex(b);
for k=1:height(D.uav)
 if D.boxMass(b)>D.uav.payload(k)+D.tol.mass || D.boxVolume(b)>D.uav.volume(k)+D.tol.volume,continue;end
 e=evaluate_q2_route(D,legs,b,node,k);if e.safe,types(end+1)=k;end %#ok<AGROW>
end
end

function [S,ok,why,badRoute,blockingRoute]=decode_fresh(D,legs,routes)
nr=numel(routes); why=''; ok=false;
badRoute=0;blockingRoute=0;
if nr==0,S=struct;why='empty route set';return;end
% Dispatch tightest routes first using latest feasible launch time across types.
due=inf(nr,1); options=zeros(nr,1);
for p=1:nr
 r0=routes(p);
 for kk=1:height(D.uav)
  if sum(D.boxMass(r0.boxIdx))>D.uav.payload(kk)+D.tol.mass || sum(D.boxVolume(r0.boxIdx))>D.uav.volume(kk)+D.tol.volume,continue;end
  e0=evaluate_q2_route(D,legs,r0.boxIdx,r0.nodeOrder,kk);
  if e0.safe,due(p)=min(due(p),min(D.boxes.expected_s(r0.boxIdx)-e0.boxArrivalOffset_s));options(p)=options(p)+1;end
 end
end
% Scarce one-type routes go first; latest feasible launch breaks ties.
[~,ord]=sortrows([options,due]); routes=routes(ord); originalRouteIndex=ord;
uavAvail=zeros(height(D.uavInventory),1); bids=strings(0,1); btype=strings(0,1); bAvail=[];
for k=1:height(D.batteryInventory),for j=1:D.batteryInventory.count(k),bids(end+1)=D.batteryInventory.type(k)+"-B"+compose('%02d',j);btype(end+1)=D.batteryInventory.type(k);bAvail(end+1)=0;end,end
out=repmat(struct('boxIdx',[],'nodeOrder',[],'typeIdx',0,'eval',[],'uavID','','batteryID','','start_s',0,'return_s',0,'batteryReady_s',0,'boxArrival_s',[]),nr,1);
sr=cell(nr,13); br=cell(0,10); W=0;E=0;C=0;
 for p=1:nr
  r=routes(p); chosen=[]; bestScore=Inf; bestViolation=Inf; diagnostic=''; limitingUav=0;
 % Reassign each route to the feasible type/resource pair with earliest
 % expected-time-safe availability; the constructor's provisional type is ignored.
 for k=1:height(D.uav)
  if sum(D.boxMass(r.boxIdx))>D.uav.payload(k)+D.tol.mass || sum(D.boxVolume(r.boxIdx))>D.uav.volume(k)+D.tol.volume,continue;end
  evk=evaluate_q2_route(D,legs,r.boxIdx,r.nodeOrder,k);
  if ~evk.capacitySafe || ~evk.safe,continue;end
  typk=D.uav.id(k); ui=find(D.uavInventory.type==typk); bi=find(btype==typk);
  for a=ui(:)',for b=bi(:)'
   st0=max(uavAvail(a),bAvail(b)); arr0=st0+evk.boxArrivalOffset_s;
   violation=max(arr0-D.boxes.expected_s(r.boxIdx));
   % Smallest feasible airframe first preserves scarce heavy aircraft for
   % routes whose payload/energy truly requires them.
   score=100*k+evk.energy_kWh+0.0001*evk.operation_s+0.00001*st0;
   if violation<=D.tol.time && score<bestScore
    bestScore=score;chosen=struct('k',k,'ev',evk,'uav',a,'bat',b,'start',st0);
   end
   if violation<bestViolation
    bestViolation=violation;badBox=find(arr0-D.boxes.expected_s(r.boxIdx)>=violation-1e-9,1);
     limitingUav=a;
     diagnostic=sprintf('route %d (%s): box %s arrival %.3f > expected %.3f by %.3f s; candidate type %s UAV-ready %.3f battery-ready %.3f',p,join(D.nodes.id(r.nodeOrder),"→"),D.boxes.id(r.boxIdx(badBox)),arr0(badBox),D.boxes.expected_s(r.boxIdx(badBox)),violation,typk,uavAvail(a),bAvail(b));
   end
  end,end
 end
  if isempty(chosen)
   why=diagnostic;badRoute=originalRouteIndex(p);
   if limitingUav>0
    prior=find(arrayfun(@(z)z<=p-1 && string(out(z).uavID)==D.uavInventory.id(limitingUav),1:nr));
    blockerScore=-Inf;
    for jj=prior(:)'
     if isempty(out(jj).boxIdx),continue;end
     if numel(out(jj).nodeOrder)>1,ss=out(jj).return_s-out(jj).start_s;else,ss=-Inf;end
     if ss>blockerScore,blockerScore=ss;blockingRoute=originalRouteIndex(jj);end
    end
   end
   S=struct;return;
  end
 k=chosen.k; ev=chosen.ev; uu=chosen.uav; bb=chosen.bat; st=chosen.start; typ=D.uav.id(k);
 ret=st+ev.operation_s; soc=ev.returnSOC;
 if soc<.9,ch=D.batteryInventory.fullCharge_s(find(D.batteryInventory.type==typ,1))*(.65*(.90-soc)/.90+.35);else,ch=D.batteryInventory.fullCharge_s(find(D.batteryInventory.type==typ,1))*.35*(1-soc)/.10;end
 ready=ret+ch; arr=st+ev.boxArrivalOffset_s;
 if any(arr>D.boxes.expected_s(r.boxIdx)+D.tol.time),why=sprintf('internal expected_s miss route %d',p);S=struct;return;end
 uavAvail(uu)=ret;bAvail(bb)=ready;
 out(p)=struct('boxIdx',r.boxIdx(:),'nodeOrder',r.nodeOrder(:)','typeIdx',k,'eval',ev,'uavID',D.uavInventory.id(uu),'batteryID',bids(bb),'start_s',st,'return_s',ret,'batteryReady_s',ready,'boxArrival_s',arr(:));
 rid="Q2-"+compose('%03d',p); boxes=join(D.boxes.id(r.boxIdx),";"); stops=join(D.nodes.id(r.nodeOrder),"→");m=sum(D.boxMass(r.boxIdx));v=sum(D.boxVolume(r.boxIdx));
 sr(p,:)={rid,typ,out(p).uavID,out(p).batteryID,boxes,stops,m,v,ev.energy_kWh,ev.flight_s,ev.operation_s,st,ret};
 for b=1:numel(r.boxIdx),z=r.boxIdx(b);br(end+1,:)={D.boxes.id(z),D.boxes.area(z),D.boxes.category(z),rid,out(p).uavID,out(p).batteryID,arr(b),D.boxes.expected_s(z),D.hardDeadline_s(z),D.boxes.priority(z)};W=W+D.boxes.priority(z)*max(0,arr(b)-D.boxes.expected_s(z));end %#ok<AGROW>
 E=E+ev.energy_kWh;C=max(C,ret);
end

S=struct;S.routes=out;S.sorties=cell2table(sr,'VariableNames',{'sortie_id','uav_type','uav_id','battery_id','box_ids','service_order','mass_kg','volume_m3','energy_kWh','flight_s','operation_s','start_s','return_s'});S.boxDelivery=cell2table(br,'VariableNames',{'box_id','area','category','sortie_id','uav_id','battery_id','arrival_s','expected_s','hard_deadline_s','priority'});S.metrics=struct('W',W,'Cmax_s',C,'energy_kWh',E,'N',nr);ok=true;
end

function [routes,changed]=split_urgent_stop(D,routes,p)
changed=false;r=routes(p);
% Split the final stop from a multi-area blocking trip to free its aircraft;
% for a direct trip, split out its most urgent box to free payload.
if numel(r.nodeOrder)==1
    if numel(r.boxIdx)<2,return;end
    [~,z]=min(D.boxes.expected_s(r.boxIdx)); at=r.boxIdx(z); rest=r.boxIdx;rest(z)=[];
    routes(p)=struct('boxIdx',rest(:),'nodeOrder',r.nodeOrder(:)','typeIdx',r.typeIdx);
    routes(end+1)=struct('boxIdx',at(:),'nodeOrder',r.nodeOrder(:)','typeIdx',r.typeIdx); %#ok<AGROW>
    changed=true;return
end
bestNode=r.nodeOrder(end);
if bestNode==0,return;end
at=r.boxIdx(D.boxNodeIndex(r.boxIdx)==bestNode); rest=r.boxIdx(D.boxNodeIndex(r.boxIdx)~=bestNode);
if isempty(at)||isempty(rest),return;end
remainingNodes=r.nodeOrder(r.nodeOrder~=bestNode);
routes(p)=struct('boxIdx',rest(:),'nodeOrder',remainingNodes(:)','typeIdx',r.typeIdx);
routes(end+1)=struct('boxIdx',at(:),'nodeOrder',bestNode,'typeIdx',r.typeIdx); %#ok<AGROW>
changed=true;
end
