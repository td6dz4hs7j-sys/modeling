# D题——山区洪涝灾害下无人机运输与通信协同优化

本仓库 td6dz4hs7j-sys/modeling 承载项目标识 D-UAV-guobaotegong 的三人协作代码与记录。

当前交付范围是问题一：固定服务区内的单点往返运输、不可拆货箱组批和返航余量敏感性。问题二至四、通信协同和完整竞赛论文不在本轮范围内。当前结果基于题面没有展开子项公式时登记的“参数化参考模型 A”，正式使用前必须由队伍人工复核该假设。

## 目录用途

| 目录 | 用途 | 约束 |
| --- | --- | --- |
| data/ | 题目附件、原始只读副本和输入说明 | 不在原始附件上写结果 |
| src/ | Python 源码、输入校验、物理模型、baseline 和改进算法 | 只提交可审阅、可复现的源码 |
| results/ | 实际运行产生的结果表、约束验证和复现清单 | 不提交猜测结果 |
| figures/ | raw、process、result 三类真实数据图和流程图 | 图表必须能追溯到运行记录 |
| paper/ | 论文草稿、模板副本和导出文件 | 不在本轮生成完整论文 |
| docs/ | 进度、模型参数、能耗核验、分工和交接记录 | 公共接口变更需在 PR 说明 |

根目录的 使用指南.md 和 SKILL_VERSION.md 记录已安装 skill 的使用边界与固定版本。

## Q1 运行方式

从仓库根目录执行。推荐先运行只含确定性 baseline/局部搜索的检查：

    python -m src.run_q1 --data-dir data --output-dir results --energy-provider src.problem_energy_provider --no-milp

完成 baseline 验证后，再运行 MILP 对照：

    python -m src.run_q1 --data-dir data --output-dir results --energy-provider src.problem_energy_provider --milp-time-limit-s 30

如需扫描返航余量，可在上述命令后增加 --reserve-values 和一组实际要检查的 rho 值。程序固定执行 FFD baseline → 约束验证 → 局部搜索；MILP 只是可选的最小架次对照，未使用遗传算法。

填写题目提供的结果模板副本，并生成详细对比工作表：

    python -m src.fill_q1_excel --template data/raw/D题/结果提交模板.xlsx --data-dir data --results-dir results --output results/结果提交模板_Q1_已填写.xlsx

输出工作簿保留 Q2–Q4 的原始空表，仅填写 Q1，并新增 Q1_架次明细、Q1_方法对比、Q1_安全载荷、Q1_敏感性、Q1_约束核验和 Q1_路线几何工作表。详细工作表使用普通筛选区域而非结构化 Table，以兼容不同版本的 Excel/WPS。原始模板和 data/raw/D题 下的附件不会被覆盖。

重算外部提供的 Q1 组批方案（输入快照只读，使用统一参考模型 A）：

    python -m src.recompute_q1_solution --solution data/raw/D题/对照方案_问题1_结果提交.xlsx --data-dir data --output-dir results --excel-output results/问题1_对照方案_统一模型_含作业时间.xlsx

该命令生成 `results/q1_对照方案_统一模型.csv`、`results/q1_对照方案_统一模型.json` 和带作业时间明细的 `results/问题1_对照方案_统一模型_含作业时间.xlsx`。重算结果是 18 架次、59.121155561792 kWh；往返飞行时间为 19272.301126723785 s，按附件参数计入准备、逐箱装载和接收点交接后总作业时间为 32760.301126723785 s（9.1000836463 h）。它是 reference-model-A-v1 下的条件性结果，原表给出的 59.2329 kWh 仅作为对照，不据此猜测原方案的未知能耗公式。

注意：`results/q1_组批方案.csv` 是另一次独立优化搜索产生的候选方案，架次明细可能与上述外部方案统一重算不同；提交工作簿和本次 59.13 kWh 版本以 `q1_对照方案_统一模型.json` 为准。

使用 MATLAB R2022a 独立验证并生成对比优势图：

    matlab -batch "addpath('src'); matlab_q1_batch"

该命令核对 80 箱唯一覆盖、逐架次时间分解、总时间和总能耗，并生成 `results/matlab_q1_verification.json`、`results/matlab_q1_method_comparison.csv`、`results/matlab_q1_advantage.csv`，以及 `figures/process_q1_matlab_time_reconciliation.*`、`figures/result_q1_matlab_method_comparison.*`、`figures/result_q1_matlab_advantage.*`。外部固定方案与候选方法的比较只表示统一口径下的结果差异，不把外部方案宣称为重新证明的全局最优。

将统一模型方案替换到主提交工作簿的 Q1 栏目，并增加每架次总作业时间列：

    python -m src.replace_q1_submission --source-workbook results/问题1_对照方案_统一模型_含作业时间.xlsx --result-json results/q1_对照方案_统一模型.json --output results/结果提交模板_Q1_已填写_含作业时间.xlsx

主表 `Q1_单点组批` 现在包含 `往返时间（s）` 和 `作业时间（s）` 两列；`作业时间（s）` 按题面附件参数计入准备、逐箱装载和接收点交接。Q2–Q4 工作表保留，原始附件不修改。若现有工作簿被 Excel/WPS 占用，请使用带“含作业时间”的新文件名。

能耗适配器的模型假设、题面已给公式、外部参考和局限见 docs/能耗模型核验.md。缺少输入、公式核验信息或依赖时，程序应停止并写出阻断状态，不得生成伪造结果。

## 三人协作步骤

1. 开始任务前，读取 docs/项目进度.md、docs/模型与参数.md、docs/分工.md，然后检查 git status、当前分支和远端。
2. 从最新 main 创建独立任务分支，建议使用 feat/<成员>-<任务>、fix/<成员>-<任务> 或 docs/<成员>-<任务>。
3. 每个任务只修改自己负责的文件；修改公共模型、参数或数据接口时，在 PR 中说明影响范围、兼容性和复验计划。
4. 先运行与任务相称的验证，再在 docs/交接记录/<成员>/<任务>-<日期>.md 留下改动、验证、未解决问题和下一步。
5. 通过 Pull Request 汇总到 main，由团队人工评审和合并；不覆盖他人修改、不强制推送、不自动合并 PR。

详细约束见 AGENTS.md。所有 skill 产物都是学习和研究草稿，提交前必须由队伍人工核对。
