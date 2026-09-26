function run_q2_21_refine(root)
% Refine the newly found 21-sortie all-on-time plan for time and energy.
x=load(fullfile(root,'results','q2_all_ontime','q2_final_solution.mat'),'D','legs');
a=load(fullfile(root,'results','q2_refinement','q2_energy_refined.mat'),'Senergy');
D=x.D;legs=x.legs;S0=a.Senergy;
v=validate_q2_solution(D,legs,S0,'RequireAllExpectedOnTime',true);
assert(strcmp(v.status,'PASS')&&S0.metrics.N==21,'21-sortie seed failed strict audit.');
out=fullfile(root,'results','q2_refinement','n21');if ~isfolder(out),mkdir(out);end
[Sorder,Torder]=refine_q2_schedule(D,legs,S0,8);
save(fullfile(out,'q2_order_refined.mat'),'Sorder','Torder','-v7.3');
Rt=optimize_q2(D,legs,Sorder,'MaxSeeds',2,'Seeds',[20261018 20261019], ...
 'MaxRounds',30,'CandidatesPerRound',200,'StagnationRounds',15, ...
 'Priority',[1 4 2 3],'Label','n21_time','OutputDir',fullfile(out,'time'));
Stime=Rt.best;Vtime=validate_q2_solution(D,legs,Stime,'RequireAllExpectedOnTime',true);
assert(strcmp(Vtime.status,'PASS'),'21-sortie time plan failed strict audit.');
save(fullfile(out,'q2_time_refined.mat'),'Stime','Rt','Vtime','-v7.3');
fprintf('N21 TIME: N=%d Cmax=%.3f E=%.6f\n',Stime.metrics.N,Stime.metrics.Cmax_s,Stime.metrics.energy_kWh);
Re=optimize_q2(D,legs,Sorder,'MaxSeeds',2,'Seeds',[20261020 20261021], ...
 'MaxRounds',30,'CandidatesPerRound',200,'StagnationRounds',15, ...
 'Priority',[1 4 3 2],'Label','n21_energy','OutputDir',fullfile(out,'energy'));
Senergy=Re.best;Venergy=validate_q2_solution(D,legs,Senergy,'RequireAllExpectedOnTime',true);
assert(strcmp(Venergy.status,'PASS'),'21-sortie energy plan failed strict audit.');
save(fullfile(out,'q2_energy_refined.mat'),'Senergy','Re','Venergy','-v7.3');
fprintf('N21 ENERGY: N=%d Cmax=%.3f E=%.6f\n',Senergy.metrics.N,Senergy.metrics.Cmax_s,Senergy.metrics.energy_kWh);
end
