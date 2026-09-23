import fs from "node:fs/promises";
import { FileBlob, SpreadsheetFile } from "file:///C:/Users/HoGaaiDik/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/@oai/artifact-tool/dist/artifact_tool.mjs";

const projectRoot = "D:/Desktop/modeling-repo";
const inputPath = `${projectRoot}/results/结果提交模板_Q1_已填写.xlsx`;
const outputPath = `${projectRoot}/results/结果提交模板_Q1_已填写_含作业时间.xlsx`;
const resultPath = `${projectRoot}/results/q1_对照方案_统一模型.json`;

const result = JSON.parse(await fs.readFile(resultPath, "utf8"));
const rows = result.per_batch;
const workbook = await SpreadsheetFile.importXlsx(await FileBlob.load(inputPath));

const main = workbook.worksheets.getItem("Q1_单点组批");
const detail = workbook.worksheets.getItem("Q1_统一模型结果");
main.getRange(`H2:H${rows.length + 1}`).values = rows.map((row) => [row.work_time_s]);
detail.getRange(`H2:H${rows.length + 1}`).values = rows.map((row) => [row.work_time_s]);

const notes = workbook.worksheets.getItem("填写说明");
notes.getRange("A7:B11").values = [
  ["重算往返飞行时间_s", result.metrics.recomputed.time_s],
  ["装卸交接总时间_s", result.metrics.recomputed.handling_time_s],
  ["重算总作业时间_s", result.metrics.recomputed.work_time_s],
  ["相对原表能耗差_kWh", result.metrics.delta.energy_kwh],
  ["相对原表时间差_s", result.metrics.delta.time_s],
];
notes.getRange("B12").values = [[
  "Q1 作业时间定义为：往返飞行 + 工位固定准备 + 每箱装载 + 接收点基础交接 + 每箱增加交接；参数来自运输无人机数据.xlsx。",
]];
notes.getRange("A13:B15").values = [
  ["时间口径说明", result.model.time_definition],
  ["时间参数来源", result.model.time_source],
  ["校验状态", "80 个货箱一次性覆盖，18 架次，质量/体积/能耗/航程约束均通过。"],
];

workbook.recalculate();

const check = await workbook.inspect({
  kind: "table",
  sheetId: "Q1_单点组批",
  range: "A1:J6",
  include: "values,formulas",
  tableMaxRows: 6,
  tableMaxCols: 10,
  maxChars: 5000,
});
console.log(check.ndjson);

const preview = await workbook.render({
  sheetName: "Q1_单点组批",
  autoCrop: "all",
  scale: 1.2,
  format: "png",
});
await fs.writeFile(`${projectRoot}/results/结果提交模板_Q1_已填写_含作业时间_预览.png`, new Uint8Array(await preview.arrayBuffer()));

const output = await SpreadsheetFile.exportXlsx(workbook);
await output.save(outputPath);
console.log(`created ${outputPath}`);
