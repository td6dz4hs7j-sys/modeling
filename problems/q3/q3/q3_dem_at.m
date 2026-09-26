function z=q3_dem_at(dem,xy)
c=floor([(xy(1)-dem.transform(3))/dem.transform(1), ...
 (xy(2)-dem.transform(6))/dem.transform(5)])+1;
assert(c(1)>=1&&c(1)<=size(dem.dem,2)&&c(2)>=1&&c(2)<=size(dem.dem,1),'Point outside DEM');
z=double(dem.dem(c(2),c(1)));assert(isfinite(z)&&z~=dem.nodata);
end
