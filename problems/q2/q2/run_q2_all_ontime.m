function run_q2_all_ontime(root)
% Optimize sortie count subject to all 80 boxes meeting expected delivery times.
out=fullfile(root,'results','q2_all_ontime');if ~isfolder(out),mkdir(out);end
environment=check_matlab_env(["data","visualization"]);
assert(environment.ok,'MATLAB environment check failed.');
D=load_q2_data(root);assert(all(D.boxes.priority>0),'W=0 would not certify every box.');
[legs,cacheMeta]=build_q2_leg_cache(D,root,false);
[baseline,~,construction]=construct_q2_minimal(D,legs);
Vbase=validate_q2_solution(D,legs,baseline);
assert(strcmp(Vbase.status,'PASS'),'Constructed baseline failed validator.');
inheritance=check_q1_inheritance(D,legs);
S0=[];
checkpointFiles=dir(fullfile(out,'q2_seed_*_checkpoint.mat'));
sources=[{fullfile(root,'results','q2_final','q2_energy_preference.mat'), ...
 fullfile(out,'q2_final_solution.mat')}, ...
 arrayfun(@(f)fullfile(f.folder,f.name),checkpointFiles,'UniformOutput',false)];
for i=1:numel(sources)
 if ~isfile(sources{i}),continue;end
 if i==1,x=load(sources{i},'Ralt');candidate=x.Ralt.best;
 elseif i==2,x=load(sources{i},'S');candidate=x.S;
 else,x=load(sources{i},'best');candidate=x.best;end
 v=validate_q2_solution(D,legs,candidate);
 if strcmp(v.status,'PASS') && candidate.metrics.W<=D.tol.time && ...
   (isempty(S0)||candidate.metrics.N<S0.metrics.N || ...
   (candidate.metrics.N==S0.metrics.N&&candidate.metrics.Cmax_s<S0.metrics.Cmax_s))
  S0=candidate;
 end
end
if isempty(S0)
 Rseed=optimize_q2(D,legs,baseline,'MaxSeeds',1,'Seeds',20261004, ...
  'MaxRounds',40,'CandidatesPerRound',200,'StagnationRounds',20, ...
  'Priority',[1 4 2 3],'Label','all_ontime_seed','OutputDir',out);
 S0=Rseed.best;
end
assert(S0.metrics.W<=D.tol.time,'No 100%% expected-on-time warm start was found.');
fprintf('ALL-ONTIME INITIAL: N=%d W=%.3f Cmax=%.3f E=%.6f\n', ...
 S0.metrics.N,S0.metrics.W,S0.metrics.Cmax_s,S0.metrics.energy_kWh);
R=optimize_q2(D,legs,S0,'MaxSeeds',4, ...
 'Seeds',[20261004 20261005 20261006 20261007], ...
 'MaxRounds',40,'CandidatesPerRound',200,'StagnationRounds',20, ...
 'Priority',[1 4 2 3],'Label','all_ontime','OutputDir',out);
S=R.best;V=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true);
assert(strcmp(V.status,'PASS'),'Final all-ontime schedule failed validator.');
assert(S.metrics.W<=D.tol.time && ...
 all(S.boxDelivery.arrival_s<=S.boxDelivery.expected_s+D.tol.time), ...
 'A box missed its expected delivery time.');
mutationTests=test_q2_mutations(D,legs,S,'RequireAllExpectedOnTime',true);
writetable(mutationTests,fullfile(out,'q2_strict_mutation_tests.csv'));
save(fullfile(out,'q2_final_solution.mat'),'D','legs','S','baseline','R','V', ...
 'cacheMeta','construction','inheritance','environment','-v7.3');
write_q2_validation(V,fullfile(out,'q2_final_validation.json'));
export_q2_results(D,legs,S,baseline,R,out);
plot_q2_results(D,legs,S,baseline,R,fullfile(root,'figures','q2_all_ontime'));
fprintf('ALL-ONTIME FINAL: N=%d W=%.3f Cmax=%.3f E=%.6f\n', ...
 S.metrics.N,S.metrics.W,S.metrics.Cmax_s,S.metrics.energy_kWh);
end
