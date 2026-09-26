function run_q2_sortie_first(root,out)
% Fresh Q2 solve with optional validated warm starts; optimize N first.
if nargin<2,out=fullfile(root,'results','q2_sortie_first');end
if ~isfolder(out),mkdir(out);end
environment=check_matlab_env(["data","visualization"]);
assert(environment.ok,'MATLAB environment check failed.');
D=load_q2_data(root);
[legs,cacheMeta]=build_q2_leg_cache(D,root,false);
[baseline,~,construction]=construct_q2_minimal(D,legs);
v=validate_q2_solution(D,legs,baseline);
assert(strcmp(v.status,'PASS'),'Constructed baseline invalid: %s',strjoin(v.issues,' | '));
inheritance=check_q1_inheritance(D,legs);
audit_q2_fast_decoder(D,legs,baseline);
S0=baseline;
sourceDirs={fullfile(root,'results','q2_final'),fullfile(root,'results','q2_sortie_first')};
for z=1:numel(sourceDirs)
 path=fullfile(sourceDirs{z},'q2_final_solution.mat');
 if ~isfile(path),continue;end
 x=load(path,'S');candidate=x.S;
 va=validate_q2_solution(D,legs,candidate);
 if strcmp(va.status,'PASS') && (candidate.metrics.N<S0.metrics.N || ...
   (candidate.metrics.N==S0.metrics.N && candidate.metrics.W<S0.metrics.W))
  S0=candidate;
 end
end
altPath=fullfile(root,'results','q2_final','q2_energy_preference.mat');
if isfile(altPath)
 a=load(altPath,'Ralt');
 candidate=a.Ralt.best;
 va=validate_q2_solution(D,legs,candidate);
 if strcmp(va.status,'PASS') && (candidate.metrics.N<S0.metrics.N || ...
   (candidate.metrics.N==S0.metrics.N && candidate.metrics.W<S0.metrics.W)),S0=candidate;end
end
fprintf('SORTIE-FIRST INITIAL: N=%d W=%.3f Cmax=%.3f E=%.6f\n', ...
 S0.metrics.N,S0.metrics.W,S0.metrics.Cmax_s,S0.metrics.energy_kWh);
R=optimize_q2(D,legs,S0,'MaxSeeds',4,'Seeds',[20260930 20261001 20261002 20261003], ...
 'MaxRounds',40,'CandidatesPerRound',200,'StagnationRounds',20, ...
 'Priority',[4 1 2 3],'Label','sortie_first','OutputDir',out);
S=R.best;
V=validate_q2_solution(D,legs,S);
assert(strcmp(V.status,'PASS'),'Final sortie-first solution invalid: %s',strjoin(V.issues,' | '));
assert(S.metrics.N<=S0.metrics.N,'Sortie count regressed.');
save(fullfile(out,'q2_final_solution.mat'),'D','legs','S','baseline','R','V','cacheMeta','construction','inheritance','environment','-v7.3');
write_q2_validation(V,fullfile(out,'q2_final_validation.json'));
export_q2_results(D,legs,S,baseline,R,out);
if strcmp(out,fullfile(root,'results','q2_final')),figDir=fullfile(root,'figures','q2_final');
else,figDir=fullfile(root,'figures','q2_sortie_first');end
plot_q2_results(D,legs,S,baseline,R,figDir);
fprintf('SORTIE-FIRST FINAL: N=%d W=%.3f Cmax=%.3f E=%.6f\n', ...
 S.metrics.N,S.metrics.W,S.metrics.Cmax_s,S.metrics.energy_kWh);
end
