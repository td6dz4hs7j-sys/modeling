# 问题一优化最新版：精确动态规划与三目标比较

本分支主成果是`results/q1_exact_dp/`和`matlab_q1_exact/`，对应聊天“问题一优化最新版”。主方案为18架次、59.1302539266485 kWh、累计作业时间9.10444881914324 h，80箱唯一覆盖。

以服务区内模式枚举、计数状态精确动态规划求解，并用MILP交叉验证。主目标N→E→T；六组三目标加权都同时包括架次、能耗、时间。极端能耗权重0.01/0.98/0.01产生19架次、59.0328677933385 kWh、9.56666039087525 h，其余常规权重选择18架次。最优性限于登记的Q1模型和相应目标。

Q1重力加速度统一为9.806，已按用户要求重新求解并验证，与Q2/Q3一致。时间为累计作业时间，不是并行最晚返航。模板往返时间列沿用本次已披露的完整架次作业口径，CSV另存纯飞行时间。

## 当前入口

- [完整结果工作簿](results/q1_exact_dp/D题_问题一_结果提交.xlsx)：与`Q1_结果提交.xlsx`同步，含方案对比、模型说明，共8个工作表。
- [指标](results/q1_exact_dp/overall_metrics.json)、[三目标比较](results/q1_exact_dp/weighted_joint_comparison.csv)、[逐架次](results/q1_exact_dp/sortie_batches.csv)。
- [最新版图件](results/q1_exact_dp/figures/)：16组彩色PNG/SVG，另有灰度预览；图件已与本地权威版本逐像素/哈希核对。
- [当前模型与术语](docs/Q1_最新版模型与术语.md)、[文档与证据索引](results/q1_exact_dp/文档线索索引.md)。

复现：`powershell -NoProfile -ExecutionPolicy Bypass -File .\matlab_q1_exact\run_q1.ps1 -Mode full`。需MATLAB及原已登记工具箱。仅重导出模型说明与对比页，可在仓库根运行MATLAB：`addpath('matlab_q1_exact/q1','matlab_q1_exact/common'); S=load('results/q1_exact_dp/q1_solution.mat','metrics','comparison'); finalize_q1_report(S.metrics,S.comparison,fullfile(pwd,'results','q1_exact_dp'));`。

完整性核对：`python verify_snapshot.py`；重新计算及验收完成后执行`python verify_snapshot.py --refresh`更新发布清单。

## 历史内容边界

根`src/`、根`figures/`以及`results/`下不在`q1_exact_dp/`中的早期Python/MILP与固定组批参考均是历史链，其63.0586 kWh或59.1212 kWh不代表当前最终方案。原首页已留存`docs/history/README_旧Python链.md`。历史阶段M1/P1与截图证据只用于追溯，最终状态以本分支Q1精确DP的P2记录及最新结果为准。
