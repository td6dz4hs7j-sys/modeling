function export_q2_alternative_21(root)
% Preserve the validated 21-sortie, higher-timeliness option beside Q2 final.
if nargin<1,root=fileparts(fileparts(mfilename('fullpath')));end
x=load(fullfile(root,'results','q2_sortie_first','q2_final_solution.mat'),'D','legs');
y=load(fullfile(root,'results','q2_sortie_first','q2_seed_20261001_best.mat'),'best');
D=x.D;legs=x.legs;S=y.best;
V=validate_q2_solution(D,legs,S);
assert(strcmp(V.status,'PASS'),'21-sortie alternative failed validation.');
assert(S.metrics.N==21,'Expected the independently audited 21-sortie alternative.');
out=fullfile(root,'results','q2_final','alternative_21');
if ~isfolder(out),mkdir(out);end
writetable(S.sorties,fullfile(out,'q2_21_sorties.csv'));
T=S.boxDelivery;
T.expected_on_time=T.arrival_s<=T.expected_s+D.tol.time;
T.hard_margin_s=T.hard_deadline_s-T.arrival_s;
writetable(T,fullfile(out,'q2_21_box_delivery.csv'));
M=table(S.metrics.N,S.metrics.W,S.metrics.Cmax_s,S.metrics.energy_kWh, ...
 sum(S.sorties.operation_s)/3600,sum(T.expected_on_time),mean(T.expected_on_time), ...
 'VariableNames',{'N','W_priority_s','Cmax_s','energy_kWh', ...
 'cumulative_operation_h','expected_on_time_count','expected_on_time_rate'});
writetable(M,fullfile(out,'q2_21_metrics.csv'));
write_q2_validation(V,fullfile(out,'q2_21_validation.json'));
save(fullfile(out,'q2_21_solution.mat'),'S','V','-v7.3');
end
