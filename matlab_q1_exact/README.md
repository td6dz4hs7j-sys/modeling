# 问题一 MATLAB 精确组批与三目标加权结果

这是问题一的独立 MATLAB 结果链，和仓库已有的 Python `MILP + relocate/swap` 结果并列保存，不替换原有方案。模型使用同一份 `data/raw/D题` 输入快照，采用 `g=9.81 m/s²`、DEM 逐像元最高地形和题面等效航程/返航余量解释。

算法流程为：

1. 对 15 个服务区和 3 种机型求最大安全载荷；
2. 枚举服务区内满足质量、体积、能量和返航余量的可行组批模式；
3. 用计数状态精确动态规划求解组批，主目标为 `N → E → T`；
4. 用 `intlinprog` 对每个服务区进行独立交叉验证；
5. 用归一化三目标加权函数 `J=wN*N/N0+wE*E/E0+wT*T/T0` 比较架次、能耗和累计作业时间的权衡。

从仓库根目录运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\matlab_q1_exact\run_q1.ps1 -Mode full
```

输出写入 `results/q1_exact_dp/`，图片写入 `results/q1_exact_dp/figures/`。主方案结果为 18 架次、59.131296 kWh、9.104449 h；80 个货箱全部覆盖。极端能耗权重 `(0.01,0.98,0.01)` 选择 19 架次、59.033942 kWh、9.566660 h，体现三项指标之间的离散权衡。

`Q1_结果提交.xlsx` 的模板列“往返时间（s）”按本项目口径填入完整架次作业时间；`sortie_batches.csv` 同时保留 `flight_time_s` 与 `operation_time_s`，便于按官方最终填写口径替换。
