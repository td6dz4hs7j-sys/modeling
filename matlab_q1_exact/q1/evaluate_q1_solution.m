function [T,U,G]=evaluate_q1_solution(D,P,S,rho)
if nargin<4,rho=D.uav.reserve;end
rows=cell(0,18);
for i=1:numel(S)
 assert(S{i}.feasible,'Infeasible area');
 for j=1:numel(S{i}.uav)
  u=D.uav(S{i}.uav(j),:);ids=S{i}.box_ids{j};b=D.boxes(ismember(D.boxes.id,ids),:);m=sum(b.mass);v=sum(b.volume);
  [E,parts]=flight_energy_model(u,P(i),m,D.g);[t,tf]=flight_time_model(u,P(i),numel(ids));
  rows(end+1,:)={P(i).area,"Q1-"+compose('%03d',size(rows,1)+1),u.id,strjoin(ids,';'),m,v,m/u.payload,v/u.volume,E,t,tf,u.energy-E,1-E/u.energy,numel(ids),parts.horizontal_out+parts.horizontal_back,parts.climb_out+parts.climb_back,P(i).index,S{i}.uav(j)}; %#ok<AGROW>
 end
end
T=cell2table(rows,'VariableNames',{'service_area','sortie_id','uav_type','box_ids','total_mass_kg','total_volume_m3','payload_utilization','volume_utilization','energy_kWh','operation_time_s','flight_time_s','remaining_energy_kWh','return_SOC','number_of_boxes','horizontal_energy_kWh','climb_energy_kWh','area_index','type_index'});
limits=solve_max_payload(D,P,rho);T.max_safe_payload_kg=zeros(height(T),1);
for j=1:height(T),x=limits.service_area==T.service_area(j) & limits.uav_type==T.uav_type(j);T.max_safe_payload_kg(j)=limits.max_safe_payload_kg(x);end
T.safe_payload_utilization=T.total_mass_kg./T.max_safe_payload_kg;
rr=cell(numel(P),7);
for i=1:numel(P)
 x=T(T.service_area==P(i).area,:);rr(i,:)={P(i).area,sum(x.number_of_boxes),height(x),sum(x.total_mass_kg),sum(x.energy_kWh),sum(x.operation_time_s),sum(x.flight_time_s)};
end
U=cell2table(rr,'VariableNames',{'service_area','number_of_boxes','number_of_sorties','total_mass_kg','total_energy_kWh','total_operation_time_s','total_flight_time_s'});
G=struct('total_sorties',height(T),'total_energy_kWh',sum(T.energy_kWh),'total_operation_time_s',sum(T.operation_time_s),'total_operation_time_h',sum(T.operation_time_s)/3600,'total_flight_time_h',sum(T.flight_time_s)/3600,'total_mass_kg',sum(T.total_mass_kg),'total_boxes',sum(T.number_of_boxes));
end
