function render_existing()
root=fileparts(fileparts(mfilename('fullpath')));addpath(fullfile(root,'common'),fullfile(root,'q1'),fullfile(root,'utils'));
X=load(fullfile(root,'results','q1_solution.mat'));dem=load_dem(root);
plot_q1_results(X.D,dem,X.P,X.payload,X.sorties,X.summary,X.proof,X.comparison,X.sensitivity,X.sensPayload);
end
