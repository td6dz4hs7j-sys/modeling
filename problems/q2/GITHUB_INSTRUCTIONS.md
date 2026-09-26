# GitHub / Codex 分支任务指令

## 可粘贴给 GitHub Codex 的指令

请在当前仓库建立分支 `feature/q2-drone-scheduling`，将提供的 `github_delivery/q2` 导入仓库 `problems/q2/`。按该目录 README 中题目二两项主要需求组织结果，保留四份冻结的严格 PASS 排程及算法和加权目标表。保留 80 箱全部按期的强化约束与提前固定准备的扩展假设，不将有界随机搜索称为精确动态规划或全局最优。若具备 MATLAB 和原附件，运行 `verify_q2_github_bundle` 重新核验；否则注明只核对文件与存档校验，不能声称新运行 MATLAB。只提交 `problems/q2/`，不提交原题附件、不修改问题一/三/四。提交完成后创建草稿 PR，描述模型、两项题面需求映射、各权重真实结果、可复现命令及时间口径。

## 本地 PowerShell 命令

用本包旁的 `import_q2_branch.ps1` 导入现有本地 clone：

```powershell
& 'D:\Desktop\modeling\github_delivery\import_q2_branch.ps1' -RepositoryPath 'D:\path\to\your-cloned-repository'
```

脚本要求工作区干净并且目标 `problems/q2` 尚不存在；建立新分支并只复制/暂存问题二文件，供审阅。检查后执行：

```powershell
git -C 'D:\path\to\your-cloned-repository' diff --cached --stat
git -C 'D:\path\to\your-cloned-repository' commit -m 'Add Q2 drone scheduling model and verified strategy results'
git -C 'D:\path\to\your-cloned-repository' push -u origin feature/q2-drone-scheduling
```

推送后在 GitHub 创建 PR。未提供仓库地址前，这份包没有建立远程分支或推送。
