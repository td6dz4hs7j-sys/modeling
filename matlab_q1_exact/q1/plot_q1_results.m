function plot_q1_results(D,dem,P,L,T,U,proof,Q,R,RL)
% Native MATLAB graphics only; each panel is a deterministic calculation.
if isfield(D,'output_root'),folder=fullfile(D.output_root,'figures');else,folder=fullfile(D.root,'figures');end
if ~isfolder(folder),mkdir(folder);end
palette=[0 .447 .698;.902 .6235 0;0 .62 .451];markers={'o','s','^'};
ids=string({P.area});short=erase(ids,'S0');
f=newfig();ax=axes(f);
% Vector contours: no embedded raster in the SVG. Crop for readable nodes.
ix=find(dem.longitude>109.15 & dem.longitude<109.30);iy=find(dem.latitude>22.995 & dem.latitude<23.09);
contourf(ax,dem.longitude(ix),dem.latitude(iy),double(dem.dem(iy,ix)),18,'LineColor','none');colormap(ax,gray(64));cb=colorbar;cb.Label.String='地面高程 (m)';hold on;
for i=1:15,plot(D.nodes.lon([1 i+1]),D.nodes.lat([1 i+1]),'-','Color',[.15 .45 .65],'LineWidth',.65);end
scatter(D.nodes.lon(2:end),D.nodes.lat(2:end),22,'w','filled','MarkerEdgeColor','k');scatter(D.nodes.lon(1),D.nodes.lat(1),60,'p','filled','MarkerFaceColor',[.85 .25 .05]);
for i=1:16,text(D.nodes.lon(i)+.0008,D.nodes.lat(i)+.0006,D.nodes.id(i),'FontSize',7,'Color','k','BackgroundColor','w','Margin',.2);end
xlabel('经度 (°E)');ylabel('纬度 (°N)');daspect([1/cosd(23) 1 1]);finish(f,'raw_q1_map');
f=newfig();histogram(D.boxes.mass,'BinEdges',[0 4 7 10 16],'FaceColor',palette(1,:));xlabel('单箱质量 (kg)');ylabel('货箱数');xticks([3 6 8 14]);finish(f,'raw_q1_box_distribution');
f=newfig();mass=zeros(15,1);vol=mass;
for i=1:15,b=D.boxes(D.boxes.area==ids(i),:);mass(i)=sum(b.mass);vol(i)=sum(b.volume);end
scatter(mass,vol,32,palette(1,:),'filled');xlabel('分区需求总质量 (kg)');ylabel('分区需求总体积 (m³)');
% Aggregate coincident demands into one readable annotation.
[xy,~,grp]=unique([mass vol],'rows');for j=1:size(xy,1),text(xy(j,1)+2,xy(j,2),strjoin(short(grp==j),','),'FontSize',7);end
xlim([0 max(mass)*1.18]);ylim([0 max(vol)*1.12]);finish(f,'raw_q1_demand');
[~,far]=max([P.distance]);[~,high]=max([P.terrainMax]);
f=newfig();f.Position(4)=5.5;tiledlayout(2,1,'TileSpacing','compact','Padding','compact');
for i=[1 high]
 nexttile;p=P(i);plot(p.profileFraction*p.distance/1000,p.profileZ,'Color',[.3 .3 .3]);hold on;
 plot([0 p.distance/1000],[p.cruise p.cruise],'--','Color',palette(1,:));
 plot([0 0 p.distance/1000 p.distance/1000],[D.nodes.z(1) p.cruise p.cruise p.nodeZ+30],'-','Color',palette(2,:));
 xlabel('距 O01 的水平距离 (km)');ylabel('海拔 (m)');title(p.area);ylim([0 p.cruise*1.12]);
end
legend('DEM剖面','巡航海拔','去程飞行剖面','Location','southoutside','Orientation','horizontal');finish(f,'process_q1_profiles');
f=newfig();hold on;h=gobjects(3,1);
for k=1:3,u=D.uav(k,:);q=linspace(0,u.payload,201);e=flight_energy_model(u,P(far),q,D.g);h(k)=plot(q,e,'Color',palette(k,:),'LineStyle',linestyle(k));yline((1-u.reserve)*u.energy,':','Color',palette(k,:),'HandleVisibility','off');end
xlabel('去程载荷 (kg)');ylabel('往返运输能耗 (kWh)');title(P(far).area);legend(h,{'A','B','C'},'Location','northwest');finish(f,'process_q1_energy_payload');
f=newfig();scatter(proof.energy_DP_kWh-proof.energy_MILP_kWh,1:15,25,palette(1,:),'filled');xline(0,':','Color',[.4 .4 .4]);yticks(1:15);yticklabels(ids);xlabel('DP − MILP 能耗 (kWh)');ylabel('服务区');xlim([-1e-7 1e-7]);finish(f,'process_q1_certificates');
f=newfig();uniqueQ=unique([Q.total_energy_kWh Q.total_operation_time_h Q.total_sorties],'rows');
scatter(uniqueQ(:,1),uniqueQ(:,2),40,palette(1,:),'filled');hold on;plot(Q.total_energy_kWh(1),Q.total_operation_time_h(1),'p','Color',palette(2,:),'MarkerSize',10,'MarkerFaceColor',palette(2,:));
for i=1:size(uniqueQ,1),text(uniqueQ(i,1)+.05,uniqueQ(i,2)+.015,string(uniqueQ(i,3))+' 次','FontSize',7);end
xlabel('总运输能耗 (kWh)');ylabel('累计作业时间 (h)');ylim([min(uniqueQ(:,2))-.04,max(uniqueQ(:,2))+.05]);legend('已求解的不同指标组合','主方案 N-E-T','Location','best');finish(f,'process_q1_tradeoff');
f=newfig();f.Position(4)=5.5;hold on;
for k=1:3,scatter(L.max_safe_payload_kg(k:3:end),(1:15)+(k-2)*.18,28,palette(k,:),markers{k},'filled');end
yticks(1:15);yticklabels(ids);ylim([.5 15.5]);xlim([0 85]);xlabel('最大安全载荷 (kg)');ylabel('服务区');legend('A','B','C','Location','southoutside','Orientation','horizontal');finish(f,'result_q1_payload');
f=newfig();barh(1:15,U.number_of_sorties,'FaceColor',palette(1,:));yticks(1:15);yticklabels(ids);xlabel('往返架次数');ylabel('服务区');xticks(0:max(U.number_of_sorties));finish(f,'result_q1_sorties');
f=newfig();hold on;
for k=1:3,x=T.type_index==k;scatter(T.payload_utilization(x),T.volume_utilization(x),32,palette(k,:),markers{k},'filled');end
xline(1,':','HandleVisibility','off');yline(1,':','HandleVisibility','off');xlim([0 1.06]);ylim([0 1.06]);xlabel('额定质量利用率');ylabel('体积利用率');legend('A','B','C','Location','southwest');finish(f,'result_q1_utilization');
e=zeros(15,2);tm=e;
for i=1:15,x=T.service_area==ids(i);e(i,:)=[sum(T.horizontal_energy_kWh(x)),sum(T.climb_energy_kWh(x))];tm(i,:)=[sum(T.flight_time_s(x)),sum(T.operation_time_s(x)-T.flight_time_s(x))]/3600;end
f=newfig();barh(1:15,e,'stacked');yticks(1:15);yticklabels(ids);xlabel('运输能耗 (kWh)');ylabel('服务区');legend('水平巡航','爬升附加','Location','southoutside','Orientation','horizontal');finish(f,'result_q1_energy');
f=newfig();barh(1:15,tm,'stacked');yticks(1:15);yticklabels(ids);xlabel('累计作业时间 (h)');ylabel('服务区');legend('飞行','准备、装载与交接','Location','southoutside','Orientation','horizontal');finish(f,'result_q1_time');
f=newfig();f.Position(4)=5.5;tiledlayout(1,3,'TileSpacing','compact','Padding','compact');
for k=1:3
 ax=nexttile;vals=reshape(RL.max_safe_payload_kg(RL.uav_type==D.uav.id(k)),15,[]);
 % Patches preserve all heat-map cells as vectors.
 hold on;for a=1:15,for b=1:11
  xx=([b-1 b b b-1]-.5)/20;
  if isfinite(vals(a,b)),patch(xx,[a-.5 a-.5 a+.5 a+.5],vals(a,b),'EdgeColor','none');
  else,patch(xx,[a-.5 a-.5 a+.5 a+.5],[.97 .97 .97],'EdgeColor','none');plot((b-1)/20,a,'x','Color',[.5 .5 .5],'MarkerSize',3);end
 end,end
 colormap(ax,.15+.7*gray(64));caxis([0 80]);xlim([-.025 .525]);ylim([.5 15.5]);yticks(1:15);yticklabels(ids);xlabel('返航安全余量');title(D.uav.id(k));
end
cb=colorbar;cb.Label.String='最大安全载荷 (kg)';finish(f,'result_q1_reserve_payload');
f=newfig();f.Position(4)=7;tiledlayout(3,1,'TileSpacing','compact','Padding','compact');
vals={R.total_sorties,R.total_energy_kWh,R.total_operation_time_h};labs={'总架次数','总能耗 (kWh)','累计作业时间 (h)'};
for j=1:3,nexttile;plot(R.reserve_fraction,vals{j},'-o','Color',palette(1,:));xline(.2,'--','基准','LabelVerticalAlignment','bottom');xlabel('返航安全余量');ylabel(labs{j});xlim([0 .5]);end
finish(f,'result_q1_reserve_metrics');
flow();
 function f=newfig()
  f=figure('Visible','off');apply_publication_style(f,'zh','double');f.Position(3:4)=[7.2 4.5];
 end
 function finish(f,name)
  export_publication_figure(f,fullfile(folder,name),300,true,true);close(f);
 end
 function flow()
  f=newfig();f.Position(4)=7;
  labels={'Excel + DEM 输入','物理参数与像元检查','45项安全载荷边界','枚举各区可行组批','计数状态精确 DP','独立约束 + MILP 检验','余量与目标权衡重求','CSV / XLSX / 仿真图'};
  for j=1:8
   y=.92-(j-1)*.112;annotation(f,'textbox',[.25 y-.05 .5 .06],'String',labels{j},'HorizontalAlignment','center','VerticalAlignment','middle','FontName','Microsoft YaHei','FontSize',9,'BackgroundColor',[.96 .97 .98]);
   if j<8,annotation(f,'arrow',[.5 .5],[y-.05 y-.102]);end
  end
  annotation(f,'textbox',[.77 .30 .2 .09],'String',{'验证失败','停止导出并返工'},'FontName','SimSun','FontSize',8,'EdgeColor','none');
  annotation(f,'arrow',[.75 .85],[.33 .33]);
  finish(f,'flow_q1_model');
  copyfile(fullfile(folder,'flow_q1_model.svg'),fullfile(folder,'flow_overall_model.svg'));
  copyfile(fullfile(folder,'flow_q1_model.png'),fullfile(folder,'flow_overall_model.png'));
 end
end
function s=linestyle(k)
ss={'-','--','-.'};s=ss{k};
end
