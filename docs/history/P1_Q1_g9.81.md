# P1独立验收

质检者 /root/q1_m1，未参与实现，状态PASS。独立运行 `powershell -NoProfile -ExecutionPolicy Bypass -File .\run_q1.ps1 -Mode minimal`，退出码0，完成状态0，核心运行6.410秒。

S001的15箱154kg，2架次C（76与78kg）；能耗5.91335157030303kWh，作业3186.33815465810s；201模式、324状态；三阶段MILP退出均1、gap全0；8故障注入全部拒绝。原始输入哈希已核验。无P0/P1。

非阻塞建议已在全量阶段落实：test_boundaries.m覆盖能量绑定二分、空载不可达、空模式集、真实超载分组；DEM格点扰动为1e-8像元浮点容差，其意义为保守纳入邻接闭像元而不是符号计算。
