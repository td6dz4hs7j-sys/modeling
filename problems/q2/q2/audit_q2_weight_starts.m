function audit_q2_weight_starts(root)
% Recompute archived warm starts against freshly loaded current Q2 inputs.
if nargin<1,root=fileparts(fileparts(mfilename('fullpath')));end
addpath(fullfile(root,'q2'),fullfile(root,'common'),fullfile(root,'utils'));
D=load_q2_data(root);[legs,legMeta]=build_q2_leg_cache(D,root,false); %#ok<NASGU>
assert(abs(D.g-9.806)<1e-12 && height(D.boxes)==80);
names=["balanced","fastest","energy6714","within120"];
rows=cell(numel(names),31);ctx=q2_fast_context(D,legs,'');
for s=1:numel(names)
    path=fullfile(root,'results','q2_weighted_verified',names(s),'solution.mat');
    a=load(path,'S');assert(isfield(a,'S'),'Missing S in %s',path);
    routes=strip_routes(a.S.routes);
    [S,st]=schedule_q2_routes(D,legs,routes);assert(st.feasible,'%s: %s',names(s),st.reason);
    V=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true);
    assert(strcmp(V.status,'PASS'),'%s current validator: %s',names(s),strjoin(V.issues,'; '));
    [F,ctx]=q2_fast_schedule(D,legs,routes,ctx);
    assert(F.feasible,'%s fast decoder: %s',names(s),F.reason);
    expectedMargin=S.boxDelivery.expected_s-S.boxDelivery.arrival_s;
    hardMargin=S.boxDelivery.hard_deadline_s-S.boxDelivery.arrival_s;
    hardMargin=hardMargin(isfinite(hardMargin));
    typeOp=zeros(1,3);typeCount=zeros(1,3);uavCount=zeros(1,3);batCount=zeros(1,3);
    for k=1:3
        typeOp(k)=sum(S.sorties.operation_s(S.sorties.uav_type==D.uav.id(k)));
        typeCount(k)=sum(S.sorties.uav_type==D.uav.id(k));
        uavCount(k)=sum(D.uavInventory.type==D.uav.id(k));
        batCount(k)=D.batteryInventory.count(D.batteryInventory.type==D.uav.id(k));
    end
    rows(s,:)={names(s),string(V.status),height(S.boxDelivery),S.metrics.N,...
        S.metrics.Cmax_s,S.metrics.energy_kWh,sum(S.sorties.operation_s),...
        sum(S.sorties.operation_s)/8,max(S.sorties.operation_s),min(expectedMargin),...
        min(hardMargin),typeCount(1),typeOp(1),uavCount(1),batCount(1),...
        typeCount(2),typeOp(2),uavCount(2),batCount(2),...
        typeCount(3),typeOp(3),uavCount(3),batCount(3),...
        F.metrics.Cmax_s,F.metrics.energy_kWh,F.metrics.W,...
        abs(F.metrics.Cmax_s-S.metrics.Cmax_s),abs(F.metrics.energy_kWh-S.metrics.energy_kWh),...
        abs(F.metrics.W-S.metrics.W),"g=9.806",ctx.modelFingerprint};
end
T=cell2table(rows,'VariableNames',{'solution','validator','delivered_boxes','sorties',...
    'makespan_s','energy_kWh','total_operation_s','mean_operation_per_8_sorties_s',...
    'longest_route_operation_s','min_expected_margin_s','min_hard_margin_s',...
    'A_sorties','A_operation_s','A_uav_inventory','A_battery_inventory',...
    'B_sorties','B_operation_s','B_uav_inventory','B_battery_inventory',...
    'C_sorties','C_operation_s','C_uav_inventory','C_battery_inventory',...
    'fast_makespan_s','fast_energy_kWh','fast_W','full_fast_abs_makespan_diff_s',...
    'full_fast_abs_energy_diff_kWh','full_fast_abs_W_diff','gravity','model_fingerprint'});
out=fullfile(root,'results','q2_weight_tuning');if ~isfolder(out),mkdir(out);end
writetable(T,fullfile(out,'initial_audit.csv'));

% Spot-check user-supplied visible rows against a fresh workbook read.
ids=["S001-MED-01","S001-WAT-01","S001-FOD-01","S001-HYG-01",...
    "S002-MED-01","S002-WAT-01","S002-FOD-01","S002-HYG-01"];
mass=[3;14;8;6;3;14;8;6];volume=[.012;.027;.028;.035;.012;.027;.028;.035];
due=[3600;3600;7200;10800;3600;3600;7200;10800];priority=[24;12;10;8;24;12;10;8];
firstDeadline=[3600;3600;NaN;NaN;3600;3600;NaN;NaN];firstBatch=[true;true;false;false;true;true;false;false];
ix=zeros(size(ids));for i=1:numel(ids),ix(i)=find(D.boxes.id==ids(i),1);assert(ix(i)>0,'Missing screenshot box %s',ids(i));end
spot=table(ids(:),D.boxes.mass(ix),mass,D.boxes.volume(ix),volume,D.boxes.expected_s(ix),due,...
    D.boxes.firstDeadline_s(ix),firstDeadline,D.boxes.firstBatch(ix),firstBatch,...
    D.boxes.priority(ix),priority,'VariableNames',{'box_id','mass_actual_kg','mass_expected_kg',...
    'volume_actual_m3','volume_expected_m3','expected_actual_s','expected_s',...
    'first_deadline_actual_s','first_deadline_expected_s','first_batch_actual','first_batch_expected',...
    'priority_actual','priority_expected'});
spot.mass_match=abs(spot.mass_actual_kg-spot.mass_expected_kg)<1e-9;
spot.volume_match=abs(spot.volume_actual_m3-spot.volume_expected_m3)<1e-12;
spot.expected_match=abs(spot.expected_actual_s-spot.expected_s)<1e-9;
spot.first_deadline_match=(isnan(spot.first_deadline_actual_s)&isnan(spot.first_deadline_expected_s))|...
    abs(spot.first_deadline_actual_s-spot.first_deadline_expected_s)<1e-9;
spot.first_batch_match=spot.first_batch_actual==spot.first_batch_expected;
spot.priority_match=spot.priority_actual==spot.priority_expected;
assert(all(spot.mass_match&spot.volume_match&spot.expected_match&spot.first_deadline_match&...
    spot.first_batch_match&spot.priority_match),'Fresh input spot-check mismatch');
writetable(spot,fullfile(out,'input_spotcheck.csv'));
fprintf('START AUDIT PASS: four starts, g=%.3f, cache fingerprint=%s\n',D.g,ctx.modelFingerprint);
end

function r=strip_routes(routes)
r=repmat(struct('boxIdx',[],'nodeOrder',[],'typeIdx',[]),numel(routes),1);
for i=1:numel(routes)
    r(i)=struct('boxIdx',routes(i).boxIdx(:),'nodeOrder',routes(i).nodeOrder(:)',...
        'typeIdx',routes(i).typeIdx);
end
end
