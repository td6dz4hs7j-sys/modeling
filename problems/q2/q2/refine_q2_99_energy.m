function refine_q2_99_energy(root,budget_s)
% Energy-first local search; frozen 99.04309-minute completion is a hard cap.
if nargin<1,root=fileparts(fileparts(mfilename('fullpath')));end
if nargin<2,budget_s=110;end
out=fullfile(root,'results','q2_99_energy');if ~isfolder(out),mkdir(out);end
D=load_q2_data(root);D.parallelPrepLoad=true;[legs,~]=build_q2_leg_cache(D,root,false);
x=load(fullfile(root,'results','q2_prestage_23_refine','best_pass.mat'),'best');best=x.best;
cap=best.metrics.Cmax_s;N=best.metrics.N;
V=strict(best);assert(strcmp(V.status,'PASS'));
save(fullfile(out,'best_pass.mat'),'best','V','cap','-v7.3');
routes=strip(best.routes);tested=0;strictPass=0;improved=0;feasible=0;rounds=0;t=tic;
while toc(t)<budget_s&&rounds<3
 rounds=rounds+1;oldE=best.metrics.energy_kWh;oldT=best.metrics.Cmax_s;
 % In-place aircraft type and stop order.
 for i=1:N
  if expired(),break;end
  for k=1:height(D.uav)
   if k==routes(i).typeIdx,continue;end
   q=routes;q(i).typeIdx=k;consider(q);
  end
  if numel(routes(i).nodeOrder)>1
   q=routes;q(i).nodeOrder=fliplr(q(i).nodeOrder);consider(q);
  end
 end
 % Move individual boxes; preserve route count and destination consistency.
 for i=1:N
  if expired(),break;end
  if numel(routes(i).boxIdx)<=1,continue;end
  for b=routes(i).boxIdx(:)'
   for j=1:N
    if j==i||expired(),continue;end
    q=routes;q(i).boxIdx(q(i).boxIdx==b)=[];
    q(i).nodeOrder=unique(D.boxNodeIndex(q(i).boxIdx),'stable')';
    q(j).boxIdx=[q(j).boxIdx(:);b];
    q(j).nodeOrder=unique(D.boxNodeIndex(q(j).boxIdx),'stable')';
    consider(q);
   end
  end
 end
 % Exchange one box across routes, bounded by wall-clock budget.
 for i=1:N-1
  if expired(),break;end
  for j=i+1:N
   if expired(),break;end
   for a=routes(i).boxIdx(:)'
    if expired(),break;end
    for b=routes(j).boxIdx(:)'
     if expired(),break;end
     q=routes;q(i).boxIdx(q(i).boxIdx==a)=b;q(j).boxIdx(q(j).boxIdx==b)=a;
     q(i).nodeOrder=unique(D.boxNodeIndex(q(i).boxIdx),'stable')';
     q(j).nodeOrder=unique(D.boxNodeIndex(q(j).boxIdx),'stable')';consider(q);
    end
   end
  end
 end
 if best.metrics.energy_kWh>=oldE-D.tol.energy&&best.metrics.Cmax_s>=oldT-D.tol.time,break;end
end
fid=fopen(fullfile(out,'summary.txt'),'w');
fprintf(fid,'status=%s\nN=%d\nCmax_min=%.12f\nE_kWh=%.12f\nboxes=%d\ntested=%d\nfeasible_under_time_cap=%d\nstrict_PASS=%d\nimprovements=%d\nrounds=%d\nelapsed_s=%.3f\n', ...
 V.status,V.routeCount,V.independentMetrics.Cmax_s/60,V.independentMetrics.energy_kWh,V.deliveredBoxes,tested,feasible,strictPass,improved,rounds,toc(t));fclose(fid);
fprintf('Q2_99_ENERGY %s N=%d Cmax=%.9f E=%.9f tested=%d improved=%d\n', ...
 V.status,V.routeCount,V.independentMetrics.Cmax_s/60,V.independentMetrics.energy_kWh,tested,improved);
 function yes=expired(),yes=toc(t)>=budget_s;end
 function v=strict(S)
  v=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true, ...
   'AllowPrepBatteryOverlap',true,'AllowFixedPrepPrestage',true);
 end
 function consider(q)
  if expired(),return;end
  tested=tested+1;
  try
   for z=1:N
    k=q(z).typeIdx;ix=q(z).boxIdx;
    if isempty(ix)||sum(D.boxMass(ix))>D.uav.payload(k)+D.tol.mass||sum(D.boxVolume(ix))>D.uav.volume(k)+D.tol.volume,return;end
   end
   [S,st]=prestage_schedule_q2_routes(D,legs,q);
   if ~st.feasible||S.metrics.Cmax_s>cap+D.tol.time||S.metrics.N>N,return;end
   feasible=feasible+1;
   betterE=S.metrics.energy_kWh<best.metrics.energy_kWh-D.tol.energy;
   betterT=abs(S.metrics.energy_kWh-best.metrics.energy_kWh)<=D.tol.energy && S.metrics.Cmax_s<best.metrics.Cmax_s-D.tol.time;
   if ~(betterE||betterT),return;end
   W=strict(S);if ~strcmp(W.status,'PASS'),return;end
   strictPass=strictPass+1;improved=improved+1;best=S;V=W;routes=strip(S.routes);
   save(fullfile(out,'best_pass.mat'),'best','V','cap','-v7.3');
   fprintf('ENERGY_IMPROVE t=%.1f Cmax=%.9f E=%.9f tested=%d\n',toc(t),S.metrics.Cmax_s/60,S.metrics.energy_kWh,tested);
  catch ME
   fprintf('candidate exception: %s\n',ME.message);
  end
 end
end
function q=strip(a)
q=repmat(struct('boxIdx',[],'nodeOrder',[],'typeIdx',0),numel(a),1);
for i=1:numel(a),q(i)=struct('boxIdx',a(i).boxIdx(:),'nodeOrder',a(i).nodeOrder(:)','typeIdx',a(i).typeIdx);end
end
