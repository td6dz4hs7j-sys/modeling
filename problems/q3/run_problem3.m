% Reproduce the selected candidate with MATLAB continuous-time optimization.
root=fileparts(mfilename('fullpath'));cd(root);
addpath(fullfile(root,'q3'),fullfile(root,'q2'),fullfile(root,'common'),fullfile(root,'utils'));
assert(exist('intlinprog','file')==2,'Optimization Toolbox required');
prepare_q3_github_bundle(root);
q3_overlay_candidate_matlab();
x=load(fullfile(root,'results','q3_overlay','overlay_validated.mat'));
D=load_q3_data(root);
q3_overlay_figures(root,D,x.S0,x.S);
q3_overlay_report(root,D,x.S0,x.S,x.relays,x.V,x.proof);
verify_q3_github_bundle(root);
