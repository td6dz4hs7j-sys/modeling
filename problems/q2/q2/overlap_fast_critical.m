function overlap_fast_critical(root,budget)
% Critical-UAV stop-group transfer neighborhood on the saved fast incumbent.
if nargin<1,root=fileparts(fileparts(mfilename('fullpath')));end;if nargin<2,budget=65;end
out=fullfile(root,'results','q2_overlap_fast');D=load_q2_data(root);D.parallelPrepLoad=true;[legs,~]=build_q2_leg_cache(D,root,false);
x=load(fullfile(out,'best_pass.mat'),'best');best=x.best;V=validate_q2_solution(D,legs,best,'RequireAllExpectedOnTime',true,'AllowPrepBatteryOverlap',true);assert(strcmp(V.status,'PASS'));
t=tic;tested=0;pruned=0;accepted=0;lastUav="";lastRoute=0;
while toc(t)<budget
 [~,p]=max([best.routes.return_s]);crit=best.routes(p);lastUav=string(crit.uavID);lastRoute=p;
 chain=find(string({best.routes.uavID})==lastUav);cand={};
 % Reassign chain routes to each compatible type; route-order exchanges within the chain.
 for ii=chain(:)'
  for typ=1:height(D.uav),if typ==best.routes(ii).typeIdx,continue;end;q=strip(best.routes);q(ii).typeIdx=typ;cand{end+1}=q;end %#ok<AGROW>
 end
 for a=1:numel(chain),for b=a+1:numel(chain),q=strip(best.routes);q([chain(a),chain(b)])=q([chain(b),chain(a)]);cand{end+1}=q;end,end %#ok<AGROW>
 % Move service stops from critical-chain multi-stop sorties to another route.
 for ii=chain(:)'
  rcrit=best.routes(ii);stops=unique(D.boxNodeIndex(rcrit.boxIdx),'stable');
  if numel(stops)>1
   for node=stops(:)'
    moved=rcrit.boxIdx(D.boxNodeIndex(rcrit.boxIdx)==node);remain=rcrit.boxIdx(D.boxNodeIndex(rcrit.boxIdx)~=node);
    for j=1:numel(best.routes),if j==ii,continue;end;q=strip(best.routes);q(ii).boxIdx=remain;q(ii).nodeOrder=unique(D.boxNodeIndex(remain),'stable')';q(j).boxIdx=[q(j).boxIdx(:);moved(:)];q(j).nodeOrder=unique(D.boxNodeIndex(q(j).boxIdx),'stable')';cand{end+1}=q;end %#ok<AGROW>
   end
  else
   % A multi-box one-stop sortie may split its box load to another sortie.
   bx=rcrit.boxIdx(:);if numel(bx)>1
    parts={bx(1:floor(end/2)),bx(floor(end/2)+1:end)};
    for z=1:2,moved=parts{z};remain=bx(~ismember(bx,moved));for j=1:numel(best.routes),if j==ii,continue;end;q=strip(best.routes);q(ii).boxIdx=remain;q(ii).nodeOrder=unique(D.boxNodeIndex(remain),'stable')';q(j).boxIdx=[q(j).boxIdx(:);moved(:)];q(j).nodeOrder=unique(D.boxNodeIndex(q(j).boxIdx),'stable')';cand{end+1}=q;end,end %#ok<AGROW>
   end
  end
 end
 if isempty(cand),break;end
 for z=1:numel(cand)
  if toc(t)>=budget,break;end
  tested=tested+1;try,[S,st]=overlap_schedule_q2_routes(D,legs,cand{z});catch,pruned=pruned+1;continue;end
  if ~st.feasible||S.metrics.N>23,pruned=pruned+1;continue;end
  if ~better(S,best),continue;end
  W=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true,'AllowPrepBatteryOverlap',true);if ~strcmp(W.status,'PASS'),pruned=pruned+1;continue;end
  best=S;V=W;accepted=accepted+1;bestV=V;save(fullfile(out,'best_pass.mat'),'D','legs','best','bestV','-v7.3');
  fprintf('critical checkpoint t=%.1f N=%d Cmax=%.9f E=%.9f\n',toc,bestV.routeCount,bestV.independentMetrics.Cmax_s/60,bestV.independentMetrics.energy_kWh);
 end
 if toc(t)<budget,break;end
end
% Fresh strict validation and a fixed allocation UAV-work lower bound.
Df=load_q2_data(root);Df.parallelPrepLoad=true;[Lf,~]=build_q2_leg_cache(Df,root,false);V=validate_q2_solution(Df,Lf,best,'RequireAllExpectedOnTime',true,'AllowPrepBatteryOverlap',true);assert(strcmp(V.status,'PASS'));
byU=unique(string({best.routes.uavID}));work=zeros(numel(byU),1);for u=1:numel(byU),ii=find(string({best.routes.uavID})==byU(u));for k=ii,uu=D.uav(best.routes(k).typeIdx,:);pre=max(uu.prep,numel(best.routes(k).boxIdx)*uu.load);work(u)=work(u)+pre+best.routes(k).eval.operation_s;end,end
fid=fopen(fullfile(out,'critical_summary.txt'),'w');fprintf(fid,'exit_status=PASS\nN=%d\nCmax_min=%.12f\nenergy_kWh=%.12f\ntested=%d\npruned=%d\naccepted=%d\nlast_critical_route=%d\nlast_critical_uav=%s\nfixed_assignment_uav_work_lb_min=%.12f\n',V.routeCount,V.independentMetrics.Cmax_s/60,V.independentMetrics.energy_kWh,tested,pruned,accepted,lastRoute,lastUav,max(work)/60);fclose(fid);
fprintf('CRITICAL_SEARCH PASS tested=%d pruned=%d accepted=%d Cmax=%.9f min LB=%.9f min\n',tested,pruned,accepted,V.independentMetrics.Cmax_s/60,max(work)/60);
end
function tf=better(a,b),tf=a.metrics.Cmax_s<b.metrics.Cmax_s-1e-6||(abs(a.metrics.Cmax_s-b.metrics.Cmax_s)<=1e-6&&a.metrics.energy_kWh<b.metrics.energy_kWh-1e-8);end
function r=strip(a),r=repmat(struct('boxIdx',[],'nodeOrder',[],'typeIdx',0),numel(a),1);for z=1:numel(a),r(z)=struct('boxIdx',a(z).boxIdx(:),'nodeOrder',a(z).nodeOrder(:)','typeIdx',a(z).typeIdx);end,end
