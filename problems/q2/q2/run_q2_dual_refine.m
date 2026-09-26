function run_q2_dual_refine(root)
% Continue route/type/grouping search on both strictly on-time 22-sortie seeds.
x=load(fullfile(root,'results','q2_all_ontime','q2_final_solution.mat'),'D','legs');
a=load(fullfile(root,'results','q2_refinement','q2_schedule_refined.mat'),'StimeRefined','SenergyRefined');
D=x.D;legs=x.legs;base=fullfile(root,'results','q2_refinement');
timeDir=fullfile(base,'time');energyDir=fullfile(base,'energy');
Rt=optimize_q2(D,legs,a.StimeRefined,'MaxSeeds',2,'Seeds',[20261014 20261015], ...
 'MaxRounds',30,'CandidatesPerRound',200,'StagnationRounds',15, ...
 'Priority',[1 4 2 3],'Label','refine_time','OutputDir',timeDir);
Stime=Rt.best;Vtime=validate_q2_solution(D,legs,Stime,'RequireAllExpectedOnTime',true);
assert(strcmp(Vtime.status,'PASS'),'Time-refined candidate failed strict validator.');
save(fullfile(base,'q2_time_refined.mat'),'Stime','Rt','Vtime','-v7.3');
fprintf('TIME REFINEMENT FINAL: N=%d Cmax=%.3f E=%.6f\n', ...
 Stime.metrics.N,Stime.metrics.Cmax_s,Stime.metrics.energy_kWh);
Re=optimize_q2(D,legs,a.SenergyRefined,'MaxSeeds',2,'Seeds',[20261016 20261017], ...
 'MaxRounds',30,'CandidatesPerRound',200,'StagnationRounds',15, ...
 'Priority',[1 4 3 2],'Label','refine_energy','OutputDir',energyDir);
Senergy=Re.best;Venergy=validate_q2_solution(D,legs,Senergy,'RequireAllExpectedOnTime',true);
assert(strcmp(Venergy.status,'PASS'),'Energy-refined candidate failed strict validator.');
save(fullfile(base,'q2_energy_refined.mat'),'Senergy','Re','Venergy','-v7.3');
fprintf('ENERGY REFINEMENT FINAL: N=%d Cmax=%.3f E=%.6f\n', ...
 Senergy.metrics.N,Senergy.metrics.Cmax_s,Senergy.metrics.energy_kWh);
end
