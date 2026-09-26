function run_q2_regroup_time(root,seed)
% Exactly 23 sorties; time-first annealing with box relocation, swap and type repair.
x=load(fullfile(root,'results','q2_all_ontime','q2_final_solution.mat'),'D','legs','baseline');
if nargin<2,seed=20261111;end
prior=fullfile(root,'results','q2_time94','regroup','q2_regroup_final.mat');
if seed~=20261111&&isfile(prior),a=load(prior,'S');
else,a=load(fullfile(root,'results','q2_time94','q2_time94_final.mat'),'S');end
D=x.D;legs=x.legs;baseline=x.baseline;best=a.S;
ctx=q2_fast_context(D,legs);rng(seed);
out=fullfile(root,'results','q2_time94','regroup');if ~isfolder(out),mkdir(out);end
current=strip(best.routes);score=best.metrics.Cmax_s;rows=[];
for iter=1:16000
 if mod(iter-1,2000)==0,current=strip(best.routes);score=best.metrics.Cmax_s;end
 cand=current;n=numel(cand);i=randi(n);j=randi(n-1);if j>=i,j=j+1;end
op=randi(7);
 if op<=3||op==7
  if op==1
   if numel(cand(i).boxIdx)<2,continue;end
   k=randi(numel(cand(i).boxIdx));b=cand(i).boxIdx(k);cand(i).boxIdx(k)=[];cand(j).boxIdx(end+1)=b;
  elseif op==7
   pool=[cand(i).boxIdx(:);cand(j).boxIdx(:)];pool=pool(randperm(numel(pool)));
   take=randi(numel(pool)-1);cand(i).boxIdx=pool(1:take);cand(j).boxIdx=pool(take+1:end);
  else
   p=randi(numel(cand(i).boxIdx));q=randi(numel(cand(j).boxIdx));
   [cand(i).boxIdx(p),cand(j).boxIdx(q)]=deal(cand(j).boxIdx(q),cand(i).boxIdx(p));
  end
  legal=true;
  for k=[i j]
   nodes=unique(D.boxNodeIndex(cand(k).boxIdx),'stable')';
   old=cand(k).nodeOrder;cand(k).nodeOrder=[old(ismember(old,nodes)),nodes(~ismember(nodes,old))];
   if rand<.3,cand(k).nodeOrder=cand(k).nodeOrder(randperm(numel(nodes)));end
   types=find(sum(D.boxMass(cand(k).boxIdx))<=D.uav.payload+D.tol.mass & ...
     sum(D.boxVolume(cand(k).boxIdx))<=D.uav.volume+D.tol.volume);
   if isempty(types),legal=false;break;end
   if ~ismember(cand(k).typeIdx,types)||rand<.45,cand(k).typeIdx=types(randi(numel(types)));end
  end
  if ~legal,continue;end
 elseif op==4
  cand([i j])=cand([j i]);
 elseif op==5
  cand(i).typeIdx=randi(3);if rand<.5,cand(j).typeIdx=randi(3);end
 else
  cand(i).nodeOrder=cand(i).nodeOrder(randperm(numel(cand(i).nodeOrder)));
  item=cand(j);cand(j)=[];cand=[cand(1:i-1);item;cand(i:end)];
 end
 [F,ctx]=q2_fast_schedule(D,legs,cand,ctx);
 if F.feasible&&F.metrics.W<=D.tol.time
  val=F.metrics.Cmax_s;temp=65*(1-mod(iter-1,2000)/2000)+.1;
  if val<score||rand<exp((score-val)/temp),current=cand;score=val;end
  if val<best.metrics.Cmax_s-D.tol.time|| ...
    (abs(val-best.metrics.Cmax_s)<=D.tol.time&&F.metrics.energy_kWh<best.metrics.energy_kWh-D.tol.energy)
   [S,st]=schedule_q2_routes(D,legs,cand);assert(st.feasible);
   V=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true);assert(strcmp(V.status,'PASS'));
   best=S;rows(end+1,:)=[iter,val,S.metrics.energy_kWh]; %#ok<AGROW>
   save(fullfile(out,'best_checkpoint.mat'),'best','V');
   fprintf('REGROUP %d: Cmax=%.3f min E=%.6f N=23 PASS\n',iter,val/60,S.metrics.energy_kWh);
  end
 end
 if mod(iter,1000)==0,fprintf('REGROUP iter=%d best=%.3f min\n',iter,best.metrics.Cmax_s/60);end
end
S=best;V=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true);assert(strcmp(V.status,'PASS'));
R=struct('trace',table(),'summary',table());
save(fullfile(out,'q2_regroup_final.mat'),'S','V','rows','-v7.3');
write_q2_validation(V,fullfile(out,'q2_final_validation.json'));
tests=test_q2_mutations(D,legs,S,'RequireAllExpectedOnTime',true);assert(all(tests.rejected));
writetable(tests,fullfile(out,'q2_strict_mutation_tests.csv'));
export_q2_results(D,legs,S,baseline,R,out);
fprintf('REGROUP FINAL N=23 Cmax=%.6f min E=%.6f PASS\n',S.metrics.Cmax_s/60,S.metrics.energy_kWh);
end
function r=strip(routes)
r=repmat(struct('boxIdx',[],'nodeOrder',[],'typeIdx',[]),numel(routes),1);
for i=1:numel(r),r(i)=struct('boxIdx',routes(i).boxIdx(:),'nodeOrder',routes(i).nodeOrder(:)','typeIdx',routes(i).typeIdx);end
end
