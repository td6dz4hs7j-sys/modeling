function finalize_q1_report(G,Q,out)
% Regenerate comparison sheets and model notes from this run, never literals.
K=physical_constants();
book=fullfile(out,'Q1_结果提交.xlsx');
writetable(Q,book,'Sheet','Q1_方案对比');
notes={'项目','说明';'重力加速度',sprintf('g=%.3f m/s^2，与问题二三统一',K.g);...
 '算法','可行模式枚举 + 精确计数状态动态规划；intlinprog交叉验证';...
 '主方案','词典序：架次数 → 能耗 → 累计作业时间';...
 '三目标加权','J=wN*N/N0+wE*E/E0+wT*T/T0，权重和为1';...
 '主方案结果',sprintf('%d架次，%.12f kWh，%.12f h',G.total_sorties,G.total_energy_kWh,G.total_operation_time_h);...
 '时间口径','模板往返时间列沿用完整架次作业时间；CSV另保留flight_time_s纯飞行时间';...
 '最优性范围','固定物理解释、枚举模式及数值容差下的所选目标；不代表所有偏好唯一最优'};
writecell(notes,book,'Sheet','Q1_模型说明');
copyfile(book,fullfile(out,'D题_问题一_结果提交.xlsx'),'f');
f=fopen(fullfile(out,'weighted_joint_tradeoff.md'),'w','n','UTF-8');c=onCleanup(@()fclose(f));
fprintf(f,'# 问题一方案对比（本次运行自动生成）\n\ng=%.3f m/s²。三目标加权 J=wN*N/N0+wE*E/E0+wT*T/T0，三个权重均参与，尺度来自单目标独立最优值。\n\n',K.g);
fprintf(f,'|方案|架次|能耗/kWh|累计作业时间/h|\n|---|---:|---:|---:|\n');
for j=1:height(Q),fprintf(f,'|%s|%d|%.12f|%.12f|\n',char(Q.objective(j)),Q.total_sorties(j),Q.total_energy_kWh(j),Q.total_operation_time_h(j));end
e=find(strcmp(Q.objective,'E-N-T'),1);
fprintf(f,'\n能耗优先相比主方案多 %d 架，节省 %.12f kWh，累计时间增加 %.6f min。累计作业时间不是多机调度完工时间。\n',Q.total_sorties(e)-G.total_sorties,G.total_energy_kWh-Q.total_energy_kWh(e),60*(Q.total_operation_time_h(e)-G.total_operation_time_h));
end
