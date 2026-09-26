function restructure_q2_prestage_23(root,budget)
% Merge two noncritical trips to free a trip, then split a critical trip.
if nargin<1,root=fileparts(fileparts(mfilename('fullpath')));end
if nargin<2,budget=90;end
out=fullfile(root,'results','q2_prestage_23_restructure');if ~isfolder(out),mkdir(out);end
D=load_q2_data(root);D.parallelPrepLoad=true;[legs,~]=build_q2_leg_cache(D,root,false);
x=load(fullfile(root,'results','q2_prestage_23_refine','best_pass.mat'),'best');best=x.best;
bestV=validate_q2_solution(D,legs,best,'RequireAllExpectedOnTime',true,'AllowPrepBatteryOverlap',true,'AllowFixedPrepPrestage',true);assert(strcmp(bestV.status,'PASS'));
save(fullfile(out,'best_pass.mat'),'D','legs','best','bestV','-v7.3');
t=tic;tested=0;valid=0;accepted=0;filtered=0;rounds=0;
while toc(t)<budget&&rounds<3
 rounds=rounds+1;routes=strip(best.routes);N=numel(routes);before=best.metrics.Cmax_s;
 [~,last]=max([best.routes.return_s]);criticalID=string(best.routes(last).uavID);
 crit=find(string({best.routes.uavID})==criticalID);
 noncrit=setdiff(1:N,crit);
 pairList=zeros(0,3);
 for aa=1:numel(noncrit)-1
  for bb=aa+1:numel(noncrit)
   i=noncrit(aa);j=noncrit(bb);
   ix=[routes(i).boxIdx(:);routes(j).boxIdx(:)];
   if sum(D.boxMass(ix))<=max(D.uav.payload)+D.tol.mass&&sum(D.boxVolume(ix))<=max(D.uav.volume)+D.tol.volume
    pairList(end+1,:)=[sum(D.boxMass(ix)),i,j]; %#ok<AGROW>
   end
  end
 end
 if isempty(pairList),break;end
 pairList=sortrows(pairList,1);pairList=pairList(1:min(14,size(pairList,1)),:);
 for pp=1:size(pairList,1)
  if toc(t)>=budget,break;end
  i=pairList(pp,2);j=pairList(pp,3);
  mergeBoxes=[routes(i).boxIdx(:);routes(j).boxIdx(:)];
  mergeNodes=unique(D.boxNodeIndex(mergeBoxes),'stable')';
  for kMerge=1:height(D.uav)
   if ~fits(mergeBoxes,kMerge),continue;end
   merge=struct('boxIdx',mergeBoxes,'nodeOrder',mergeNodes,'typeIdx',kMerge);
   for p=crit(:)'
    if toc(t)>=budget,break;end
    source=routes(p);if numel(source.boxIdx)<2,continue;end
    groups=cell(0,1);
    for b=source.boxIdx(:)',groups{end+1}=b;end %#ok<AGROW>
    nodes=unique(D.boxNodeIndex(source.boxIdx));
    for node=nodes(:)',g=source.boxIdx(D.boxNodeIndex(source.boxIdx)==node);if numel(g)<numel(source.boxIdx),groups{end+1}=g;end,end %#ok<AGROW>
    for z=1:numel(groups)
     if toc(t)>=budget,break;end
     moved=groups{z}(:);remain=setdiff(source.boxIdx,moved,'stable');if isempty(remain),continue;end
     for kNew=1:height(D.uav)
      if ~fits(moved,kNew),continue;end
      split=struct('boxIdx',moved,'nodeOrder',unique(D.boxNodeIndex(moved),'stable')','typeIdx',kNew);
      q=routes;q(p).boxIdx=remain(:);q(p).nodeOrder=unique(D.boxNodeIndex(remain),'stable')';
      q([i,j])=[];q=[q;merge;split];
      % Move the new trips into early, source-adjacent, and late positions.
      for mode=1:3
       if toc(t)>=budget,break;end
       v=q;
       if mode==1
        v=[v(end-1:end);v(1:end-2)];
       elseif mode==2
        v(end)=[];pos=min(p,numel(v)+1);v=[v(1:pos-1);split;v(pos:end)];
       end
       consider(v);
      end
     end
    end
   end
  end
 end
 if best.metrics.Cmax_s>=before-D.tol.time,break;end
end
fid=fopen(fullfile(out,'summary.txt'),'w');fprintf(fid,'status=%s\nN=%d\nCmax_min=%.12f\nE_kWh=%.12f\nboxes=%d\nrounds=%d\ntested=%d\nstrict_pass=%d\naccepted=%d\nfiltered=%d\nelapsed_s=%.3f\n',bestV.status,bestV.routeCount,bestV.independentMetrics.Cmax_s/60,bestV.independentMetrics.energy_kWh,bestV.deliveredBoxes,rounds,tested,valid,accepted,filtered,toc(t));fclose(fid);
fprintf('RESTRUCTURE PASS N=%d Cmax=%.9f E=%.9f tested=%d accepted=%d elapsed=%.1f\n',bestV.routeCount,bestV.independentMetrics.Cmax_s/60,bestV.independentMetrics.energy_kWh,tested,accepted,toc(t));
 function tf=fits(ix,k)
  tf=sum(D.boxMass(ix))<=D.uav.payload(k)+D.tol.mass&&sum(D.boxVolume(ix))<=D.uav.volume(k)+D.tol.volume;
 end
 function consider(v)
  if toc(t)>=budget,return;end
  tested=tested+1;
  try
   [S,st]=prestage_schedule_q2_routes(D,legs,v);
   if ~st.feasible||S.metrics.Cmax_s>=best.metrics.Cmax_s-D.tol.time,return;end
   W=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true,'AllowPrepBatteryOverlap',true,'AllowFixedPrepPrestage',true);
   if ~strcmp(W.status,'PASS'),filtered=filtered+1;return;end
   valid=valid+1;accepted=accepted+1;best=S;bestV=W;
   save(fullfile(out,'best_pass.mat'),'D','legs','best','bestV','-v7.3');
   fprintf('RESTRUCTURE_IMPROVE t=%.1f Cmax=%.9f E=%.9f tested=%d\n',toc(t),W.independentMetrics.Cmax_s/60,W.independentMetrics.energy_kWh,tested);
  catch
   filtered=filtered+1;
  end
 end
end
function r=strip(a)
r=repmat(struct('boxIdx',[],'nodeOrder',[],'typeIdx',0),numel(a),1);
for k=1:numel(a),r(k)=struct('boxIdx',a(k).boxIdx(:),'nodeOrder',a(k).nodeOrder(:)','typeIdx',a(k).typeIdx);end
end
