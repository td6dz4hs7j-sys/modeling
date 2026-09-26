function run_q2_split_energy_23(root)
% Check every single-box route split from the best 22-sortie energy schedule.
x=load(fullfile(root,'results','q2_all_ontime','q2_final_solution.mat'),'D','legs');
a=load(fullfile(root,'results','q2_energy_22_23','n22','q2_energy_best.mat'),'S');
b=load(fullfile(root,'results','q2_energy_22_23','n23','q2_energy_best.mat'),'S');
D=x.D;legs=x.legs;src=a.S;best=b.S;
assert(src.metrics.N==22&&best.metrics.N==23);
assert(strcmp(validate_q2_solution(D,legs,src,'RequireAllExpectedOnTime',true).status,'PASS'));
assert(strcmp(validate_q2_solution(D,legs,best,'RequireAllExpectedOnTime',true).status,'PASS'));
out=fullfile(root,'results','q2_energy_22_23','split_search');if ~isfolder(out),mkdir(out);end
r0=strip(src.routes);ctx=q2_fast_context(D,legs,fullfile(root,'cache','route_cache.mat'));
tested=0;feasible=0;onTime=0;improved=0;
for i=1:numel(r0)
 boxes=r0(i).boxIdx(:);
 if numel(boxes)<2,continue;end
 for j=1:numel(boxes)
  moved=boxes(j);remain=boxes;remain(j)=[];
  r=r0;r(i).boxIdx=remain;
  nodes=unique(D.boxNodeIndex(remain),'stable');
  r(i).nodeOrder=r(i).nodeOrder(ismember(r(i).nodeOrder,nodes));
  new=struct('boxIdx',moved,'nodeOrder',D.boxNodeIndex(moved),'typeIdx',1);
  for t=1:height(D.uav)
   new.typeIdx=t;
   if D.boxMass(moved)>D.uav.payload(t)+D.tol.mass|| ...
     D.boxVolume(moved)>D.uav.volume(t)+D.tol.volume,continue;end
   for p=1:numel(r)+1
    cand=[r(1:p-1);new;r(p:end)];tested=tested+1;
    [F,ctx]=q2_fast_schedule(D,legs,cand,ctx);
    if ~F.feasible,continue;end
    feasible=feasible+1;
    if F.metrics.W>D.tol.time,continue;end
    onTime=onTime+1;
    if F.metrics.energy_kWh<best.metrics.energy_kWh-D.tol.energy
     [S,status]=schedule_q2_routes(D,legs,cand);
     assert(status.feasible,'Fast/full mismatch.');
     V=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true);
     assert(strcmp(V.status,'PASS'),'Split candidate fails strict audit.');
     best=S;improved=improved+1;
     fprintf('SPLIT ENERGY 23: E=%.6f Cmax=%.3f source=%d box=%d type=%d pos=%d\n', ...
      best.metrics.energy_kWh,best.metrics.Cmax_s,i,moved,t,p);
    end
   end
  end
 end
end
V=validate_q2_solution(D,legs,best,'RequireAllExpectedOnTime',true);
assert(strcmp(V.status,'PASS'));
save(fullfile(out,'q2_split_energy_23.mat'),'best','V','tested','feasible','onTime','improved','-v7.3');
fprintf('SPLIT 23 FINAL: N=%d E=%.6f Cmax=%.3f tested=%d feasible=%d ontime=%d improved=%d\n', ...
 best.metrics.N,best.metrics.energy_kWh,best.metrics.Cmax_s,tested,feasible,onTime,improved);
end

function routes=strip(r)
routes=repmat(struct('boxIdx',[],'nodeOrder',[],'typeIdx',[]),numel(r),1);
for p=1:numel(r)
 routes(p)=struct('boxIdx',r(p).boxIdx(:),'nodeOrder',r(p).nodeOrder(:)','typeIdx',r(p).typeIdx);
end
end
