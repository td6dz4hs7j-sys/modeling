function plot_q3_final(root,D,dem,~,S,relays,V,C,T,outName)
if nargin<10,outName='q3';end
figDir=fullfile(root,'figures',outName);if ~isfolder(figDir),mkdir(figDir);end
plot_q3_dem(D,dem,figDir);
xy=D.nodes;
% 2. Terrain, complete transport routes, and actual relay hover sites.
f=figure('Visible','off','Color','w','Position',[100 100 1000 760]);
imagesc(dem.longitude,dem.latitude,double(dem.dem));set(gca,'YDir','normal');
axis equal tight;hold on;colormap(parula(256));cb=colorbar;cb.Label.String='Elevation (m)';
for p=1:numel(S.routes)
 seq=[1,S.routes(p).nodeOrder(:)',1];
 plot(xy.lon(seq),xy.lat(seq),'-','Color',[.42 .62 .88],'LineWidth',1.4);
end
plot(xy.lon(2:end),xy.lat(2:end),'o','Color',[.95 .45 .05], ...
 'MarkerFaceColor',[.95 .45 .05],'MarkerSize',4);
plot(xy.lon(1),xy.lat(1),'p','Color','w','MarkerFaceColor',[.85 .05 .12], ...
 'MarkerSize',13,'LineWidth',1.3);
P=unique(vertcat(relays.loc),'rows','stable');
for j=1:size(P,1)
 plot(P(j,1),P(j,2),'s','MarkerSize',10,'MarkerFaceColor',[.1 .9 .8], ...
  'MarkerEdgeColor','k','LineWidth',1.2);
 dy=.002;if j==3,dy=.004;elseif j==5,dy=-.004;end
 text(P(j,1)+.001,P(j,2)+dy,sprintf('S%d',j),'Color','k', ...
  'BackgroundColor','w','Margin',1,'FontWeight','bold','FontSize',8);
end
xl=[min([xy.lon;P(:,1)]),max([xy.lon;P(:,1)])];
yl=[min([xy.lat;P(:,2)]),max([xy.lat;P(:,2)])];
xlim(xl+[-.02 .02]);ylim(yl+[-.02 .02]);
xlabel('Longitude (°E)');ylabel('Latitude (°N)');
title('Final transport routes and relay hover sites');
q3_save_overlay_plot(f,figDir,'q3_routes_relays.png','result_q3_routes_relays','Routes and relays');close(f);
% 3. Certified provider for each transport sortie and time bin.
dt=10;t=(dt/2):dt:V.makespan_s;M=zeros(numel(S.routes),numel(t));
for k=1:height(C)
 if string(C.provider(k))=="G01",v=1;
 elseif string(C.provider(k))==D.relayIDs(1),v=2;else,v=3;end
 z=t>=C.t0(k)-1e-8&t<=C.t1(k)+1e-8;M(C.route(k),z)=v;
end
f=figure('Visible','off','Color','w','Position',[100 100 1200 670]);
if strcmp(outName,'q3_overlay')
 hold on;providerColors=[1 1 1;.26 .55 .9;.9 .4 .16;.35 .7 .4];
 for k=1:height(C)
  if string(C.provider(k))=="G01",v=1;elseif string(C.provider(k))==D.relayIDs(1),v=2;else,v=3;end
  rectangle('Position',[C.t0(k)/3600,C.route(k)-.5,(C.t1(k)-C.t0(k))/3600,1], ...
   'FaceColor',providerColors(v+1,:),'EdgeColor','none');
 end
 xlim([0 V.makespan_s/3600]);ylim([.5 numel(S.routes)+.5]);caxis([-.5 3.5]);
else
 imagesc(t/3600,1:numel(S.routes),M);
end
set(gca,'YDir','normal');
colormap([1 1 1;.26 .55 .9;.9 .4 .16;.35 .7 .4]);
cb=colorbar;cb.Ticks=0:3;cb.TickLabels={'Inactive','Gateway','Relay 1','Relay 2'};
xlabel('Elapsed time (h)');ylabel('Transport sortie');
title('Certified continuous communication provider');
q3_save_overlay_plot(f,figDir,'q3_communication_coverage.png','result_q3_coverage','Coverage');close(f);
% 4. Joint Gantt by physical UAV. Relay service is the dark inner bar.
f=figure('Visible','off','Color','w','Position',[100 100 1200 620]);hold on;
for p=1:numel(S.routes)
 r=S.routes(p);i=find(D.uavInventory.id==r.uavID,1);
 rectangle('Position',[r.start_s/3600,i-.35,(r.return_s-r.start_s)/3600,.7], ...
  'FaceColor',[.26 .55 .9],'EdgeColor','none');
end
for j=1:numel(relays)
 r=relays(j);i=8+find(D.relayIDs==r.uavID,1);
 rectangle('Position',[r.start_s/3600,i-.35,(r.return_s-r.start_s)/3600,.7], ...
  'FaceColor',[.95 .72 .43],'EdgeColor','none');
 rectangle('Position',[r.serviceStart_s/3600,i-.24,(r.serviceEnd_s-r.serviceStart_s)/3600,.48], ...
  'FaceColor',[.86 .3 .08],'EdgeColor','none');
end
yticks(1:10);yticklabels([cellstr(D.uavInventory.id);cellstr(D.relayIDs)]);
ylim([.3 10.7]);xlim([0 V.makespan_s/3600+.1]);grid on;
xlabel('Elapsed time (h)');ylabel('UAV');title('Transport and relay joint schedule');
if strcmp(outName,'q3_overlay')
 plot(NaN,NaN,'s','MarkerFaceColor',[.26 .55 .9],'Color',[.26 .55 .9]);
 plot(NaN,NaN,'s','MarkerFaceColor',[.95 .72 .43],'Color',[.95 .72 .43]);
 plot(NaN,NaN,'s','MarkerFaceColor',[.86 .3 .08],'Color',[.86 .3 .08]);
 legend({'Transport','Relay mission','Relay service'},'Location','southoutside','Orientation','horizontal');
end
q3_save_overlay_plot(f,figDir,'q3_joint_gantt.png','process_q3_joint_gantt','Joint schedule');close(f);
% 5. Relay service only, colored by the five hover sites.
f=figure('Visible','off','Color','w','Position',[100 100 1200 320]);hold on;
co=lines(size(P,1));
for j=1:numel(relays)
 r=relays(j);i=find(D.relayIDs==r.uavID,1);
 h=find(all(abs(P-r.loc)<1e-8,2),1);
 rectangle('Position',[r.serviceStart_s/3600,i-.33, ...
  (r.serviceEnd_s-r.serviceStart_s)/3600,.66], ...
  'FaceColor',co(h,:),'EdgeColor','k');
 label=r.name;if strcmp(outName,'q3_overlay'),label=sprintf('S%d',h);end
 text((r.serviceStart_s+r.serviceEnd_s)/7200,i,label, ...
  'HorizontalAlignment','center','FontSize',8,'Color','k');
end
yticks(1:2);yticklabels(cellstr(D.relayIDs));ylim([.4 2.6]);
xlim([0 V.makespan_s/3600+.1]);grid on;
xlabel('Elapsed time (h)');ylabel('Relay UAV');title('Relay service windows');
q3_save_overlay_plot(f,figDir,'q3_relay_service.png','process_q3_relay_service','Relay service');close(f);
% 6. Total energy decomposition.
f=figure('Visible','off','Color','w','Position',[100 100 800 450]);
b=barh(1,[V.transportEnergy_kWh,V.relayEnergy_kWh],'stacked');
b(1).FaceColor=[.26 .55 .9];b(2).FaceColor=[.9 .4 .16];
if strcmp(outName,'q3_overlay')
 b(2).FaceColor=[.55 .15 .03];b(2).EdgeColor=[.1 .1 .1];b(2).LineWidth=.5;
end
yticks(1);yticklabels({'Joint mission'});grid on;
xlabel('Energy (kWh)');title(sprintf('Total %.3f kWh',V.jointEnergy_kWh));
legend({'Transport','Relay'},'Location','southoutside','Orientation','horizontal');
if strcmp(outName,'q3_overlay')
 legend({sprintf('Transport %.3f kWh',V.transportEnergy_kWh),sprintf('Relay %.3f kWh',V.relayEnergy_kWh)}, ...
  'Location','southoutside','Orientation','horizontal');
end
text(V.jointEnergy_kWh+.2,1,sprintf('%.3f kWh',V.jointEnergy_kWh));
xlim([0 V.jointEnergy_kWh*1.15]);
q3_save_overlay_plot(f,figDir,'q3_energy.png','result_q3_energy','Energy');close(f);
end
