function publish_q2_weight_tuning(root)
% Fresh validation and export for the bounded Q2 weight search.
addpath(fullfile(root,'q2'),fullfile(root,'common'),fullfile(root,'utils'));
src=fullfile(root,'results','q2_weight_tuning','full');
dst=fullfile(root,'results','q2_weight_tuning','published');
if ~isfolder(dst),mkdir(dst);end
D=load_q2_data(root);[legs,~]=build_q2_leg_cache(D,root,false);
names={'balanced','fastest','energy6714','within120'};
branches={'w_25','w_50','w_75','target_deviation'};
old=cell(4,1);for k=1:4,z=load(fullfile(root,'results','q2_weighted_verified',names{k},'solution.mat'),'S');old{k}=z.S;end
summary=readtable(fullfile(src,'weight_summary.csv'));
freshRows=cell(4,6);traceData=cell(4,1);reasonRows=cell(0,3);scoreRows=cell(4,7);
new=cell(4,1);
for k=1:4
    b=branches{k};a=load(fullfile(src,b,'best.mat'),'bestS','bestRoutes','bestScore');S=a.bestS;
    V=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true);
    assert(strcmp(V.status,'PASS')&&S.metrics.N==23&&abs(S.metrics.W)<=D.tol.time,...
        'Fresh strict validator failed for %s: %s',b,strjoin(V.issues,'; '));
    [fresh,st]=schedule_q2_routes(D,legs,a.bestRoutes);
    assert(st.feasible&&abs(fresh.metrics.Cmax_s-S.metrics.Cmax_s)<=D.tol.time&&...
        abs(fresh.metrics.energy_kWh-S.metrics.energy_kWh)<=D.tol.energy,'Fresh schedule mismatch for %s',b);
    new{k}=S;
    freshRows(k,:)={b,S.metrics.N,S.metrics.Cmax_s/60,S.metrics.energy_kWh,...
        sum(S.boxDelivery.arrival_s<=S.boxDelivery.expected_s+D.tol.time),string(V.status)};
    A=readtable(fullfile(src,b,'attempts.csv'));traceData{k}=A;
    r=string(A.reason);u=unique(r);
    for j=1:numel(u),reasonRows(end+1,:)={b,u(j),sum(r==u(j))};end %#ok<AGROW>
    feasible=isfinite(A.candidate_score);s=A.candidate_score(feasible);
    if isempty(s),s=NaN;end
    scoreRows(k,:)={b,sum(feasible),mean(s,'omitnan'),min(s,[],'omitnan'),max(s,[],'omitnan'),std(s,'omitnan'),...
        'Within-branch objective only; feasible attempts are correlated search samples.'};
end
writetable(cell2table(freshRows,'VariableNames',{'branch','sorties','makespan_min','energy_kWh','on_time_boxes','fresh_validator'}),...
    fullfile(dst,'fresh_candidate_audit.csv'));
writetable(cell2table(reasonRows,'VariableNames',{'branch','reason','attempts'}),fullfile(dst,'attempt_reason_counts.csv'));
writetable(cell2table(scoreRows,'VariableNames',{'branch','feasible_candidate_count','score_mean','score_min','score_max','score_std','interpretation'}),...
    fullfile(dst,'feasible_score_summary.csv'));

% Only w_50 is a distinct, freshly validated result; export its full deliverables.
S=new{2};V=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true);
tests=test_q2_mutations(D,legs,S,'RequireAllExpectedOnTime',true);
assert(height(tests)==13&&all(tests.rejected),'Strict mutation tests failed for w_50');
out=fullfile(dst,'w_50');if ~isfolder(out),mkdir(out);end
writetable(tests,fullfile(out,'q2_strict_mutation_tests.csv'));
write_q2_validation(V,fullfile(out,'q2_final_validation.json'));
z=load(fullfile(root,'results','q2_weighted_verified','balanced','solution.mat'),'S');
save(fullfile(out,'solution.mat'),'S','V','-v7.3');
export_q2_results(D,legs,S,z.S,struct('summary',table(),'trace',table()),out);

% Retain unique, strict-feasible route-pool points and combine with old/new archives.
pool=readtable(fullfile(root,'results','q2_weight_tuning','route_pool','decode_audit.csv'));
pool=pool(pool.strict_feasible==1&pool.expected_late_boxes==0,:);
poolXY=unique([pool.actual_makespan_s/60,pool.actual_energy_kWh],'rows');
oldT=cellfun(@(x)x.metrics.Cmax_s/60,old);oldE=cellfun(@(x)x.metrics.energy_kWh,old);
newT=cellfun(@(x)x.metrics.Cmax_s/60,new);newE=cellfun(@(x)x.metrics.energy_kWh,new);
T=[oldT(:);newT(:);poolXY(:,1)];E=[oldE(:);newE(:);poolXY(:,2)];
label=[string(names(:));"new_"+string(branches(:));"route_pool_"+string((1:size(poolXY,1))')];
kind=[repmat("previous",4,1);repmat("weight",4,1);repmat("route_pool",size(poolXY,1),1)];
keep=true(size(T));for i=1:numel(T),keep(i)=~any(T<=T(i)+1e-8&E<=E(i)+1e-9&(T<T(i)-1e-8|E<E(i)-1e-9));end
pareto=table(label(keep),kind(keep),T(keep),E(keep),'VariableNames',{'candidate','source','makespan_min','energy_kWh'});
writetable(pareto,fullfile(dst,'pareto_candidates.csv'));

f=figure('Visible','off','Color','w','Position',[100 100 900 620]);hold on;grid on;box on;
ix=kind=="previous";scatter(T(ix),E(ix),70,[.4 .43 .48],'filled','DisplayName','Previously verified');
ix=kind=="weight";scatter(T(ix),E(ix),76,[.0 .42 .7],'filled','DisplayName','Weight search');
ix=kind=="route_pool";ix=ix&keep;scatter(T(ix),E(ix),72,[.85 .38 .12],'filled','DisplayName','Route pool Pareto');
front=unique([T(keep),E(keep)],'rows');front=sortrows(front,1);
plot(front(:,1),front(:,2),'-','Color',[.1 .38 .62],'LineWidth',1.1,'HandleVisibility','off');
scatter(94,66,100,[.2 .2 .2],'o','LineWidth',1.8,'DisplayName','User target (unverified)');
apply_publication_style(f,"en","double");
xlabel('Makespan (min)');ylabel('Energy (kWh)');legend('Location','best');
export_publication_figure(f,string(fullfile(dst,'pareto')),300,true,true);savefig(f,fullfile(dst,'pareto.fig'));close(f);

f=figure('Visible','off','Color','w','Position',[100 100 920 600]);tl=tiledlayout(f,2,2,'TileSpacing','compact');
for k=1:4
    A=traceData{k};base=A.best_score(1);improvement=100*(base-A.best_score)/max(abs(base),eps);
    ax=nexttile(tl);plot(A.attempt,improvement,'LineWidth',1.2);grid(ax,'on');
    title(ax,strrep(branches{k},'_',' '));xlabel(ax,'Attempt');ylabel(ax,'Improvement (%)');
end
apply_publication_style(f,"en","double");
export_publication_figure(f,string(fullfile(dst,'search_trace')),300,true,true);savefig(f,fullfile(dst,'search_trace.fig'));close(f);

% Add attempt and feasible-acceptance counts to a compact branch summary.
attempts=zeros(4,1);feasibleAccepted=zeros(4,1);for k=1:4
    A=traceData{k};attempts(k)=height(A);feasibleAccepted(k)=sum(contains(string(A.reason),'feasible_accepted_current'));
end
summary.attempts=attempts;summary.feasible_accepted_current=feasibleAccepted;
writetable(summary,fullfile(dst,'weight_summary.csv'));
write_manifest(root,src,dst,branches,summary);
disp(summary);
end

function write_manifest(root,src,dst,branches,summary)
paths={'input','q2/run_q2_weight_tuning.m','q2/publish_q2_weight_tuning.m','run_q2_weight_tuning.ps1','run_q2_weight_tuning_publish.ps1',...
 'q2/load_q2_data.m','q2/schedule_q2_routes.m','q2/validate_q2_solution.m','q2/evaluate_q2_route.m',...
 'q2/q2_fast_context.m','q2/q2_fast_schedule.m','common/physical_constants.m'};
hashes=cell(numel(paths),1);
for k=1:numel(paths)
    p=fullfile(root,paths{k});
    if strcmp(paths{k},'input')
        files=dir(fullfile(p,'**','*'));files=files(~[files.isdir]);rel=cell(numel(files),1);hh=cell(numel(files),1);
        for j=1:numel(files),rel{j}=strrep(fullfile(files(j).folder,files(j).name),[p filesep],'');hh{j}=sha256(fullfile(files(j).folder,files(j).name));end
        hashes{k}=struct('path','input/**','files',{rel},'sha256',{hh});
    else
        hashes{k}=struct('path',paths{k},'sha256',sha256(p));
    end
end
blockRuntime=cell(4,1);for k=1:4
    B=readtable(fullfile(src,branches{k},'blocks.csv'));blockRuntime{k}=max(B.elapsed_s);
end
manifest=struct('project_root',root,'model','Q2 weight tuning on verified 23-sortie, 80-box all-expected-on-time balanced solution',...
    'physical_parameters',struct('g_m_s2',9.806,'clearance_m',50,'delivery_height_m',30),...
    'seeds',20261201:20261204,'weights',struct('w_25',[.25 .75],'w_50',[.5 .5],'w_75',[.75 .25],...
        'target_deviation','max(T/5640-1,E/66-1)+0.01*(T/5640+E/66)'),...
    'budget',struct('per_branch_attempt_cap',6000,'block_size',1000,'stop_after_stale_blocks',3),...
    'source_solution','results/q2_weighted_verified/balanced/solution.mat',...
    'runtime',struct('matlab','R2022a','branch_seconds',{blockRuntime},'branch_names',{branches}),...
    'reproduction_commands',{{'powershell -NoProfile -ExecutionPolicy Bypass -File .\run_q2_weight_tuning.ps1 -Mode full',...
      'powershell -NoProfile -ExecutionPolicy Bypass -File .\run_q2_weight_tuning_publish.ps1'}},...
    'sources_and_inputs',{hashes},'results',summary);
txt=jsonencode(manifest,'PrettyPrint',true);fid=fopen(fullfile(dst,'复现清单.json'),'w','n','UTF-8');fwrite(fid,txt,'char');fclose(fid);
end
function h=sha256(p)
[status,out]=system(['certutil -hashfile "' p '" SHA256']);assert(status==0,'Could not hash %s',p);
t=regexp(out,'(?m)^[0-9A-Fa-f ]{64,}$','match');assert(~isempty(t),'SHA256 output missing for %s',p);
h=lower(regexprep(t{1},'\s',''));
end
