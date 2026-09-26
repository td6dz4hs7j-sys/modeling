function T=audit_q2_fast_decoder(D,legs,S,outDir)
% Compare fast decoder feasibility, metrics and timings with the full decoder.
if nargin<4||isempty(outDir),outDir=fullfile(D.root,'results','q2_fast_audit');end
if ~isfolder(outDir),mkdir(outDir);end
ctx=q2_fast_context(D,legs,fullfile(D.root,'cache','route_cache.mat'));
cases=cell(0,2);cases(end+1,:)={"baseline",strip_routes(S.routes)};
base=strip_routes(S.routes);
for i=1:min(10,numel(base)-1)
 x=base;x([i,i+1])=x([i+1,i]);cases(end+1,:)={"adjacent_swap_"+i,x}; %#ok<AGROW>
end
multi=find(arrayfun(@(r)numel(r.nodeOrder)>1,base),1);
if ~isempty(multi),x=base;x(multi).nodeOrder=fliplr(x(multi).nodeOrder);cases(end+1,:)={"reverse_multistop_"+multi,x};end
rows=cell(size(cases,1),12);
for i=1:size(cases,1)
 routes=cases{i,2};t=tic;[Sf,st]=schedule_q2_routes(D,legs,routes);fullSeconds=toc(t);
 t=tic;[F,ctx]=q2_fast_schedule(D,legs,routes,ctx);fastSeconds=toc(t);
 assert(F.feasible==st.feasible,'Fast/full feasibility mismatch in %s (%s vs %s).',cases{i,1},string(F.feasible),string(st.feasible));
 metricError=NaN;
 if F.feasible
  a=[Sf.metrics.W,Sf.metrics.Cmax_s,Sf.metrics.energy_kWh,Sf.metrics.N];b=[F.metrics.W,F.metrics.Cmax_s,F.metrics.energy_kWh,F.metrics.N];
  metricError=max(abs(a-b));
  tol=[D.tol.time,D.tol.time,D.tol.energy,0];assert(all(abs(a-b)<=tol), ...
   'Fast/full metric mismatch in %s: full=%s fast=%s.',cases{i,1},mat2str(a,15),mat2str(b,15));
 end
 rows(i,:)={cases{i,1},st.feasible,fullSeconds,fastSeconds,F.routeEvalSeconds,F.decodeSeconds, ...
  F.cacheHits,F.cacheMisses,metricError,Sf.metrics.W,Sf.metrics.Cmax_s,Sf.metrics.energy_kWh};
end
T=cell2table(rows,'VariableNames',{'case','feasible','full_s','fast_s','fast_route_eval_s','fast_decode_s', ...
 'cache_hits','cache_misses','max_metric_abs_error','W','Cmax_s','energy_kWh'});
writetable(T,fullfile(outDir,'fast_decoder_vs_full.csv'));
audit=struct('status','PASS','modelFingerprint',ctx.modelFingerprint,'routeCacheEntries',ctx.routeCache.Count, ...
 'caseCount',height(T),'allFeasibilityMatched',true,'maxMetricAbsError',max(T.max_metric_abs_error,[],'omitnan'));
save(fullfile(outDir,'fast_decoder_vs_full.mat'),'T','audit','ctx','-v7.3');
q2_fast_save_cache(ctx);
end

function routes=strip_routes(r)
routes=repmat(struct('boxIdx',[],'nodeOrder',[],'typeIdx',[]),numel(r),1);
for i=1:numel(r),routes(i)=struct('boxIdx',r(i).boxIdx(:),'nodeOrder',r(i).nodeOrder(:)','typeIdx',r(i).typeIdx);end
end
