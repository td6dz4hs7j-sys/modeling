function prepare_q3_github_bundle(root)
if nargin<1,root=fileparts(mfilename('fullpath'));end
D=load_q3_data(root);[legs,~]=build_q2_leg_cache(D,root,false);
z=load(fullfile(root,'results','q2_strategy_scenarios','balanced_best_pass.mat'),'best');S=z.best;
q3_verify_q2_workbook(D,S,fullfile(root,'results','q2_strategy_scenarios','Q2_综合均衡最终结果.xlsx'));
Q=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true,'AllowPrepBatteryOverlap',true,'AllowFixedPrepPrestage',true);
assert(strcmp(Q.status,'PASS'));assert(abs(D.g-9.806)<1e-12);
save(fullfile(root,'results','q3_overlay','source_overlay.mat'),'S','Q','-v7.3');
end
