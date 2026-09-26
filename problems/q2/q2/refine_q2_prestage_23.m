function refine_q2_prestage_23(root,budget)
% Bounded time-first search from the independently validated 23-sortie plan.
if nargin<1,root=fileparts(fileparts(mfilename('fullpath')));end
if nargin<2,budget=90;end
out=fullfile(root,'results','q2_prestage_23_refine');if ~isfolder(out),mkdir(out);end
D=load_q2_data(root);D.parallelPrepLoad=true;[legs,~]=build_q2_leg_cache(D,root,false);
x=load(fullfile(root,'results','q2_prestage_split23','best_23_pass.mat'),'best23');best=x.best23;
V=validate_q2_solution(D,legs,best,'RequireAllExpectedOnTime',true,'AllowPrepBatteryOverlap',true,'AllowFixedPrepPrestage',true);assert(strcmp(V.status,'PASS'));
bestV=V;save(fullfile(out,'best_pass.mat'),'D','legs','best','bestV','-v7.3');
t=tic;tested=0;passed=0;accepted=0;invalid=0;rounds=0;
while toc(t)<budget&&rounds<4
 rounds=rounds+1;rr=strip(best.routes);n=numel(rr);old=best.metrics.Cmax_s;
 % Execution order: all relocations and swaps.
 for i=1:n
  for j=1:n
   if toc(t)>=budget,break;end
   if i==j,continue;end
   q=rr;item=q(i);q(i)=[];q=[q(1:j-1);item;q(j:end)];consider(q);
   if j>i,q=rr;q([i j])=q([j i]);consider(q);end
  end
  if toc(t)>=budget,break;end
 end
 % Critical UAV: move one box or a complete service stop into another route.
 [~,p]=max([best.routes.return_s]);uid=string(best.routes(p).uavID);
 critical=find(string({best.routes.uavID})==uid);
 for ii=critical(:)'
  if toc(t)>=budget,break;end
  source=rr(ii);if numel(source.boxIdx)<2,continue;end
  groups=cell(0,1);for b=source.boxIdx(:)',groups{end+1}=b;end %#ok<AGROW>
  nodes=unique(D.boxNodeIndex(source.boxIdx));
  for nd=nodes(:)',g=source.boxIdx(D.boxNodeIndex(source.boxIdx)==nd);if numel(g)<numel(source.boxIdx),groups{end+1}=g;end,end %#ok<AGROW>
  for gi=1:numel(groups)
   moved=groups{gi}(:);remain=setdiff(source.boxIdx,moved,'stable');if isempty(remain),continue;end
   for j=1:n
    if j==ii||toc(t)>=budget,continue;end
    q=rr;q(ii).boxIdx=remain(:);q(ii).nodeOrder=unique(D.boxNodeIndex(remain),'stable')';
    q(j).boxIdx=[q(j).boxIdx(:);moved];q(j).nodeOrder=unique(D.boxNodeIndex(q(j).boxIdx),'stable')';consider(q);
   end
  end
 end
 % In-place type and service order changes.
 for i=1:n
  if toc(t)>=budget,break;end
  for k=1:height(D.uav)
   if k==rr(i).typeIdx,continue;end
   q=rr;q(i).typeIdx=k;consider(q);
  end
  if numel(rr(i).nodeOrder)>1
   q=rr;q(i).nodeOrder=fliplr(q(i).nodeOrder);consider(q);
  end
 end
 if best.metrics.Cmax_s>=old-D.tol.time,break;end
end
fid=fopen(fullfile(out,'summary.txt'),'w');fprintf(fid,'status=%s\nN=%d\nCmax_min=%.12f\nE_kWh=%.12f\nboxes=%d\nrounds=%d\ntested=%d\nstrict_pass=%d\naccepted=%d\ninvalid=%d\nelapsed_s=%.3f\n',bestV.status,bestV.routeCount,bestV.independentMetrics.Cmax_s/60,bestV.independentMetrics.energy_kWh,bestV.deliveredBoxes,rounds,tested,passed,accepted,invalid,toc(t));fclose(fid);
fprintf('PRESTAGE23_REFINE PASS N=%d Cmax=%.9f E=%.9f tested=%d accepted=%d elapsed=%.1f\n',bestV.routeCount,bestV.independentMetrics.Cmax_s/60,bestV.independentMetrics.energy_kWh,tested,accepted,toc(t));
 function consider(q)
  if toc(t)>=budget,return;end
  tested=tested+1;
  try
   for h=1:numel(q)
    k=q(h).typeIdx;ix=q(h).boxIdx;
    if isempty(ix)||sum(D.boxMass(ix))>D.uav.payload(k)+D.tol.mass||sum(D.boxVolume(ix))>D.uav.volume(k)+D.tol.volume,invalid=invalid+1;return;end
   end
   [S,st]=prestage_schedule_q2_routes(D,legs,q);
   if ~st.feasible||S.metrics.Cmax_s>=best.metrics.Cmax_s-D.tol.time,return;end
   W=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true,'AllowPrepBatteryOverlap',true,'AllowFixedPrepPrestage',true);
   if ~strcmp(W.status,'PASS'),invalid=invalid+1;return;end
   passed=passed+1;accepted=accepted+1;best=S;bestV=W;
   save(fullfile(out,'best_pass.mat'),'D','legs','best','bestV','-v7.3');
   fprintf('IMPROVE t=%.1f N=%d Cmax=%.9f E=%.9f tested=%d\n',toc(t),W.routeCount,W.independentMetrics.Cmax_s/60,W.independentMetrics.energy_kWh,tested);
  catch
   invalid=invalid+1;
  end
 end
end
function r=strip(a)
r=repmat(struct('boxIdx',[],'nodeOrder',[],'typeIdx',0),numel(a),1);
for i=1:numel(a),r(i)=struct('boxIdx',a(i).boxIdx(:),'nodeOrder',a(i).nodeOrder(:)','typeIdx',a(i).typeIdx);end
end
