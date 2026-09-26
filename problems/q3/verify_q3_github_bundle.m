function A=verify_q3_github_bundle(root)
if nargin<1,root=fileparts(mfilename('fullpath'));end
addpath(fullfile(root,'q3'),fullfile(root,'q2'),fullfile(root,'common'),fullfile(root,'utils'));
D=load_q3_data(root);[legs,~]=build_q2_leg_cache(D,root,false);dem=load_dem(root);
b=load(fullfile(root,'results','q2_strategy_scenarios','balanced_best_pass.mat'),'best');
q3_verify_q2_workbook(D,b.best,fullfile(root,'results','q2_strategy_scenarios','Q2_综合均衡最终结果.xlsx'));
z=load(fullfile(root,'results','q3_overlay','overlay_validated.mat'));S=z.S;relays=z.relays;
assert(numel(S.routes)==23&&height(S.boxDelivery)==80&&numel(relays)==4);
assert(numel(unique(string({relays.uavID})))==2);assert(abs(D.g-9.806)<1e-12);
for k=1:23
 assert(isequal(S.routes(k).boxIdx,b.best.routes(k).boxIdx));
 assert(isequal(S.routes(k).nodeOrder,b.best.routes(k).nodeOrder));
 assert(S.routes(k).typeIdx==b.best.routes(k).typeIdx);
end
Q=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true,'AllowPrepBatteryOverlap',true,'AllowFixedPrepPrestage',true);
assert(strcmp(Q.status,'PASS'));
V=validate_q3_solution(D,dem,legs,S,relays,'InheritQ2Prestage',true);assert(strcmp(V.status,'PASS'));
A=q3_audit_continuous_certificate(D,dem,legs,S,relays,V);
assert(abs(V.makespan_s-5933.08218081291)<1e-4);
assert(abs(V.jointEnergy_kWh-68.6107416805141)<1e-7);
A.g_m_s2=D.g;A.makespan_s=V.makespan_s;A.jointEnergy_kWh=V.jointEnergy_kWh;
A.transport_structure_inherited=true;A.all_expected_deadlines=true;
f=fopen(fullfile(root,'results','q3_overlay','github_bundle_validation.json'),'w');fprintf(f,'%s',jsonencode(A));fclose(f);disp(A);
end
