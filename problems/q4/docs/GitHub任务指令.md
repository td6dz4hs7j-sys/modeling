# 问题四 GitHub 任务指令

仓库：https://github.com/td6dz4hs7j-sys/modeling

分支：`feature/q4-resource-partition`。修改范围：`problems/q4/`。

## 可交给后续开发任务的指令

请先阅读problems/q4/README.md、results/q4_final/问题四_最终结果与方法.md、results/q3_overlay/模型口径.md和原题第四问。使用本包冻结的问题三联合调度输入，保持货箱组批、机型、服务区访问顺序、运输与中继任务时刻及通信保障关系；共访服务区不得拆组。将15区分成2组和3组，各区唯一归属、组非空、四类资源不得跨组调配。

沿用组内同型实体重新指派口径。以时间DAG最大匹配求最低实体配置，检查预准备、返航后装载、充满复用、中继周转；跨组中继任务须整段复制。库存固定为运输机A/B/C=4/2/2、电池=6/4/4、中继机2、组件6。

主目标按库存缺口→总配置件数→工作量CV排序，不人为施加CV≤0.25。正式基线为两组9/15/2/3、29件配置、缺口2；三组9/15/4/6、34件配置、缺口4。两个方案同时达到缺口和总件数各自的全局最少。不要将历史截图优先方案10/15/4/5填入主表。

先运行python verify_bundle.py检查发布快照，再按需运行python run_problem4.py完整复现。原模板Q4_分区配置必须2+3共5行且列结构不变；保留原有其他表，补充资源规模、冗余、工作量、库存缺口及原因。两个方案分别检查15区、23运输任务、80箱、296通信区间，无跨组实体混用。求解独立遍历127/966种分区；独立验证255个非空子集的匹配下界，并与全候选一致。

任何更改应更新工作簿、CSV、报告、独立证书和manifest。区别原库存可执行与补齐设备后可执行；公开工作量不均衡和中继复制代价。不得将固定Q3内全局最优扩大为Q3全局最优、采购成本最优或所有指标同时最优。如需更改Q3，应另立明确方案并先通过Q3物理与连续通信验证，再重做Q4证书。

## Git操作

```bash
git clone https://github.com/td6dz4hs7j-sys/modeling.git
cd modeling
git fetch origin
git switch --track origin/feature/q4-resource-partition
cd problems/q4
python -m pip install -r requirements.txt
python verify_bundle.py
# 需要重新计算时：python run_problem4.py
cd ../..
git add problems/q4
git diff --cached --check
git commit -m "q4: update verified resource-optimal partition results"
git push origin feature/q4-resource-partition
```

本地已有分支时使用`git switch feature/q4-resource-partition`。只提交问题四范围内文件；不要强推、合并其他题目或提交原题附件、凭据及缓存。
