function dem=load_dem(root)
f=dir(fullfile(root,'input','**','*DEM.mat'));
if isempty(f),f=dir(fullfile(root,'data','raw','D题','数据','**','*DEM.mat'));end
assert(numel(f)==1);
dem=load(fullfile(f.folder,f.name));
assert(isequal(size(dem.dem),[numel(dem.latitude),numel(dem.longitude)]));
assert(all(diff(dem.latitude)<0) && all(diff(dem.longitude)>0));
assert(dem.epsg_code==4326 && ~any(dem.dem(:)==dem.nodata));
f=dir(fullfile(root,'input','**','*DEM.tif'));
if isempty(f),f=dir(fullfile(root,'data','raw','D题','数据','**','*DEM.tif'));end
assert(numel(f)==1);
z=imread(fullfile(f.folder,f.name));assert(isequal(z,dem.dem),'DEM MAT/TIF mismatch');
end
