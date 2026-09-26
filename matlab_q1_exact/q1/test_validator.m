function R=test_validator(D,P,T)
% Deliberately corrupt solutions. Each mutation must be rejected.
names=["duplicate sortie","wrong energy unit","cross-area ID","invalid type","wrong mass","wrong time","wrong SOC","missing sortie"];
for k=1:numel(names)
 X=T;
 switch k
  case 1,X=[T;T(1,:)];
  case 2,X.energy_kWh(1)=X.energy_kWh(1)*3600;
  case 3,X.box_ids(1)="S015-MED-01";
  case 4,X.uav_type(1)="INVALID";
  case 5,X.total_mass_kg(1)=X.total_mass_kg(1)+1;
  case 6,X.operation_time_s(1)=X.operation_time_s(1)/3600;
  case 7,X.return_SOC(1)=1;
  case 8,X(1,:)=[];
 end
 caught=false;try,validate_q1_solution(D,P,X);catch,caught=true;end
 assert(caught,'Validator accepted mutation: %s',names(k));
end
R=table(names',true(numel(names),1),'VariableNames',{'mutation','rejected'});
end
