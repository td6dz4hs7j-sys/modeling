function [ok,margin]=q3_link_interval(A0,A1,B,kind,D,dem)
% Sufficient certificate for every moving endpoint between A0 and A1.
% A pessimistic blocked-link bound is tried first. Otherwise every point
% in the swept LOS is enclosed by DEM-cell rectangles before clear FSPL.
switch kind
 case 'fixed',pt1=D.radio.transportPt_dBm;gt1=D.radio.transportGain_dBi;pt2=D.radio.gatewayPt_dBm;gt2=D.radio.gatewayGain_dBi;
 case 'access',pt1=D.radio.transportPt_dBm;gt1=D.radio.transportGain_dBi;pt2=D.radio.accessPt_dBm;gt2=D.radio.accessGain_dBi;
 case 'backhaul',pt1=D.radio.backhaulPt_dBm;gt1=D.radio.backhaulGain_dBi;pt2=D.radio.gatewayPt_dBm;gt2=D.radio.gatewayGain_dBi;
 otherwise,error('Unknown link type');
end
th=D.radio.sensitivity_dBm+D.radio.fade_dB;
budget=min(pt1+gt1+gt2-D.radio.system_dB-th,pt2+gt2+gt1-D.radio.system_dB-th);
earth=wgs84Ellipsoid('meter');
d0=hypot(distance(A0(2),A0(1),B(2),B(1),earth),A0(3)-B(3));
d1=hypot(distance(A1(2),A1(1),B(2),B(1),earth),A1(3)-B(3));
% Triangle inequality gives a conservative bound even on the WGS84 ellipsoid.
% 112 km per degree bounds local WGS84 meridional and zonal arc lengths.
move=hypot(112000*hypot(A1(1)-A0(1),A1(2)-A0(2)),A1(3)-A0(3));
dmax=max([d0,d1,(d0+d1+move)/2])/1000;
loss=32.45+20*log10(D.radio.fMHz)+20*log10(max(dmax,1e-9));
margin=budget-loss-D.radio.obstruction_dB;
if margin>=0,ok=true;return;end
if ~clear_swept(A0,A1,B,dem,0,1,0,1,0)
 ok=false;return;
end
margin=budget-loss;ok=margin>=0;
end

function yes=clear_swept(A0,A1,B,dem,t0,t1,r0,r1,depth)
% Bilinear A(t)*(1-r)+B*r stays in the convex hull of four corners.
P=zeros(4,3);n=0;
for t=[t0,t1],for r=[r0,r1]
 n=n+1;A=A0+t*(A1-A0);P(n,:)=A*(1-r)+B*r;
end,end
x0=dem.transform(3);y0=dem.transform(6);dx=dem.transform(1);dy=dem.transform(5);
cx=(P(:,1)-x0)/dx;cy=(P(:,2)-y0)/dy;
% Include exactly the cells touching the closed bounding rectangle.
% The old whole-cell padding also included unrelated adjacent ridges and
% prevented a certificate even after subdivision to a single LOS point.
e=1e-9;
cmin=max(1,floor(min(cx)-e)+1);cmax=min(size(dem.dem,2),floor(max(cx)+e)+1);
rmin=max(1,floor(min(cy)-e)+1);rmax=min(size(dem.dem,1),floor(max(cy)+e)+1);
if cmin>cmax||rmin>rmax,error('LOS outside DEM');end
z=double(dem.dem(rmin:rmax,cmin:cmax));
if any(~isfinite(z(:))|z(:)==dem.nodata),error('Invalid DEM along LOS');end
if min(P(:,3))>max(z(:))+1e-6,yes=true;return;end
if depth>=22,yes=false;return;end
% Split angular/ray direction first, then the transport time direction.
spanR=norm(B(1:2)-A0(1:2))*(r1-r0);
spanT=norm(A1(1:2)-A0(1:2))*(t1-t0);
if spanR>=spanT
 m=(r0+r1)/2;
 yes=clear_swept(A0,A1,B,dem,t0,t1,r0,m,depth+1)&& ...
     clear_swept(A0,A1,B,dem,t0,t1,m,r1,depth+1);
else
 m=(t0+t1)/2;
 yes=clear_swept(A0,A1,B,dem,t0,m,r0,r1,depth+1)&& ...
     clear_swept(A0,A1,B,dem,m,t1,r0,r1,depth+1);
end
end
