function run_q2_weighted_verified(root,weights,tag)
% Fresh inputs, corrected common gravity, hard expected deadlines, 23 sorties.
D=load_q2_data(root);[legs,cacheMeta]=build_q2_leg_cache(D,root,false);
assert(abs(D.g-9.806)<1e-12&&max(abs(D.uav.volume-[.06;.073;.25]))<1e-12);
if nargin<2,weights=[1 .97 .90 .75];end
if nargin<3,tag='';end
out=fullfile(root,'results','q2_weighted_verified',tag);if ~isfolder(out),mkdir(out);end
writetable(D.uav,fullfile(out,'verified_aircraft_parameters.csv'));
writetable(D.uavInventory,fullfile(out,'verified_uav_inventory.csv'));
writetable(D.batteryInventory,fullfile(out,'verified_battery_inventory.csv'));
paths={fullfile(root,'results','q2_time94','regroup','q2_regroup_final.mat'), ...
 fullfile(root,'results','q2_current','q2_current_solution.mat'), ...
 fullfile(root,'results','q2_energy_22_23','published_n23','q2_energy_solution.mat')};
initial=cell(3,1);audit=cell(3,7);
for k=1:3
 a=load(paths{k},'S');[S,st]=schedule_q2_routes(D,legs,strip(a.S.routes));assert(st.feasible);
 V=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true);assert(strcmp(V.status,'PASS'));
 initial{k}=S;audit(k,:)={k,a.S.metrics.Cmax_s,a.S.metrics.energy_kWh,S.metrics.Cmax_s,S.metrics.energy_kWh,D.g,string(V.status)};
end
writetable(cell2table(audit,'VariableNames',{'source','old_makespan_s','old_energy_kWh','new_makespan_s','new_energy_kWh','g','validator'}),fullfile(out,'parameter_recalculation.csv'));
baseline=initial{1};ctx=q2_fast_context(D,legs);archive=initial;
summary=cell(numel(weights),8);trace=[];
for branch=1:numel(weights)
 w=weights(branch);rng(20261120+branch);
 scores=cellfun(@(s)objective(s.metrics,w),archive);[~,ix]=min(scores);best=archive{ix};
 current=strip(best.routes);score=objective(best.metrics,w);
 for iter=1:14000
  if mod(iter-1,2000)==0,current=strip(best.routes);score=objective(best.metrics,w);end
  cand=mutate(D,current);
  if isempty(cand),continue;end
  [F,ctx]=q2_fast_schedule(D,legs,cand,ctx);
  if F.feasible&&F.metrics.W<=D.tol.time
   val=objective(F.metrics,w);temp=.012*(1-mod(iter-1,2000)/2000)+.00002;
   if val<score||rand<exp((score-val)/temp),current=cand;score=val;end
   if val<objective(best.metrics,w)-1e-11 || ...
    (abs(val-objective(best.metrics,w))<=1e-11&&F.metrics.energy_kWh<best.metrics.energy_kWh-D.tol.energy)
    [S,st]=schedule_q2_routes(D,legs,cand);assert(st.feasible);
    V=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true);assert(strcmp(V.status,'PASS'));
    best=S;archive{end+1}=S; %#ok<AGROW>
    trace(end+1,:)=[branch,w,iter,S.metrics.Cmax_s,S.metrics.energy_kWh]; %#ok<AGROW>
    fprintf('WEIGHT %.2f iter=%d: T=%.4f min E=%.6f PASS\n',w,iter,S.metrics.Cmax_s/60,S.metrics.energy_kWh);
   end
  end
  if mod(iter,2000)==0,fprintf('WEIGHT %.2f progress=%d T=%.4f E=%.6f\n',w,iter,best.metrics.Cmax_s/60,best.metrics.energy_kWh);end
 end
 S=best;V=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true);assert(strcmp(V.status,'PASS'));
 save(fullfile(out,sprintf('weight_%02d.mat',branch)),'S','V','w','-v7.3');
 summary(branch,:)={branch,w,1-w,23,S.metrics.Cmax_s/60,S.metrics.energy_kWh,80,string(V.status)};
end
% Retain only non-dominated feasible schedules; select shortest time for recommendation.
t=cellfun(@(s)s.metrics.Cmax_s,archive);e=cellfun(@(s)s.metrics.energy_kWh,archive);keep=true(size(t));
for i=1:numel(t),keep(i)=~any(t<=t(i)+1e-6&e<=e(i)+1e-8&(t<t(i)-1e-6|e<e(i)-1e-8));end
archive=archive(keep);t=t(keep);e=e(keep);[~,ix]=sortrows([t(:),e(:)],[1 2]);archive=archive(ix);
S=archive{1};V=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true);assert(strcmp(V.status,'PASS'));
R=struct('trace',table(),'summary',table());
tests=test_q2_mutations(D,legs,S,'RequireAllExpectedOnTime',true);assert(all(tests.rejected));
writetable(tests,fullfile(out,'q2_strict_mutation_tests.csv'));
save(fullfile(out,'q2_weighted_final.mat'),'D','legs','cacheMeta','S','V','archive','summary','trace','weights','-v7.3');
write_q2_validation(V,fullfile(out,'q2_final_validation.json'));
export_q2_results(D,legs,S,baseline,R,out);
writetable(cell2table(summary,'VariableNames',{'branch','time_weight','energy_weight','sorties','makespan_min','energy_kWh','on_time_boxes','validator'}),fullfile(out,'weight_comparison.csv'));
writetable(array2table(trace,'VariableNames',{'branch','time_weight','iteration','makespan_s','energy_kWh'}),fullfile(out,'weighted_search_trace.csv'));
pt=cellfun(@(s)s.metrics.Cmax_s/60,archive);pe=cellfun(@(s)s.metrics.energy_kWh,archive);
writetable(table(pt(:),pe(:),'VariableNames',{'makespan_min','energy_kWh'}),fullfile(out,'pareto_front.csv'));
fprintf('VERIFIED FINAL T=%.6f min E=%.6f N=23 g=%.3f PASS\n',S.metrics.Cmax_s/60,S.metrics.energy_kWh,D.g);
end
function f=objective(m,w),f=w*m.Cmax_s/5640+(1-w)*m.energy_kWh/67.14;end
function cand=mutate(D,current)
cand=current;n=numel(cand);i=randi(n);j=randi(n-1);if j>=i,j=j+1;end
op=randi(7);
if op<=3||op==7
 if op==1
  if numel(cand(i).boxIdx)<2,cand=[];return;end
  k=randi(numel(cand(i).boxIdx));b=cand(i).boxIdx(k);cand(i).boxIdx(k)=[];cand(j).boxIdx(end+1)=b;
 elseif op==7
  pool=[cand(i).boxIdx(:);cand(j).boxIdx(:)];pool=pool(randperm(numel(pool)));
  take=randi(numel(pool)-1);cand(i).boxIdx=pool(1:take);cand(j).boxIdx=pool(take+1:end);
 else
  p=randi(numel(cand(i).boxIdx));q=randi(numel(cand(j).boxIdx));
  [cand(i).boxIdx(p),cand(j).boxIdx(q)]=deal(cand(j).boxIdx(q),cand(i).boxIdx(p));
 end
 for k=[i j]
  nodes=unique(D.boxNodeIndex(cand(k).boxIdx),'stable')';old=cand(k).nodeOrder;
  cand(k).nodeOrder=[old(ismember(old,nodes)),nodes(~ismember(nodes,old))];
  if rand<.3,cand(k).nodeOrder=cand(k).nodeOrder(randperm(numel(nodes)));end
  types=find(sum(D.boxMass(cand(k).boxIdx))<=D.uav.payload+D.tol.mass & sum(D.boxVolume(cand(k).boxIdx))<=D.uav.volume+D.tol.volume);
  if isempty(types),cand=[];return;end
  if ~ismember(cand(k).typeIdx,types)||rand<.45,cand(k).typeIdx=types(randi(numel(types)));end
 end
elseif op==4,cand([i j])=cand([j i]);
elseif op==5,cand(i).typeIdx=randi(3);if rand<.5,cand(j).typeIdx=randi(3);end
else
 cand(i).nodeOrder=cand(i).nodeOrder(randperm(numel(cand(i).nodeOrder)));
 item=cand(j);cand(j)=[];cand=[cand(1:i-1);item;cand(i:end)];
end
end
function r=strip(routes)
r=repmat(struct('boxIdx',[],'nodeOrder',[],'typeIdx',[]),numel(routes),1);
for i=1:numel(r),r(i)=struct('boxIdx',routes(i).boxIdx(:),'nodeOrder',routes(i).nodeOrder(:)','typeIdx',routes(i).typeIdx);end
end
