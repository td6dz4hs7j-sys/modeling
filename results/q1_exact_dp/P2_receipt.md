# P2 编程终检回执

日期：2026-09-26  
范围：D 题问题一 MATLAB 精确组批与三目标加权结果链

**状态：P2 PASS。** 独立工作树中的 `matlab_q1_exact/run_q1.ps1 -Mode full` 已完成，`results/q1_exact_dp/run_status_full.txt` 为 `0`。

- MATLAB R2022a（`9.12.0.1884302`），`g=9.81 m/s²`。
- 主方案：18 架次、59.1312960221 kWh、9.1044488191 h；80 个货箱、758 kg。
- `validation.json`：`PASS`，80 个货箱恰好覆盖，独立重算为真，最小 SOC 为 0.2308835。
- 15 个服务区完成计数状态 DP 与 `intlinprog` 交叉验证，`N_gap/E_gap/T_gap` 均为 0。
- 三目标加权结果见 `weighted_joint_comparison.csv`；极端能耗权重方案为 19 架次、59.0339420922 kWh、9.5666603909 h。
- 图表、Excel、复现清单和输入哈希均写入本目录；本目录与仓库原有 Python 结果链并列，不替换原有结果。
