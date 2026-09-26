function relays=q3_build_relays(D,dem,plan)
% A plan row fixes UAV, hover position, and requested service interval.
relays=struct('uavID',{},'componentID',{},'loc',{},'start_s',{}, ...
 'serviceStart_s',{},'serviceEnd_s',{},'return_s',{},'ready_s',{}, ...
 'componentReady_s',{},'energy_kWh',{},'name',{});
uavReady=zeros(numel(D.relayIDs),1);
componentReady=zeros(D.relayComponentCount,1);
for j=1:numel(plan)
 a=plan(j);serviceDuration=a.serviceEnd_s-a.serviceStart_s;
 P=q3_relay_physics(D,dem,a.loc,serviceDuration);
 assert(P.valid,'Relay %s physical plan invalid: %s',a.name,P.reason);
 minStart=max(0,uavReady(a.uav));
 serviceStart=max(a.serviceStart_s,minStart+D.relay.prep_s+P.outbound_s+D.relay.link_s);
 start=max(0,serviceStart-D.relay.prep_s-P.outbound_s-D.relay.link_s);
 free=find(componentReady<=start+D.tol.time);
 if isempty(free)
  [earliest,component]=min(componentReady);
  start=earliest;serviceStart=start+D.relay.prep_s+P.outbound_s+D.relay.link_s;
 else
  [~,h]=min(componentReady(free));component=free(h);
 end
 serviceEnd=serviceStart+serviceDuration;
 ret=serviceEnd+P.return_s;ready=ret+D.relay.turn_s;
 soc=1-P.energy_kWh/D.relay.energy_kWh;T=D.relayChargeFull_s;
 if soc<.9,chg=T*(.65*(.9-soc)/.9+.35);else,chg=T*.35*(1-soc)/.1;end
 compReady=ret+chg;
 relays(end+1)=struct('uavID',D.relayIDs(a.uav), ...
  'componentID',"R-B"+compose('%02d',component),'loc',a.loc, ...
  'start_s',start,'serviceStart_s',serviceStart, ...
  'serviceEnd_s',serviceEnd,'return_s',ret,'ready_s',ready, ...
  'componentReady_s',compReady,'energy_kWh',P.energy_kWh,'name',string(a.name)); %#ok<AGROW>
 uavReady(a.uav)=ready;componentReady(component)=compReady;
end
end
