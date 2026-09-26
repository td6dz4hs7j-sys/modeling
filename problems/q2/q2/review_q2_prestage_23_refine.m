function review_q2_prestage_23_refine(root)
if nargin<1,root=fileparts(fileparts(mfilename('fullpath')));end
D=load_q2_data(root);D.parallelPrepLoad=true;[legs,~]=build_q2_leg_cache(D,root,false);
x=load(fullfile(root,'results','q2_prestage_23_refine','best_pass.mat'),'best');S=x.best;
V=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true,'AllowPrepBatteryOverlap',true,'AllowFixedPrepPrestage',true);
assert(strcmp(V.status,'PASS'),strjoin(cellstr(V.issues),'; '));
assert(V.routeCount==23&&V.deliveredBoxes==80);
assert(all(S.boxDelivery.arrival_s<=S.boxDelivery.expected_s+D.tol.time));
[~,p]=max([S.routes.return_s]);uid=string(S.routes(p).uavID);
out=fullfile(root,'results','q2_prestage_23_refine','independent_review.txt');fid=fopen(out,'w');
fprintf(fid,'status=%s\nN=%d\nCmax_min=%.12f\nE_kWh=%.12f\nboxes_on_time=%d\nlast_return_UAV=%s\n',V.status,V.routeCount,V.independentMetrics.Cmax_s/60,V.independentMetrics.energy_kWh,V.deliveredBoxes,uid);fclose(fid);
fprintf('PRESTAGE23_FINAL PASS N=%d Cmax_min=%.12f E_kWh=%.12f boxes=%d last_UAV=%s\n',V.routeCount,V.independentMetrics.Cmax_s/60,V.independentMetrics.energy_kWh,V.deliveredBoxes,uid);
end
