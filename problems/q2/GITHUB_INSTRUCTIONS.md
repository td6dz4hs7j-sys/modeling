# 问题二分支维护指令

仓库：https://github.com/td6dz4hs7j-sys/modeling；分支：feature/q2-drone-scheduling。当前交付已推送，工作范围problems/q2。

以README和results/q2_strategy_scenarios中的四份冻结MAT及两份工作簿为准，主选综合均衡版23架次、97.705871716 min、65.869091416 kWh、80箱按期。保留预准备扩展假设和全按期强化约束，不将有界搜索称为全局最优。其他结果目录均为历史种子/诊断，对照图需标明版本。

```bash
git clone https://github.com/td6dz4hs7j-sys/modeling.git
cd modeling
git switch --track origin/feature/q2-drone-scheduling
cd problems/q2
# 按README准备原附件并完成MATLAB与文件核验
python verify_snapshot.py
cd ../..
git add problems/q2
git diff --cached --check
git commit -m "q2: update verified latest deliverables"
git push origin feature/q2-drone-scheduling
```

不强推，不提交凭据、缓存或未经验证的新候选。更新模型或排程后，应重新生成与之对应的图表、来源哈希及manifest。
