function review_overlap_fast_independent(root)
% Fresh-source audit of the bounded fastest-overlap checkpoint.
if nargin<1,root=fileparts(fileparts(mfilename('fullpath')));end
D=load_q2_data(root);D.parallelPrepLoad=true;
[legs,~]=build_q2_leg_cache(D,root,false);
x=load(fullfile(root,'results','q2_overlap_fast','best_pass.mat'),'best');S=x.best;
V=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true,'AllowPrepBatteryOverlap',true);
assert(strcmp(V.status,'PASS'),strjoin(cellstr(V.issues),'; '));
assert(V.routeCount==22 && V.deliveredBoxes==80);
assert(all(S.boxDelivery.arrival_s<=S.boxDelivery.expected_s+D.tol.time));
uids=unique(string({S.routes.uavID}));work=zeros(numel(uids),1);
for j=1:numel(uids)
 ix=find(string({S.routes.uavID})==uids(j));
 for p=ix
  r=S.routes(p);u=D.uav(r.typeIdx,:);
  work(j)=work(j)+max(u.prep,numel(r.boxIdx)*u.load)+(r.return_s-r.takeoff_s);
 end
end
[lb,k]=max(work);
chain=find(string({S.routes.uavID})==uids(k));
chain=chain(:);
fprintf('CRITICAL_UAV %s sorties=%d prep_s=%g potential_pre_stage_after_first_s=%g\n', ...
 uids(k),numel(chain),D.uav(S.routes(chain(1)).typeIdx,:).prep,max(0,numel(chain)-1)*D.uav(S.routes(chain(1)).typeIdx,:).prep);
fprintf('FAST_INDEPENDENT PASS N=%d Cmax_min=%.12f E_kWh=%.12f boxes=%d fixedUAVworkLB_min=%.12f bottleneck=%s\n', ...
 V.routeCount,V.independentMetrics.Cmax_s/60,V.independentMetrics.energy_kWh,V.deliveredBoxes,lb/60,uids(k));
fid=fopen(fullfile(root,'results','q2_overlap_fast','independent_review.txt'),'w');
fprintf(fid,'status=%s\nN=%d\nCmax_min=%.12f\nE_kWh=%.12f\nboxes_on_time=%d\nfixed_assignment_UAV_work_lb_min=%.12f\nbottleneck_UAV=%s\n', ...
 V.status,V.routeCount,V.independentMetrics.Cmax_s/60,V.independentMetrics.energy_kWh,V.deliveredBoxes,lb/60,uids(k));fclose(fid);
end
