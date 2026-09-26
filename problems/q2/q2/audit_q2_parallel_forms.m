function audit_q2_parallel_forms(root)
if nargin<1,root=fileparts(fileparts(mfilename('fullpath')));end
out=fullfile(root,'results','q2_parallel_forms');z=load(fullfile(out,'best_pass.mat'),'D','legs','best');D=z.D;legs=z.legs;best=z.best;
V=validate_q2_solution(D,legs,best,'RequireAllExpectedOnTime',true);assert(strcmp(V.status,'PASS'));
fid=fopen(fullfile(out,'final_metrics.txt'),'w');fprintf(fid,'23_route_status=%s\n23_N=%d\n23_Cmax_min=%.12f\n23_energy_kWh=%.12f\n',V.status,V.routeCount,V.independentMetrics.Cmax_s/60,V.independentMetrics.energy_kWh);fclose(fid);
f=fullfile(out,'best_22_pass.mat');if isfile(f)
 z=load(f,'D','legs','best22');V22=validate_q2_solution(z.D,z.legs,z.best22,'RequireAllExpectedOnTime',true);assert(strcmp(V22.status,'PASS'));
 fid=fopen(fullfile(out,'final_metrics.txt'),'a');fprintf(fid,'22_route_status=%s\n22_N=%d\n22_Cmax_min=%.12f\n22_energy_kWh=%.12f\n',V22.status,V22.routeCount,V22.independentMetrics.Cmax_s/60,V22.independentMetrics.energy_kWh);fclose(fid);
 fprintf('STRICT 22-route PASS N=%d Cmax=%.9f min E=%.9f kWh\n',V22.routeCount,V22.independentMetrics.Cmax_s/60,V22.independentMetrics.energy_kWh);
end
fprintf('STRICT BEST PASS N=%d Cmax=%.9f min E=%.9f kWh\n',V.routeCount,V.independentMetrics.Cmax_s/60,V.independentMetrics.energy_kWh);
end
