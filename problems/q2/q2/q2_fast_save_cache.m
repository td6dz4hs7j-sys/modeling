function q2_fast_save_cache(ctx)
% Persist key/value pairs so P2 reruns can reuse evaluated routes safely.
if isempty(ctx.cachePath),return;end
cacheKeys=keys(ctx.routeCache);cacheValues=values(ctx.routeCache,cacheKeys);
cacheMeta=struct('modelFingerprint',ctx.modelFingerprint,'version',ctx.version, ...
 'entryCount',numel(cacheKeys),'savedUTC',char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss''Z''')));
parent=fileparts(ctx.cachePath);if ~isfolder(parent),mkdir(parent);end
tmp=[ctx.cachePath '.tmp.mat'];save(tmp,'cacheMeta','cacheKeys','cacheValues','-v7.3');movefile(tmp,ctx.cachePath,'f');
end
