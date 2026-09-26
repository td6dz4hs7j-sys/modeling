function audit_q2_time_target(root)
% Strictly audit the capped-time result and quantify schedule-only limits.
x=load(fullfile(root,'results','q2_all_ontime','q2_final_solution.mat'),'D','legs');
y=load(fullfile(root,'results','q2_time_23_cap','q2_time_cap23_final.mat'),'best');
D=x.D;legs=x.legs;S=y.best;
V=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true);
assert(strcmp(V.status,'PASS')&&S.metrics.N<=23,'Capped time result failed strict audit.');
base=fullfile(root,'results','q2_time_23_cap');
counts=zeros(height(D.uav),1);work=zeros(height(D.uav),1);bound=zeros(height(D.uav),1);
for k=1:height(D.uav)
 typ=D.uav.id(k);counts(k)=sum(D.uavInventory.type==typ);
 q=S.sorties.uav_type==typ;work(k)=sum(S.sorties.operation_s(q));
 bound(k)=work(k)/counts(k);
end
T=table(D.uav.id,counts,work,bound,'VariableNames', ...
 {'uav_type','physical_count','fixed_route_operation_s','fixed_type_workload_bound_s'});
writetable(T,fullfile(base,'q2_fixed_route_type_bounds.csv'));
quality=struct('strict_status',V.status,'sorties',S.metrics.N, ...
 'Cmax_s',S.metrics.Cmax_s,'energy_kWh',S.metrics.energy_kWh, ...
 'on_time_boxes',sum(S.boxDelivery.arrival_s<=S.boxDelivery.expected_s+D.tol.time), ...
 'fixed_routes_types_workload_lb_s',max(bound), ...
 'fixed_route_lb_scope','Only schedule reorder/reassignment of this frozen grouping and UAV type mix; does not prove global infeasibility below bound.', ...
 'target_90min_s',5400,'target_reached',S.metrics.Cmax_s<=5400+D.tol.time);
fid=fopen(fullfile(base,'q2_time_target_audit.json'),'w','n','UTF-8');c=onCleanup(@()fclose(fid));
fprintf(fid,'%s',jsonencode(quality,'PrettyPrint',true));
write_q2_validation(V,fullfile(base,'q2_time_cap23_validation.json'));
fprintf('CAP23 AUDIT: N=%d Cmax=%.3f E=%.6f LBfixed=%.3f target5400=%d\n', ...
 S.metrics.N,S.metrics.Cmax_s,S.metrics.energy_kWh,max(bound),quality.target_reached);
end
