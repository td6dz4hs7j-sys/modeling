function run_q2_time94(root)
% Time-first search at exactly 23 sorties. Energy reference is not a constraint.
x=load(fullfile(root,'results','q2_all_ontime','q2_final_solution.mat'),'D','legs','baseline');
D=x.D;legs=x.legs;baseline=x.baseline;
paths={fullfile(root,'results','q2_current','q2_current_solution.mat'), ...
 fullfile(root,'results','q2_energy_22_23','published_n23','q2_energy_solution.mat'), ...
 fullfile(root,'results','q2_time_23_cap','type_chain','q2_type_chain_final.mat')};
out=fullfile(root,'results','q2_time94');if ~isfolder(out),mkdir(out);end
best=[];bounds=cell(3,4);rng(20261110);
ctx=q2_fast_context(D,legs); % Avoid expensive disk cache serialization during search.
for source=1:3
 a=load(paths{source});if isfield(a,'S'),S0=a.S;else,S0=a.best;end
 v=validate_q2_solution(D,legs,S0,'RequireAllExpectedOnTime',true);assert(strcmp(v.status,'PASS'));
 if isempty(best)||S0.metrics.Cmax_s<best.metrics.Cmax_s,best=S0;end
 r=strip(S0.routes);n=numel(r);assert(n==23);
 opts=cell(n,1);duration=[];energy=[];rr=[];tt=[];
 for i=1:n
  opts{i}=struct('typeIdx',{},'nodeOrder',{});
  order=perms(r(i).nodeOrder);if size(order,1)>120,order=order(1:120,:);end
  for t=1:height(D.uav)
   if sum(D.boxMass(r(i).boxIdx))>D.uav.payload(t)+D.tol.mass||sum(D.boxVolume(r(i).boxIdx))>D.uav.volume(t)+D.tol.volume,continue;end
   for j=1:size(order,1)
    ev=evaluate_q2_route(D,legs,r(i).boxIdx,order(j,:),t);
    if ~ev.safe,continue;end
    opts{i}(end+1)=struct('typeIdx',t,'nodeOrder',order(j,:));
    rr(end+1)=i;tt(end+1)=t;duration(end+1)=ev.operation_s;energy(end+1)=ev.energy_kWh;
   end
  end
 end
 m=numel(rr);Aeq=zeros(n,m+1);A=zeros(3,m+1);
 for j=1:m,Aeq(rr(j),j)=1;A(tt(j),j)=duration(j);end
 for t=1:3,A(t,end)=-sum(D.uavInventory.type==D.uav.id(t));end
 f=zeros(m+1,1);f(end)=1;
 [z,lb,flag,output]=intlinprog(f,1:m,A,zeros(3,1),Aeq,ones(n,1),zeros(m+1,1),[ones(m,1);Inf], ...
  optimoptions('intlinprog','Display','off','MaxTime',30,'RelativeGapTolerance',1e-8));
 assert(flag>0,'Workload-bound MILP did not certify a solution.');
 certifiedLB=lb-output.absolutegap;
 bounds(source,:)={source,certifiedLB,certifiedLB/60,certifiedLB>94*60};
 fprintf('SOURCE %d fixed-group best-type workload lower bound %.3f min\n',source,certifiedLB/60);
 current=r;score=S0.metrics.Cmax_s;bestLocal=score;
 for iter=1:6000
  cand=current;
  if mod(iter,1000)==1
   cand=r;
   if iter>1
    for i=1:n
     chosen=find(rr==i & z(1:m)'>0.5,1);local=find(find(rr==i)==chosen,1);
     cand(i).typeIdx=opts{i}(local).typeIdx;cand(i).nodeOrder=opts{i}(local).nodeOrder;
    end
   end
  else
   op=randi(4);i=randi(n);j=randi(n);
   if op==1,cand([i j])=cand([j i]);
   elseif op==2,item=cand(i);cand(i)=[];cand=[cand(1:j-1);item;cand(j:end)];
   else
    original=find(arrayfun(@(q)isequal(sort(q.boxIdx),sort(cand(i).boxIdx)),r),1);
    o=opts{original}(randi(numel(opts{original})));cand(i).typeIdx=o.typeIdx;cand(i).nodeOrder=o.nodeOrder;
    if op==4
     original=find(arrayfun(@(q)isequal(sort(q.boxIdx),sort(cand(j).boxIdx)),r),1);
     o=opts{original}(randi(numel(opts{original})));cand(j).typeIdx=o.typeIdx;cand(j).nodeOrder=o.nodeOrder;
    end
   end
  end
  [F,ctx]=q2_fast_schedule(D,legs,cand,ctx);
  if F.feasible&&F.metrics.W<=D.tol.time
   val=F.metrics.Cmax_s;temperature=120*(1-mod(iter-1,1000)/1000)+1;
   if val<score||rand<exp((score-val)/temperature),current=cand;score=val;end
   if val<best.metrics.Cmax_s-D.tol.time|| ...
     (abs(val-best.metrics.Cmax_s)<=D.tol.time&&F.metrics.energy_kWh<best.metrics.energy_kWh-D.tol.energy)
    [candidate,st]=schedule_q2_routes(D,legs,cand);assert(st.feasible);
    V=validate_q2_solution(D,legs,candidate,'RequireAllExpectedOnTime',true);assert(strcmp(V.status,'PASS'));
    best=candidate;save(fullfile(out,'best_checkpoint.mat'),'best','V');
    fprintf('IMPROVE source=%d iter=%d N=23 Cmax=%.3f E=%.6f PASS\n',source,iter,val,best.metrics.energy_kWh);
   end
   bestLocal=min(bestLocal,val);
  end
  if mod(iter,1000)==0,fprintf('source=%d iter=%d local=%.3f global=%.3f\n',source,iter,bestLocal,best.metrics.Cmax_s);end
 end
end
S=best;V=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true);assert(strcmp(V.status,'PASS'));
R=struct('trace',table(),'summary',table());
save(fullfile(out,'q2_time94_final.mat'),'S','V','bounds','-v7.3');
writetable(cell2table(bounds,'VariableNames',{'source','fixed_group_bound_s','bound_min','above94'}),fullfile(out,'conditional_bounds.csv'));
write_q2_validation(V,fullfile(out,'q2_final_validation.json'));
export_q2_results(D,legs,S,baseline,R,out);
fprintf('FINAL N=%d Cmax=%.3f min E=%.6f PASS; 94min achieved=%d\n',S.metrics.N,S.metrics.Cmax_s/60,S.metrics.energy_kWh,S.metrics.Cmax_s<=5640);
end
function r=strip(routes)
r=repmat(struct('boxIdx',[],'nodeOrder',[],'typeIdx',[]),numel(routes),1);
for i=1:numel(r),r(i)=struct('boxIdx',routes(i).boxIdx(:),'nodeOrder',routes(i).nodeOrder(:)','typeIdx',routes(i).typeIdx);end
end
