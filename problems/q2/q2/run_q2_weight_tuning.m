function run_q2_weight_tuning(root,mode)
% Bounded weighted Q2 search. Physical model and hard constraints are unchanged.
if nargin<1||isempty(root),root=fileparts(fileparts(mfilename('fullpath')));end
if nargin<2,mode='full';end
assert(ismember(string(mode),["full","smoke"]),'mode must be full or smoke');
addpath(fullfile(root,'q2'),fullfile(root,'common'),fullfile(root,'utils'));
D=load_q2_data(root);[legs,cacheMeta]=build_q2_leg_cache(D,root,false);
assert(abs(D.g-9.806)<1e-12&&height(D.boxes)==80);
out=fullfile(root,'results','q2_weight_tuning',mode);if ~isfolder(out),mkdir(out);end
names=["balanced","fastest","energy6714","within120"];
weights=[.25,.5,.75,NaN];seeds=20261201:20261204;
sources=cell(4,1);for k=1:4,a=load(fullfile(root,'results','q2_weighted_verified',names(k),'solution.mat'),'S');sources{k}=a.S;end
ctx=q2_fast_context(D,legs,'');workCache=containers.Map('KeyType','char','ValueType','double');
if strcmp(mode,'smoke'),caps=25*ones(1,4);else,caps=6000*ones(1,4);end
summaryRows=cell(4,10);pareto=[];
for b=1:4
    rng(seeds(b),'twister');[startRoutes,startS,startSource]=select_start(D,legs,sources,names,weights(b));
    bestRoutes=startRoutes;current=startRoutes;bestS=startS;
    bestScore=score_metrics(bestS.metrics,weights(b));currentScore=bestScore;
    branch=branch_name(b,weights(b));bd=fullfile(out,branch);if ~isfolder(bd),mkdir(bd);end
    cap=caps(b);blockSize=1000;nBlocks=ceil(cap/blockSize);stale=0;lastBlockBest=bestScore;
    trace=cell(cap,17);nTrace=0;blocks=cell(nBlocks,8);nBlocksDone=0;ticBranch=tic;
    for iter=1:cap
        reason="";cand=[];F=[];accepted=false;improved=false;
        try
            if rand<.5,[cand,reason,workCache]=directed_transfer(D,legs,current,workCache);
            else,cand=legacy_mutate(D,current);if isempty(cand),reason="legacy_mutation_invalid";end,end
        catch ME,cand=[];reason="mutation_error:"+string(ME.identifier);end
        candMetrics=nan_metrics();candScore=NaN;
        if isempty(cand)
            if strlength(reason)==0,reason="empty_candidate";end
        else
            [F,ctx]=q2_fast_schedule(D,legs,cand,ctx);
            if ~F.feasible,reason="fast_infeasible:"+string(F.reason);
            elseif F.metrics.N~=23,candMetrics=F.metrics;reason="sortie_count_not_23";
            elseif abs(F.metrics.W)>D.tol.time,candMetrics=F.metrics;reason="expected_deadline_miss";
            else
                candMetrics=F.metrics;candScore=score_metrics(F.metrics,weights(b));
                temp=.012*(1-mod(iter-1,1000)/1000)+.00002;
                if candScore<currentScore||rand<exp(min(0,(currentScore-candScore)/temp))
                    current=cand;currentScore=candScore;accepted=true;reason="feasible_accepted_current";
                else,reason="feasible_rejected_annealing";end
                if candScore<bestScore-1e-11
                    [candidateS,status]=schedule_q2_routes(D,legs,cand);
                    assert(status.feasible&&candidateS.metrics.N==23&&abs(candidateS.metrics.W)<=D.tol.time,...
                        'Fast/full schedule disagreed or fixed constraints failed: %s',status.reason);
                    V=validate_q2_solution(D,legs,candidateS,'RequireAllExpectedOnTime',true);
                    assert(strcmp(V.status,'PASS'),'Fresh validator rejected candidate: %s',strjoin(V.issues,'; '));
                    assert(abs(candidateS.metrics.Cmax_s-F.metrics.Cmax_s)<=D.tol.time&&...
                        abs(candidateS.metrics.energy_kWh-F.metrics.energy_kWh)<=D.tol.energy,...
                        'Fast/full candidate metric mismatch');
                    bestS=candidateS;bestRoutes=cand;bestScore=candScore;improved=true;
                    reason=reason+";strict_validator_PASS";
                    pareto(end+1,:)=[bestS.metrics.Cmax_s,bestS.metrics.energy_kWh,b,bestScore]; %#ok<AGROW>
                end
            end
        end
        nTrace=nTrace+1;
        trace(nTrace,:)={iter,seeds(b),string(branch),reason,candScore,...
            metric(candMetrics,'Cmax_s'),metric(candMetrics,'energy_kWh'),metric(candMetrics,'W'),...
            accepted,currentScore,bestScore,improved,bestS.metrics.Cmax_s,bestS.metrics.energy_kWh,...
            elapsed(F),fastval(F,'cacheHits'),fastval(F,'cacheMisses')};
        % Every attempt counts. Block logging/checkpoint is outside all rejection paths.
        if mod(iter,blockSize)==0||iter==cap
            if bestScore<lastBlockBest-1e-6,stale=0;else,stale=stale+1;end
            lastBlockBest=bestScore;nBlocksDone=nBlocksDone+1;
            blocks(nBlocksDone,:)={iter,bestScore,bestS.metrics.Cmax_s,bestS.metrics.energy_kWh,...
                stale,ctx.routeCache.Count,toc(ticBranch),"saved"};
            writetable(trace_table(trace(1:nTrace,:)),fullfile(bd,'attempts.csv'));
            writetable(block_table(blocks(1:nBlocksDone,:)),fullfile(bd,'blocks.csv'));
            rngState=rng;checkpoint=struct('branch',branch,'seed',seeds(b),'completedAttempts',iter,...
                'startSource',startSource,'startMetrics',startS.metrics,'bestScore',bestScore,...
                'bestRoutes',bestRoutes,'bestS',bestS,'currentRoutes',current,'currentScore',currentScore,...
                'rngState',rngState,'modelFingerprint',ctx.modelFingerprint); %#ok<NASGU>
            tmp=fullfile(bd,'checkpoint.tmp.mat');save(tmp,'checkpoint','-v7.3');movefile(tmp,fullfile(bd,'checkpoint.mat'),'f');
            fprintf('%s %d/%d best=%.9f T=%.3f E=%.6f stale=%d\n',branch,iter,cap,bestScore,...
                bestS.metrics.Cmax_s/60,bestS.metrics.energy_kWh,stale);
            if strcmp(mode,'full')&&stale>=3,break;end
        end
    end
    V=validate_q2_solution(D,legs,bestS,'RequireAllExpectedOnTime',true);assert(bestS.metrics.N==23&&strcmp(V.status,'PASS'));
    save(fullfile(bd,'best.mat'),'bestS','V','bestRoutes','bestScore','startS','startSource','-v7.3');
    summaryRows(b,:)={branch,weights(b),1-weights(b),startSource,startS.metrics.Cmax_s/60,...
        startS.metrics.energy_kWh,bestS.metrics.Cmax_s/60,bestS.metrics.energy_kWh,bestScore,nTrace};
    pareto(end+1,:)=[bestS.metrics.Cmax_s,bestS.metrics.energy_kWh,b,bestScore]; %#ok<AGROW>
end
summary=cell2table(summaryRows,'VariableNames',{'branch','time_weight','energy_weight','start_source',...
    'start_makespan_min','start_energy_kWh','best_makespan_min','best_energy_kWh','best_score','attempts'});
writetable(summary,fullfile(out,'weight_summary.csv'));
pt=table(pareto(:,1)/60,pareto(:,2),pareto(:,3),pareto(:,4),'VariableNames',...
    {'makespan_min','energy_kWh','branch_id','score'});keep=pareto_mask(pt.makespan_min,pt.energy_kWh);
pt=pt(keep,:);writetable(pt,fullfile(out,'pareto_front.csv'));
save(fullfile(out,'q2_weight_tuning.mat'),'D','cacheMeta','summary','pt','weights','seeds','mode','-v7.3');
end

function [routes,S,source]=select_start(D,legs,sources,names,w)
scores=inf(4,1);verified=cell(4,1);
for k=1:4
 [q,st]=schedule_q2_routes(D,legs,strip_routes(sources{k}.routes));
 if st.feasible&&q.metrics.N==23
  V=validate_q2_solution(D,legs,q,'RequireAllExpectedOnTime',true);
  if strcmp(V.status,'PASS'),scores(k)=score_metrics(q.metrics,w);verified{k}=q;end
 end
end
[~,ix]=min(scores);assert(isfinite(scores(ix)),'No verified 23-sortie warm start');
S=verified{ix};routes=strip_routes(S.routes);source=names(ix);
end
function name=branch_name(b,w),if b<4,name=sprintf('w_%02d',round(100*w));else,name='target_deviation';end,end
function x=score_metrics(m,w)
t=m.Cmax_s/5640;e=m.energy_kWh/66;if isnan(w),x=max(t-1,e-1)+.01*(t+e);else,x=w*t+(1-w)*e;end
end

function [cand,reason,workCache]=directed_transfer(D,legs,current,workCache)
cand=[];reason="directed_BC_to_A";inv=zeros(3,1);work=zeros(3,1);
for t=1:3,inv(t)=sum(D.uavInventory.type==D.uav.id(t));end
for r=1:numel(current)
    [op,workCache]=route_work(D,legs,current(r),workCache);
    work(current(r).typeIdx)=work(current(r).typeIdx)+op;
end
load=work./inv;[~,srcType]=max(load(2:3));srcType=srcType+1;
if load(srcType)<=load(1)+eps,reason="directed_no_BC_overload";return;end
src=find([current.typeIdx]==srcType);dst=find([current.typeIdx]==1);
if isempty(src)||isempty(dst),reason="directed_no_source_or_A_receiver";return;end
[dur,workCache]=source_route_durations(D,legs,current,src,workCache);
[~,q]=max(dur);i=src(q);j=dst(randi(numel(dst)));if numel(current(i).boxIdx)<2,reason="directed_source_single_box";return;end
b=current(i).boxIdx(randi(numel(current(i).boxIdx)));cand=current;
cand(i).boxIdx(cand(i).boxIdx==b)=[];cand(j).boxIdx(end+1)=b;
cand(i)=refresh_nodes(D,cand(i));cand(j)=refresh_nodes(D,cand(j));
if ~type_safe(D,legs,cand(j),1),cand=[];reason="directed_A_capacity_or_energy";return;end
cand(j).typeIdx=1;
[sourceType,ok]=fastest_safe_type(D,legs,cand(i));
if ~ok,cand=[];reason="directed_source_capacity_or_energy";return;end
cand(i).typeIdx=sourceType;
end
function [dur,cache]=source_route_durations(D,legs,current,src,cache)
dur=zeros(numel(src),1);for k=1:numel(src),[dur(k),cache]=route_work(D,legs,current(src(k)),cache);end
end
function [op,cache]=route_work(D,legs,r,cache)
key=sprintf('b=%s|n=%s|t=%d',sprintf('%d,',sort(r.boxIdx)),sprintf('%d,',r.nodeOrder),r.typeIdx);
if isKey(cache,key),op=cache(key);else,ev=evaluate_q2_route(D,legs,r.boxIdx,r.nodeOrder,r.typeIdx);op=ev.operation_s;cache(key)=op;end
end
function r=refresh_nodes(D,r)
n=unique(D.boxNodeIndex(r.boxIdx),'stable')';old=r.nodeOrder;r.nodeOrder=[old(ismember(old,n)),n(~ismember(n,old))];
if rand<.25&&numel(n)>1,r.nodeOrder=r.nodeOrder(randperm(numel(n)));end
end
function tf=type_safe(D,legs,r,t)
u=D.uav(t,:);ix=r.boxIdx;tf=sum(D.boxMass(ix))<=u.payload+D.tol.mass&&sum(D.boxVolume(ix))<=u.volume+D.tol.volume;
if tf,ev=evaluate_q2_route(D,legs,ix,r.nodeOrder,t);tf=ev.capacitySafe&&ev.safe;end
end
function [tBest,ok]=fastest_safe_type(D,legs,r)
tBest=NaN;best=Inf;ok=false;types=capacity_types(D,r.boxIdx);
for t=types(:)'
    ev=evaluate_q2_route(D,legs,r.boxIdx,r.nodeOrder,t);
    if ev.safe&&ev.capacitySafe&&ev.operation_s<best,best=ev.operation_s;tBest=t;ok=true;end
end
end

function cand=legacy_mutate(D,current)
cand=current;n=numel(cand);i=randi(n);j=randi(n-1);if j>=i,j=j+1;end;op=randi(7);
if op<=3||op==7
 if op==1
  if numel(cand(i).boxIdx)<2,cand=[];return;end;k=randi(numel(cand(i).boxIdx));b=cand(i).boxIdx(k);cand(i).boxIdx(k)=[];cand(j).boxIdx(end+1)=b;
 elseif op==7
  pool=[cand(i).boxIdx(:);cand(j).boxIdx(:)];if numel(pool)<2,cand=[];return;end;pool=pool(randperm(numel(pool)));take=randi(numel(pool)-1);cand(i).boxIdx=pool(1:take);cand(j).boxIdx=pool(take+1:end);
 else
  if isempty(cand(i).boxIdx)||isempty(cand(j).boxIdx),cand=[];return;end;p=randi(numel(cand(i).boxIdx));q=randi(numel(cand(j).boxIdx));[cand(i).boxIdx(p),cand(j).boxIdx(q)]=deal(cand(j).boxIdx(q),cand(i).boxIdx(p));
 end
 for k=[i j],cand(k)=refresh_nodes(D,cand(k));types=capacity_types(D,cand(k).boxIdx);if isempty(types),cand=[];return;end;if ~ismember(cand(k).typeIdx,types)||rand<.45,cand(k).typeIdx=types(randi(numel(types)));end,end
elseif op==4,cand([i j])=cand([j i]);
elseif op==5
 types=capacity_types(D,cand(i).boxIdx);if isempty(types),cand=[];return;end;cand(i).typeIdx=types(randi(numel(types)));
 if rand<.5,types=capacity_types(D,cand(j).boxIdx);if isempty(types),cand=[];return;end;cand(j).typeIdx=types(randi(numel(types)));end
else
 cand(i).nodeOrder=cand(i).nodeOrder(randperm(numel(cand(i).nodeOrder)));item=cand(j);cand(j)=[];cand=[cand(1:i-1);item;cand(i:end)];
end
end
function t=capacity_types(D,ix)
t=find(sum(D.boxMass(ix))<=D.uav.payload+D.tol.mass&sum(D.boxVolume(ix))<=D.uav.volume+D.tol.volume);
end
function r=strip_routes(routes)
r=repmat(struct('boxIdx',[],'nodeOrder',[],'typeIdx',[]),numel(routes),1);
for i=1:numel(routes),r(i)=struct('boxIdx',routes(i).boxIdx(:),'nodeOrder',routes(i).nodeOrder(:)','typeIdx',routes(i).typeIdx);end
end
function m=nan_metrics(),m=struct('W',NaN,'Cmax_s',NaN,'energy_kWh',NaN,'N',NaN);end
function v=metric(m,n),if isempty(m)||~isfield(m,n),v=NaN;else,v=m.(n);end,end
function v=elapsed(F),if isempty(F)||~isfield(F,'elapsedSeconds'),v=NaN;else,v=F.elapsedSeconds;end,end
function v=fastval(F,n),if isempty(F)||~isfield(F,n),v=NaN;else,v=F.(n);end,end
function T=trace_table(c)
T=cell2table(c,'VariableNames',{'attempt','seed','branch','reason','candidate_score','candidate_makespan_s',...
 'candidate_energy_kWh','candidate_W','accepted_current','current_score','best_score','best_improved',...
 'best_makespan_s','best_energy_kWh','candidate_elapsed_s','cache_hits','cache_misses'});
end
function T=block_table(c)
T=cell2table(c,'VariableNames',{'completed_attempts','best_score','best_makespan_s','best_energy_kWh','stale_blocks','cache_entries','elapsed_s','status'});
end
function keep=pareto_mask(t,e)
keep=true(size(t));for i=1:numel(t),keep(i)=~any(t<=t(i)+1e-8&e<=e(i)+1e-9&(t<t(i)-1e-8|e<e(i)-1e-9));end
end
