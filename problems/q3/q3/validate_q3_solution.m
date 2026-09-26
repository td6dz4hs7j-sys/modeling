function V=validate_q3_solution(D,dem,legs,S,relays,varargin)
% Independent Q3 audit. No communication sampling is accepted as a PASS.
issues=strings(0,1);certificate=struct('route',{},'t0',{},'t1',{},'provider',{},'margin_dB',{});
ip=inputParser;addParameter(ip,'InheritQ2Prestage',false,@(x)islogical(x)&&isscalar(x));parse(ip,varargin{:});
if isfield(S.routes,'takeoff_s')
 qt=validate_q2_solution(D,legs,S,'RequireAllExpectedOnTime',false, ...
  'AllowPrepBatteryOverlap',true,'AllowFixedPrepPrestage',true);
else
 qt=validate_q2_solution(D,legs,S);
end
if ~strcmp(qt.status,'PASS'),issues=[issues;"Q2 transport audit: "+qt.issues(:)];end
if ip.Results.InheritQ2Prestage
 prepAudit=struct('status',qt.status,'issues',qt.issues,'contract','Inherited Q2 fixed prestaging; post-return loading and full battery recharge');
else
 prepAudit=q3_audit_conservative_prep(D,S);
 if ~strcmp(prepAudit.status,'PASS')
  issues=[issues;"Post-return preparation/loading audit: "+prepAudit.issues(:)];
 end
end
n=numel(relays);relayEnergy=0;lastReturn=0;
G=[D.nodes.lon(1),D.nodes.lat(1),D.nodes.z(1)+D.radio.gatewayAGL_m];
for j=1:n
 r=relays(j);
 if ~ismember(string(r.uavID),D.relayIDs),issues(end+1)="invalid relay UAV ID";end %#ok<AGROW>
 expectedComponent="R-B"+compose('%02d',1:D.relayComponentCount);
 if ~ismember(string(r.componentID),expectedComponent),issues(end+1)="invalid relay component ID";end %#ok<AGROW>
 if ~all(isfinite([r.loc,r.start_s,r.serviceStart_s,r.serviceEnd_s,r.return_s,r.ready_s,r.componentReady_s]))
  issues(end+1)="nonfinite relay task field";continue
 end
 if r.start_s<0||r.serviceEnd_s<r.serviceStart_s
  issues(end+1)="invalid relay task time";continue
 end
 agl=r.loc(3)-q3_dem_at(dem,r.loc(1:2));
 if agl<0||agl>D.relay.maxAGL_m+1e-6,issues(end+1)="relay AGL out of range";end %#ok<AGROW>
 P=q3_relay_physics(D,dem,r.loc,r.serviceEnd_s-r.serviceStart_s);
 if ~P.valid,issues(end+1)="relay route or energy invalid: "+string(P.reason);end %#<AGROW>
 if abs(r.serviceStart_s-(r.start_s+D.relay.prep_s+P.outbound_s+D.relay.link_s))>D.tol.time
  issues(end+1)="relay service start mismatch";end %#ok<AGROW>
 if abs(r.return_s-(r.serviceEnd_s+P.return_s))>D.tol.time
  issues(end+1)="relay O01 return mismatch";end %#ok<AGROW>
 if abs(r.ready_s-(r.return_s+D.relay.turn_s))>D.tol.time
  issues(end+1)="relay UAV turnover mismatch";end %#ok<AGROW>
 soc=1-P.energy_kWh/D.relay.energy_kWh;
 if soc<D.relay.reserve-1e-8,issues(end+1)="relay return SOC below reserve";end %#ok<AGROW>
 T=D.relayChargeFull_s;
 if soc<.9,chg=T*(.65*(.9-soc)/.9+.35);else,chg=T*.35*(1-soc)/.1;end
 if abs(r.componentReady_s-(r.return_s+chg))>D.tol.time
  issues(end+1)="relay component charge-ready mismatch";end %#ok<AGROW>
 [bh,bm]=q3_link_interval(r.loc,r.loc,G,'backhaul',D,dem);
 if ~bh,issues(end+1)="relay backhaul unavailable";end %#<AGROW>
 if isfield(r,'energy_kWh')&&abs(r.energy_kWh-P.energy_kWh)>D.tol.energy
  issues(end+1)="relay reported energy mismatch";end %#ok<AGROW>
 relayEnergy=relayEnergy+P.energy_kWh;lastReturn=max(lastReturn,r.return_s);
end
for i=1:n,for j=i+1:n
 a=relays(i);b=relays(j);
 if a.uavID==b.uavID&&max(a.start_s,b.start_s)<min(a.ready_s,b.ready_s)-D.tol.time
  issues(end+1)="relay UAV tasks overlap";end %#ok<AGROW>
 if a.componentID==b.componentID&&max(a.start_s,b.start_s)<min(a.componentReady_s,b.componentReady_s)-D.tol.time
  issues(end+1)="relay energy component/charging overlap";end %#ok<AGROW>
end,end
% A relay is usable only after its link setup and only until service ends.
if isempty(issues)
 try
  seg=q3_transport_segments(D,legs,S);
  for k=1:numel(seg)
   ss=seg(k);bounds=[ss.t0,ss.t1];
   for j=1:n
    if relays(j).serviceStart_s>ss.t0&&relays(j).serviceStart_s<ss.t1,bounds(end+1)=relays(j).serviceStart_s;end %#ok<AGROW>
    if relays(j).serviceEnd_s>ss.t0&&relays(j).serviceEnd_s<ss.t1,bounds(end+1)=relays(j).serviceEnd_s;end %#ok<AGROW>
   end
   bounds=unique(sort(bounds));
   for b=1:numel(bounds)-1
    [ok,C]=audit_interval(ss,bounds(b),bounds(b+1),G,D,dem,relays,0);
    if ~ok,issues(end+1)=sprintf('uncertified continuous communication: route %d, %.6f to %.6f s',ss.route,bounds(b),bounds(b+1)); %#ok<AGROW>
    else,certificate=[certificate;C(:)];end %#ok<AGROW>
   end
  end
 catch ME
  issues(end+1)="communication validator exception: "+string(ME.message);
 end
end
V=struct('status',char(ternary(isempty(issues),"PASS","FAIL")), ...
 'issues',issues,'transportAudit',qt,'preparationAudit',prepAudit,'relaySorties',n, ...
 'inheritQ2Prestage',ip.Results.InheritQ2Prestage, ...
 'transportEnergy_kWh',qt.independentMetrics.energy_kWh, ...
 'relayEnergy_kWh',relayEnergy,'jointEnergy_kWh',qt.independentMetrics.energy_kWh+relayEnergy, ...
 'makespan_s',max(qt.independentMetrics.Cmax_s,lastReturn), ...
 'continuousCertificate',certificate);
end

function [ok,C]=audit_interval(s,t0,t1,G,D,dem,relays,depth)
C=struct('route',{},'t0',{},'t1',{},'provider',{},'margin_dB',{});
a=s.A+((t0-s.t0)/(s.t1-s.t0))*(s.B-s.A);
b=s.A+((t1-s.t0)/(s.t1-s.t0))*(s.B-s.A);
[yes,m]=q3_link_interval(a,b,G,'fixed',D,dem);
if yes
 ok=true;C=struct('route',s.route,'t0',t0,'t1',t1,'provider',"G01",'margin_dB',m);return
end
for j=1:numel(relays)
 r=relays(j);
 if r.serviceStart_s<=t0+1e-9&&r.serviceEnd_s>=t1-1e-9
  [yes,m]=q3_link_interval(a,b,r.loc,'access',D,dem);
  if yes
   ok=true;C=struct('route',s.route,'t0',t0,'t1',t1,'provider',string(r.uavID),'margin_dB',m);return
  end
 end
end
if depth>=16||t1-t0<.01,ok=false;return;end
mid=(t0+t1)/2;[ok1,C1]=audit_interval(s,t0,mid,G,D,dem,relays,depth+1);
if ~ok1,ok=false;return;end
[ok2,C2]=audit_interval(s,mid,t1,G,D,dem,relays,depth+1);
ok=ok2;if ok,C=[C1;C2];end
end

function v=ternary(test,a,b)
if test,v=a;else,v=b;end
end
