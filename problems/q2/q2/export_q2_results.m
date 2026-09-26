function export_q2_results(D,legs,S,baseline,R,outFolder)
% EXPORT_Q2_RESULTS Write auditable CSV/JSON and fill only the Q2 template sheets.
if nargin<6||strlength(string(outFolder))==0,outFolder=fullfile(D.root,'results','q2_final');end
if ~isfolder(outFolder),mkdir(outFolder);end
assert(isstruct(S)&&isfield(S,'sorties')&&isfield(S,'boxDelivery')&&isfield(S,'metrics'),'S must be the frozen scheduled solution.');
assert(isstruct(baseline)&&isfield(baseline,'sorties')&&isfield(baseline,'metrics'),'baseline must be a scheduled solution.');

sorties=S.sorties;boxes=S.boxDelivery;
if istable(sorties)&&height(sorties)>0
 sorties.multi_point=cellfun(@(x)numel(strsplit(char(x),'→'))>1,cellstr(sorties.service_order));
 writetable(sorties,fullfile(outFolder,'q2_final_sorties.csv'));
else,writetable(table(),fullfile(outFolder,'q2_final_sorties.csv'));end
if istable(boxes)&&height(boxes)>0
 boxes.hard_margin_s=boxes.hard_deadline_s-boxes.arrival_s;boxes.soft_lateness_s=max(0,boxes.arrival_s-boxes.expected_s);
 boxes.hard_deadline_met=~isfinite(boxes.hard_deadline_s)|boxes.hard_margin_s>=-D.tol.time;
 writetable(boxes,fullfile(outFolder,'q2_final_box_delivery.csv'));
else,writetable(table(),fullfile(outFolder,'q2_final_box_delivery.csv'));end

% Physical battery records include every inventory battery, including unused units.
br=cell(0,12);for k=1:height(D.batteryInventory)
 for j=1:D.batteryInventory.count(k)
  bid=D.batteryInventory.type(k)+"-B"+compose('%02d',j);ix=find(S.sorties.battery_id==bid);
  if isempty(ix),br(end+1,:)={bid,D.batteryInventory.type(k),false,"",NaN,NaN,0,1,1,0,0,D.batteryInventory.fullCharge_s(k)}; %#ok<AGROW>
  else
   for z=ix(:)'
    rid=S.routes(z);ev=rid.eval; br(end+1,:)={bid,D.batteryInventory.type(k),true,sorties.sortie_id(z),sorties.start_s(z),sorties.return_s(z),rid.batteryReady_s,1,ev.returnSOC,ev.energy_kWh,ev.charge_s,D.batteryInventory.fullCharge_s(k)}; %#ok<AGROW>
   end
  end
 end
end
battery=cell2table(br,'VariableNames',{'battery_id','uav_type','used','sortie_id','occupied_start_s','return_s','ready_s','start_SOC_fraction','return_SOC_fraction','energy_kWh','charge_s','full_charge_s'});
writetable(battery,fullfile(outFolder,'q2_final_battery_SOC_charge_ready.csv'));

% Fleet and battery resource totals use explicit physical IDs.
rr=cell(0,8);for i=1:height(D.uavInventory)
 id=D.uavInventory.id(i);q=sorties.uav_id==id;dur=sum(sorties.return_s(q)-sorties.start_s(q));
 rr(end+1,:)={id,D.uavInventory.type(i),sum(q),dur,max([0;sorties.return_s(q)]),dur/max(S.metrics.Cmax_s,eps),numel(unique(sorties.battery_id(q))),D.uavInventory.initialNode(i)}; %#ok<AGROW>
end
resource=cell2table(rr,'VariableNames',{'uav_id','uav_type','sortie_count','occupied_s_total','last_return_s','busy_fraction_of_Cmax','distinct_battery_count','initial_node'});
writetable(resource,fullfile(outFolder,'q2_final_uav_resource_summary.csv'));
if isfield(D,'batteryInventory'),writetable(D.batteryInventory,fullfile(outFolder,'q2_battery_inventory_summary.csv'));end

% Preserve baseline and final objective values, including the actual route mix.
q2=struct('W',S.metrics.W,'Cmax_s',S.metrics.Cmax_s,'energy_kWh',S.metrics.energy_kWh,'N',S.metrics.N);
qb=struct('W',baseline.metrics.W,'Cmax_s',baseline.metrics.Cmax_s,'energy_kWh',baseline.metrics.energy_kWh,'N',baseline.metrics.N);
q2Operation_h=sum(sorties.operation_s)/3600;baselineOperation_h=sum(baseline.sorties.operation_s)/3600;
multiPoint=countMulti(S);baseMulti=countMulti(baseline);
metrics=struct('final',q2,'baseline',qb,'final_multi_point_routes',multiPoint,'baseline_multi_point_routes',baseMulti, ...
 'final_cumulative_operation_h',q2Operation_h,'baseline_cumulative_operation_h',baselineOperation_h, ...
 'final_delivered_boxes',height(boxes),'final_hard_deadline_violations',sum(~boxes.hard_deadline_met), ...
 'final_soft_lateness_priority_s',S.metrics.W, ...
 'final_expected_on_time_count',sum(boxes.arrival_s<=boxes.expected_s+D.tol.time), ...
 'final_expected_on_time_rate',mean(boxes.arrival_s<=boxes.expected_s+D.tol.time), ...
 'q1_weighted_lateness','N/A (not evaluated)');
writejson(fullfile(outFolder,'q2_final_metrics.json'),metrics);
radial=[legs([legs.fromIdx]==1).distance_m];
fixedTypeLB=zeros(height(D.uav),1);
for k=1:height(D.uav)
 q=sorties.uav_type==D.uav.id(k);count=sum(D.uavInventory.type==D.uav.id(k));
 if count>0,fixedTypeLB(k)=sum(sorties.operation_s(q))/count;end
end
quality=struct('status','best-known feasible; no global lexicographic optimality proof', ...
 'W_nonnegative_lower_bound',0,'W_lower_bound_attained',S.metrics.W<=D.tol.time, ...
 'Cmax_safe_horizontal_roundtrip_lower_bound_s',2*max(radial)/max(D.uav.speed), ...
 'sortie_capacity_lower_bound',max(ceil(sum(D.boxMass)/max(D.uav.payload)),ceil(sum(D.boxVolume)/max(D.uav.volume))), ...
 'bound_explanation','Any closed depot route serving a node travels at least twice its geodesic depot distance; all aircraft speeds are bounded by max speed. Bound omits handling, terrain and resources and is weak.', ...
 'limitations','Sampled neighborhoods and greedy resource decoder; at most one visit per area per route. No global gap certificate for Cmax/E/N.');
quality.fixed_routes_and_types_Cmax_workload_lower_bound_s=max(fixedTypeLB);
quality.fixed_routes_and_types_schedule_gap_pct=100*(S.metrics.Cmax_s/max(fixedTypeLB)-1);
quality.conditional_bound_scope='Only reassign/reorder these frozen routes among same-type UAVs; changing route grouping, visits or types invalidates this workload bound. This is not a global Q2 optimality gap.';
writejson(fullfile(outFolder,'q2_solution_quality.json'),quality);
metricRows={'Q2 baseline',qb.W,qb.Cmax_s,qb.energy_kWh,qb.N,baseMulti;'Q2 final',q2.W,q2.Cmax_s,q2.energy_kWh,q2.N,multiPoint};
writetable(cell2table(metricRows,'VariableNames',{'scenario','W_priority_s','Cmax_s','energy_kWh','sorties_N','multi_point_routes'}),fullfile(outFolder,'q2_optimization_metrics.csv'));

% Optimization records remain traceable to all seeds/rounds when supplied.
if isstruct(R)&&isfield(R,'summary')&&istable(R.summary),writetable(R.summary,fullfile(outFolder,'q2_optimization_seed_summary.csv'));else,writetable(table(),fullfile(outFolder,'q2_optimization_seed_summary.csv'));end
if isstruct(R)&&isfield(R,'trace')&&istable(R.trace),writetable(R.trace,fullfile(outFolder,'q2_optimization_trace.csv'));else,writetable(table(),fullfile(outFolder,'q2_optimization_trace.csv'));end
if isstruct(R)&&isfield(R,'statistics')
 fn=fieldnames(R.statistics);sr=cell(numel(fn),5);for i=1:numel(fn),v=R.statistics.(fn{i});sr(i,:)={fn{i},v.best,v.mean,v.worst,v.std};end
 writetable(cell2table(sr,'VariableNames',{'metric','best','mean','worst','std'}),fullfile(outFolder,'q2_optimization_statistics.csv'));
else,writetable(table(),fullfile(outFolder,'q2_optimization_statistics.csv'));end

% Q1 comparison intentionally excludes weighted lateness and time-improvement claims.
q1Path=fullfile(D.root,'results','overall_metrics.json');q1=struct('total_sorties',NaN,'total_energy_kWh',NaN,'total_operation_time_h',NaN);
if isfile(q1Path),q1=jsondecode(fileread(q1Path));end
rows={'Q1 published baseline',NaN,q1.total_energy_kWh,q1.total_sorties,q1.total_operation_time_h,NaN,'Q1 cumulative time; W not evaluated'; ...
 'Q2 supplied baseline',qb.W,qb.energy_kWh,qb.N,baselineOperation_h,qb.Cmax_s/3600,sprintf('Cmax is makespan; baseline has %d routes, %d multi-point',qb.N,baseMulti); ...
 'Q2 final',q2.W,q2.energy_kWh,q2.N,q2Operation_h,q2.Cmax_s/3600,'Cmax is makespan; multi-point count is separately reported'};
writetable(cell2table(rows,'VariableNames',{'scenario','W_priority_s','energy_kWh','sorties_N','cumulative_operation_time_h','Cmax_h','interpretation'}),fullfile(outFolder,'q1_q2_comparison.csv'));

% Source fingerprints cover Q2/common MATLAB source and the relevant input workbooks.
sourceFiles=[dir(fullfile(D.root,'q2','*.m'));dir(fullfile(D.root,'common','*.m'));dir(fullfile(D.root,'utils','*.m'))];paths=string(fullfile({sourceFiles.folder},{sourceFiles.name}));
inputDir=fullfile(D.root,'input','数据','无人机应急物资运输基础数据');
books=dir(fullfile(inputDir,'*.xlsx'));paths=[paths,string(fullfile({books.folder},{books.name})),string(fullfile(D.root,'input','结果提交模板.xlsx')),string(fullfile(D.root,'input','problem_text.txt')),string(fullfile(D.root,'run_q2.ps1')),string(fullfile(D.root,'results','overall_metrics.json'))];
demMat=dir(fullfile(D.root,'input','**','*DEM.mat'));demTif=dir(fullfile(D.root,'input','**','*DEM.tif'));
paths=[paths,string(fullfile({demMat.folder},{demMat.name})),string(fullfile({demTif.folder},{demTif.name})),string(fullfile(D.root,'results','Q1_结果提交.xlsx'))];paths=paths(isfile(paths));
hashRows=cell(numel(paths),2);for i=1:numel(paths),hashRows(i,:)={erase(paths(i),string(D.root)+filesep),file_sha256(paths(i))};end
hashTable=cell2table(hashRows,'VariableNames',{'relative_path','sha256'});writetable(hashTable,fullfile(outFolder,'source_hashes.csv'));
writejson(fullfile(outFolder,'source_hash_manifest.json'),struct('aggregateSHA256',q2_sha256(paths),'aggregateAlgorithm','q2_sha256: sorted path bytes followed by file bytes','fileAlgorithm','SHA-256 over file bytes only','relativePaths',{hashRows(:,1)},'sha256',{hashRows(:,2)}));

altPath=fullfile(outFolder,'q2_energy_preference.mat');
if isfile(altPath)
 alt=load(altPath,'Ralt');a=alt.Ralt.best.metrics;
 comp={'main_W_Cmax_E_N',numel(R.seeds),q2.W,q2.Cmax_s,q2.energy_kWh,q2.N; ...
 'alternative_W_E_Cmax_N',numel(alt.Ralt.seeds),a.W,a.Cmax_s,a.energy_kWh,a.N};
 writetable(cell2table(comp,'VariableNames',{'preference','seed_count','W_priority_s','Cmax_s','energy_kWh','N'}),fullfile(outFolder,'q2_preference_comparison.csv'));
end
writeWorkbook();writeConclusions();

 function writeWorkbook()
  template=fullfile(D.root,'input','结果提交模板.xlsx');q1book=fullfile(D.root,'results','Q1_结果提交.xlsx');
  target=fullfile(outFolder,'Q2_结果提交.xlsx');if isfile(q1book),copyfile(q1book,target,'f');else,copyfile(template,target,'f');end
  expected2={'架次编号','无人机编号','机型编号','电池编号','开始时刻（s）','访问服务区顺序','返回O01时刻（s）','架次能耗（kWh）'};
  expected3={'货箱编号','架次编号','服务区编号','交付完成时刻（s）'};
  h2=string(readcell(template,'Sheet','Q2_运输架次','Range','A1:H1'));h3=string(readcell(template,'Sheet','Q2_逐箱交付','Range','A1:D1'));
  assert(isequal(cellstr(h2),expected2),'Q2_运输架次 template headers changed; refusing workbook export.');
  assert(isequal(cellstr(h3),expected3),'Q2_逐箱交付 template headers changed; refusing workbook export.');
  sortiesCell=cell(height(sorties),8);
  for i=1:height(sorties),sortiesCell(i,:)={sorties.sortie_id(i),sorties.uav_id(i),sorties.uav_type(i),sorties.battery_id(i),sorties.start_s(i),sorties.service_order(i),sorties.return_s(i),sorties.energy_kWh(i)};end
  boxCell=cell(height(boxes),4);
  for i=1:height(boxes),boxCell(i,:)={boxes.box_id(i),boxes.sortie_id(i),boxes.area(i),boxes.arrival_s(i)};end
  if ~isempty(sortiesCell),writecell(sortiesCell,target,'Sheet','Q2_运输架次','Range','A2');end
  if ~isempty(boxCell),writecell(boxCell,target,'Sheet','Q2_逐箱交付','Range','A2');end
 end
 function writeConclusions()
  path=fullfile(outFolder,'conclusions_q2.md');fid=fopen(path,'w','n','UTF-8');c=onCleanup(@()fclose(fid));
  fprintf(fid,'# Q2 结果口径与来源\n\n');
  fprintf(fid,'最终排程：%d 架次，其中多点路线 %d 架；该数由冻结的 S.routes.nodeOrder 实际统计。Q2 基线：%d 架次，其中多点路线 %d 架。\n\n',q2.N,multiPoint,qb.N,baseMulti);
  fprintf(fid,'Q1 加权迟到未评价，必须记为 N/A；不得把旧图中的 0 当作已计算值。Q1 与 Q2 的累计作业时间均为各架次作业时长求和，可以比较；Q2 Cmax 是并行排程的最晚完工时刻，与累计作业时间不同，不计算两者之间的改善率。Q1/Q2 可直接比较架次数、能耗与累计作业时间；Q2 基线、最终方案可比较 W、Cmax、E、N。\n\n');
  fprintf(fid,'旧 Python 汇总图未作为数据源。本次图表应由 MATLAB 原生对象调用 `apply_publication_style` 与严格门禁 `export_publication_figure` 生成；门禁失败时不会导出成功图。\n\n');
  fprintf(fid,'本文件随冻结 S/R 导出；validator、独立 P1 与最终解冻结状态由主代理回执确认，本脚本不自行声称这些审查通过。源文件指纹见 `source_hashes.csv`。\n');
 end
end

function n=countMulti(S)
n=0;if ~isfield(S,'routes'),return;end
for i=1:numel(S.routes),if numel(S.routes(i).nodeOrder)>1,n=n+1;end,end
end
function writejson(path,value)
fid=fopen(path,'w','n','UTF-8');assert(fid>=0,'Cannot open JSON output: %s',path);c=onCleanup(@()fclose(fid));fprintf(fid,'%s',jsonencode(value,'PrettyPrint',true));
end
function h=file_sha256(path)
md=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(path,'rb');assert(fid>=0,'Cannot hash source: %s',path);c=onCleanup(@()fclose(fid));bytes=fread(fid,Inf,'*uint8');clear c;md.update(bytes);d=typecast(md.digest(),'uint8');h=lower(reshape(dec2hex(d,2)',1,[]));
end
