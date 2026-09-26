function plot_q3_dem(D,dem,outDir)
if ~isfolder(outDir),mkdir(outDir);end
fig=figure('Visible','off','Color','w');
imagesc(dem.longitude,dem.latitude,double(dem.dem));
set(gca,'YDir','normal');axis equal tight;hold on;
colormap(parula(256));cb=colorbar;cb.Label.String='Elevation (m)';
plot(D.nodes.lon(2:end),D.nodes.lat(2:end),'o','MarkerSize',3.5, ...
 'MarkerFaceColor',[.95,.43,.05],'MarkerEdgeColor','k');
plot(D.nodes.lon(1),D.nodes.lat(1),'p','MarkerSize',9, ...
 'MarkerFaceColor',[.75,.05,.15],'MarkerEdgeColor','w');
text(D.nodes.lon(1)+.006,D.nodes.lat(1)-.006,'O01 / G01', ...
 'Color','k','BackgroundColor','w','Margin',2,'FontWeight','bold','FontSize',8);
xlabel('Longitude (°E)');ylabel('Latitude (°N)');
title('Terrain');
apply_publication_style(fig,"en","report");
export_publication_figure(fig,string(fullfile(outDir,'raw_q3_dem_nodes_gateway')),300);
close(fig);
end
