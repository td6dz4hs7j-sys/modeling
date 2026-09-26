function run_q2_strategy_scenarios(root,budgetPerScenario_s)
% Four independently RUN weighted searches under the same strict Q2 rules.
if nargin<1,root=fileparts(fileparts(mfilename('fullpath')));end
if nargin<2,budgetPerScenario_s=30;end
out=fullfile(root,'results','q2_strategy_scenarios');if ~isfolder(out),mkdir(out);end
D=load_q2_data(root);D.parallelPrepLoad=true;[legs,~]=build_q2_leg_cache(D,root,false);
a=load(fullfile(root,'results','q2_prestage','recovered_101027_pass.mat'),'best');
b=load(fullfile(root,'results','q2_99_review','final_best_pass.mat'),'best');
seeds={a.best,b.best};for k=1:2,v=strict(seeds{k});assert(strcmp(v.status,'PASS'));end
archiveDir=fullfile(out,'round1');
if isfolder(archiveDir)
 archiveNames=["sortie_priority";"time_priority";"energy_priority";"balanced"];
 for h=1:numel(archiveNames)
  p=fullfile(archiveDir,archiveNames(h)+"_best_pass.mat");
  if isfile(p),z=load(p,'best');v=strict(z.best);assert(strcmp(v.status,'PASS'));seeds{end+1}=z.best;end %#ok<AGROW>
 end
end
names=["sortie_priority";"time_priority";"energy_priority";"balanced"];
weights=[.60 .20 .20;.10 .65 .25;.10 .20 .70;1/3 1/3 1/3];
% Fixed, declared scales from the four previously verified alternatives.
refMin=[22,98.4931479718722,67.2902172297666];
refMax=[23,101.027192065093,69.2519599834115];
rows=cell(4,12);
for branch=1:4
 rng(2026092600+branch,'twister');w=weights(branch,:);
 [~,ix]=min(cellfun(@(S)score(S,w),seeds));best=seeds{ix};bestV=strict(best);
 current=strip(best.routes);currentScore=score(best,w);bestScore=currentScore;
 tested=0;feasible=0;strictPass=0;improvements=0;timerToken=tic;
 save(fullfile(out,names(branch)+"_best_pass.mat"),'best','bestV','w','-v7.3');
 while toc(timerToken)<budgetPerScenario_s
  tested=tested+1;
  if mod(tested,1200)==0,current=strip(best.routes);currentScore=bestScore;end
  q=mutate(current);if isempty(q),continue;end
  try
   [S,st]=prestage_schedule_q2_routes(D,legs,q);
   if ~st.feasible||S.metrics.W>D.tol.time||S.metrics.N>23,continue;end
   feasible=feasible+1;s=score(S,w);
   temperature=.045*(1-min(toc(timerToken)/budgetPerScenario_s,1))+.0005;
   if s<currentScore||rand<exp((currentScore-s)/temperature)
    current=q;currentScore=s;
   end
   if s>=bestScore-1e-9,continue;end
   V=strict(S);if ~strcmp(V.status,'PASS'),continue;end
   strictPass=strictPass+1;improvements=improvements+1;
   best=S;bestV=V;bestScore=s;
   save(fullfile(out,names(branch)+"_best_pass.mat"),'best','bestV','w','-v7.3');
   fprintf('STRATEGY %s t=%.1f N=%d Cmax=%.6f E=%.6f score=%.6f\n', ...
    names(branch),toc(timerToken),S.metrics.N,S.metrics.Cmax_s/60,S.metrics.energy_kWh,s);
  catch
   % Capacity/route-evaluation assertions are expected for random neighbors.
  end
 end
 V=strict(best);assert(strcmp(V.status,'PASS'));
 rows(branch,:)={names(branch),w(1),w(2),w(3),best.metrics.N, ...
  V.independentMetrics.Cmax_s/60,V.independentMetrics.energy_kWh,V.deliveredBoxes, ...
  string(V.status),tested,feasible,improvements};
 fprintf('STRATEGY_FINAL %s N=%d Cmax=%.6f E=%.6f tested=%d improved=%d\n', ...
  names(branch),best.metrics.N,best.metrics.Cmax_s/60,best.metrics.energy_kWh,tested,improvements);
end
T=cell2table(rows,'VariableNames',{'strategy','sortie_weight','time_weight','energy_weight', ...
 'sorties','Cmax_min','energy_kWh','boxes_on_time','validator','tested','feasible','improvements'});
writetable(T,fullfile(out,'actual_strategy_results.csv'));
fid=fopen(fullfile(out,'scoring_contract.txt'),'w');fprintf(fid, ...
 'All four strategies used fresh Q2 data, parallel fixed-prep/load/charging, strict 80-box-on-time validator, the same %d PASS seeds (including the archived first-round pool), the same %.1f-s search budget, the same random-neighborhood algorithm, and independently saved the best PASS plan.\nScore=wN*(N-%.12f)/(%.12f-%.12f)+wT*(Cmax_min-%.12f)/(%.12f-%.12f)+wE*(E_kWh-%.12f)/(%.12f-%.12f).\nReference extrema were frozen from four previously verified candidates and were not recomputed during search.\n', ...
 numel(seeds),budgetPerScenario_s,refMin(1),refMax(1),refMin(1),refMin(2),refMax(2),refMin(2),refMin(3),refMax(3),refMin(3));fclose(fid);
fprintf('Q2_STRATEGY_SCENARIOS PASS all=%d\n',height(T));
 function V=strict(S)
  V=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true, ...
   'AllowPrepBatteryOverlap',true,'AllowFixedPrepPrestage',true);
 end
 function s=score(S,w)
  x=[S.metrics.N,S.metrics.Cmax_s/60,S.metrics.energy_kWh];
  s=sum(w.*((x-refMin)./(refMax-refMin)));
 end
 function q=mutate(r)
  q=r;n=numel(q);i=randi(n);j=randi(n-1);if j>=i,j=j+1;end
  op=randi(8);
  if op==1
   q([i j])=q([j i]);
  elseif op==2
   item=q(i);q(i)=[];q=[q(1:j-1);item;q(j:end)];
  elseif op==3
   q(i).typeIdx=randi(height(D.uav));
  elseif op==4
   if numel(q(i).nodeOrder)<2,return;end
   q(i).nodeOrder=q(i).nodeOrder(randperm(numel(q(i).nodeOrder)));
  elseif op<=6
   if numel(q(i).boxIdx)<2,q=[];return;end
   t=randi(numel(q(i).boxIdx));b=q(i).boxIdx(t);q(i).boxIdx(t)=[];
   q(j).boxIdx=[q(j).boxIdx(:);b];
   q(i).nodeOrder=unique(D.boxNodeIndex(q(i).boxIdx),'stable')';
   q(j).nodeOrder=unique(D.boxNodeIndex(q(j).boxIdx),'stable')';
  elseif op==7
   p=randi(numel(q(i).boxIdx));z=randi(numel(q(j).boxIdx));
   b=q(i).boxIdx(p);q(i).boxIdx(p)=q(j).boxIdx(z);q(j).boxIdx(z)=b;
   q(i).nodeOrder=unique(D.boxNodeIndex(q(i).boxIdx),'stable')';
   q(j).nodeOrder=unique(D.boxNodeIndex(q(j).boxIdx),'stable')';
  else
   q(i).typeIdx=randi(height(D.uav));
   if numel(q(i).nodeOrder)>1,q(i).nodeOrder=fliplr(q(i).nodeOrder);end
  end
  for k=[i j]
   if isempty(q(k).boxIdx)||sum(D.boxMass(q(k).boxIdx))>D.uav.payload(q(k).typeIdx)+D.tol.mass|| ...
      sum(D.boxVolume(q(k).boxIdx))>D.uav.volume(q(k).typeIdx)+D.tol.volume
    q=[];return;
   end
  end
 end
end
function q=strip(a)
q=repmat(struct('boxIdx',[],'nodeOrder',[],'typeIdx',0),numel(a),1);
for i=1:numel(a),q(i)=struct('boxIdx',a(i).boxIdx(:),'nodeOrder',a(i).nodeOrder(:)','typeIdx',a(i).typeIdx);end
end
