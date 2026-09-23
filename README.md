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

输出工作簿保留 Q2–Q4 的原始空表，仅填写 Q1，并新增 Q1_架次明细、Q1_方法对比、Q1_安全载荷、Q1_敏感性、Q1_约束核验和 Q1_路线几何工作表。原始模板和 data/raw/D题 下的附件不会被覆盖。

能耗适配器的模型假设、题面已给公式、外部参考和局限见 docs/能耗模型核验.md。缺少输入、公式核验信息或依赖时，程序应停止并写出阻断状态，不得生成伪造结果。

## 三人协作步骤

1. 开始任务前，读取 docs/项目进度.md、docs/模型与参数.md、docs/分工.md，然后检查 git status、当前分支和远端。
2. 从最新 main 创建独立任务分支，建议使用 feat/<成员>-<任务>、fix/<成员>-<任务> 或 docs/<成员>-<任务>。
3. 每个任务只修改自己负责的文件；修改公共模型、参数或数据接口时，在 PR 中说明影响范围、兼容性和复验计划。
4. 先运行与任务相称的验证，再在 docs/交接记录/<成员>/<任务>-<日期>.md 留下改动、验证、未解决问题和下一步。
5. 通过 Pull Request 汇总到 main，由团队人工评审和合并；不覆盖他人修改、不强制推送、不自动合并 PR。

详细约束见 AGENTS.md。所有 skill 产物都是学习和研究草稿，提交前必须由队伍人工核对。
