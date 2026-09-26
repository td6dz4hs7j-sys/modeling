function audit_export_q2_99(root)
% Recompute and publish only strict-PASS Q2 prestage schedules.
if nargin<1,root=fileparts(fileparts(mfilename('fullpath')));end
out=fullfile(root,'results','q2_99_review');if ~isfolder(out),mkdir(out);end
D=load_q2_data(root);D.parallelPrepLoad=true;
[legs,~]=build_q2_leg_cache(D,root,false);
files={fullfile(root,'results','q2_prestage','recovered_101027_pass.mat'), ...
 fullfile(root,'results','q2_prestage_split23','best_23_pass.mat'), ...
 fullfile(root,'results','q2_prestage_23_refine','best_pass.mat')};
labels=["22-sortie time-first search";"23-sortie route split";"23-sortie local refinement"];
energyPath=fullfile(root,'results','q2_99_energy','best_pass.mat');
if isfile(energyPath)
 files{end+1}=energyPath;labels(end+1)="23-sortie energy refinement";
end
rows=cell(numel(files),9);solutions=cell(numel(files),1);
for i=1:numel(files)
 x=load(files{i});if isfield(x,'best'),S=x.best;else,S=x.best23;end
 V=strict(S);assert(strcmp(V.status,'PASS'),'%s: %s',labels(i),strjoin(cellstr(V.issues),'; '));
 assert(V.deliveredBoxes==80&&V.routeCount==numel(S.routes));
 solutions{i}=S;
 rows(i,:)={labels(i),V.routeCount,V.independentMetrics.Cmax_s/60,V.independentMetrics.energy_kWh, ...
  V.independentMetrics.W,80,sum(arrayfun(@(r)numel(r.nodeOrder)>1,S.routes)), ...
  min(S.boxDelivery.expected_s-S.boxDelivery.arrival_s)/60,"PASS"};
end
comparison=cell2table(rows,'VariableNames',{'method','sorties','Cmax_min','energy_kWh', ...
 'weighted_lateness_priority_s','boxes_on_time','multi_area_sorties','minimum_expected_margin_min','validator'});
writetable(comparison,fullfile(out,'algorithm_comparison.csv'));
S=solutions{end};V=strict(S);
assert(S.metrics.Cmax_s<=99.043089527783*60+D.tol.time);
assert(S.metrics.energy_kWh<=solutions{3}.metrics.energy_kWh+D.tol.energy);
best=S;save(fullfile(out,'final_best_pass.mat'),'best','V','-v7.3');
% Corrupt timing fields alone, leaving reported metrics unchanged. Each must fail.
mut=cell(4,3);
M=S;M.routes(2).prepStart_s=M.routes(2).prepStart_s-60;mut(1,:)=check_mutation('early_fixed_prep',M);
M=S;M.routes(2).loadStart_s=M.routes(2).loadStart_s-60;mut(2,:)=check_mutation('early_load',M);
M=S;M.routes(1).batteryReady_s=M.routes(1).batteryReady_s+60;mut(3,:)=check_mutation('wrong_charge_ready',M);
M=S;M.routes(1).eval.energy_kWh=M.routes(1).eval.energy_kWh+1;mut(4,:)=check_mutation('wrong_energy',M);
mutations=cell2table(mut,'VariableNames',{'mutation','rejected','diagnostic'});
writetable(mutations,fullfile(out,'validator_mutations.csv'));

R=S.routes;N=numel(R);sorties=S.sorties;
sorties.prep_start_s=[R.prepStart_s]';sorties.prep_end_s=sorties.prep_start_s+arrayfun(@(r)D.uav.prep(r.typeIdx),R);
sorties.load_start_s=[R.loadStart_s]';sorties.load_end_s=sorties.load_start_s+arrayfun(@(r)numel(r.boxIdx)*D.uav.load(r.typeIdx),R);
sorties.takeoff_s=[R.takeoff_s]';sorties.battery_ready_s=[R.batteryReady_s]';
sorties.return_SOC=arrayfun(@(r)1-r.eval.energy_kWh/D.uav.energy(r.typeIdx),R);
sorties.charge_s=sorties.battery_ready_s-sorties.return_s;
sorties.service_area_count=arrayfun(@(r)numel(r.nodeOrder),R);
sorties.box_count=arrayfun(@(r)numel(r.boxIdx),R);
sorties.reserve_margin_kWh=arrayfun(@(r)(1-D.uav.reserve(r.typeIdx))*D.uav.energy(r.typeIdx)-r.eval.energy_kWh,R);
sorties.takeoff_min=sorties.takeoff_s/60;sorties.return_min=sorties.return_s/60;
sorties.prep_start_min=sorties.prep_start_s/60;sorties.load_start_min=sorties.load_start_s/60;
assert(all(sorties.prep_end_s<=sorties.takeoff_s+D.tol.time));
assert(all(sorties.load_end_s<=sorties.takeoff_s+D.tol.time));
assert(all(sorties.reserve_margin_kWh>=-D.tol.energy));
writetable(sorties,fullfile(out,'sorties_23.csv'));
boxes=S.boxDelivery;boxes.expected_margin_min=(boxes.expected_s-boxes.arrival_s)/60;
boxes.hard_margin_min=(boxes.hard_deadline_s-boxes.arrival_s)/60;
boxes.arrival_min=boxes.arrival_s/60;
assert(all(boxes.expected_margin_min>=-D.tol.time/60));
writetable(boxes,fullfile(out,'boxes_80.csv'));
fleet=cell(8,6);for i=1:8
 id=D.uavInventory.id(i);ix=find(sorties.uav_id==id);
 fleet(i,:)={id,D.uavInventory.type(i),numel(ix),sum(sorties.operation_s(ix))/60, ...
  max([0;sorties.return_min(ix)]),join(sorties.sortie_id(ix),';')};
end
fleet=cell2table(fleet,'VariableNames',{'uav_id','type','sorties','flight_and_handover_min','last_return_min','sortie_ids'});
writetable(fleet,fullfile(out,'uav_summary.csv'));
batt=cell(0,8);for t=1:height(D.batteryInventory)
 for j=1:D.batteryInventory.count(t)
  id=D.batteryInventory.type(t)+"-B"+compose('%02d',j);ix=find(sorties.battery_id==id);
  if isempty(ix),batt(end+1,:)={id,D.batteryInventory.type(t),"",NaN,NaN,NaN,NaN,NaN};end %#ok<AGROW>
  for p=ix(:)',batt(end+1,:)={id,D.batteryInventory.type(t),sorties.sortie_id(p), ...
   sorties.takeoff_min(p),sorties.return_min(p),sorties.battery_ready_s(p)/60,sorties.return_SOC(p),sorties.energy_kWh(p)};end %#ok<AGROW>
 end
end
batt=cell2table(batt,'VariableNames',{'battery_id','type','sortie_id','takeoff_min','return_min','recharged_min','return_SOC','energy_kWh'});
writetable(batt,fullfile(out,'battery_timeline.csv'));
area=unique(D.boxes.area,'stable');ar=cell(numel(area),5);for i=1:numel(area)
 ix=boxes.area==area(i);ar(i,:)={area(i),sum(ix),max(boxes.arrival_min(ix)), ...
  min(boxes.expected_margin_min(ix)),numel(unique(boxes.sortie_id(ix)))};
end
areaTable=cell2table(ar,'VariableNames',{'area','boxes','last_arrival_min','minimum_expected_margin_min','sorties_serving'});
writetable(areaTable,fullfile(out,'area_summary.csv'));
assert(abs(sum(sorties.energy_kWh)-V.independentMetrics.energy_kWh)<D.tol.energy);
assert(abs(max(sorties.return_s)-V.independentMetrics.Cmax_s)<D.tol.time);
fid=fopen(fullfile(out,'audit_report.txt'),'w','n','UTF-8');c=onCleanup(@()fclose(fid));
fprintf(fid,'Q2 99-minute scenario independent audit\nstatus=%s\nN=%d\nCmax_min=%.12f\nE_kWh=%.12f\nboxes_on_time=80/80\n', ...
 V.status,N,V.independentMetrics.Cmax_s/60,V.independentMetrics.energy_kWh);
fprintf(fid,'multi_area_sorties=%d\nminimum_expected_margin_min=%.8f\nminimum_energy_reserve_margin_kWh=%.8f\n', ...
 sum(sorties.service_area_count>1),min(boxes.expected_margin_min),min(sorties.reserve_margin_kWh));
fprintf(fid,'assumption=fixed preparation of next sortie may start after prior takeoff; loading waits for prior return; shared battery must be fully charged at takeoff.\n');
fprintf(fid,'comparison=%d verified candidate-generation/search methods, same data and timing scenario; no equal-runtime or global-optimality claim.\n',numel(files));
fprintf('Q2_99_AUDIT PASS N=%d Cmax=%.9f min E=%.9f kWh multi=%d\n',N,V.independentMetrics.Cmax_s/60,V.independentMetrics.energy_kWh,sum(sorties.service_area_count>1));
 function W=strict(X)
 W=validate_q2_solution(D,legs,X,'RequireAllExpectedOnTime',true, ...
  'AllowPrepBatteryOverlap',true,'AllowFixedPrepPrestage',true);
 end
 function z=check_mutation(name,X)
 W=strict(X);assert(strcmp(W.status,'FAIL'),'Validator accepted %s',name);
 z={string(name),true,strjoin(W.issues,' | ')};
 end
end
