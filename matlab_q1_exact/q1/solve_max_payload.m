function T=solve_max_payload(D,P,rho)
if nargin<3,rho=D.uav.reserve;end
if isscalar(rho),rho=repmat(rho,3,1);end
rows=cell(0,15);
for i=1:numel(P)
 for k=1:3
  u=D.uav(k,:);p=P(i);budget=(1-rho(k))*u.energy;
  E0=flight_energy_model(u,p,0,D.g);EF=flight_energy_model(u,p,u.payload,D.g);
  binding=false;el=NaN;
  if E0>budget,m=NaN;
  elseif EF<=budget,m=u.payload;
  else
   lo=0;hi=u.payload;
   while hi-lo>1e-10
    mid=(lo+hi)/2;
    if flight_energy_model(u,p,mid,D.g)<=budget,lo=mid;else,hi=mid;end
   end
   m=lo;el=m;binding=true;
  end
  if isnan(m),e=NaN;else,e=flight_energy_model(u,p,m,D.g);end
  [~,t]=flight_time_model(u,p,0);
  rows(end+1,:)={p.area,u.id,p.distance,p.terrainMax,p.cruise,p.outUp,p.backUp,u.payload,el,m,e,t,rho(k),binding,isfinite(m)}; %#ok<AGROW>
 end
end
T=cell2table(rows,'VariableNames',{'service_area','uav_type','distance_m','terrain_max_m','cruise_altitude_m','outbound_climb_m','return_climb_m','rated_payload_kg','energy_limited_payload_kg','max_safe_payload_kg','round_trip_energy_kWh','round_trip_flight_time_s','reserve_fraction','energy_binding','reachable'});
end
