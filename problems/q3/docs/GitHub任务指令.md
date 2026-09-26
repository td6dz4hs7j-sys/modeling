# 问题三 GitHub 任务指令

目标仓库：https://github.com/td6dz4hs7j-sys/modeling

目标分支：`feature/q3-relay-overlay`；本任务范围：`problems/q3/`。

## 可直接交给后续开发任务的指令

请先阅读 problems/q3/README.md、模型口径.md、六项检查与修正.md 和原题第三问及通信/飞行附件。按题目主要需求验证“第二题当前运输结构 + 并行中继覆盖调度”。第二题来源固定为随包的 Q2_综合均衡最终结果.xlsx 与 balanced_best_pass.mat；不要换用历史方案。保持 23 个运输批次、访问顺序、机型和路线，允许已有同型实体机、电池及起飞时刻重排。重力加速度取 9.806。

检查运输/中继并行，不设全体中继完成的前置条件；各阶段时间只计一次；4 个中继架次由 2 架独立中继机承担；充分利用第二题空闲窗口。显式保留第二题预准备、装载和满电充电口径。通信必须连续满足直连或单中继双链路约束，不能用少量采样声称全程可行。

先运行 verify_q3_github_bundle，再按需要执行 run_problem3。基线为 23+4 架次、80 箱按期、5933.082180813 秒、68.610741681 kWh、未覆盖 0 秒。改进必须通过完整物理、交付、库存和连续覆盖核验，更新表格、图和清单；注明最优性范围，不以参考截图反推参数或包装成全局最优。

## Git 操作

本分支建立后，后续使用者可执行：

```bash
git clone https://github.com/td6dz4hs7j-sys/modeling.git
cd modeling
git fetch origin
git switch --track origin/feature/q3-relay-overlay
# 修改及 MATLAB 验收完成后
git add problems/q3
git diff --cached --check
git commit -m "q3: update validated concurrent relay overlay"
git push origin feature/q3-relay-overlay
```

若本地已有此分支，使用 `git switch feature/q3-relay-overlay`。不要强制推送或提交原题 input、缓存、凭据及其他题目的改动。
