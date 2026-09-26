function R=validate_q1_solution(D,P,T,rho)
% Independent arithmetic, reconstructing box membership and phase energy.
if nargin<4,rho=D.uav.reserve;end
if isscalar(rho),rho=repmat(rho,3,1);end
seen=strings(0,1);
for j=1:height(T)
 ids=split(T.box_ids(j),';');assert(numel(unique(ids))==numel(ids),'duplicate within sortie');
 [found,loc]=ismember(ids,D.boxes.id);assert(all(found),'unknown box');b=D.boxes(loc,:);
 assert(all(b.area==T.service_area(j)),'cross service area');seen=[seen;ids]; %#ok<AGROW>
 k=find(D.uav.id==T.uav_type(j));assert(numel(k)==1,'invalid UAV type');u=D.uav(k,:);
 i=find(string({P.area})==T.service_area(j));assert(numel(i)==1);p=P(i);
 m=sum(b.mass);v=sum(b.volume);assert(m<=u.payload+D.tol.mass && v<=u.volume+D.tol.volume,'capacity');
 range=u.range0-(u.range0-u.rangeF)*(m/u.payload)^1.5;
 e=u.energy*(p.distance/range+p.distance/u.range0)+D.g*((u.mass+m)*p.outUp+u.mass*p.backUp)/u.eta/3600000;
 tf=p.outUp/u.up+p.distance/u.speed+p.backUp/u.down+p.backUp/u.up+p.distance/u.speed+p.outUp/u.down;
 t=tf+u.prep+height(b)*u.load+u.handover+height(b)*u.boxhandover;
 assert(e<=(1-rho(k))*u.energy+D.tol.energy,'energy reserve');
 assert(1-e/u.energy>=rho(k)-1e-10,'SOC');
 assert(abs(m-T.total_mass_kg(j))<1e-8 && abs(v-T.total_volume_m3(j))<1e-10,'mass volume mismatch');
 assert(abs(e-T.energy_kWh(j))<1e-8 && abs(t-T.operation_time_s(j))<1e-6,'energy/time units or value');
 assert(abs(tf-T.flight_time_s(j))<1e-6 && abs(1-e/u.energy-T.return_SOC(j))<1e-9);
 assert(abs(u.energy-e-T.remaining_energy_kWh(j))<1e-8);
 assert(abs(m/u.payload-T.payload_utilization(j))<1e-9 && abs(v/u.volume-T.volume_utilization(j))<1e-9,'utilization');
 assert(height(b)==T.number_of_boxes(j) && T.type_index(j)==k && T.area_index(j)==p.index,'metadata');
end
required=D.boxes.id(ismember(D.boxes.area,string({P.area})));
assert(numel(seen)==numel(required) && numel(unique(seen))==numel(seen),'duplicate or missing boxes');
assert(isequal(sort(seen),sort(required)),'coverage');
R=struct('status','PASS','verified_boxes',numel(seen),'verified_sorties',height(T),'minimum_SOC',min(T.return_SOC),'units','kg m^3 m s kWh','independent_recalculation',true);
end
