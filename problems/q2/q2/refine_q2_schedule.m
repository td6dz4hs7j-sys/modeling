function [best,T]=refine_q2_schedule(D,legs,S0,maxPasses)
% Exhaustive route-order descent with frozen grouping, stop order and UAV types.
% Every candidate is decoded with the real UAV/battery charging timetable.
if nargin<4,maxPasses=8;end
v=validate_q2_solution(D,legs,S0,'RequireAllExpectedOnTime',true);
assert(strcmp(v.status,'PASS'),'Initial schedule fails strict validation.');
routes=strip(S0.routes);best=S0;ctx=q2_fast_context(D,legs,fullfile(D.root,'cache','route_cache.mat'));
rows=cell(0,5);n=numel(routes);
for pass=1:maxPasses
 bestRoutes=[];bestCmax=best.metrics.Cmax_s;tested=0;feasible=0;
 for mode=1:3
  for i=1:n
   if mode==2,targets=1:n;else,targets=i+1:n;end
   for j=targets
    if j==i,continue;end
    x=routes;
    if mode==1
     x([i j])=x([j i]);
    elseif mode==2
     item=x(i);x(i)=[];x=[x(1:j-1);item;x(j:end)];
    else
     x(i:j)=x(j:-1:i);
    end
    tested=tested+1;[F,ctx]=q2_fast_schedule(D,legs,x,ctx);
    if ~F.feasible||F.metrics.W>D.tol.time,continue;end
    feasible=feasible+1;
    if F.metrics.Cmax_s<bestCmax-D.tol.time
     bestCmax=F.metrics.Cmax_s;bestRoutes=x;
    end
   end
  end
 end
 if isempty(bestRoutes)
  rows(end+1,:)={pass,best.metrics.Cmax_s,best.metrics.energy_kWh,tested,feasible}; %#ok<AGROW>
  break;
 end
 [candidate,status]=schedule_q2_routes(D,legs,bestRoutes);
 assert(status.feasible,'Fast/full schedule feasibility mismatch.');
 v=validate_q2_solution(D,legs,candidate,'RequireAllExpectedOnTime',true);
 assert(strcmp(v.status,'PASS'),'Schedule descent candidate failed strict validation.');
 assert(candidate.metrics.N==S0.metrics.N && ...
  abs(candidate.metrics.energy_kWh-S0.metrics.energy_kWh)<=D.tol.energy, ...
  'Frozen-route schedule changed count or energy.');
 best=candidate;routes=bestRoutes;
 rows(end+1,:)={pass,best.metrics.Cmax_s,best.metrics.energy_kWh,tested,feasible}; %#ok<AGROW>
 fprintf('SCHEDULE PASS %d: N=%d Cmax=%.3f E=%.6f (%d/%d feasible)\n', ...
  pass,best.metrics.N,best.metrics.Cmax_s,best.metrics.energy_kWh,feasible,tested);
end
T=cell2table(rows,'VariableNames',{'pass','Cmax_s','energy_kWh','tested','feasible'});
end

function routes=strip(r)
routes=repmat(struct('boxIdx',[],'nodeOrder',[],'typeIdx',[]),numel(r),1);
for p=1:numel(r)
 routes(p)=struct('boxIdx',r(p).boxIdx(:),'nodeOrder',r(p).nodeOrder(:)','typeIdx',r(p).typeIdx);
end
end
