function report = matlab_validate_q1()
%MATLAB_VALIDATE_Q1 用 MATLAB 独立复核 Q1 统一模型结果并生成对比图。
%
% 该脚本不重新优化组批方案；它读取已冻结的统一模型 JSON 和方法比较
% CSV，独立复核时间分解、能耗汇总、货箱唯一覆盖，并输出对比优势。

projectRoot = fileparts(fileparts(mfilename("fullpath")));
utilsDir = fullfile(projectRoot, "utils");
resultsDir = fullfile(projectRoot, "results");
figuresDir = fullfile(projectRoot, "figures");
addpath(utilsDir);
rng(0, "twister");

environment = check_matlab_env(["data", "visualization"]);
assert(environment.ok, "MATLAB 数据/可视化环境检查未通过");

resultJsonPath = fullfile(resultsDir, "q1_对照方案_统一模型.json");
methodCsvPath = fullfile(resultsDir, "q1_方法比较.csv");
uavDataPath = fullfile(projectRoot, "data", "raw", "D题", "数据", ...
    "无人机应急物资运输基础数据", "运输无人机数据.xlsx");
result = jsondecode(fileread(resultJsonPath));
batchRows = result.per_batch;
assert(isstruct(batchRows) && ~isempty(batchRows), "统一模型 JSON 没有架次明细");

flightTime = reshape([batchRows.time_s], [], 1);
handlingTime = reshape([batchRows.handling_time_s], [], 1);
workTime = reshape([batchRows.work_time_s], [], 1);
energy = reshape([batchRows.energy_kwh], [], 1);

% 独立检查：总作业时间必须逐架次满足飞行 + 装卸交接。
timeResidual = workTime - flightTime - handlingTime;
assert(max(abs(timeResidual)) <= 1e-9, "逐架次作业时间分解不一致");
expected = result.metrics.recomputed;
assert(abs(sum(flightTime) - expected.time_s) <= 1e-8, "往返飞行时间汇总不一致");
assert(abs(sum(handlingTime) - expected.handling_time_s) <= 1e-8, "装卸交接时间汇总不一致");
assert(abs(sum(workTime) - expected.work_time_s) <= 1e-8, "总作业时间汇总不一致");
assert(abs(sum(energy) - expected.energy_kwh) <= 1e-8, "能耗汇总不一致");
assert(all(isfinite([flightTime; handlingTime; workTime; energy])));
assert(all([flightTime; handlingTime; workTime; energy] >= 0));

% 直接读取题目附件中的四项运输作业参数，独立重算装卸交接时间。
uavTable = readtable(uavDataPath, "TextType", "string", ...
    "VariableNamingRule", "preserve");
uavHeaders = string(uavTable.Properties.VariableNames);
typeColumn = findColumn(uavHeaders, ["机型编号", "运输机型", "无人机型号", "型号", "机型"]);
prepColumn = findColumn(uavHeaders, ["工位固定准备时间（s）", "工位固定准备时间", "固定准备时间"]);
loadColumn = findColumn(uavHeaders, ["每箱装载时间（s）", "每箱装载时间", "装载时间"]);
handoffBaseColumn = findColumn(uavHeaders, ["接收点基础交接时间（s）", "接收点基础交接时间", "基础交接时间"]);
handoffBoxColumn = findColumn(uavHeaders, ["每箱增加交接时间（s）", "每箱增加交接时间", "每箱交接时间"]);
sourceType = upper(strip(string(uavTable.(char(uavHeaders(typeColumn))))));
sourcePrep = toNumeric(uavTable.(char(uavHeaders(prepColumn))));
sourceLoad = toNumeric(uavTable.(char(uavHeaders(loadColumn))));
sourceHandoffBase = toNumeric(uavTable.(char(uavHeaders(handoffBaseColumn))));
sourceHandoffBox = toNumeric(uavTable.(char(uavHeaders(handoffBoxColumn))));
sourceHandling = zeros(numel(batchRows), 1);
for k = 1:numel(batchRows)
    typeIndex = find(sourceType == upper(string(batchRows(k).uav_type)), 1);
    assert(~isempty(typeIndex), "附件中找不到机型 %s", batchRows(k).uav_type);
    boxCount = double(batchRows(k).box_count);
    sourceHandling(k) = sourcePrep(typeIndex) + boxCount * sourceLoad(typeIndex) + ...
        sourceHandoffBase(typeIndex) + boxCount * sourceHandoffBox(typeIndex);
end
sourceHandlingResidual = sourceHandling - handlingTime;
assert(max(abs(sourceHandlingResidual)) <= 1e-9, "附件参数重算的装卸交接时间不一致");

% 独立核对货箱编号是否恰好覆盖一次。
boxIds = strings(0, 1);
for k = 1:numel(batchRows)
    currentIds = string(strsplit(string(batchRows(k).box_ids_normalized), ";"));
    boxIds = [boxIds; reshape(currentIds, [], 1)]; %#ok<AGROW>
end
boxIds = strip(boxIds);
uniqueBoxIds = unique(boxIds);
assert(numel(boxIds) == result.validation.n_boxes, "货箱总数与验证记录不一致");
assert(numel(uniqueBoxIds) == numel(boxIds), "存在重复货箱编号");
assert(result.validation.passed, "Python 统一模型约束核验标记未通过");

% 读取已有候选方法结果，并追加固定外部方案。外部方案不标记为重新优化的最优解。
methodTable = readtable(methodCsvPath, "TextType", "string", ...
    "VariableNamingRule", "preserve");
methodNames = reshape(string(methodTable.("方法")), [], 1);
sorties = reshape(double(methodTable.("架次数")), [], 1);
methodEnergy = reshape(double(methodTable.("总运输能耗_kWh")), [], 1);
methodWorkTime = reshape(double(methodTable.("累计作业时间_s")), [], 1);

comparisonNames = [methodNames; "External fixed plan"];
comparisonSorties = [sorties; expected.sorties];
comparisonEnergy = [methodEnergy; expected.energy_kwh];
comparisonWorkTime = [methodWorkTime; expected.work_time_s];
comparisonSource = [repmat("independent candidate", height(methodTable), 1); ...
    "fixed external grouping, unified-model recomputation"];
comparisonTable = table(comparisonNames, comparisonSorties, comparisonEnergy, ...
    comparisonWorkTime, comparisonSource, ...
    'VariableNames', {'Method', 'Sorties', 'Energy_kWh', ...
    'CumulativeWorkTime_s', 'Source'});
writetable(comparisonTable, fullfile(resultsDir, "matlab_q1_method_comparison.csv"));

targetIndex = numel(comparisonNames);
referenceNames = ["FFD baseline"; "MILP + local search"];
referenceIndex = [find(comparisonNames == referenceNames(1), 1), ...
    find(comparisonNames == referenceNames(2), 1)];
referenceEnergy = reshape(comparisonEnergy(referenceIndex), [], 1);
referenceWorkTime = reshape(comparisonWorkTime(referenceIndex), [], 1);
referenceSorties = reshape(comparisonSorties(referenceIndex), [], 1);
energySavings = 100 * (referenceEnergy - comparisonEnergy(targetIndex)) ./ referenceEnergy;
workTimeSavings = 100 * (referenceWorkTime - comparisonWorkTime(targetIndex)) ./ referenceWorkTime;
sortieSavings = 100 * (referenceSorties - comparisonSorties(targetIndex)) ./ referenceSorties;
advantageTable = table(referenceNames, energySavings, workTimeSavings, sortieSavings, ...
    referenceEnergy - comparisonEnergy(targetIndex), ...
    (referenceWorkTime - comparisonWorkTime(targetIndex)) / 3600, ...
    'VariableNames', {'Reference', 'EnergyReduction_percent', ...
    'WorkTimeReduction_percent', 'SortieReduction_percent', ...
    'EnergyReduction_kWh', 'WorkTimeReduction_h'});
writetable(advantageTable, fullfile(resultsDir, "matlab_q1_advantage.csv"));

report = struct();
report.engine = "MATLAB";
report.matlab_version = version;
report.required_toolboxes = environment.required_toolboxes;
report.n_sorties = expected.sorties;
report.n_boxes = result.validation.n_boxes;
report.unique_box_count = numel(uniqueBoxIds);
report.flight_time_s = expected.time_s;
report.handling_time_s = expected.handling_time_s;
report.work_time_s = expected.work_time_s;
report.work_time_h = expected.work_time_s / 3600;
report.energy_kwh = expected.energy_kwh;
report.max_work_time_residual_s = max(abs(timeResidual));
report.flight_time_sum_residual_s = sum(flightTime) - expected.time_s;
report.handling_time_sum_residual_s = sum(handlingTime) - expected.handling_time_s;
report.work_time_sum_residual_s = sum(workTime) - expected.work_time_s;
report.energy_sum_residual_kwh = sum(energy) - expected.energy_kwh;
report.source_handling_time_residual_max_s = max(abs(sourceHandlingResidual));
report.input_sha256 = struct( ...
    "unified_model_json", sha256File(resultJsonPath), ...
    "method_comparison_csv", sha256File(methodCsvPath), ...
    "transport_uav_xlsx", sha256File(uavDataPath));
report.constraint_validation_passed = result.validation.passed;
report.time_definition = "work = round-trip flight + preparation + per-box loading + base handoff + per-box handoff";
report.comparison_note = "External fixed plan is a re-evaluated supplied grouping, not a newly proven global optimum.";
writeJson(fullfile(resultsDir, "matlab_q1_verification.json"), report);

plotTimeReconciliation(flightTime, handlingTime, figuresDir);
plotMethodComparison(comparisonNames, comparisonEnergy, comparisonWorkTime, figuresDir);
plotAdvantages(referenceNames, energySavings, workTimeSavings, sortieSavings, figuresDir);

disp(jsonencode(report));
end

function writeJson(path, value)
fid = fopen(path, "w", "n", "UTF-8");
assert(fid >= 0, "无法写入 MATLAB 验证 JSON: %s", path);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, "%s", jsonencode(value));
end

function index = findColumn(headers, candidates)
index = find(ismember(headers, string(candidates)), 1);
assert(~isempty(index), "题目附件缺少字段：%s", strjoin(string(candidates), " / "));
end

function values = toNumeric(rawValues)
if isnumeric(rawValues)
    values = double(rawValues);
else
    values = str2double(string(rawValues));
end
values = reshape(values, [], 1);
end

function hash = sha256File(path)
fid = fopen(path, "rb");
assert(fid >= 0, "无法读取文件用于 SHA-256: %s", path);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
bytes = fread(fid, inf, "*uint8");
digest = java.security.MessageDigest.getInstance("SHA-256");
digest.update(bytes);
digestBytes = typecast(digest.digest(), "uint8");
hash = lower(reshape(dec2hex(digestBytes, 2).', 1, []));
end

function plotTimeReconciliation(flightTime, handlingTime, figuresDir)
fig = figure("Visible", "off");
bar(1:numel(flightTime), [flightTime, handlingTime], "stacked");
xlabel("Sortie index");
ylabel("Time (s)");
title("Time reconciliation");
legend({"Round-trip flight", "Handling"}, "Location", "northwest");
xticks(1:2:numel(flightTime));
apply_publication_style(fig, "en", "report");
export_publication_figure(fig, fullfile(figuresDir, "process_q1_matlab_time_reconciliation"), 300, true, true);
close(fig);
end

function plotMethodComparison(names, energy, workTime, figuresDir)
labels = ["FFD", "Local", "MILP", "MILP+LS", "External"];
fig = figure("Visible", "off");
tiledlayout(fig, 1, 2, "TileSpacing", "compact", "Padding", "compact");

ax1 = nexttile;
b1 = bar(ax1, energy, "FaceColor", "flat");
b1.CData = repmat([0.3373, 0.7059, 0.9137], numel(energy), 1);
b1.CData(end, :) = [0.0000, 0.4471, 0.6980];
xticks(ax1, 1:numel(labels));
xticklabels(ax1, labels);
xtickangle(ax1, 25);
ylabel(ax1, "Energy (kWh)");
title(ax1, "Energy comparison");

ax2 = nexttile;
b2 = bar(ax2, workTime / 3600, "FaceColor", "flat");
b2.CData = repmat([0.9020, 0.6235, 0.0000], numel(workTime), 1);
b2.CData(end, :) = [0.0000, 0.6196, 0.4510];
xticks(ax2, 1:numel(labels));
xticklabels(ax2, labels);
xtickangle(ax2, 25);
ylabel(ax2, "Cumulative work time (h)");
title(ax2, "Work time comparison");

apply_publication_style(fig, "en", "double");
export_publication_figure(fig, fullfile(figuresDir, "result_q1_matlab_method_comparison"), 300, true, true);
close(fig);
end

function plotAdvantages(referenceNames, energySavings, workTimeSavings, sortieSavings, figuresDir)
fig = figure("Visible", "off");
data = [energySavings, workTimeSavings, sortieSavings];
b = bar(data, "grouped");
b(1).FaceColor = [0.0000, 0.4471, 0.6980];
b(2).FaceColor = [0.9020, 0.6235, 0.0000];
b(3).FaceColor = [0.0000, 0.6196, 0.4510];
xticks(1:numel(referenceNames));
xticklabels({"vs FFD", "vs MILP+LS"});
ylabel("Reduction (%)");
title("Relative advantage");
legend({"Energy", "Work time", "Sorties"}, "Location", "northeast");
ylim([0, max(data(:)) * 1.18]);
for k = 1:size(data, 1)
    for j = 1:size(data, 2)
        x = b(j).XEndPoints(k);
        text(x, data(k, j), sprintf("%.1f", data(k, j)), ...
            "HorizontalAlignment", "center", "VerticalAlignment", "bottom", ...
            "FontSize", 7);
    end
end
apply_publication_style(fig, "en", "single");
export_publication_figure(fig, fullfile(figuresDir, "result_q1_matlab_advantage"), 300, true, true);
close(fig);
end
