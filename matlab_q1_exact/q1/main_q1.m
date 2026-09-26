function main_q1(mode)
if nargin<1,mode='full';end
moduleRoot=fileparts(fileparts(mfilename('fullpath')));
root=fileparts(moduleRoot);addpath(fullfile(moduleRoot,'common'),fullfile(moduleRoot,'q1'),fullfile(moduleRoot,'utils'));
out=fullfile(root,'results','q1_exact_dp');if ~isfolder(out),mkdir(out);end
diary(fullfile(out,['matlab_' char(mode) '.log']));cleanup=onCleanup(@()diary('off')); %#ok<NASGU>
t0=tic;rng(20260924,'twister');env=check_matlab_env(["data","visualization","optimization"]);assert(env.ok);assert(exist('wgs84Ellipsoid','file')==2);
D=load_problem_data(root);D.output_root=out;dem=load_dem(root);
if strcmp(mode,'minimal'),areas=1;else,areas=1:15;end
P=terrain_profile(D,dem,areas);physics=validate_physics(D,P);payload=solve_max_payload(D,P);
C=cell(numel(P),1);S=C;
for i=1:numel(P),C{i}=enumerate_patterns(D,P(i),D.uav.reserve);S{i}=solve_batching(D,C{i});end
[sorties,summary,metrics]=evaluate_q1_solution(D,P,S);validation=validate_q1_solution(D,P,sorties);
disp(metrics);disp(validation);
if strcmp(mode,'minimal')
 proof=verify_milp(D,C{1},S{1});disp(proof);mutations=test_validator(D,P,sorties);disp(mutations);
 writetable(payload,fullfile(out,'minimal_payload.csv'));writetable(sorties,fullfile(out,'minimal_sorties.csv'));
 save(fullfile(out,'minimal.mat'),'D','P','C','S','metrics','validation','physics','proof','mutations');
else
 proof=struct([]);
 for i=1:numel(P),proof=[proof;verify_milp(D,C{i},S{i})];end %#ok<AGROW>
 proof=struct2table(proof);mutations=test_validator(D,P,sorties);boundaries=test_boundaries(D,P,sorties);disp(boundaries);
 export_q1(D,P,sorties,summary,metrics,payload,proof,validation,physics,mutations,out);
 comparison=compare_objectives(D,P,C,out);writetable(comparison,fullfile(out,'objective_comparison.csv'));
 [sensitivity,sensPayload]=sensitivity_q1(D,P,out);writetable(sensitivity,fullfile(out,'reserve_sensitivity.csv'));writetable(sensPayload,fullfile(out,'reserve_payloads.csv'));
 save(fullfile(out,'q1_solution.mat'),'D','P','C','S','sorties','summary','metrics','payload','proof','validation','physics','comparison','sensitivity','sensPayload','boundaries');
 plot_q1_results(D,dem,P,payload,sorties,summary,proof,comparison,sensitivity,sensPayload);
 make_manifest(D,toc(t0),out);
end
fprintf('Elapsed %.3f s\n',toc(t0));
end
