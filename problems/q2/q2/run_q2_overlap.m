function run_q2_overlap(root,budget)
if nargin<1,root=fileparts(fileparts(mfilename('fullpath')));end
if nargin<2,budget=130;end
out=fullfile(root,'results','q2_overlap');if ~isfolder(out),mkdir(out);end
D=load_q2_data(root);D.parallelPrepLoad=true;[legs,~]=build_q2_leg_cache(D,root,false);
z=load(fullfile(root,'results','q2_parallel_forms','best_pass.mat'),'best');
routes=strip(z.best.routes);[best,st]=overlap_schedule_q2_routes(D,legs,routes);assert(st.feasible,st.reason);
bestV=validate_q2_solution(D,legs,best,'RequireAllExpectedOnTime',true,'AllowPrepBatteryOverlap',true);assert(strcmp(bestV.status,'PASS'),strjoin(bestV.issues,';'));
save(fullfile(out,'best_23_pass.mat'),'D','legs','best','bestV','-v7.3');
z22=load(fullfile(root,'results','q2_parallel_forms','best_22_pass.mat'),'best22');r22=strip(z22.best22.routes);
[s22,t22]=overlap_schedule_q2_routes(D,legs,r22);
if t22.feasible
 v22=validate_q2_solution(D,legs,s22,'RequireAllExpectedOnTime',true,'AllowPrepBatteryOverlap',true);if strcmp(v22.status,'PASS'),best22=s22;best22V=v22;save(fullfile(out,'best_22_pass.mat'),'D','legs','best22','best22V','-v7.3');end
end
% Bounded neighborhoods on both fixed route counts: swaps, relocations, type and stop-order changes.
[best,bestV,test23]=refine(best,bestV,55,@save23);
[best22,best22V,test22]=refine(best22,best22V,55,@save22);
% Final fresh input/cache audit and same-route legacy timing controls.
Df=load_q2_data(root);Df.parallelPrepLoad=true;[lf,~]=build_q2_leg_cache(Df,root,false);
bestV=validate_q2_solution(Df,lf,best,'RequireAllExpectedOnTime',true,'AllowPrepBatteryOverlap',true);
best22V=validate_q2_solution(Df,lf,best22,'RequireAllExpectedOnTime',true,'AllowPrepBatteryOverlap',true);
assert(strcmp(bestV.status,'PASS')&&strcmp(best22V.status,'PASS'));
save(fullfile(out,'best_23_pass.mat'),'D','legs','best','bestV','-v7.3');
save(fullfile(out,'best_22_pass.mat'),'D','legs','best22','best22V','-v7.3');
Dp=Df;
[serial23,ss23]=schedule_q2_routes(Dp,lf,strip(best.routes));assert(ss23.feasible);
[serial22,ss22]=schedule_q2_routes(Dp,lf,strip(best22.routes));assert(ss22.feasible);
old23=validate_q2_solution(Dp,lf,serial23,'RequireAllExpectedOnTime',true);
old22=validate_q2_solution(Dp,lf,serial22,'RequireAllExpectedOnTime',true);
assert(strcmp(old23.status,'PASS')&&strcmp(old22.status,'PASS'));
[n23,max23,sum23]=overlapStats(best);[n22,max22,sum22]=overlapStats(best22);
fid=fopen(fullfile(out,'run_summary.txt'),'w');
fprintf(fid,'budget_each_s=55\ntested23=%d\ntested22=%d\nN23=%d\noverlap_Cmax23_min=%.12f\nparallel_prep_load_same_routes_Cmax23_min=%.12f\nE23_kWh=%.12f\nstatus23=%s\ncharge_prep_overlap_routes23=%d\nmax_overlap23_s=%.6f\nsum_overlap23_s=%.6f\nN22=%d\noverlap_Cmax22_min=%.12f\nparallel_prep_load_same_routes_Cmax22_min=%.12f\nE22_kWh=%.12f\nstatus22=%s\ncharge_prep_overlap_routes22=%d\nmax_overlap22_s=%.6f\nsum_overlap22_s=%.6f\n', ...
 test23,test22,bestV.routeCount,bestV.independentMetrics.Cmax_s/60,old23.independentMetrics.Cmax_s/60,bestV.independentMetrics.energy_kWh,bestV.status,n23,max23,sum23,best22V.routeCount,best22V.independentMetrics.Cmax_s/60,old22.independentMetrics.Cmax_s/60,best22V.independentMetrics.energy_kWh,best22V.status,n22,max22,sum22);
fclose(fid);
fprintf('OVERLAP strict PASS: 23 %.6f min, 22 %.6f min; tests=%d/%d\n',bestV.independentMetrics.Cmax_s/60,best22V.independentMetrics.Cmax_s/60,test23,test22);
 function save23(c,w),best=c;bestV=w;save(fullfile(out,'best_23_pass.mat'),'D','legs','best','bestV','-v7.3');end
 function save22(c,w),best22=c;best22V=w;save(fullfile(out,'best_22_pass.mat'),'D','legs','best22','best22V','-v7.3');end
 function [b,v,tested]=refine(b,v,secs,savefn)
  t=tic;tested=0;changed=true;
  while changed&&toc(t)<secs
   changed=false;rr=strip(b.routes);n=numel(rr);base=b.metrics.Cmax_s;
   for i=1:n
    for j=1:n
     if i==j||toc(t)>=secs,continue;end
     q=rr;item=q(i);q(i)=[];pos=min(j,numel(q)+1);q=[q(1:pos-1);item;q(pos:end)];tested=tested+1;consider(q);
    end
    if toc(t)>=secs,break;end
   end
   for i=1:n
    if toc(t)>=secs,break;end
    for k=1:height(D.uav)
     if k==rr(i).typeIdx||toc(t)>=secs,continue;end
     q=rr;q(i).typeIdx=k;tested=tested+1;consider(q);
    end
    nd=rr(i).nodeOrder;
    if numel(nd)>1
     for a=1:numel(nd)-1
      for c=a+1:numel(nd)
       if toc(t)>=secs,break;end
       q=rr;q(i).nodeOrder(a:c)=q(i).nodeOrder(c:-1:a);tested=tested+1;consider(q);
      end
     end
    end
   end
   if b.metrics.Cmax_s<base-D.tol.time,changed=true;end
  end
  function consider(q)
   try,[c,st]=overlap_schedule_q2_routes(D,legs,q);catch,return;end
   if ~st.feasible||c.metrics.Cmax_s>=b.metrics.Cmax_s-D.tol.time,return;end
   w=validate_q2_solution(D,legs,c,'RequireAllExpectedOnTime',true,'AllowPrepBatteryOverlap',true);if ~strcmp(w.status,'PASS'),return;end
   b=c;v=w;savefn(b,v);
  end
 end
end
function r=strip(a),r=repmat(struct('boxIdx',[],'nodeOrder',[],'typeIdx',[]),numel(a),1);for z=1:numel(a),r(z)=struct('boxIdx',a(z).boxIdx(:),'nodeOrder',a(z).nodeOrder(:)','typeIdx',a(z).typeIdx);end,end
function [n,mx,sm]=overlapStats(S)
n=0;mx=0;sm=0;
for p=1:numel(S.routes)
 r=S.routes(p);prevRet=-Inf;prevReady=-Inf;
 for q=1:numel(S.routes)
  z=S.routes(q);if z.batteryID==r.batteryID&&z.return_s<=r.takeoff_s&&z.return_s>prevRet,prevRet=z.return_s;prevReady=z.batteryReady_s;end
 end
 if isfinite(prevRet)
  ov=max(0,min(r.takeoff_s,prevReady)-max(r.prepStart_s,prevRet));
  if ov>0,n=n+1;mx=max(mx,ov);sm=sm+ov;end
 end
end
end
