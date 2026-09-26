function run_q2_minimal(root,runTag)
if nargin<1,root=fileparts(fileparts(mfilename('fullpath')));end
if nargin<2,runTag='';end
out=fullfile(root,'results','q2');if ~isempty(runTag),out=fullfile(out,char(runTag));end
if ~isfolder(out),mkdir(out);end
diary(fullfile(out,'matlab_minimal.log'));cl=onCleanup(@()diary('off')); %#ok<NASGU>
t0=tic;rng(20260924,'twister');addpath(fullfile(root,'q2'),fullfile(root,'common'),fullfile(root,'utils'));
fprintf('Q2 minimal run; root=%s\n',root);
env=check_matlab_env(["data"]);assert(env.ok,'Required MATLAB base data functions missing.');
assert(exist('wgs84Ellipsoid','file')==2,'Mapping Toolbox function wgs84Ellipsoid missing.');
D=load_q2_data(root);save(fullfile(out,'q2_loaded_data.mat'),'D','-v7.3');
fprintf('Loaded: %d nodes, %d boxes, %d UAVs, %d battery groups.\n',height(D.nodes),height(D.boxes),height(D.uavInventory),sum(D.batteryInventory.count));
[legs,cacheMeta]=build_q2_leg_cache(D,root,false);save(fullfile(out,'q2_leg_cache_audit.mat'),'cacheMeta');
fprintf('Terrain cache ready: %d directed legs; input/code SHA recorded.\n',numel(legs));
direct=q2_direct_degradation(D,legs);writetable(direct,fullfile(out,'q2_direct_q1_degradation.csv'));
fprintf('Q1 direct round-trip degradation: %d rows, max energy/time delta %.3g / %.3g.\n',height(direct),max(direct.energy_delta_kWh),max(direct.flight_delta_s));
[S,routes,construction]=construct_q2_minimal(D,legs);save(fullfile(out,'q2_construction.mat'),'routes','construction','-v7.3');
writecell({construction.status;construction.message;construction.urgentRoutes;construction.residualRoutes},fullfile(out,'q2_construction_status.csv'));
fprintf('Construction: %s; %d routes (%d urgent, %d residual): %s\n',construction.status,numel(routes),construction.urgentRoutes,construction.residualRoutes,construction.message);
if strcmp(construction.status,'BUILT')
 V=validate_q2_solution(D,legs,S);save(fullfile(out,'q2_solution.mat'),'D','legs','S','V','construction','cacheMeta','-v7.3');
 writetable(S.sorties,fullfile(out,'q2_sorties.csv'));writetable(S.boxDelivery,fullfile(out,'q2_box_delivery.csv'));
 writetable(struct2table(S.metrics),fullfile(out,'q2_metrics.csv'));write_q2_validation(V,fullfile(out,'q2_validation.json'));
 fprintf('Independent validator: %s, delivered=%d, routes=%d, W=%.6g, Cmax=%.3f s, E=%.6f kWh.\n',V.status,V.deliveredBoxes,V.routeCount,V.independentMetrics.W,V.independentMetrics.Cmax_s,V.independentMetrics.energy_kWh);
 if ~strcmp(V.status,'PASS'),error('Q2:ValidatorFailure','Independent validator rejected constructed solution.');end
 inheritance=check_q1_inheritance(D,legs);save(fullfile(out,'q2_q1_inheritance.mat'),'inheritance');
 writetable(struct2table(inheritance),fullfile(out,'q2_q1_inheritance.csv'));
 fprintf('Q1 inheritance check: %s, energy max error %.3g kWh, time max error %.3g s (%d energy, %d time cases).\n', ...
  inheritance.status,inheritance.maxEnergyError_kWh,inheritance.maxTimeError_s,inheritance.energyCaseCount,inheritance.timeCaseCount);
 mutations=test_q2_mutations(D,legs,S);writetable(mutations,fullfile(out,'q2_mutation_tests.csv'));
 save(fullfile(out,'q2_mutation_tests.mat'),'mutations');
 fprintf('Adversarial mutation tests: %d/%d rejected.\n',sum(mutations.rejected),height(mutations));
 assert(all(mutations.rejected),'Q2:MutationTestFailure','One or more adversarial mutations were accepted.');
else
 save(fullfile(out,'q2_failed_construction.mat'),'D','legs','routes','construction','cacheMeta','-v7.3');
 error('Q2:ConstructionFailure','Construction failed: %s',construction.message);
end
fprintf('Elapsed %.3f s\n',toc(t0));
end

function T=q2_direct_degradation(D,legs)
rows=cell(0,8);
for i=2:height(D.nodes)
 a=q2leg(legs,1,i);b=q2leg(legs,i,1);p=struct('distance',a.distance_m,'outUp',a.up_m,'backUp',b.up_m);
 for k=1:height(D.uav)
  u=D.uav(k,:);budget=(1-u.reserve)*u.energy;E0=flight_energy_model(u,p,0,D.g);
  if E0>budget,qSafe=NaN;reachable=false;else
   lo=0;hi=u.payload;for j=1:60,mid=(lo+hi)/2;if flight_energy_model(u,p,mid,D.g)<=budget,lo=mid;else,hi=mid;end,end
   qSafe=lo;reachable=true;
  end
  qs=0;if reachable&&qSafe>1e-8,qs(end+1)=0.5*qSafe;end %#ok<AGROW>
  for q=qs
   [Eq,~]=flight_energy_model(u,p,q,D.g);[~,tf]=flight_time_model(u,p,0);
   Lout=u.range0-(u.range0-u.rangeF)*(q/u.payload)^1.5;
   Eroute=u.energy*a.distance_m/Lout+(u.mass+q)*D.g*a.up_m/(u.eta*3.6e6)+u.energy*b.distance_m/u.range0+u.mass*D.g*b.up_m/(u.eta*3.6e6);
   tRoute=a.up_m/u.up+a.distance_m/u.speed+a.down_m/u.down+b.up_m/u.up+b.distance_m/u.speed+b.down_m/u.down;
   rows(end+1,:)={D.nodes.id(i),u.id,q,reachable,Eq,Eroute,tf,tRoute}; %#ok<AGROW>
   assert(abs(Eq-Eroute)<=D.tol.energy && abs(tf-tRoute)<=D.tol.time,'Q2/Q1 direct formula drift for %s/%s q=%g',D.nodes.id(i),u.id,q);
  end
 end
end
T=cell2table(rows,'VariableNames',{'service_area','uav_type','payload_kg','zero_payload_reachable','q1_energy_kWh','q2_energy_kWh','q1_flight_s','q2_flight_s'});
T.energy_delta_kWh=T.q2_energy_kWh-T.q1_energy_kWh;T.flight_delta_s=T.q2_flight_s-T.q1_flight_s;
end
function P=q2leg(legs,a,b)
n=16;ix=(a-1)*(n-1)+b-double(b>a);P=legs(ix);
end
function write_q2_validation(V,path)
x=struct('status',V.status,'issues',{cellstr(V.issues)},'deliveredBoxes',V.deliveredBoxes,'routeCount',V.routeCount,'metrics',V.independentMetrics);
f=fopen(path,'w','n','UTF-8');c=onCleanup(@()fclose(f));fprintf(f,'%s',jsonencode(x,'PrettyPrint',true));
end
