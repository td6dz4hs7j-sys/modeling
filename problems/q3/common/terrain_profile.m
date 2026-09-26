function P=terrain_profile(D,dem,areas)
% Closed-cell supercover: corner and edge touches include both adjacent cells.
if nargin<3,areas=1:15;end
o=D.nodes(1,:); P=struct([]);
dx=dem.transform(1);dy=dem.transform(5);x0=dem.transform(3);y0=dem.transform(6);
for i=areas
 s=D.nodes(i+1,:); a=[(o.lon-x0)/dx,(o.lat-y0)/dy];b=[(s.lon-x0)/dx,(s.lat-y0)/dy];
 t=[0 1];
 for j=1:2
  if abs(b(j)-a(j))>eps
   edges=ceil(min(a(j),b(j))):floor(max(a(j),b(j)));
   tt=(edges-a(j))/(b(j)-a(j)); t=[t tt(tt>=0 & tt<=1)]; %#ok<AGROW>
  end
 end
 t=unique(t); tm=(t(1:end-1)+t(2:end))/2; ts=sort([t tm]);
 xy=a+ts(:).*(b-a); cells=[];
 for ex=[-1,1]*1e-8
  for ey=[-1,1]*1e-8
   cells=[cells;floor(xy+[ex ey])+1]; %#ok<AGROW>
  end
 end
 cells=unique(cells,'rows');
 assert(all(cells(:,1)>=1 & cells(:,1)<=size(dem.dem,2) & cells(:,2)>=1 & cells(:,2)<=size(dem.dem,1)));
 z=double(dem.dem(sub2ind(size(dem.dem),cells(:,2),cells(:,1))));
 h=max(z)+D.clearance; assert(h>=max(o.z,s.z+D.deliveryHeight),'Cruise below work altitude');
 dist=distance(o.lat,o.lon,s.lat,s.lon,wgs84Ellipsoid('meter'));
 midlat=(o.lat+s.lat)/2;local=6371008.8*pi/180*hypot((s.lon-o.lon)*cosd(midlat),s.lat-o.lat);
 tt=linspace(0,1,ceil(dist)+1);xy2=a+tt(:).*(b-a);cc=floor(xy2)+1;
 zz=double(dem.dem(sub2ind(size(dem.dem),cc(:,2),cc(:,1))));
 assert(max(zz)<=max(z)+1e-10,'Supercover missed dense sample');
 P=[P;struct('area',s.id,'index',i,'distance',dist,'localDistance',local,'terrainMax',max(z),'cruise',h,'outUp',h-o.z,'backUp',h-s.z-D.deliveryHeight,'cells',cells,'profileFraction',tt,'profileZ',zz,'nodeDEM',zz(end),'nodeZ',s.z)]; %#ok<AGROW>
end
end

