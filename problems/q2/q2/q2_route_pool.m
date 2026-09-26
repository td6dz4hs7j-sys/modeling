function q2_route_pool(root,mode)
% Pool MILP relaxation followed by full strict schedule decoding.
if nargin<1,root=fileparts(fileparts(mfilename('fullpath')));end
if nargin<2,mode='full';end
out=fullfile(root,'results','q2_weight_tuning','route_pool');if ~isfolder(out),mkdir(out);end
D=load_q2_data(root);[legs,~]=build_q2_leg_cache(D,root,false);
assert(abs(D.g-9.806)<1e-12&&height(D.boxes)==80);
files=collectArchives(root);[seeds,seedSources]=loadSeeds(files);assert(~isempty(seeds),'No route archives found.');
ctx=q2_fast_context(D,legs,'');fp=q2_sha256([{which('q2_route_pool')};files]);fp=[ctx.modelFingerprint fp];cachePath=fullfile(out,'route_pool_cache.mat');
[pool,cacheHit]=buildPool(D,legs,seeds,fp,cachePath);
save(fullfile(out,'pool_build.mat'),'pool','files','seedSources','fp','cacheHit','-v7.3');
fprintf('POOL candidates=%d sourceSchedules=%d cacheHit=%d\n',numel(pool),numel(seeds),cacheHit);
if strcmpi(mode,'smoke'),smoke(D,legs,seeds{1},numel(pool),out);return;end
weights=[.25 .5 .75 1];summ=cell(4,12);decodeRows=cell(0,13);best=[];
for wi=1:4
 w=weights(wi);t0=tic;[x,T,ef,op,obj,lb,gap]=solvePool(D,pool,D, w,45);milpWall=toc(t0);
 ids=find(x>.5);
 if numel(ids)~=23
  summ(wi,:)={wi,w,ef,obj,lb,gap,T,milpWall,numel(pool),0,0,'skipped_no_incumbent'};
  save(fullfile(out,sprintf('weight_%02d.mat',wi)),'w','x','T','ef','op','obj','lb','gap','milpWall','-v7.3');
  writeProgress(out,summ,decodeRows,wi);fprintf('MILP w=%.2f has no 23-route incumbent (exitflag=%d).\n',w,ef);continue;
 end
 routes=latestOrder(D,legs,poolRoutes(pool,ids));
 nPert=99;if strcmpi(mode,'short'),nPert=9;end
 variants=perturb(routes,nPert,20260925+wi);records=cell(numel(variants),1);feasibleN=0;branchBest=[];branchObj=Inf;dt=tic;
 for k=1:numel(variants)
  [S,st]=schedule_q2_routes(D,legs,variants{k});ok=false;late=NaN;why=st.reason;V=[];
  if st.feasible
   late=sum(S.boxDelivery.arrival_s>S.boxDelivery.expected_s+D.tol.time);
   if late==0
    V=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true);ok=strcmp(V.status,'PASS');why=string(V.status);
   else,why=sprintf('expectedLate=%d',late);end
  end
  if ok
   assert(S.metrics.N==23);feasibleN=feasibleN+1;val=w*S.metrics.Cmax_s/5640+(1-w)*S.metrics.energy_kWh/66;
   if val<branchObj,branchObj=val;branchBest=S;end
   if isempty(best)||S.metrics.Cmax_s<best.metrics.Cmax_s||(S.metrics.Cmax_s==best.metrics.Cmax_s&&S.metrics.energy_kWh<best.metrics.energy_kWh)
    best=S;bestV=V;bestWeight=w;bestDecode=k;
   end
  end
  records{k}=struct('feasible',ok,'T_s',S.metrics.Cmax_s,'E_kWh',S.metrics.energy_kWh,'late',late,'reason',char(why),'S',S,'V',V);
  decodeRows(end+1,:)={wi,w,k,ok,S.metrics.Cmax_s,S.metrics.energy_kWh,late,why,obj,lb,gap,milpWall,ef}; %#ok<AGROW>
 end
 decodeWall=toc(dt);refine='disabled_decode_budget';
 save(fullfile(out,sprintf('weight_%02d.mat',wi)),'w','x','T','ef','op','obj','lb','gap','milpWall','decodeWall','records','branchBest','refine','-v7.3');
 summ(wi,:)={wi,w,ef,obj,lb,gap,T,milpWall,numel(pool),feasibleN,decodeWall,refine};
 if ~isempty(branchBest)
  rv=validate_q2_solution(D,legs,branchBest,'RequireAllExpectedOnTime',true);
  if strcmp(rv.status,'PASS')&&(isempty(best)||branchBest.metrics.Cmax_s<best.metrics.Cmax_s|| ...
     (branchBest.metrics.Cmax_s==best.metrics.Cmax_s&&branchBest.metrics.energy_kWh<best.metrics.energy_kWh))
   best=branchBest;bestV=rv;bestWeight=w;bestDecode=NaN;
  end
 end
 writeProgress(out,summ,decodeRows,wi);
 fprintf('MILP w=%.2f ef=%d obj=%g lb=%g gap=%g Tlb=%.3fmin decode=%d pass=%d time=%.2fs\n',w,ef,obj,lb,gap,T/60,numel(variants),feasibleN,milpWall+decodeWall);
end
if ~isempty(best),save(fullfile(out,'best_feasible.mat'),'best','bestV','bestWeight','bestDecode','-v7.3');end
M=cell2table(summ,'VariableNames',{'branch','time_weight','exitflag','incumbent_objective','solver_lower_bound','gap','T_relax_s','milp_wall_s','pool_size','feasible_decodes','decode_wall_s','refine'});writetable(M,fullfile(out,'milp_summary.csv'));
Q=cell2table(decodeRows,'VariableNames',{'branch','time_weight','decode','strict_feasible','actual_makespan_s','actual_energy_kWh','expected_late_boxes','reason','milp_objective','solver_lower_bound','gap','milp_wall_s','exitflag'});writetable(Q,fullfile(out,'decode_audit.csv'));
writeReport(out,numel(pool),numel(files),cacheHit);
end

function f=collectArchives(root)
p=fullfile(root,'results','q2_weighted_verified');d=dir(fullfile(p,'**','solution.mat'));f=fullfile({d.folder},{d.name})';
z={fullfile(p,'q2_weighted_final.mat'),fullfile(root,'results','q2_weighted_final.mat')};f=unique([f;z(isfile(z))'],'stable');f=f(isfile(f));
end
function [seeds,src]=loadSeeds(files)
seeds={};src=cell(0,2);seen=containers.Map('KeyType','char','ValueType','logical');
for i=1:numel(files)
 try,a=load(files{i});catch,continue;end;c={};if isfield(a,'S'),c{end+1}=a.S;end;if isfield(a,'archive'),c=[c,a.archive(:)'];end
 for j=1:numel(c),if ~isstruct(c{j})||~isfield(c{j},'routes'),continue;end;r=strip(c{j}.routes);if isempty(r),continue;end;k=seedKey(r);if ~isKey(seen,k),seen(k)=true;seeds{end+1}=r;src(end+1,:)={files{i},j};end,end %#ok<AGROW>
end
end
function [pool,hit]=buildPool(D,legs,seeds,fp,path)
pool=repmat(template(),0,1);hit=false;if isfile(path),a=load(path,'fp','pool');if isfield(a,'fp')&&strcmp(a.fp,fp),pool=a.pool;hit=true;return;end,end
seen=containers.Map('KeyType','char','ValueType','logical');
for s=1:numel(seeds),for r=1:numel(seeds{s})
 boxes=seeds{s}(r).boxIdx(:);nodes=unique(D.boxNodeIndex(boxes),'stable')';orderSet=orders(nodes,seeds{s}(r).nodeOrder);
 for o=1:size(orderSet,1),ord=orderSet(o,:);for typ=1:height(D.uav)
  u=D.uav(typ,:);if sum(D.boxMass(boxes))>u.payload+D.tol.mass||sum(D.boxVolume(boxes))>u.volume+D.tol.volume,continue;end
  sig=sprintf('%s|%s|%d',sprintf('%d,',sort(boxes)),sprintf('%d,',ord),typ);if isKey(seen,sig),continue;end;seen(sig)=true;
  e=evaluate_q2_route(D,legs,boxes,ord,typ);if ~e.safe||~e.capacitySafe,continue;end
  deadline=min(D.boxes.expected_s(boxes),D.hardDeadline_s(boxes));latest=min(deadline-e.boxArrivalOffset_s);if latest< -D.tol.time,continue;end
  q=template();q.boxIdx=boxes;q.nodeOrder=ord;q.typeIdx=typ;q.energy=e.energy_kWh;q.operation=e.operation_s;q.duration=e.returnOffset_s;q.latest=latest;q.signature=sig;pool(end+1,1)=q; %#ok<AGROW>
 end,end
end,end
save(path,'fp','pool','-v7.3');
end
function p=template(),p=struct('boxIdx',[],'nodeOrder',[],'typeIdx',0,'energy',0,'operation',0,'duration',0,'latest',0,'signature','');end
function out=strip(r),out=repmat(struct('boxIdx',[],'nodeOrder',[],'typeIdx',[]),numel(r),1);for k=1:numel(r),out(k)=struct('boxIdx',r(k).boxIdx(:),'nodeOrder',r(k).nodeOrder(:)','typeIdx',r(k).typeIdx);end,end
function k=seedKey(r),a=cell(numel(r),1);for i=1:numel(r),a{i}=sprintf('%s:%s',sprintf('%d,',sort(r(i).boxIdx)),sprintf('%d,',r(i).nodeOrder));end;k=strjoin(sort(a),'|');end
function o=orders(nodes,old),old=old(ismember(old,nodes));old=[old,nodes(~ismember(nodes,old))];if numel(nodes)<=4,o=perms(nodes);else,o=[old;fliplr(old)];end;o=unique(o,'rows','stable');end
function [x,T,ef,op,obj,lb,gap]=solvePool(D,pool,~,w,limit)
n=numel(pool);f=[(1-w)*[pool.energy]'/66;w/5640];A=sparse(0,n+1);b=[];
for typ=1:height(D.uav),row=sparse(1,n+1);ix=find([pool.typeIdx]==typ);row(ix)=[pool(ix).operation];row(end)=-sum(D.uavInventory.type==D.uav.id(typ));A(end+1,:)=row;b(end+1,1)=0;end %#ok<AGROW>
for j=1:n,row=sparse(1,n+1);row(j)=[pool(j).duration];row(end)=-1;A(end+1,:)=row;b(end+1,1)=0;end %#ok<AGROW>
Aeq=sparse(height(D.boxes)+1,n+1);beq=ones(height(D.boxes)+1,1);for j=1:n,Aeq(pool(j).boxIdx,j)=1;end;Aeq(end,1:n)=1;beq(end)=23;
opts=optimoptions('intlinprog','Display','off','MaxTime',limit,'RelativeGapTolerance',.01);[z,obj,ef,op]=intlinprog(f,1:n,A,b,Aeq,beq,[zeros(n,1);0],[ones(n,1);inf],opts);
if isempty(z),x=zeros(n,1);T=NaN;obj=NaN;else,x=z(1:n);T=z(end);end;lb=NaN;gap=NaN;if isfield(op,'lowerbound'),lb=op.lowerbound;elseif isfield(op,'absolutegap')&&isfinite(obj),lb=obj-op.absolutegap;end;if isfield(op,'relativegap'),gap=op.relativegap;elseif isfinite(lb)&&isfinite(obj),gap=(obj-lb)/max(abs(obj),eps);end
end
function r=poolRoutes(p,ix),r=repmat(struct('boxIdx',[],'nodeOrder',[],'typeIdx',[]),numel(ix),1);for j=1:numel(ix),q=p(ix(j));r(j)=struct('boxIdx',q.boxIdx,'nodeOrder',q.nodeOrder,'typeIdx',q.typeIdx);end,end
function r=latestOrder(D,L,r),due=zeros(numel(r),1);for i=1:numel(r),e=evaluate_q2_route(D,L,r(i).boxIdx,r(i).nodeOrder,r(i).typeIdx);due(i)=min(min(D.boxes.expected_s(r(i).boxIdx),D.hardDeadline_s(r(i).boxIdx))-e.boxArrivalOffset_s);end;[~,ix]=sortrows([due(:),(1:numel(r))'],[1 2]);r=r(ix);end
function v=perturb(r,n,seed)
rng(seed,'twister');v={r};seen=containers.Map('KeyType','char','ValueType','logical');seen(keyOrder(r))=true;t=0;
while numel(v)<n+1&&t<40*n
 t=t+1;q=r;variant=numel(v);
 % More than half the variants only reorder sorties within one aircraft type.
 sameType=variant<=ceil(.60*n);ops=randi([1,3]);
 for opi=1:ops
  if sameType
   types=unique([q.typeIdx]);tt=types(randi(numel(types)));ix=find([q.typeIdx]==tt);
   if numel(ix)<2,continue;end
   ia=randi(numel(ix));ib=randi(numel(ix)-1);if ib>=ia,ib=ib+1;end;a=ix(ia);b=ix(ib);
  else
   a=randi(numel(q));b=randi(numel(q)-1);if b>=a,b=b+1;end
  end
  if rand<.25
   item=q(a);q(a)=[];pos=min(b,numel(q)+1);q=[q(1:pos-1);item;q(pos:end)];
  else,q([a b])=q([b a]);end
 end
 if ~sameType&&variant>ceil(.92*n)&&rand<.5,q=q(randperm(numel(q)));end
 k=keyOrder(q);if ~isKey(seen,k),seen(k)=true;v{end+1}=q;end
end
end
function k=keyOrder(r),a=cell(numel(r),1);for i=1:numel(r),a{i}=sprintf('%s/%s/%d',sprintf('%d,',r(i).boxIdx),sprintf('%d,',r(i).nodeOrder),r(i).typeIdx);end;k=strjoin(a,'|');end
function smoke(D,L,r,nPool,out)
% Exercise an actual MILP solve on the 23 archived routes, then the real decoder.
tiny=repmat(template(),numel(r),1);
for i=1:numel(r)
 sig=sprintf('%s|%s|%d',sprintf('%d,',sort(r(i).boxIdx)),sprintf('%d,',r(i).nodeOrder),r(i).typeIdx);
 e=evaluate_q2_route(D,L,r(i).boxIdx,r(i).nodeOrder,r(i).typeIdx);p=template();p.boxIdx=r(i).boxIdx;p.nodeOrder=r(i).nodeOrder;p.typeIdx=r(i).typeIdx;p.energy=e.energy_kWh;p.operation=e.operation_s;p.duration=e.returnOffset_s;p.signature=sig;tiny(i)=p;
end
[x,T,ef,op,obj,lb,gap]=solvePool(D,tiny,D,.5,5);assert(numel(find(x>.5))==23,'Smoke MILP did not select 23 routes.');
assert(all(sumRouteCover(tiny,x)==1),'Smoke MILP exact cover failed.');
for i=find(x>.5)',assert(tiny(i).duration<=T+D.tol.time);end
for typ=1:height(D.uav),ix=find([tiny.typeIdx]==typ);assert(sum([tiny(ix).operation].*x(ix)')<=sum(D.uavInventory.type==D.uav.id(typ))*T+D.tol.time);end
baseRoutes=poolRoutes(tiny,find(x>.5));[S,st]=schedule_q2_routes(D,L,latestOrder(D,L,baseRoutes));assert(st.feasible&&S.metrics.N==23);
V=validate_q2_solution(D,L,S,'RequireAllExpectedOnTime',true);assert(strcmp(V.status,'PASS'),'Smoke route chain strict validator failed.');
v=perturb(baseRoutes,9,20260924);rows=cell(10,8);
for i=1:10,[Q,ss]=schedule_q2_routes(D,L,v{i});ok=false;why=ss.reason;if ss.feasible&&all(Q.boxDelivery.arrival_s<=Q.boxDelivery.expected_s+D.tol.time),vv=validate_q2_solution(D,L,Q,'RequireAllExpectedOnTime',true);ok=strcmp(vv.status,'PASS');why=string(vv.status);end;rows(i,:)={i,ss.feasible,ok,Q.metrics.N,Q.metrics.Cmax_s,Q.metrics.energy_kWh,why,nPool};end
Z=cell2table(rows,'VariableNames',{'decode','decoderFeasible','strictPass','sorties','actual_makespan_s','actual_energy_kWh','reason','poolCandidates'});writetable(Z,fullfile(out,'smoke_10_decode.csv'));
save(fullfile(out,'smoke_milp.mat'),'tiny','x','T','ef','op','obj','lb','gap','S','V','-v7.3');fprintf('SMOKE MILP PASS pool=%d tiny=%d exitflag=%d T=%.2f strict=PASS variants=%d\n',nPool,numel(tiny),ef,T,sum(Z.strictPass));
end
function q=sumRouteCover(p,x),q=zeros(80,1);for j=1:numel(p),if x(j)>.5,q(p(j).boxIdx)=q(p(j).boxIdx)+1;end,end,end
function writeProgress(out,summ,decodeRows,n)
M=cell2table(summ(1:n,:),'VariableNames',{'branch','time_weight','exitflag','incumbent_objective','solver_lower_bound','gap','T_relax_s','milp_wall_s','pool_size','feasible_decodes','decode_wall_s','refine'});writetable(M,fullfile(out,'milp_summary.csv'));
if ~isempty(decodeRows),Q=cell2table(decodeRows,'VariableNames',{'branch','time_weight','decode','strict_feasible','actual_makespan_s','actual_energy_kWh','expected_late_boxes','reason','milp_objective','solver_lower_bound','gap','milp_wall_s','exitflag'});writetable(Q,fullfile(out,'decode_audit.csv'));end
end
function writeReport(out,nPool,nFiles,hit),f=fopen(fullfile(out,'route_pool_report.md'),'w');c=onCleanup(@()fclose(f));fprintf(f,'# Q2 route-pool search\n\nPool candidates: %d\n\nArchive files: %d\n\nCache reused: %d\n\nFour weighted MILP relaxations, 45 seconds each; each uses at most 100 seeded order perturbations after the latest-allowable-start ordering. Every actual T/E is in decode_audit.csv. The solver bound applies only to this route pool and workload relaxation, not to the original Q2 problem.\n',nPool,nFiles,hit);end
