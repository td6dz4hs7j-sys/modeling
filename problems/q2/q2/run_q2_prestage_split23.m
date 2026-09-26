function run_q2_prestage_split23(root,budget)
if nargin<1,root=fileparts(fileparts(mfilename('fullpath')));end
if nargin<2,budget=62;end
budget=min(budget,62);out=fullfile(root,'results','q2_prestage_split23');if ~isfolder(out),mkdir(out);end
D=load_q2_data(root);D.parallelPrepLoad=true;[legs,~]=build_q2_leg_cache(D,root,false);
x=load(fullfile(root,'results','q2_prestage','recovered_101027_pass.mat'),'best');base=x.best;
V0=validate_q2_solution(D,legs,base,'RequireAllExpectedOnTime',true,'AllowPrepBatteryOverlap',true,'AllowFixedPrepPrestage',true);assert(strcmp(V0.status,'PASS'),'Recovered source failed strict validation');baseC=V0.independentMetrics.Cmax_s;
ixU=find(string({base.routes.uavID})=="U07");[~,oo]=sort([base.routes(ixU).takeoff_s]);ixU=ixU(oo);splitSpecs={};
for ii=ixU(:)'
 r=base.routes(ii);bx=r.boxIdx(:);if numel(bx)<2,continue;end
 ns=unique(D.boxNodeIndex(bx),'stable');
 for k=1:numel(ns)
  moved=bx(D.boxNodeIndex(bx)==ns(k));remain=bx(~ismember(bx,moved));if ~isempty(remain)&&~isempty(moved),splitSpecs{end+1}={ii,remain,moved};end %#ok<AGROW>
 end
 if numel(ns)==1&&numel(bx)>2
  moved=bx(ceil(numel(bx)/2)+1:end);remain=bx(1:ceil(numel(bx)/2));splitSpecs{end+1}={ii,remain,moved}; %#ok<AGROW>
 end
end
% Add deadline-aware box partitions to split long same-station assignments.
for ii=ixU(:)'
 bx=base.routes(ii).boxIdx(:);if numel(bx)<2,continue;end
 [~,ord]=sort(D.boxes.expected_s(bx),'descend');moved=bx(ord(1));remain=bx(ord(2:end));splitSpecs{end+1}={ii,remain,moved}; %#ok<AGROW>
end
% Deduplicate moved route and sort by route index, then small/high-urgency groups.
keys=strings(numel(splitSpecs),1);for k=1:numel(splitSpecs),keys(k)=compose('%d_',splitSpecs{k}{1})+join(string(splitSpecs{k}{3}),',');end
[~,uix]=unique(keys,'stable');splitSpecs=splitSpecs(uix);
best23=[];best23V=[];tested=0;strictPass=0;fastPass=0;firstFail="none";ticSearch=tic;
for ss=1:numel(splitSpecs)
 if toc(ticSearch)>=budget,break;end
 sp=splitSpecs{ss};orig=sp{1};remain=sp{2};moved=sp{3};
 % Retain original route type for its remainder; try every feasible type for the new sortie.
 r0=base.routes(orig);newTypes=[];for kt=1:height(D.uav),if routeFits(D,moved,kt),newTypes(end+1)=kt;end,end %#ok<AGROW>
 if isempty(newTypes),continue;end
 for kt=newTypes
  rnew=struct('boxIdx',moved(:),'nodeOrder',unique(D.boxNodeIndex(moved),'stable')','typeIdx',kt);
  routes=stripRoutes(base.routes);routes(orig).boxIdx=remain(:);routes(orig).nodeOrder=unique(D.boxNodeIndex(remain),'stable')';
  % Priority insertion positions: immediately before/after source, then all remaining slots.
  pos=unique([orig,orig+1,1:23],'stable');
  for pp=pos
   if toc(ticSearch)>=budget,break;end
   q=routes;q=[q(1:pp-1);rnew;q(pp:end)];if numel(q)~=23,continue;end
   tested=tested+1;
   try
    if ~allFits(D,q),if firstFail=="none",firstFail="capacity filter";end;continue;end
    [S,st]=prestage_schedule_q2_routes(D,legs,q);
    V=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true,'AllowPrepBatteryOverlap',true,'AllowFixedPrepPrestage',true);
    if strcmp(V.status,'PASS')
     strictPass=strictPass+1;
     if V.independentMetrics.Cmax_s<baseC-D.tol.time
      fastPass=fastPass+1;
      if isempty(best23)||V.independentMetrics.Cmax_s<best23V.independentMetrics.Cmax_s
       best23=S;best23V=V;save(fullfile(out,'best_23_pass.mat'),'D','legs','base','best23','best23V','-v7.3');
       fprintf('SPLIT23_CHECKPOINT t=%.1f cmax_min=%.9f E=%.9f source_route=%d moved=%d type=%s pos=%d tested=%d\n',toc(ticSearch),V.independentMetrics.Cmax_s/60,V.independentMetrics.energy_kWh,orig,numel(moved),D.uav.id(kt),pp,tested);
      end
     end
    elseif firstFail=="none"
     if ~isempty(V.issues),firstFail=V.issues(1);elseif ~st.feasible,firstFail=string(st.reason);else,firstFail="validator failure";end
    end
   catch ME
    if firstFail=="none",firstFail=string(ME.message);end
   end
  end
 end
end
fid=fopen(fullfile(out,'search_summary.txt'),'w');fprintf(fid,'source_status=PASS\nsource_N=%d\nsource_Cmax_min=%.12f\nsource_energy_kWh=%.12f\ncritical_UAV=U07\ntested_23_sortie_candidates=%d\nstrict_pass_count=%d\nfaster_pass_count=%d\nfirst_failure=%s\nelapsed_s=%.3f\n',V0.routeCount,baseC/60,V0.independentMetrics.energy_kWh,tested,strictPass,fastPass,firstFail,toc(ticSearch));if ~isempty(best23V),fprintf(fid,'best_23_Cmax_min=%.12f\nbest_23_E_kWh=%.12f\n',best23V.independentMetrics.Cmax_s/60,best23V.independentMetrics.energy_kWh);else,fprintf(fid,'best_23_Cmax_min=none\n');end;fclose(fid);
fprintf('SPLIT23_DONE tested=%d strict_pass=%d faster_pass=%d elapsed=%.2f first_failure=%s\n',tested,strictPass,fastPass,toc(ticSearch),firstFail);
end
function r=stripRoutes(a),r=repmat(struct('boxIdx',[],'nodeOrder',[],'typeIdx',0),numel(a),1);for k=1:numel(a),r(k)=struct('boxIdx',a(k).boxIdx(:),'nodeOrder',a(k).nodeOrder(:)','typeIdx',a(k).typeIdx);end,end
function tf=routeFits(D,ix,k),tf=sum(D.boxMass(ix))<=D.uav.payload(k)+D.tol.mass&&sum(D.boxVolume(ix))<=D.uav.volume(k)+D.tol.volume;end
function tf=allFits(D,r),tf=true;for k=1:numel(r),if ~routeFits(D,r(k).boxIdx,r(k).typeIdx),tf=false;return;end,end,end
