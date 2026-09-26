function plot_q2_99_review(root)
if nargin<1,root=fileparts(fileparts(mfilename('fullpath')));end
addpath(fullfile(root,'utils'));
out=fullfile(root,'results','q2_99_review');figdir=fullfile(out,'figures');if ~isfolder(figdir),mkdir(figdir);end
D=load_q2_data(root);x=load(fullfile(out,'final_best_pass.mat'),'best');S=x.best;
T=readtable(fullfile(out,'sorties_23.csv'),'TextType','string');B=readtable(fullfile(out,'boxes_80.csv'),'TextType','string');
A=readtable(fullfile(out,'algorithm_comparison.csv'),'TextType','string');
blue=[0 .4471 .698];orange=[.902 .624 0];green=[0 .620 .451];red=[.835 .369 0];gray=[.76 .79 .81];

f=mk(8.0,5.0);hold on;
uav=D.uavInventory.id;
for i=1:height(T)
 y=find(uav==T.uav_id(i));
 rect(T.takeoff_min(i),T.return_min(i),y-.17,y+.17,blue);
 rect(T.prep_start_min(i),T.prep_end_s(i)/60,y+.20,y+.32,orange);
 rect(T.load_start_min(i),T.load_end_s(i)/60,y-.33,y-.21,green);
end
yticks(1:8);yticklabels(uav);ylim([.4 8.6]);xlim([0 105]);
xlabel('任务时刻 (min)');ylabel('实体无人机');title('无人机作业时序');
legend([patch(nan,nan,blue),patch(nan,nan,orange),patch(nan,nan,green)], ...
 {'飞行与交付','固定准备','装载'},'Location','northoutside','Orientation','horizontal');
finish(f,'uav_prep_load_flight');

f=mk(8.0,6.2);hold on;
BT=readtable(fullfile(out,'battery_timeline.csv'),'TextType','string');ids=unique(BT.battery_id,'stable');
for i=1:height(BT)
 if strlength(BT.sortie_id(i))==0,continue;end
 y=find(ids==BT.battery_id(i));
 rect(BT.takeoff_min(i),BT.return_min(i),y-.28,y+.28,blue);
 rect(BT.return_min(i),BT.recharged_min(i),y-.28,y+.28,gray);
end
yticks(1:numel(ids));yticklabels(ids);ylim([.4 numel(ids)+.6]);xlim([0 max(110,max(BT.recharged_min(isfinite(BT.recharged_min)))+3)]);
xlabel('任务时刻 (min)');ylabel('共享电池');title('电池占用与充电');
legend([patch(nan,nan,blue),patch(nan,nan,gray)],{'任务占用','返航后充电'},'Location','northoutside','Orientation','horizontal');
finish(f,'battery_flight_charge');

f=mk(8.0,5.1);hold on;
colors=[blue;orange;green];
for i=1:numel(S.routes)
 r=S.routes(i);seq=[1 r.nodeOrder(:)' 1];
 for j=1:numel(seq)-1
  plot(D.nodes.lon(seq(j:j+1)),D.nodes.lat(seq(j:j+1)),'Color',colors(r.typeIdx,:),'LineWidth',.75);
 end
end
scatter(D.nodes.lon(2:end),D.nodes.lat(2:end),22,[.1 .1 .1],'filled');
scatter(D.nodes.lon(1),D.nodes.lat(1),65,red,'p','filled');
for i=1:height(D.nodes),text(D.nodes.lon(i)+.00035,D.nodes.lat(i)+.00025,D.nodes.id(i),'FontSize',6.5,'Interpreter','none');end
xlabel('经度 (°E)');ylabel('纬度 (°N)');title('23 架次实际路线');
legend([plot(nan,nan,'Color',blue),plot(nan,nan,'Color',orange),plot(nan,nan,'Color',green)], ...
 {'A 型','B 型','C 型'},'Location','northoutside','Orientation','horizontal');
axis tight;finish(f,'routes_geographic');

f=mk(8.0,4.7);v=sort(B.expected_margin_min);bar(1:height(B),v,'FaceColor',green,'EdgeColor','none');
xlim([.5 80.5]);ylim([0 max(v)*1.08]);xlabel('货箱（按时限裕度排序）');ylabel('期望时限裕度 (min)');title('80 箱交付裕度');
finish(f,'box_deadline_margins');

f=mk(8.0,4.4);hold on;
for i=1:height(A)
 scatter(A.sorties(i),A.Cmax_min(i),100,A.energy_kWh(i),'filled','MarkerEdgeColor','k');
 text(A.sorties(i)+.10,A.Cmax_min(i)+.15,sprintf('%s\n%.2f kWh',A.method(i),A.energy_kWh(i)), ...
  'FontSize',7,'Interpreter','none');
end
xlim([21.5 24.5]);ylim([98 103]);xticks(22:23);xlabel('架次数');ylabel('最晚返航 (min)');title('已验证方案对比');
finish(f,'algorithm_comparison');

f=mk(8.0,4.8);hold on;
bar(1:height(T),T.energy_kWh,'FaceColor',blue,'EdgeColor','none');
scatter(1:height(T),T.reserve_margin_kWh,24,red,'filled');
xlim([.5 height(T)+.5]);ylim([0 max([T.energy_kWh;T.reserve_margin_kWh])*1.12]);
xticks(1:height(T));xticklabels(T.sortie_id);xtickangle(45);
xlabel('架次');ylabel('能量 (kWh)');title('单架次能耗与余量');
legend({'实际能耗','安全余量'},'Location','northoutside','Orientation','horizontal');
finish(f,'sortie_energy_reserve');

f=mk(7.5,4.5);area=readtable(fullfile(out,'area_summary.csv'),'TextType','string');
bar(1:height(area),area.boxes,'FaceColor',blue,'EdgeColor','none');
xticks(1:height(area));xticklabels(area.area);xtickangle(45);ylabel('货箱数');xlabel('服务区');title('15 区原始需求');
finish(f,'area_demand');

f=mk(7.5,4.5);histogram(D.boxes.mass,'BinMethod','integers','FaceColor',blue,'EdgeColor','none');
xlabel('货箱质量 (kg)');ylabel('货箱数');title('原始货箱质量分布');finish(f,'box_mass_distribution');

f=mk(7.5,4.5);nstop=T.service_area_count;histogram(nstop,'BinMethod','integers','FaceColor',orange,'EdgeColor','none');
xticks(unique(nstop));xlabel('单架次服务区数');ylabel('架次数');title('路线组合结构');finish(f,'route_stops_distribution');
fprintf('Q2_99_FIGURES PASS count=9\n');
 function fig=mk(w,h)
  fig=figure('Visible','off','Color','white');apply_publication_style(fig,'zh','double');fig.Position(3:4)=[w h];
 end
 function rect(a,b,c,d,col)
  if b>a,patch([a b b a],[c c d d],col,'EdgeColor','none');end
 end
 function finish(fig,name)
  export_publication_figure(fig,fullfile(figdir,name),300,true,true);close(fig);
 end
end
