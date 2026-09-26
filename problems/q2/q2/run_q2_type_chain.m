function run_q2_type_chain(root)
% Simultaneous C->B and B->A reassignment with exhaustive pair insertion.
x=load(fullfile(root,'results','q2_all_ontime','q2_final_solution.mat'),'D','legs');
a=load(fullfile(root,'results','q2_time_23_cap','start_1','q2_seed_20261026_best.mat'),'best');
D=x.D;legs=x.legs;S0=a.best;
v=validate_q2_solution(D,legs,S0,'RequireAllExpectedOnTime',true);
assert(strcmp(v.status,'PASS')&&S0.metrics.N==23,'23-route chain start invalid.');
out=fullfile(root,'results','q2_time_23_cap','type_chain');if ~isfolder(out),mkdir(out);end
routes=strip(S0.routes);n=numel(routes);
typ=string(D.uav.id);ai=find(typ=="A");bi=find(typ=="B");ci=find(typ=="C");
canC=find(arrayfun(@(r)r.typeIdx==ci&&fits(D,r,bi),routes));
canB=find(arrayfun(@(r)r.typeIdx==bi&&fits(D,r,ai),routes));
assert(~isempty(canC)&&~isempty(canB),'No C-to-B or B-to-A type transfer candidate.');
ctx=q2_fast_context(D,legs,fullfile(root,'cache','route_cache.mat'));
best=S0;bestRoute=[];tested=0;feasible=0;onTime=0;rows=cell(0,5);
for c=canC(:)'
 for b=canB(:)'
  changed=routes;changed(c).typeIdx=bi;changed(b).typeIdx=ai;
  others=setdiff(1:n,[c,b],'stable');
  for p1=1:n
   for p2=1:n
    if p1==p2,continue;end
    order=zeros(1,n);order(p1)=c;order(p2)=b;order(order==0)=others;
    candidate=changed(order);tested=tested+1;
    [F,ctx]=q2_fast_schedule(D,legs,candidate,ctx);
    if ~F.feasible,continue;end
    feasible=feasible+1;
    if F.metrics.W>D.tol.time,continue;end
    onTime=onTime+1;
    key=[F.metrics.Cmax_s,F.metrics.energy_kWh];old=[best.metrics.Cmax_s,best.metrics.energy_kWh];
    if lexLess(key,old)
     bestRoute=candidate;
     [best,status]=schedule_q2_routes(D,legs,bestRoute);
     assert(status.feasible,'Fast/full feasibility mismatch.');
     v=validate_q2_solution(D,legs,best,'RequireAllExpectedOnTime',true);
     assert(strcmp(v.status,'PASS'),'Type-chain candidate failed strict audit.');
     rows(end+1,:)={c,b,p1,p2,best.metrics.Cmax_s}; %#ok<AGROW>
     fprintf('TYPE CHAIN: Croute=%d Broute=%d pos=(%d,%d) N=%d Cmax=%.3f E=%.6f\n', ...
      c,b,p1,p2,best.metrics.N,best.metrics.Cmax_s,best.metrics.energy_kWh);
    end
   end
  end
 end
end
V=validate_q2_solution(D,legs,best,'RequireAllExpectedOnTime',true);
assert(strcmp(V.status,'PASS'),'Best type-chain solution failed strict audit.');
T=cell2table(rows,'VariableNames',{'old_C_route','old_B_route','new_C_position','new_B_position','Cmax_s'});
writetable(T,fullfile(out,'q2_type_chain_improvements.csv'));
save(fullfile(out,'q2_type_chain_final.mat'),'best','V','T','canC','canB','tested','feasible','onTime','-v7.3');
fprintf('TYPE CHAIN FINAL: N=%d Cmax=%.3f E=%.6f tested=%d feasible=%d ontime=%d target7200=%d\n', ...
 best.metrics.N,best.metrics.Cmax_s,best.metrics.energy_kWh,tested,feasible,onTime, ...
 best.metrics.Cmax_s<=7200+D.tol.time);
end

function tf=fits(D,r,k)
idx=r.boxIdx(:);u=D.uav(k,:);
tf=sum(D.boxMass(idx))<=u.payload+D.tol.mass && ...
 sum(D.boxVolume(idx))<=u.volume+D.tol.volume;
end
function routes=strip(r)
routes=repmat(struct('boxIdx',[],'nodeOrder',[],'typeIdx',[]),numel(r),1);
for p=1:numel(r)
 routes(p)=struct('boxIdx',r(p).boxIdx(:),'nodeOrder',r(p).nodeOrder(:)','typeIdx',r(p).typeIdx);
end
end
function tf=lexLess(a,b)
tf=false;
for k=1:numel(a)
 if a(k)<b(k)-1e-9,tf=true;return;
 elseif a(k)>b(k)+1e-9,return;end
end
end
