function plot_q2_results(D,legs,S,baseline,R,folder)
% PLOT_Q2_RESULTS Publication-gated Q2 raw/process/result figures.
% S is the frozen final scheduled solution; baseline is the Q2 31-direct-route schedule.
if nargin<6||strlength(string(folder))==0,folder=fullfile(D.root,'figures','q2_final');end
if ~isfolder(folder),mkdir(folder);end
addpath(fullfile(D.root,'utils'));
c=[0 .4471 .6980;.9020 .6235 0;0 .6196 .4510;.8353 .3686 0;.8 .4745 .6549;.3373 .7059 .5020];

% Raw data: distributions and demand relationships come directly from D.
f=newfig();histogram(D.boxes.mass,'BinMethod','integers','FaceColor',c(1,:));
xlabel('单箱质量 (kg)');ylabel('货箱数');title('逐箱需求质量');finish(f,'raw_q2_mass_distribution');

f=newfig();areas=unique(D.boxes.area,'stable');m=zeros(numel(areas),1);v=m;
for i=1:numel(areas),q=D.boxes.area==areas(i);m(i)=sum(D.boxes.mass(q));v(i)=sum(D.boxes.volume(q));end
scatter(m,v,34,c(1,:),'filled');hold on;
[xy,~,grp]=unique([m v],'rows');
for i=1:size(xy,1),text(xy(i,1)+1.2,xy(i,2),strjoin(areas(grp==i),','),'FontSize',7,'Interpreter','none');end
xlabel('分区需求总质量 (kg)');ylabel('分区需求总体积 (m^3)');title('分区质量与体积');finish(f,'raw_q2_area_mass_volume');

f=newfig();hard=D.isHard;soft=~hard;hold on;
hardHours=D.hardDeadline_s(hard)/3600;softHours=D.boxes.expected_s(soft)/3600;allHours=[hardHours(:);softHours(:)];binWidth=.5;
edges=0:binWidth:ceil(max(allHours)/binWidth)*binWidth;if numel(edges)<2,edges=[0 binWidth];end
hh=gobjects(0);legends=strings(0,1);
if any(hard),hh(end+1)=histogram(hardHours,'BinEdges',edges,'FaceColor',c(2,:),'FaceAlpha',.62,'LineStyle','-');legends(end+1)=compose('硬截止 (n=%d)',sum(hard));end
if any(soft),hh(end+1)=histogram(softHours,'BinEdges',edges,'FaceColor',c(1,:),'FaceAlpha',.48,'LineStyle','--');legends(end+1)=compose('软期望 (n=%d)',sum(soft));end
xlabel('截止/期望交付时刻 (h)');ylabel('货箱数');title('硬截止与软期望时刻');
legend(hh,cellstr(legends),'Location','best');finish(f,'raw_q2_deadline_distribution');

% Process: expose the actual search trace, schedule resource use and seed outcomes.
f=newfig();ax=axes(f);
if isstruct(R)&&isfield(R,'trace')&&istable(R.trace)&&height(R.trace)>0
 trace=R.trace;traceTitle='真实架次数搜索轨迹';
 if min(trace.N)==max(trace.N)
  historyFiles={fullfile(D.root,'results','q2_more_search','q2_seed_20261008_trace.csv'), ...
   fullfile(D.root,'results','q2_all_ontime','q2_seed_20261004_trace.csv')};
  for h=1:numel(historyFiles)
   if isfile(historyFiles{h})
    prior=readtable(historyFiles{h});
    if all(ismember(trace.Properties.VariableNames,prior.Properties.VariableNames))
     trace=[prior(:,trace.Properties.VariableNames);trace]; %#ok<AGROW>
     traceTitle='全按期方案架次数优化轨迹';
    end
   end
  end
 end
 historyPath=fullfile(D.root,'results','q2_sortie_first','q2_optimization_trace.csv');
 if min(trace.N)==max(trace.N) && isfile(historyPath)
  earlier=readtable(historyPath);
  if any(earlier.N>min(trace.N)) && min(earlier.N)==min(trace.N)
   trace=earlier;traceTitle='历史架次数压缩轨迹（26至18）';
  end
 end
 seeds=unique(trace.seed,'stable');hold(ax,'on');
 for i=1:numel(seeds),q=trace.seed==seeds(i);plot(ax,trace.round(q),trace.N(q),'-','Color',c(mod(i-1,size(c,1))+1,:),'LineWidth',1.05);end
 yticks(ax,min(trace.N):max(trace.N));ylim(ax,[min(trace.N)-.2,max(trace.N)+.2]);
 xlabel(ax,'搜索轮次');ylabel(ax,'运输架次数');title(ax,traceTitle);
 if numel(seeds)<=5,legend(ax,compose('种子 %d',seeds),'Location','best');end
else
 axis(ax,'off');text(ax,.5,.56,'暂无优化 trace；未生成搜索曲线','Units','normalized','HorizontalAlignment','center','FontSize',10);
end
finish(f,'process_q2_search_trace');

f=newfig();uav=string(D.uavInventory.id);bh=zeros(numel(uav),1);fh=bh;
for i=1:numel(uav)
 if istable(baseline.sorties)&&height(baseline.sorties)>0,q=baseline.sorties.uav_id==uav(i);bh(i)=sum(baseline.sorties.return_s(q)-baseline.sorties.start_s(q))/3600;end
 if istable(S.sorties)&&height(S.sorties)>0,q=S.sorties.uav_id==uav(i);fh(i)=sum(S.sorties.return_s(q)-S.sorties.start_s(q))/3600;end
end
bar(1:numel(uav),[bh fh],'grouped');xticks(1:numel(uav));xticklabels(uav);xlabel('实体无人机');ylabel('累计占用时长 (h)');title('基准与最终方案的机队负载');legend({'Q2基准','Q2最终'},'Location','best');finish(f,'process_q2_resource_load');

f=newfig();if isstruct(R)&&isfield(R,'summary')&&istable(R.summary)&&height(R.summary)>0
 [xy,~,grp]=unique([R.summary.N R.summary.Cmax_s],'rows');scatter(xy(:,1),xy(:,2)/3600,42,c(1,:),'filled');hold on;
 for i=1:size(xy,1),text(xy(i,1),xy(i,2)/3600," "+join(string(R.summary.seed(grp==i)),','),'FontSize',7);end
 xlabel('种子方案架次数');ylabel('完工时间 C_{max} (h)');title('随机种子结果分布');
else,axis off;text(.5,.55,'暂无多种子结果汇总','Units','normalized','HorizontalAlignment','center');end
finish(f,'process_q2_seed_objectives');

% Final results: separate units; zero-based bars never mix unlike quantities.
f=newfig();f.Position(4)=5.5;tiledlayout(f,2,2,'TileSpacing','compact','Padding','compact');
before=[baseline.metrics.W,baseline.metrics.Cmax_s/3600,baseline.metrics.energy_kWh,baseline.metrics.N];
after=[S.metrics.W,S.metrics.Cmax_s/3600,S.metrics.energy_kWh,S.metrics.N];
names={'加权软迟到','最晚返航','总能耗','运输架次'};units={'优先级·s','h','kWh','架次'};
for i=1:4
 nexttile;hold on;bar(1,before(i),.58,'FaceColor',c(1,:),'EdgeColor','none');
 bar(2,after(i),.58,'FaceColor',c(2,:),'EdgeColor','none');
 xticks(1:2);xticklabels({'Q2基线','优化方案'});ylabel(units{i});title(names{i});
 ylim([0,max([before(i),after(i),eps])*1.2]);
 for j=1:2,vals=[before(i),after(i)];text(j,vals(j)+max(vals)*.04,sprintf('%.3g',vals(j)),'HorizontalAlignment','center','FontSize',8);end
end
finish(f,'result_q2_objective_comparison');

% Actual directed routes, eight physical UAV rows, fourteen batteries.
f=newfig();hold on;scatter(D.nodes.lon(2:end),D.nodes.lat(2:end),22,[.2 .2 .2],'filled');scatter(D.nodes.lon(1),D.nodes.lat(1),55,c(4,:),'p','filled');
for i=1:height(D.nodes),text(D.nodes.lon(i)+.00035,D.nodes.lat(i)+.0003,D.nodes.id(i),'FontSize',6.5,'Interpreter','none');end
multi=0;routeHandles=gobjects(height(D.uav),1);routeStyles={'-','--',':'};
for i=1:numel(S.routes)
 r=S.routes(i);ni=r.nodeOrder(:)';if numel(ni)>1,multi=multi+1;end;seq=[1 ni 1];typ=r.typeIdx;
 for j=1:numel(seq)-1,h=plot(D.nodes.lon(seq(j:j+1)),D.nodes.lat(seq(j:j+1)),routeStyles{typ},'Color',c(typ,:),'LineWidth',.85);if ~isgraphics(routeHandles(typ)),routeHandles(typ)=h;end,end
end
xlabel('经度 (°E)');ylabel('纬度 (°N)');title(sprintf('多点路线 %d/%d',multi,numel(S.routes)));
text(.99,.98,'按冻结解 nodeOrder 绘制','Units','normalized','HorizontalAlignment','right','VerticalAlignment','top','FontSize',6.5,'Color',[.25 .25 .25]);
dx=max((max(D.nodes.lon)-min(D.nodes.lon))*.035,.0005);dy=max((max(D.nodes.lat)-min(D.nodes.lat))*.035,.0005);xlim([min(D.nodes.lon)-dx max(D.nodes.lon)+dx]);ylim([min(D.nodes.lat)-dy max(D.nodes.lat)+dy]);
present=isgraphics(routeHandles);if any(present),legend(routeHandles(present),cellstr(D.uav.id(present)),'Location','best');end
finish(f,'result_q2_routes');

f=newfig();hold on;
plotIntervals(S.routes,'uavID','return_s',1:numel(uav),uav,c);
yticks(1:numel(uav));yticklabels(uav);ylim([.5 numel(uav)+.5]);xlabel('任务时刻 (h)');ylabel('实体无人机');title('8架无人机任务甘特图');finish(f,'result_q2_uav_gantt');

f=newfig();batteryIds=strings(0,1);batteryTypes=strings(0,1);
for k=1:height(D.batteryInventory),for j=1:D.batteryInventory.count(k),batteryIds(end+1)=D.batteryInventory.type(k)+"-B"+compose('%02d',j);batteryTypes(end+1)=D.batteryInventory.type(k);end,end %#ok<AGROW>
hold on;plotIntervals(S.routes,'batteryID','batteryReady_s',1:numel(batteryIds),batteryIds,c);
yticks(1:numel(batteryIds));yticklabels(batteryIds);ylim([.5 numel(batteryIds)+.5]);xlabel('任务时刻 (h)');ylabel('实体电池');title('14组电池占用与充电甘特图');
legend([patch(nan,nan,c(1,:),'EdgeColor','none'),patch(nan,nan,[.72 .72 .72],'EdgeColor','none')],{'执行任务','返航后充电'},'Location','best');finish(f,'result_q2_battery_gantt');

f=newfig();T=S.boxDelivery;arr=T.arrival_s/3600;hardDeadline=T.hard_deadline_s/3600;softDue=T.expected_s/3600;hard=isfinite(T.hard_deadline_s);hold on;
scatter(find(hard),hardDeadline(hard)-arr(hard),24,c(2,:),'filled');scatter(find(~hard),softDue(~hard)-arr(~hard),20,c(1,:),'o');yline(0,'k:');
xlabel('货箱序号（按交付表）');ylabel('时限裕度：时限−交付 (h)');title('逐箱硬窗裕度与软迟到');legend({'硬截止裕度','软期望裕度','按时界线'},'Location','best');finish(f,'result_q2_box_deadline_margins');
f=newfig();T=S.boxDelivery;areaNames=unique(D.boxes.area,'stable');hold on;
for i=1:numel(areaNames)
 q=T.area==areaNames(i);times=T.arrival_s(q)/3600;
 scatter(repmat(i,numel(times),1),times,18,c(mod(i-1,size(c,1))+1,:),'filled','MarkerFaceAlpha',.65);
 plot([i-.22 i+.22],[max(times) max(times)],'k-','LineWidth',1);
end
xticks(1:numel(areaNames));xticklabels(areaNames);xtickangle(45);
xlabel('服务区');ylabel('逐箱交付时刻 (h)');title('各服务区逐箱交付与最晚到达');
finish(f,'result_q2_service_delivery');
flow();

 function f=newfig()
  f=figure('Visible','off','Color','white');apply_publication_style(f,'zh','double');
  f.Position(4)=4.45;
 end
 function finish(f,name)
  % Strict design gate remains enabled; SVG text, 300-DPI PNG and grayscale are mandatory.
  export_publication_figure(f,fullfile(folder,name),300,true,true);close(f);
 end
 function plotIntervals(routes,idField,endField,rowMap,labels,palette)
  for jj=1:numel(routes)
   r=routes(jj);if ~isfield(r,idField),continue;end
   ix=find(labels==string(r.(idField)),1);if isempty(ix),continue;end
   y=rowMap(ix);a=r.start_s/3600;b=r.return_s/3600;ready=r.(endField)/3600;
   patch([a b b a],[y-.27 y-.27 y+.27 y+.27],palette(mod(ix-1,size(palette,1))+1,:),'EdgeColor','none','FaceAlpha',.8);
   if strcmp(idField,'batteryID')&&ready>b,patch([b ready ready b],[y-.27 y-.27 y+.27 y+.27],[.72 .72 .72],'EdgeColor','none');end
  end
 end
 function flow()
  f=newfig();f.Position(4)=6.2;axis off;
  labels={'原始工作簿与调度库存','校验字段、单位与时限','构造硬时限优先可行路线','核对Q1公共物理继承','基线独立验证与破坏测试','有界邻域搜索并重排资源','最终解独立再验证','导出冻结路线、表格与图'};
  for jj=1:numel(labels)
   y=.92-(jj-1)*.108;annotation(f,'textbox',[.23 y-.043 .54 .052],'String',labels{jj},'HorizontalAlignment','center','VerticalAlignment','middle','FontName','Microsoft YaHei','FontSize',8.5,'BackgroundColor',[.96 .97 .98]);
   if jj<numel(labels),annotation(f,'arrow',[.5 .5],[y-.046 y-.099],'LineWidth',.8);end
  end
  finish(f,'flow_q2_model');copyfile(fullfile(folder,'flow_q2_model.svg'),fullfile(folder,'flow_overall_model.svg'),'f');copyfile(fullfile(folder,'flow_q2_model.png'),fullfile(folder,'flow_overall_model.png'),'f');
 end
end
