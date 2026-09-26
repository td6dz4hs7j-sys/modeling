function ctx=q2_fast_context(D,legs,cachePath)
% Create an exact-domain route cache and reload compatible persistent entries.
if nargin<3,cachePath='';end
version='q2-fast-schedule-v1';
payload=struct('version',version,'nodes',table2struct(D.nodes),'uav',table2struct(D.uav), ...
 'uavInventory',table2struct(D.uavInventory),'batteryInventory',table2struct(D.batteryInventory), ...
 'boxes',table2struct(D.boxes),'boxNodeIndex',D.boxNodeIndex,'boxMass',D.boxMass,'boxVolume',D.boxVolume, ...
 'hardDeadline_s',D.hardDeadline_s,'g',D.g,'tol',D.tol, ...
 'legEndpoints',[[legs.fromIdx]' [legs.toIdx]'],'legPhysics',[[legs.distance_m]' [legs.up_m]' [legs.down_m]']);
codeFiles={which('evaluate_q2_route'),which('q2_fast_schedule'),which('q2_fast_context')};
payload.codeSHA256=q2_sha256(codeFiles);
bytes=unicode2native(jsonencode(payload),'UTF-8');md=java.security.MessageDigest.getInstance('SHA-256');md.update(uint8(bytes));dig=typecast(md.digest(),'uint8');fp=lower(reshape(dec2hex(dig,2)',1,[]));
ctx=struct('modelFingerprint',fp,'routeCache',containers.Map('KeyType','char','ValueType','any'), ...
 'version',version,'cachePath',cachePath,'cacheLoaded',false);
if ~isempty(cachePath)&&isfile(cachePath)
 x=load(cachePath,'cacheMeta','cacheKeys','cacheValues');
 if isfield(x,'cacheMeta')&&strcmp(x.cacheMeta.modelFingerprint,fp)&&strcmp(x.cacheMeta.version,version)
  for i=1:numel(x.cacheKeys),ctx.routeCache(x.cacheKeys{i})=x.cacheValues{i};end
  ctx.cacheLoaded=true;
 end
end
end
