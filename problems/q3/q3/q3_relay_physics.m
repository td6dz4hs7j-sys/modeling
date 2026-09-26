function P=q3_relay_physics(D,dem,loc,service_s)
% O01 -> hover point -> O01, using the appendix flight and energy rules.
if nargin<4,service_s=0;end
P=struct('valid',false,'reason','','distance_m',NaN,'cruise_m',NaN, ...
 'outbound_s',NaN,'return_s',NaN,'flightEnergy_kWh',NaN,'energy_kWh',NaN);
if loc(3)-q3_dem_at(dem,loc(1:2))>D.relay.maxAGL_m+1e-9
 P.reason='hover AGL exceeds cap';return
end
O=D.nodes(1,:);a=[O.lon,O.lat,O.z];
if all(abs(a(1:2)-loc(1:2))<1e-10)
 d=0;zmax=q3_dem_at(dem,a(1:2));
else
 dx=dem.transform(1);dy=dem.transform(5);x0=dem.transform(3);y0=dem.transform(6);
 aa=[(a(1)-x0)/dx,(a(2)-y0)/dy];bb=[(loc(1)-x0)/dx,(loc(2)-y0)/dy];t=[0,1];
 for j=1:2
  ed=ceil(min(aa(j),bb(j))):floor(max(aa(j),bb(j)));
  tj=(ed-aa(j))/(bb(j)-aa(j));t=[t,tj(tj>=0 & tj<=1)]; %#ok<AGROW>
 end
 t=unique(t);mid=(t(1:end-1)+t(2:end))/2;
 xy=aa+[t(:);mid(:)].*(bb-aa);cells=zeros(0,2);
 for ex=[-1,1]*1e-8
  for ey=[-1,1]*1e-8
   cells=[cells;floor(xy+[ex ey])+1]; %#ok<AGROW>
  end
 end
 cells=unique(cells,'rows');
 if any(cells(:,1)<1|cells(:,1)>size(dem.dem,2)|cells(:,2)<1|cells(:,2)>size(dem.dem,1))
  P.reason='route outside DEM';return
 end
 z=double(dem.dem(sub2ind(size(dem.dem),cells(:,2),cells(:,1))));
 if any(~isfinite(z)|z==dem.nodata),P.reason='invalid DEM';return;end
 zmax=max(z);d=distance(a(2),a(1),loc(2),loc(1),wgs84Ellipsoid('meter'));
end
h=zmax+D.clearance;
if h<max(a(3),loc(3))-1e-9,P.reason='hover above planned cruise';return;end
upOut=h-a(3);downOut=h-loc(3);upBack=downOut;downBack=upOut;
out=upOut/D.relay.up_mps+d/D.relay.speed_mps+downOut/D.relay.down_mps;
ret=upBack/D.relay.up_mps+d/D.relay.speed_mps+downBack/D.relay.down_mps;
ef=D.relay.cruise_kW*(2*d/D.relay.speed_mps)/3600+ ...
 D.relay.mass_kg*D.g*(upOut+upBack)/(D.relay.eta*3.6e6);
E=ef+(D.relay.hover_kW+D.relay.radio_kW)*(D.relay.link_s+service_s)/3600;
P=struct('valid',E<=(1-D.relay.reserve)*D.relay.energy_kWh+D.tol.energy, ...
 'reason','','distance_m',d,'cruise_m',h,'outbound_s',out, ...
 'return_s',ret,'flightEnergy_kWh',ef,'energy_kWh',E);
if ~P.valid,P.reason='energy reserve';end
end
