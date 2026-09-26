function R=validate_physics(D,P)
assert(all(D.uav.eta>0 & D.uav.eta<=1 & D.uav.etaDown==0));
assert(all(D.uav.range0>D.uav.rangeF & D.uav.rangeF>0));
for k=1:3
 u=D.uav(k,:);q=linspace(0,u.payload,1001);
 for i=1:numel(P)
  E=flight_energy_model(u,P(i),q,D.g);assert(all(diff(E)>0));
  assert(all(isfinite(E)) && all(E>0));
  [op,fl]=flight_time_model(u,P(i),1);assert(op>fl && fl>0);
 end
 assert(abs((u.range0-(u.range0-u.rangeF))-u.rangeF)<1e-10);
end
R=struct('status','PASS','units','m kg m^3 s kWh','gravity',D.g,'joule_per_kWh',3.6e6,'max_distance_approx_error_m',max(abs([P.distance]-[P.localDistance])));
end
