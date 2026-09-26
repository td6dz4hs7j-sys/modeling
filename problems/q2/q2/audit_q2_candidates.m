function audit_q2_candidates(root)
% Recompute strict validity and compare every saved on-time candidate.
out=fullfile(root,'results','q2_all_ontime');
x=load(fullfile(out,'q2_final_solution.mat'),'D','legs','baseline');D=x.D;legs=x.legs;baseline=x.baseline;
files={fullfile(root,'results','q2_opt_main','q2_seed_20260927_best.mat'), ...
 fullfile(root,'results','q2_final','q2_energy_preference.mat')};
folders={out,fullfile(root,'results','q2_more_search'),fullfile(root,'results','q2_deeper_search')};
for j=1:numel(folders)
 found=dir(fullfile(folders{j},'q2_seed_*_best.mat'));
 files=[files,reshape(arrayfun(@(f)fullfile(f.folder,f.name),found,'UniformOutput',false),1,[])]; %#ok<AGROW>
end
extra={fullfile(root,'results','q2_refinement','q2_time_refined.mat'), ...
 fullfile(root,'results','q2_refinement','q2_energy_refined.mat'), ...
 fullfile(root,'results','q2_refinement','n21','q2_time_refined.mat'), ...
 fullfile(root,'results','q2_refinement','n21','q2_energy_refined.mat')};
files=[files,extra(cellfun(@isfile,extra))];
records=cell(numel(files),8);valid=cell(numel(files),1);
for i=1:numel(files)
 a=load(files{i});
 if isfield(a,'Ralt'),S=a.Ralt.best;
 elseif isfield(a,'best'),S=a.best;
 elseif isfield(a,'Stime'),S=a.Stime;
 elseif isfield(a,'Senergy'),S=a.Senergy;
 else,error('Unrecognized candidate MAT: %s',files{i});end
 V=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',true);
 records(i,:)={string(erase(files{i},[root filesep])),string(V.status), ...
 S.metrics.N,S.metrics.W,S.metrics.Cmax_s,S.metrics.energy_kWh, ...
 sum(S.sorties.operation_s)/3600,sum(S.boxDelivery.arrival_s<=S.boxDelivery.expected_s+D.tol.time)};
 if strcmp(V.status,'PASS'),valid{i}=S;end
end
T=cell2table(records,'VariableNames',{'source','strict_status','N','W_priority_s', ...
 'Cmax_s','energy_kWh','cumulative_operation_h','on_time_boxes'});
writetable(T,fullfile(out,'q2_eligible_candidates.csv'));
ok=find(T.strict_status=="PASS" & T.on_time_boxes==80);
assert(~isempty(ok),'No strictly feasible candidate found.');
[~,iE]=min(T.energy_kWh(ok));[~,iT]=min(T.Cmax_s(ok));
Senergy=valid{ok(iE)};Stime=valid{ok(iT)};
save(fullfile(out,'q2_validated_alternatives.mat'),'Senergy','Stime','T','-v7.3');
emptySearch=struct('seeds',[],'summary',table(),'trace',table());
export_q2_results(D,legs,Senergy,baseline,emptySearch,fullfile(out,'alternative_energy'));
export_q2_results(D,legs,Stime,baseline,emptySearch,fullfile(out,'alternative_time'));
write_q2_validation(validate_q2_solution(D,legs,Senergy,'RequireAllExpectedOnTime',true), ...
 fullfile(out,'alternative_energy','q2_final_validation.json'));
write_q2_validation(validate_q2_solution(D,legs,Stime,'RequireAllExpectedOnTime',true), ...
 fullfile(out,'alternative_time','q2_final_validation.json'));
final=load(fullfile(out,'q2_final_solution.mat'),'S','R');
export_q2_results(D,legs,final.S,baseline,final.R,out);
fprintf('AUDIT CANDIDATES: %d strict PASS. ENERGY N=%d E=%.6f Cmax=%.3f; TIME N=%d E=%.6f Cmax=%.3f\n', ...
 numel(ok),Senergy.metrics.N,Senergy.metrics.energy_kWh,Senergy.metrics.Cmax_s, ...
 Stime.metrics.N,Stime.metrics.energy_kWh,Stime.metrics.Cmax_s);
end
