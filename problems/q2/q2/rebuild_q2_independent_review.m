function rebuild_q2_independent_review(root)
% Independently reload sources and validate the saved Q2 result.
if nargin < 1, root = fileparts(fileparts(mfilename('fullpath'))); end
D = load_q2_data(root);
[legs, ~] = build_q2_leg_cache(D, root, false);
x = load(fullfile(root,'results','q2_rebuild_fresh','q2_rebuild_solution.mat'),'S');
V = validate_q2_solution(D, legs, x.S, 'RequireAllExpectedOnTime', true);
assert(strcmp(V.status,'PASS'), strjoin(cellstr(V.issues), '; '));
assert(V.deliveredBoxes == 80 && V.routeCount == 23);
arr = x.S.boxDelivery.arrival_s;
due = x.S.boxDelivery.expected_s;
assert(all(arr <= due + D.tol.time));
fprintf('INDEPENDENT_Q2_REVIEW PASS boxes=%d N=%d Cmax_s=%.9f E_kWh=%.9f ontime=%d\n', ...
    V.deliveredBoxes,V.routeCount,V.independentMetrics.Cmax_s, ...
    V.independentMetrics.energy_kWh,sum(arr <= due + D.tol.time));
end
