function Q=compare_objectives(D,P,C,out)
% Compare lexicographic objectives and genuinely joint three-metric weights.
% Pattern costs are [sorties, energy_kWh, operation_time_s].  For a
% weighted run the scalar objective is
%   J = wN*N/N0 + wE*E/E0 + wT*T/T0,
% where N0, E0 and T0 are independently computed anchor scales.
orders=[1 2 3;1 3 2;2 1 3;2 3 1;3 1 2;3 2 1];
names=["N-E-T","N-T-E","E-N-T","E-T-N","T-N-E","T-E-N"];
rows=cell(0,13);lexG=cell(6,1);
for j=1:6
 S=cellfun(@(c)solve_batching(D,c,orders(j,:)),C,'UniformOutput',false);
 [T,~,G]=evaluate_q1_solution(D,P,S);validate_q1_solution(D,P,T);
 writetable(T,fullfile(out,"alternative_"+names(j)+".csv"));
 lexG{j}=G;
 rows(end+1,:)={names(j),"lexicographic",NaN,NaN,NaN,NaN,NaN,NaN,G.total_sorties,G.total_energy_kWh,G.total_operation_time_h,NaN,"single-objective priority order"}; %#ok<AGROW>
end

% These are computed anchors, rather than user-tuned target values.
N0=max(1,lexG{1}.total_sorties);
E0=max(eps,lexG{3}.total_energy_kWh);
T0=max(eps,lexG{5}.total_operation_time_s);

% Every scheme below includes all three criteria and has weights summing to 1.
schemes={
  'weighted_joint_N60_E25_T15',[0.60 0.25 0.15];
  'weighted_joint_balanced',[1/3 1/3 1/3];
  'weighted_joint_N15_E60_T25',[0.15 0.60 0.25];
  'weighted_joint_N15_E25_T60',[0.15 0.25 0.60];
  'weighted_joint_N45_E30_T25',[0.45 0.30 0.25];
  'weighted_joint_energy_dominant_N01_E98_T01',[0.01 0.98 0.01]
};
for i=1:size(schemes,1)
 name=string(schemes{i,1});w=schemes{i,2};
 % The third pattern cost is seconds; T0 is converted to seconds here.
 coef=[w(1)/N0,w(2)/E0,w(3)/T0];
 S=cellfun(@(c)solve_batching(D,c,[1 2 3],coef),C,'UniformOutput',false);
 [T,~,G]=evaluate_q1_solution(D,P,S);validate_q1_solution(D,P,T);
 writetable(T,fullfile(out,name+"_sorties.csv"));
 J=w(1)*G.total_sorties/N0+w(2)*G.total_energy_kWh/E0+w(3)*G.total_operation_time_s/T0;
 rows(end+1,:)={name,"joint_weighted",w(1),w(2),w(3),N0,E0,T0/3600,G.total_sorties,G.total_energy_kWh,G.total_operation_time_h,J,"all three criteria included"}; %#ok<AGROW>
end

S=cellfun(@(c)baseline_batching(D,c),C,'UniformOutput',false);
[T,~,G]=evaluate_q1_solution(D,P,S);validate_q1_solution(D,P,T);
writetable(T,fullfile(out,'baseline_sorties.csv'));
rows(end+1,:)={"greedy_baseline","greedy",NaN,NaN,NaN,NaN,NaN,NaN,G.total_sorties,G.total_energy_kWh,G.total_operation_time_h,NaN,"baseline only"}; %#ok<AGROW>

Q=cell2table(rows,'VariableNames',{'objective','method','sortie_weight','energy_weight','time_weight','scale_sorties','scale_energy_kWh','scale_time_h','total_sorties','total_energy_kWh','total_operation_time_h','normalized_objective','note'});
Qjoint=Q(strcmp(Q.method,"joint_weighted"),:);
writetable(Qjoint,fullfile(out,'weighted_joint_comparison.csv'));
end
