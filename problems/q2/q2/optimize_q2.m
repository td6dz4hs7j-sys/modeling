function R = optimize_q2(D,legs,S0,varargin)
% Bounded Q2 route-level local search. Requires a feasible scheduled seed S0.
% Budgets are adjustable within the reviewed upper bounds.
ip=inputParser; addParameter(ip,'Priority',[1 2 3 4],@(x)isnumeric(x)&&isequal(sort(x(:))',(1:4)));
addParameter(ip,'Label','main',@(x)ischar(x)||isstring(x));
addParameter(ip,'MaxSeeds',8,@(x)isnumeric(x)&&isscalar(x)&&x==fix(x)&&x>=1&&x<=8);
addParameter(ip,'MaxRounds',40,@(x)isnumeric(x)&&isscalar(x)&&x==fix(x)&&x>=1&&x<=40);
addParameter(ip,'CandidatesPerRound',200,@(x)isnumeric(x)&&isscalar(x)&&x==fix(x)&&x>=1&&x<=200);
addParameter(ip,'StagnationRounds',5,@(x)isnumeric(x)&&isscalar(x)&&x==fix(x)&&x>=1&&x<=40);
addParameter(ip,'MaxSorties',Inf,@(x)isnumeric(x)&&isscalar(x)&&x>=1);
addParameter(ip,'MinSorties',1,@(x)isnumeric(x)&&isscalar(x)&&x>=1);
addParameter(ip,'Seeds',[],@(x)isnumeric(x)&&isvector(x));
addParameter(ip,'OutputDir','',@(x)ischar(x)||isstring(x)); parse(ip,varargin{:});
priority=ip.Results.Priority(:)'; label=char(ip.Results.Label);
params=struct('MaxSeeds',ip.Results.MaxSeeds,'MaxRounds',ip.Results.MaxRounds, ...
 'CandidatesPerRound',ip.Results.CandidatesPerRound,'StagnationRounds',ip.Results.StagnationRounds, ...
 'MaxSorties',ip.Results.MaxSorties,'MinSorties',ip.Results.MinSorties,'Priority',priority);
assert(isfield(S0,'routes')&&isfield(S0,'metrics'),'S0 must be a scheduled solution.');
assert(S0.metrics.N<=params.MaxSorties&&S0.metrics.N>=params.MinSorties,'Initial solution violates sortie bounds.');
assert(all(isfield(S0.routes,{'boxIdx','nodeOrder','typeIdx'})),'S0 routes lack required fields.');
routes=strip_routes(S0.routes);
[S0,st0]=schedule_q2_routes(D,legs,routes);
assert(st0.feasible,'Initial solution must be feasible: %s',st0.reason);
V0=validate_q2_solution(D,legs,S0);assert(strcmp(V0.status,'PASS'),'Initial solution failed validator: %s',strjoin(V0.issues,' | '));
if isempty(ip.Results.Seeds),seeds=20260924+(0:params.MaxSeeds-1);else,seeds=ip.Results.Seeds(:)';assert(numel(seeds)<=params.MaxSeeds&&numel(seeds)<=8,'Seeds exceed configured cap.');end
if strlength(string(ip.Results.OutputDir))>0,outDir=char(ip.Results.OutputDir);else,outDir=fullfile(D.root,'results',['q2_opt_' label]);end
if ~exist(outDir,'dir'),mkdir(outDir);end
prefix='q2';ctx=q2_fast_context(D,legs,fullfile(D.root,'cache','route_cache.mat'));
seedBest=cell(numel(seeds),1); seedRows=cell(numel(seeds),6); allTrace=table();
for si=1:numel(seeds)
 rng(seeds(si),'twister'); current=S0; best=S0; noImprove=0; tr=cell(0,15);
 for roundNo=1:params.MaxRounds
  ticRound=tic; cand=make_candidates(D,current.routes,params.CandidatesPerRound); bestCandidate=[]; bestKey=[]; nEvaluated=0; nFeasible=0;
  fastSeconds=0;fullRebuildSeconds=0;cacheHits=0;cacheMisses=0;
  for ci=1:numel(cand)
   cr=cand{ci}; if numel(cr)>params.MaxSorties||numel(cr)<params.MinSorties||~capacity_possible(D,cr),continue;end
   nEvaluated=nEvaluated+1;
   tFast=tic;[Fc,ctx]=q2_fast_schedule(D,legs,cr,ctx);fastSeconds=fastSeconds+toc(tFast);
   cacheHits=cacheHits+Fc.cacheHits;cacheMisses=cacheMisses+Fc.cacheMisses;
   if ~Fc.feasible,continue;end
   nFeasible=nFeasible+1; key=objective_key(Fc.metrics,priority);
   if lex_less(key,objective_key(best.metrics,priority)) && (isempty(bestCandidate)||lex_less(key,bestKey))
    tFull=tic;[Sc,st]=schedule_q2_routes(D,legs,cr);fullRebuildSeconds=fullRebuildSeconds+toc(tFull);
    assert(st.feasible,'Fast/full feasibility mismatch for promising route set: %s',st.reason);
    assert_metrics_match(Fc.metrics,Sc.metrics,D);
    Vc=validate_q2_solution(D,legs,Sc);assert(strcmp(Vc.status,'PASS'),'Candidate failed validator: %s',strjoin(Vc.issues,' | '));
    bestCandidate=Sc; bestKey=objective_key(Sc.metrics,priority);
   end
  end
  improved=~isempty(bestCandidate);
  if improved, current=bestCandidate; best=bestCandidate; noImprove=0; else,noImprove=noImprove+1;end
  elapsed=toc(ticRound); m=current.metrics; tr(end+1,:)={seeds(si),roundNo,m.W,m.Cmax_s,m.energy_kWh,m.N,nEvaluated,nFeasible,elapsed, ...
   numel(cand),fastSeconds,fullRebuildSeconds,cacheHits,cacheMisses,ctx.routeCache.Count}; %#ok<AGROW>
  fprintf('%s seed %d round %d: W=%.6f Cmax=%.3f E=%.6f N=%d (%d feasible, %.2fs)\n',label,seeds(si),roundNo,m.W,m.Cmax_s,m.energy_kWh,m.N,nFeasible,elapsed);
  T=cell2table(tr,'VariableNames',{'seed','round','W','Cmax_s','energy_kWh','N','evaluated','feasible','elapsed_s', ...
   'generated','fast_s','full_rebuild_s','cache_hits','cache_misses','route_cache_entries'});
  writetable(T,fullfile(outDir,sprintf('%s_seed_%d_trace.csv',prefix,seeds(si))));
  q2_fast_save_cache(ctx);
  save(fullfile(outDir,sprintf('%s_seed_%d_checkpoint.mat',prefix,seeds(si))),'current','best','T','priority','params','-v7.3');
  if noImprove>=params.StagnationRounds,break;end
 end
 seedBest{si}=best; m=best.metrics; seedRows(si,:)={seeds(si),m.W,m.Cmax_s,m.energy_kWh,m.N,height(T)};
 save(fullfile(outDir,sprintf('%s_seed_%d_best.mat',prefix,seeds(si))),'best','T','priority','params');
 allTrace=[allTrace;T]; %#ok<AGROW>
end
vals=cell2mat(seedRows(:,2:5)); summary=table(seeds(:),vals(:,1),vals(:,2),vals(:,3),vals(:,4),cell2mat(seedRows(:,6)),...
 'VariableNames',{'seed','W','Cmax_s','energy_kWh','N','rounds'});
R=struct('priority',priority,'label',label,'params',params,'seeds',seeds,'modelFingerprint',ctx.modelFingerprint,'seedBest',{seedBest},'summary',summary,'trace',allTrace);
R.best=seedBest{1}; for i=2:numel(seedBest),if lex_less(objective_key(seedBest{i}.metrics,priority),objective_key(R.best.metrics,priority)),R.best=seedBest{i};end,end
R.statistics=struct(); names={'W','Cmax_s','energy_kWh','N'};
for j=1:4, x=vals(:,j); R.statistics.(names{j})=struct('best',min(x),'mean',mean(x),'worst',max(x),'std',std(x,0)); end
save(fullfile(outDir,[prefix '_summary.mat']),'R','params'); writetable(summary,fullfile(outDir,[prefix '_summary.csv']));
end

function assert_metrics_match(a,b,D)
va=[a.W,a.Cmax_s,a.energy_kWh,a.N];vb=[b.W,b.Cmax_s,b.energy_kWh,b.N];tol=[D.tol.time,D.tol.time,D.tol.energy,0];
assert(all(abs(va-vb)<=tol),'Fast/full metric mismatch: fast=%s full=%s.',mat2str(va,15),mat2str(vb,15));
end

function routes=strip_routes(r)
routes=repmat(struct('boxIdx',[],'nodeOrder',[],'typeIdx',[]),numel(r),1);
for i=1:numel(r),routes(i)=struct('boxIdx',r(i).boxIdx(:),'nodeOrder',r(i).nodeOrder(:)','typeIdx',r(i).typeIdx);end
end
function C=make_candidates(D,routes,limit)
routes=strip_routes(routes);
C={}; nr=numel(routes); nt=height(D.uav);
% Deterministic route-wide type changes first, then schedule precedence moves/swaps.
for i=1:nr, for t=1:nt, if t~=routes(i).typeIdx, x=routes; x(i).typeIdx=t; C{end+1}=x; end,end,end
nType=numel(C);
% Deterministic route splits: singleton boxes and same-destination groups.
Csplit={};
for i=1:nr
 b=routes(i).boxIdx(:); if numel(b)<2,continue;end
 subsets=cell(0,1);
 for z=1:numel(b),subsets{end+1}=b(z);end %#ok<AGROW>
 areas=unique(D.boxNodeIndex(b),'stable');
 for z=1:numel(areas)
  group=b(D.boxNodeIndex(b)==areas(z)); if numel(group)>1 && numel(group)<numel(b),subsets{end+1}=group;end %#ok<AGROW>
 end
 for si=1:numel(subsets)
  moved=subsets{si}; if numel(moved)>=numel(b),continue;end
  remain=b(~ismember(b,moved)); src=routes(i); src.boxIdx=remain;
  srcNodes=unique(D.boxNodeIndex(remain),'stable'); src.nodeOrder=src.nodeOrder(ismember(src.nodeOrder,srcNodes));
  new=struct('boxIdx',moved(:),'nodeOrder',unique(D.boxNodeIndex(moved),'stable'),'typeIdx',routes(i).typeIdx);
  for t=1:nt
   new.typeIdx=t;
   for before=[true false]
    x=routes; x(i)=src; item=new;
    if before,x=[x(1:i-1);item;x(i:end)];else,x=[x(1:i);item;x(i+1:end)];end
    Csplit{end+1}=x; %#ok<AGROW>
   end
  end
 end
end
for i=1:nr-1, x=routes; x([i i+1])=x([i+1 i]); C{end+1}=x; end
% A bounded set of longer precedence moves covers route insertion positions.
for i=1:nr
 for j=[1 nr]
  if i==j,continue;end
  x=routes; item=x(i); x(i)=[]; x=[x(1:j-1);item;x(j:end)]; C{end+1}=x;
 end
end
% Deterministic within-route node order exchange and reversal.
for i=1:nr
 n=numel(routes(i).nodeOrder);
 for a=1:n,for b=a+1:n
  x=routes; x(i).nodeOrder([a b])=x(i).nodeOrder([b a]); C{end+1}=x;
  x=routes; x(i).nodeOrder(a:b)=x(i).nodeOrder(b:-1:a); C{end+1}=x;
 end,end
end
% Route merge candidates; shared destinations remain one visit in stable order.
for i=1:nr,for j=i+1:nr
 x=routes; x(i).boxIdx=[x(i).boxIdx(:);x(j).boxIdx(:)]; x(i).nodeOrder=unique([x(i).nodeOrder(:)' x(j).nodeOrder(:)'],'stable'); x(j)=[];
 for t=1:nt, xt=x; xt(i).typeIdx=t; C{end+1}=xt; end
end,end
% Rotate among type, split and other deterministic moves while reserving random moves.
nTypeKeep=min(floor(.15*limit),nType); if nTypeKeep>0,typePick=randperm(nType,nTypeKeep);else,typePick=[];end
nSplitKeep=min(floor(.15*limit),numel(Csplit)); if nSplitKeep>0,splitPick=randperm(numel(Csplit),nSplitKeep);else,splitPick=[];end
nOtherKeep=max(0,floor(0.4*limit)-nTypeKeep-nSplitKeep);
pool=(nType+1):numel(C);
if nOtherKeep>0&&~isempty(pool),pool=pool(randperm(numel(pool),min(nOtherKeep,numel(pool))));else,pool=[];end
C=[C(typePick),Csplit(splitPick),C(pool)];
% Bounded random box relocation/swap and node order moves fill remaining slots.
attempts=0;
while numel(C)<limit && attempts<limit*20
 attempts=attempts+1; x=routes; if nr<1,break;end
 op=randi(5);
 if op<=2 && nr>=2
  i=randi(nr); j=randi(nr-1); if j>=i,j=j+1;end
  if op==1
   b=x(i).boxIdx(randi(numel(x(i).boxIdx))); x(i).boxIdx(x(i).boxIdx==b)=[]; x(j).boxIdx(end+1)=b;
   if isempty(x(i).boxIdx),x(i)=[]; if i<j,j=j-1;end
   else,x(i).nodeOrder=unique(D.boxNodeIndex(x(i).boxIdx),'stable');end
   x(j).nodeOrder=unique(D.boxNodeIndex(x(j).boxIdx),'stable');
  elseif op==2 && ~isempty(x(i).boxIdx)&&~isempty(x(j).boxIdx)
   a=randi(numel(x(i).boxIdx)); b=randi(numel(x(j).boxIdx)); [x(i).boxIdx(a),x(j).boxIdx(b)]=deal(x(j).boxIdx(b),x(i).boxIdx(a));
   x(i).nodeOrder=unique(D.boxNodeIndex(x(i).boxIdx),'stable'); x(j).nodeOrder=unique(D.boxNodeIndex(x(j).boxIdx),'stable');
  else,continue;end
 elseif op==3
  i=randi(nr); if numel(x(i).nodeOrder)<2,continue;end
  a=randi(numel(x(i).nodeOrder)); b=randi(numel(x(i).nodeOrder)); x(i).nodeOrder([a b])=x(i).nodeOrder([b a]);
 elseif op==4
  x=split_random(D,routes,nt); if isempty(x),continue;end
 else
  i=randi(nr); x(i).typeIdx=randi(nt);
 end
 C=push(C,x,limit);
end
end
function x=split_random(D,routes,nt)
x=[]; eligible=find(arrayfun(@(r)numel(r.boxIdx)>1,routes)); if isempty(eligible),return;end
i=eligible(randi(numel(eligible))); b=routes(i).boxIdx(:); areas=unique(D.boxNodeIndex(b),'stable');
if rand<0.5
 moved=b(randi(numel(b)));
else
 area=areas(randi(numel(areas))); group=b(D.boxNodeIndex(b)==area);
 if numel(group)==1,moved=group;else
  take=rand(1,numel(group))<0.5; if ~any(take),take(randi(numel(take)))=true;end
  if all(take),take(randi(numel(take)))=false;end
  moved=group(take);
 end
end
remain=b(~ismember(b,moved)); if isempty(remain),return;end
src=routes(i); src.boxIdx=remain; srcNodes=unique(D.boxNodeIndex(remain),'stable'); src.nodeOrder=src.nodeOrder(ismember(src.nodeOrder,srcNodes));
new=struct('boxIdx',moved(:),'nodeOrder',unique(D.boxNodeIndex(moved),'stable'),'typeIdx',randi(nt));
x=routes; x(i)=src; if rand<0.5,x=[x(1:i-1);new;x(i:end)];else,x=[x(1:i);new;x(i+1:end)];end
end
function C=push(C,x,limit)
if numel(C)<limit,C{end+1}=x;end
end
function ok=capacity_possible(D,r)
ok=true;
for i=1:numel(r)
 b=r(i).boxIdx(:); if isempty(b)||numel(unique(b))~=numel(b),ok=false;return;end
 if any(b<1|b>height(D.boxes))||r(i).typeIdx<1||r(i).typeIdx>height(D.uav),ok=false;return;end
 u=D.uav(r(i).typeIdx,:);
 if sum(D.boxMass(b))>u.payload+D.tol.mass||sum(D.boxVolume(b))>u.volume+D.tol.volume,ok=false;return;end
 destinations=unique(D.boxNodeIndex(b),'stable');
 if numel(destinations)~=numel(r(i).nodeOrder)||~isequal(sort(destinations(:)),sort(r(i).nodeOrder(:))),ok=false;return;end
end
end
function k=objective_key(m,p), v=[m.W m.Cmax_s m.energy_kWh m.N]; k=v(p); end
function tf=lex_less(a,b)
tf=false; for i=1:numel(a), if a(i)<b(i)-1e-9,tf=true;return;elseif a(i)>b(i)+1e-9,return;end,end
end
