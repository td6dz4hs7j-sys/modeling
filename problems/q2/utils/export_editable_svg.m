function export_editable_svg(fig,path)
% MATLAB R2022a Batik prints glyph outlines. Export geometry natively and
% replace visible labels with real SVG text located from graphics objects.
% The PNG remains the direct MATLAB print output. No invisible audit tokens.
f=copyobj(fig,groot);f.Visible='off';cleanup=onCleanup(@()close(f));drawnow;
fu=f.Units;f.Units='pixels';fp=f.Position;W=fp(3);H=fp(4);f.Units=fu;
ppi=get(groot,'ScreenPixelsPerInch');labels={};axesList=findall(f,'Type','axes');
% Freeze tiled positions by reparenting axes onto figure before hiding labels.
for ax=reshape(axesList,1,[])
 pp=getpixelposition(ax,true);ax.Parent=f;ax.Units='pixels';ax.Position=pp;
end
drawnow;
for ax=reshape(axesList,1,[])
 pp=getpixelposition(ax,true);pb=pp;
 if strcmp(ax.DataAspectRatioMode,'manual')
  ratio=diff(ax.XLim)/diff(ax.YLim)*ax.DataAspectRatio(2)/ax.DataAspectRatio(1);
  if pp(3)/pp(4)>ratio,pb(3)=pp(4)*ratio;pb(1)=pp(1)+(pp(3)-pb(3))/2;
  else,pb(4)=pp(3)/ratio;pb(2)=pp(2)+(pp(4)-pb(4))/2;end
 end
 xt=ax.XTick;yt=ax.YTick;xl=string(ax.XTickLabel);yl=string(ax.YTickLabel);
 for j=1:numel(xt)
  if j>numel(xl),continue;end
  tx=xl(j);if ax.XAxis.Exponent~=0,tx=string(xt(j));end
  if xt(j)<ax.XLim(1)||xt(j)>ax.XLim(2),continue;end
  x=pb(1)+(xt(j)-ax.XLim(1))/diff(ax.XLim)*pb(3);y=H-pb(2)+ax.FontSize*ppi/72*1.25;
  put(x,y,tx,ax.FontSize,ax.FontName,'middle',0,[.15 .15 .15]);
 end
 for j=1:numel(yt)
  if j>numel(yl),continue;end
  tx=yl(j);if ax.YAxis.Exponent~=0,tx=string(yt(j));end
  if yt(j)<ax.YLim(1)||yt(j)>ax.YLim(2),continue;end
  y=H-(pb(2)+(yt(j)-ax.YLim(1))/diff(ax.YLim)*pb(4));
  put(pb(1)-5,y,tx,ax.FontSize,ax.FontName,'end',0,[.15 .15 .15]);
 end
 tx=findall(ax,'Type','text');
 for t=reshape(tx,1,[])
  if isempty(t.String),continue;end
  t.Units='pixels';p=t.Position;x=pp(1)+p(1)-1;y=H-(pp(2)+p(2)-1);
  anchor='start';if strcmp(t.HorizontalAlignment,'center'),anchor='middle';elseif strcmp(t.HorizontalAlignment,'right'),anchor='end';end
  if t==ax.XLabel,x=pb(1)+pb(3)/2;y=H-pb(2)+t.FontSize*ppi/72*3;end
  if t==ax.YLabel,x=pb(1)-t.FontSize*ppi/72*5.5;y=H-pb(2)-pb(4)/2;end
  put(x,y,t.String,t.FontSize,t.FontName,anchor,-t.Rotation,t.Color);
 end
 for t=reshape(tx,1,[]),t.String='';end
 ax.XTickLabel=[];ax.YTickLabel=[];
end
% Colorbars use their own pixel positions.
for cb=reshape(findall(f,'Type','colorbar'),1,[])
 cb.Units='pixels';pp=cb.Position;ticks=cb.Ticks;ticklabels=string(cb.TickLabels);
 for j=1:numel(ticks)
  if j<=numel(ticklabels),put(pp(1)+pp(3)+5,H-pp(2)-(ticks(j)-cb.Limits(1))/diff(cb.Limits)*pp(4),ticklabels(j),cb.FontSize,cb.FontName,'start',0,[.15 .15 .15]);end
 end
 cb.TickLabels={};t=cb.Label;
 if ~isempty(t.String)
  put(pp(1)+pp(3)+48,H-pp(2)-pp(4)/2,t.String,t.FontSize,t.FontName,'middle',-90,[.15 .15 .15]);t.String='';
 end
end
% Legends are redrawn with their actual strings and representative swatches.
for lg=reshape(findall(f,'Type','legend'),1,[])
 lg.Units='pixels';pp=lg.Position;ss=string(lg.String);n=numel(ss);horizontal=strcmp(lg.Orientation,'horizontal');
 colors=[0 .447 .698;.902 .6235 0;0 .62 .451];
 for j=1:n
  if horizontal,x=pp(1)+(j-1)*pp(3)/n+20;y=H-pp(2)-pp(4)/2;
  else,x=pp(1)+22;y=H-pp(2)-pp(4)+(j-.5)*pp(4)/n;end
  put(x,y,ss(j),lg.FontSize,lg.FontName,'start',0,[.1 .1 .1]);
  col=colors(mod(j-1,3)+1,:);marker='o';lineStyle='-';
  if isprop(lg,'PlotChildren') && numel(lg.PlotChildren)>=j
   obj=lg.PlotChildren(j);
   if isprop(obj,'Color') && isnumeric(obj.Color),col=obj.Color;
   elseif isprop(obj,'CData') && isnumeric(obj.CData) && numel(obj.CData)==3,col=obj.CData;
   elseif isprop(obj,'FaceColor') && isnumeric(obj.FaceColor),col=obj.FaceColor;marker='s';end
   if isprop(obj,'Marker'),marker=obj.Marker;end
   if isprop(obj,'LineStyle'),lineStyle=char(obj.LineStyle);end
  end
  if strcmp(marker,'none')
   dash='';
   switch lineStyle
    case '--',dash=' stroke-dasharray="4,2"';
    case ':',dash=' stroke-dasharray="1,2"';
    case '-.',dash=' stroke-dasharray="4,2,1,2"';
   end
   labels{end+1}=sprintf('<line x1="%.4f" x2="%.4f" y1="%.4f" y2="%.4f" stroke="rgb(%d,%d,%d)" stroke-width="1.3"%s/>',x-18,x-4,y,y,round(col*255),dash);
  elseif strcmp(marker,'s')
   labels{end+1}=sprintf('<rect x="%.4f" y="%.4f" width="5.4" height="5.4" fill="rgb(%d,%d,%d)"/>',x-12.7,y-2.7,round(col*255));
  elseif strcmp(marker,'^')
   labels{end+1}=sprintf('<polygon points="%.4f,%.4f %.4f,%.4f %.4f,%.4f" fill="rgb(%d,%d,%d)"/>',x-10,y-3,x-13,y+3,x-7,y+3,round(col*255));
  else,labels{end+1}=sprintf('<circle cx="%.4f" cy="%.4f" r="2.7" fill="rgb(%d,%d,%d)"/>',x-10,y,round(col*255));end
 end
 lg.Visible='off';
end
for t=reshape(findall(f,'Type','textboxshape'),1,[])
 t.Units='pixels';pp=t.Position;put(pp(1)+pp(3)/2,H-pp(2)-pp(4)/2,t.String,t.FontSize,t.FontName,'middle',0,[.1 .1 .1]);t.String='';
end
set(f,'PaperUnits','inches','PaperPosition',[0 0 W/ppi H/ppi],'PaperSize',[W/ppi H/ppi]);
print(f,path,'-dsvg','-painters');
svg=fileread(path);tok=regexp(svg,'width="([0-9.]+)" height="([0-9.]+)"','tokens','once');
if isempty(tok)
 sw=regexp(svg,'width="([0-9.]+)"','tokens','once');sh=regexp(svg,'height="([0-9.]+)"','tokens','once');tok=[sw sh];
end
sx=str2double(tok{1})/W;sy=str2double(tok{2})/H;
overlay=sprintf('<g id="editable-labels" transform="scale(%.8f %.8f)">%s</g>',sx,sy,strjoin(labels,''));
svg=regexprep(svg,'</svg\s*>',[overlay '</svg>']);
fid=fopen(path,'w','n','UTF-8');fprintf(fid,'%s',svg);fclose(fid);
 function put(x,y,s,fs,font,anchor,rotation,color)
  if isempty(s),return;end
  s=string(s);s=s(:);if ischar(color),color=[0 0 0];end
  for ii=1:numel(s)
   text=char(s(ii));text=strrep(text,'&','&amp;');text=strrep(text,'<','&lt;');text=strrep(text,'>','&gt;');
   yy=y+(ii-(numel(s)+1)/2)*fs*ppi/72*1.2;
  labels{end+1}=sprintf('<text x="%.4f" y="%.4f" font-family="%s" font-size="%.4f" text-anchor="%s" dominant-baseline="central" fill="rgb(%d,%d,%d)" stroke="none" transform="rotate(%.4f %.4f %.4f)">%s</text>',x,yy,font,fs*ppi/72,anchor,round(color*255),rotation,x,yy,text); %#ok<AGROW>
  end
 end
end

