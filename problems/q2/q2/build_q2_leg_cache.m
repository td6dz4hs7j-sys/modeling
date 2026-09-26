function [legs,meta] = build_q2_leg_cache(D,root,force)
% Full directed all-node terrain/leg cache with source and code fingerprints.
if nargin<2,root=D.root;end
if nargin<3,force=false;end
cacheDir=fullfile(root,'cache'); if ~isfolder(cacheDir),mkdir(cacheDir);end
inputFiles={fullfile(root,'input','数据','无人机应急物资运输基础数据','调度中心与服务区.xlsx')};
df=dir(fullfile(root,'input','**','*DEM.mat')); tf=dir(fullfile(root,'input','**','*DEM.tif'));
assert(numel(df)==1 && numel(tf)==1); inputFiles=[inputFiles,{fullfile(df.folder,df.name),fullfile(tf.folder,tf.name)}];
codeFiles={fullfile(root,'q2','build_q2_leg_cache.m'),fullfile(root,'q2','q2_sha256.m'),fullfile(root,'common','load_dem.m'),fullfile(root,'common','terrain_profile.m')};
inputHash=q2_sha256(inputFiles); codeHash=q2_sha256(codeFiles);
meta=struct('inputSHA256',inputHash,'codeSHA256',codeHash,'inputFiles',{inputFiles},'codeFiles',{codeFiles},'formulaVersion','q2-leg-v1','clearance_m',D.clearance,'deliveryHeight_m',D.deliveryHeight,'createdUTC',char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss''Z''')));
f=fullfile(cacheDir,'leg_cache.mat');
if ~force && isfile(f)
    x=load(f,'legs','meta');
    if strcmp(x.meta.inputSHA256,inputHash) && strcmp(x.meta.codeSHA256,codeHash) && strcmp(x.meta.formulaVersion,meta.formulaVersion) && isequal(x.meta.clearance_m,D.clearance) && isequal(x.meta.deliveryHeight_m,D.deliveryHeight)
        legs=x.legs;meta=x.meta;return
    end
end
dem=load_dem(root); n=height(D.nodes);
legs=repmat(struct('fromIdx',0,'toIdx',0,'fromID','','toID','','distance_m',0,'localDistance_m',0,'terrainMax_m',0,'cruise_m',0,'up_m',0,'down_m',0,'cells',zeros(0,2)),n*n,1);
z=0;
for i=1:n
 for j=1:n
  if i==j,continue;end
  A=D.nodes(i,:); B=D.nodes(j,:);
  P=q2_pair_profile(A,B,dem,D);
  z=z+1; legs(z)=struct('fromIdx',i,'toIdx',j,'fromID',char(A.id),'toID',char(B.id),'distance_m',P.distance,'localDistance_m',P.localDistance,'terrainMax_m',P.terrainMax,'cruise_m',P.cruise,'up_m',P.up,'down_m',P.down,'cells',P.cells);
 end
end
legs=legs(1:z);
save(f,'legs','meta','-v7.3');
save(fullfile(cacheDir,'terrain_cache.mat'),'legs','meta','-v7.3');
end

function P=q2_pair_profile(A,B,dem,D)
dx=dem.transform(1);dy=dem.transform(5);x0=dem.transform(3);y0=dem.transform(6);
a=[(A.lon-x0)/dx,(A.lat-y0)/dy]; b=[(B.lon-x0)/dx,(B.lat-y0)/dy]; t=[0 1];
for k=1:2
 if abs(b(k)-a(k))>eps
  e=ceil(min(a(k),b(k))):floor(max(a(k),b(k))); tt=(e-a(k))/(b(k)-a(k)); t=[t,tt(tt>=0 & tt<=1)]; %#ok<AGROW>
 end
end
t=unique(t); mid=(t(1:end-1)+t(2:end))/2; ts=sort([t mid]); xy=a+ts(:).*(b-a); cells=[];
for ex=[-1,1]*1e-8
 for ey=[-1,1]*1e-8, cells=[cells;floor(xy+[ex ey])+1]; %#ok<AGROW>
 end
end
cells=unique(cells,'rows');
assert(all(cells(:,1)>=1 & cells(:,1)<=size(dem.dem,2) & cells(:,2)>=1 & cells(:,2)<=size(dem.dem,1)),'Leg exceeds DEM coverage: %s -> %s',A.id,B.id);
zz=double(dem.dem(sub2ind(size(dem.dem),cells(:,2),cells(:,1)))); zm=max(zz); h=zm+D.clearance;
assert(all(isfinite(zz)) && all(zz~=dem.nodata),'NoData/invalid DEM cells on leg %s -> %s',A.id,B.id);
aH=A.z+double(A.id~="O01")*D.deliveryHeight; bH=B.z+double(B.id~="O01")*D.deliveryHeight;
assert(h>=max(aH,bH),'Cruise below work altitude for %s -> %s',A.id,B.id);
d=distance(A.lat,A.lon,B.lat,B.lon,wgs84Ellipsoid('meter')); midlat=(A.lat+B.lat)/2;
local=6371008.8*pi/180*hypot((B.lon-A.lon)*cosd(midlat),B.lat-A.lat);
tt=linspace(0,1,max(2,ceil(d)+1)); sample=a+tt(:).*(b-a); cc=floor(sample)+1;
zs=double(dem.dem(sub2ind(size(dem.dem),cc(:,2),cc(:,1)))); assert(max(zs)<=zm+1e-10,'Supercover failed dense profile: %s -> %s',A.id,B.id);
P=struct('distance',d,'localDistance',local,'terrainMax',zm,'cruise',h,'up',h-aH,'down',h-bH,'cells',cells);
end
