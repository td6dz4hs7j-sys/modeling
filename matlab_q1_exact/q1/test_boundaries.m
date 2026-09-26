function R=test_boundaries(D,P,T)
% Exercise branches not necessarily reached by the nominal case.
p=P(1);u=D.uav(1,:);e0=flight_energy_model(u,p,0,D.g);ef=flight_energy_model(u,p,u.payload,D.g);
rho=1-(e0+ef)/(2*u.energy);tab=solve_max_payload(D,p,rho);assert(tab.energy_binding(1) && tab.max_safe_payload_kg(1)>0 && tab.max_safe_payload_kg(1)<u.payload);
assert(abs(tab.round_trip_energy_kWh(1)-(1-rho)*u.energy)<1e-9);
tab2=solve_max_payload(D,p,.999);assert(~any(tab2.reachable));
C=enumerate_patterns(D,p,.999);S=solve_batching(D,C);assert(~S.feasible);
X=T;allids=D.boxes.id(D.boxes.area==P(1).area);X.box_ids(1)=strjoin(allids,';');X.uav_type(1)="A";
caught=false;try,validate_q1_solution(D,P,X);catch ME,caught=contains(ME.message,'capacity');end;assert(caught,'actual overloaded batch not rejected');
R=struct('status','PASS','binding_payload_kg',tab.max_safe_payload_kg(1),'unreachable_case',true,'empty_patterns_case',true,'actual_overload_rejected',true);
end
