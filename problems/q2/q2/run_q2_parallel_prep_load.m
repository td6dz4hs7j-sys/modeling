function run_q2_parallel_prep_load(root)
% Re-time the same validated 23 routes when preparation and loading overlap.
if nargin < 1, root=fileparts(fileparts(mfilename('fullpath'))); end
out=fullfile(root,'results','q2_parallel_prep_load');
if ~isfolder(out), mkdir(out); end
D0=load_q2_data(root);
[legs,~]=build_q2_leg_cache(D0,root,false);
x=load(fullfile(root,'results','q2_rebuild_fresh','q2_rebuild_solution.mat'),'S');
S0=x.S;
V0=validate_q2_solution(D0,legs,S0,'RequireAllExpectedOnTime',true);
assert(strcmp(V0.status,'PASS'),'Saved serial-time comparison failed fresh validation.');
[Sserial,statusSerial]=schedule_q2_routes(D0,legs,S0.routes);
assert(statusSerial.feasible,'Serial control rescheduling failed.');
Vserial=validate_q2_solution(D0,legs,Sserial,'RequireAllExpectedOnTime',true);
assert(strcmp(Vserial.status,'PASS'),'Serial control failed strict validation.');

D=D0; D.parallelPrepLoad=true;
[S,status]=schedule_q2_routes(D,legs,S0.routes);
assert(status.feasible,'Parallel-time rescheduling failed: %s',status.reason);
V=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true);
assert(strcmp(V.status,'PASS'),strjoin(cellstr(V.issues),'; '));
assert(V.routeCount==V0.routeCount && V.deliveredBoxes==V0.deliveredBoxes);
assert(abs(V.independentMetrics.energy_kWh-V0.independentMetrics.energy_kWh)<D.tol.energy);

comparison=table(["saved serial baseline";"serial control rescheduled";"parallel preparation and loading"], ...
 [V0.independentMetrics.N;Vserial.independentMetrics.N;V.independentMetrics.N], ...
 [V0.independentMetrics.Cmax_s;Vserial.independentMetrics.Cmax_s;V.independentMetrics.Cmax_s]/60, ...
 [V0.independentMetrics.energy_kWh;Vserial.independentMetrics.energy_kWh;V.independentMetrics.energy_kWh], ...
 [V0.deliveredBoxes;Vserial.deliveredBoxes;V.deliveredBoxes], ...
 'VariableNames',{'scenario','sorties','completion_min','energy_kWh','boxes_on_time'});
writetable(comparison,fullfile(out,'comparison.csv'));
write_q2_validation(V,fullfile(out,'parallel_validation.json'));
save(fullfile(out,'parallel_solution.mat'),'D','legs','S','V','V0','Vserial','comparison','-v7.3');
fprintf('PARALLEL_PREP_LOAD PASS old=%.9f min new=%.9f min reduction=%.9f min N=%d E=%.9f kWh\n', ...
 V0.independentMetrics.Cmax_s/60,V.independentMetrics.Cmax_s/60, ...
 (V0.independentMetrics.Cmax_s-V.independentMetrics.Cmax_s)/60, ...
 V.routeCount,V.independentMetrics.energy_kWh);
fprintf('SERIAL_CONTROL %.9f min; parallel-only reduction %.9f min\n', ...
 Vserial.independentMetrics.Cmax_s/60, ...
 (Vserial.independentMetrics.Cmax_s-V.independentMetrics.Cmax_s)/60);
end
