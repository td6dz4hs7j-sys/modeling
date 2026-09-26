function run_q2_prestage(root,budget)
if nargin<1,root=fileparts(fileparts(mfilename('fullpath')));end
if nargin<2,budget=180;end
out=fullfile(root,'results','q2_prestage');if ~isfolder(out),mkdir(out);end
D=load_q2_data(root);D.parallelPrepLoad=true;[legs,~]=build_q2_leg_cache(D,root,false);
a=load(fullfile(root,'results','q2_overlap','best_22_pass.mat'),'best22');b=load(fullfile(root,'results','q2_overlap','best_23_pass.mat'),'best');c=load(fullfile(root,'results','q2_overlap_fast','best_pass.mat'),'best');seeds={a.best22.routes,b.best.routes,c.best.routes};best=[];bestV=[];
checkpoint=fullfile(out,'best_pass.mat');if isfile(checkpoint),old=load(checkpoint,'best');Vo=validate_q2_solution(D,legs,old.best,'RequireAllExpectedOnTime',true,'AllowPrepBatteryOverlap',true,'AllowFixedPrepPrestage',true);if strcmp(Vo.status,'PASS'),best=old.best;bestV=Vo;end,end
for j=1:numel(seeds)
 [S,st]=prestage_schedule_q2_routes(D,legs,seeds{j});V=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true,'AllowPrepBatteryOverlap',true,'AllowFixedPrepPrestage',true);
 fprintf('FIXED_SEED_%d feasible=%d status=%s routes=%d cmax_min=%.9f energy=%.9f\n',j,st.feasible,V.status,V.routeCount,V.independentMetrics.Cmax_s/60,V.independentMetrics.energy_kWh);
 if ~strcmp(V.status,'PASS'),disp(V.issues');end
 if strcmp(V.status,'PASS')&&(isempty(best)||S.metrics.Cmax_s<best.metrics.Cmax_s-1e-7||(abs(S.metrics.Cmax_s-best.metrics.Cmax_s)<=1e-7&&S.metrics.energy_kWh<best.metrics.energy_kWh)),best=S;bestV=V;end
end
assert(~isempty(best),'No seed passed strict prestage validation');save(fullfile(out,'best_pass.mat'),'D','legs','best','bestV','-v7.3');
fprintf('PRESTAGE_FIXED PASS N=%d Cmax=%.9f min E=%.9f kWh\n',bestV.routeCount,bestV.independentMetrics.Cmax_s/60,bestV.independentMetrics.energy_kWh);
% Bounded order/type/box neighborhood; reserve time for MATLAB startup.
t=tic;tested=0;accepted=0;rng(260926,'twister');budget=min(budget,145);
while toc(t)<budget
 base=strip_routes(best.routes);n=numel(base);cand=cell(0,1);
 [~,lastRoute]=max([best.routes.return_s]);criticalID=string(best.routes(lastRoute).uavID);criticalRoutes=find(string({best.routes.uavID})==criticalID);
 for z=1:35
  q=base;
  if rand<.65
   i=criticalRoutes(randi(numel(criticalRoutes)));types=setdiff(1:height(D.uav),q(i).typeIdx);if ~isempty(types),q(i).typeIdx=types(randi(numel(types)));end
   if n>1,j=randi(n);if i~=j,x=q(i);q(i)=q(j);q(j)=x;end,end
  elseif n>1&&rand<.55
   i=randi(n);j=randi(n);if i~=j&&~isempty(q(i).boxIdx)&&~isempty(q(j).boxIdx)
    ai=randi(numel(q(i).boxIdx));aj=randi(numel(q(j).boxIdx));tmp=q(i).boxIdx(ai);q(i).boxIdx(ai)=q(j).boxIdx(aj);q(j).boxIdx(aj)=tmp;
    q(i).nodeOrder=unique(D.boxNodeIndex(q(i).boxIdx),'stable')';q(j).nodeOrder=unique(D.boxNodeIndex(q(j).boxIdx),'stable')';
   end
  else
   i=randi(n);q(i).typeIdx=randi(height(D.uav));
  end
  if rand<.65&&n>1,i=randi(n);j=randi(n);if i~=j,x=q(i);q(i)=q(j);q(j)=x;end,end
  cand{end+1}=q; %#ok<AGROW>
 end
 for z=1:numel(cand)
  if toc(t)>=budget,break;end;tested=tested+1;
  try
   if ~all_route_types_feasible(D,cand{z}),continue;end
   [S,st]=prestage_schedule_q2_routes(D,legs,cand{z});if ~st.feasible||S.metrics.N>23|| (S.metrics.Cmax_s>best.metrics.Cmax_s-1e-7)||(abs(S.metrics.Cmax_s-best.metrics.Cmax_s)<=1e-7&&S.metrics.energy_kWh>=best.metrics.energy_kWh-1e-8),continue;end
   V=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true,'AllowPrepBatteryOverlap',true,'AllowFixedPrepPrestage',true);
   if ~strcmp(V.status,'PASS'),continue;end
   best=S;bestV=V;accepted=accepted+1;save(fullfile(out,'best_pass.mat'),'D','legs','best','bestV','-v7.3');
   fprintf('PRESTAGE_CHECKPOINT elapsed=%.1f N=%d cmax_min=%.9f E=%.9f tested=%d\n',toc(t),V.routeCount,V.independentMetrics.Cmax_s/60,V.independentMetrics.energy_kWh,tested);
  catch
  end
 end
end
fprintf('PRESTAGE_SEARCH tested=%d accepted=%d elapsed=%.2f\n',tested,accepted,toc(t));
fid=fopen(fullfile(out,'assumptions.txt'),'w');fprintf(fid,'Fixed preparation may start at previous takeoff on same UAV. Per-box loading starts no earlier than previous return. Prep and loading may overlap. Same-type battery must be charged before takeoff. No worksite count/capacity is given, so no cross-UAV station conflict is imposed.\n');fclose(fid);
end
function r=strip_routes(a)
r=repmat(struct('boxIdx',[],'nodeOrder',[],'typeIdx',0),numel(a),1);
for z=1:numel(a),r(z)=struct('boxIdx',a(z).boxIdx(:),'nodeOrder',a(z).nodeOrder(:)','typeIdx',a(z).typeIdx);end
end
function tf=all_route_types_feasible(D,r)
tf=true;for i=1:numel(r),k=r(i).typeIdx;ix=r(i).boxIdx;if sum(D.boxMass(ix))>D.uav.payload(k)+D.tol.mass||sum(D.boxVolume(ix))>D.uav.volume(k)+D.tol.volume,tf=false;return;end,end
end
