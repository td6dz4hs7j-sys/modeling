function [M,L]=sensitivity_q1(D,P,out)
rows=cell(0,6);L=table;
for rho=0:0.05:0.5
 payload=solve_max_payload(D,P,rho);payload.scenario_reserve=repmat(rho,height(payload),1);L=[L;payload]; %#ok<AGROW>
 S=cell(numel(P),1);
 for i=1:numel(P),C=enumerate_patterns(D,P(i),rho);S{i}=solve_batching(D,C);end
 feasible=all(cellfun(@(s)s.feasible,S));
 if feasible
  [T,~,G]=evaluate_q1_solution(D,P,S,rho);validate_q1_solution(D,P,T,rho);
  writetable(T,fullfile(out,sprintf('reserve_%02d_sorties.csv',round(rho*100))));
  rows(end+1,:)={rho,true,G.total_sorties,G.total_energy_kWh,G.total_operation_time_h,G.total_flight_time_h}; %#ok<AGROW>
 else,rows(end+1,:)={rho,false,NaN,NaN,NaN,NaN};end %#ok<AGROW>
end
M=cell2table(rows,'VariableNames',{'reserve_fraction','feasible','total_sorties','total_energy_kWh','total_operation_time_h','total_flight_time_h'});
end
