function run_q2_schedule_refine(root)
% Time-only refinement on both 22-sortie Pareto candidates.
x=load(fullfile(root,'results','q2_all_ontime','q2_final_solution.mat'),'D','legs','S');
a=load(fullfile(root,'results','q2_all_ontime','q2_validated_alternatives.mat'),'Senergy');
D=x.D;legs=x.legs;out=fullfile(root,'results','q2_refinement');
if ~isfolder(out),mkdir(out);end
[StimeRefined,timeTrace]=refine_q2_schedule(D,legs,x.S,8);
[SenergyRefined,energyTrace]=refine_q2_schedule(D,legs,a.Senergy,8);
Vtime=validate_q2_solution(D,legs,StimeRefined,'RequireAllExpectedOnTime',true);
Venergy=validate_q2_solution(D,legs,SenergyRefined,'RequireAllExpectedOnTime',true);
assert(strcmp(Vtime.status,'PASS')&&strcmp(Venergy.status,'PASS'),'Refined schedules failed strict validation.');
save(fullfile(out,'q2_schedule_refined.mat'),'StimeRefined','SenergyRefined','Vtime','Venergy', ...
 'timeTrace','energyTrace','-v7.3');
writetable(timeTrace,fullfile(out,'q2_time_schedule_trace.csv'));
writetable(energyTrace,fullfile(out,'q2_energy_schedule_trace.csv'));
fprintf('SCHEDULE TIME: N=%d Cmax=%.3f E=%.6f; ENERGY: N=%d Cmax=%.3f E=%.6f\n', ...
 StimeRefined.metrics.N,StimeRefined.metrics.Cmax_s,StimeRefined.metrics.energy_kWh, ...
 SenergyRefined.metrics.N,SenergyRefined.metrics.Cmax_s,SenergyRefined.metrics.energy_kWh);
end
