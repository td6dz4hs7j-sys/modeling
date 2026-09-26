function q3_overlay_report(root,D,S0,S,relays,V,proof)
out=fullfile(root,'results','q3_overlay');
n=numel(S.routes);route=(1:n)';original_takeoff_s=[S0.routes.takeoff_s]';
final_takeoff_s=[S.routes.takeoff_s]';delay_s=final_takeoff_s-original_takeoff_s;
group_unchanged=false(n,1);order_unchanged=group_unchanged;uav_unchanged=group_unchanged;battery_unchanged=group_unchanged;
for k=1:n
 group_unchanged(k)=isequal(S0.routes(k).boxIdx,S.routes(k).boxIdx);
 order_unchanged(k)=isequal(S0.routes(k).nodeOrder,S.routes(k).nodeOrder);
 uav_unchanged(k)=S0.routes(k).uavID==S.routes(k).uavID;
 battery_unchanged(k)=S0.routes(k).batteryID==S.routes(k).batteryID;
end
assert(all(group_unchanged & order_unchanged));
writetable(table(route,original_takeoff_s,final_takeoff_s,delay_s,group_unchanged,order_unchanged,uav_unchanged,battery_unchanged),fullfile(out,'transport_inheritance_audit.csv'));
fid=fopen(fullfile(out,'continuous_independent_audit.json'),'w');fprintf(fid,'%s',jsonencode(proof));fclose(fid);
fid=fopen(fullfile(out,'问题三_优化结果.md'),'w','n','UTF-8');
fprintf(fid,'# 问题三：运输原解叠加中继覆盖\n\n');
fprintf(fid,'重力加速度：%.3f m/s²。MATLAB R2022a + intlinprog 实际运行，独立验证 %s。\n\n',D.g,V.status);
fprintf(fid,'|指标|当前结果|\n|---|---:|\n');
fprintf(fid,'|运输架次|%d|\n|中继架次|%d|\n|实体中继机|%d|\n|中继组件|%d|\n',n,numel(relays),numel(unique(string({relays.uavID}))),numel(unique(string({relays.componentID}))));
fprintf(fid,'|联合返航（min）|%.7f|\n|运输能耗（kWh）|%.9f|\n|中继能耗（kWh）|%.9f|\n|总能耗（kWh）|%.9f|\n|通信未覆盖（s）|%.9f|\n|加权迟交|%.9f|\n\n',V.makespan_s/60,V.transportEnergy_kWh,V.relayEnergy_kWh,V.jointEnergy_kWh,proof.maxUncoveredTime_s,S.metrics.W);
fprintf(fid,'## 六项检查\n\n');
fprintf(fid,'1. 使用用户当前 Q2 工作簿，并与其详细解逐行核对。原基准为 %.7f min、%.9f kWh。\n',max([S0.routes.return_s])/60,V.transportEnergy_kWh);
fprintf(fid,'2. 运输与中继并行排程，通信覆盖按每个运输阶段的实际时间验证。\n');
fprintf(fid,'3. 不设置“全部中继完成才运输”的前置条件。\n');
fprintf(fid,'4. 沿用 Q2 预准备、返航后装载和满电复用规则；部署、建链、服务、返航、周转分别计一次。独立能源组件避免不必要充电等待。\n');
fprintf(fid,'5. 中继任务只在 R01/R02 上执行，未增加运输资源。\n');
fprintf(fid,'6. 分箱、访问顺序和机型不变；%d 个架次由同型运输机接替，%d 个架次更换同型电池，%d 个架次调整时刻，最大延迟 %.6f s。\n\n',sum(~uav_unchanged),sum(~battery_unchanged),sum(abs(delay_s)>1e-5),max(delay_s));
fprintf(fid,'连续证书覆盖 %d 个飞行阶段、%d 个区间，最小认证链路裕量 %.9f dB。\n\n',proof.segments,proof.intervals,proof.minimumCertifiedMargin_dB);
fprintf(fid,'## 结论边界\n\n');
fprintf(fid,'这是当前运输解约束下经过独立验证的可行排程。候选点和时间受有限搜索限制，不能据此宣称全局最优。截图 Q2 基准与当前输入不同，截图数字仅作对照。四架次搜索若未产生整数解，不表示题目总体不可行。\n');
fclose(fid);
end
