function A=q3_audit_continuous_certificate(D,dem,legs,S,relays,V)
% Separate, sample-free audit of the exported interval certificate.
assert(strcmp(V.status,'PASS'),'Q3 solution is not validator PASS');
seg=q3_transport_segments(D,legs,S);C=V.continuousCertificate;
G=[D.nodes.lon(1),D.nodes.lat(1),D.nodes.z(1)+D.radio.gatewayAGL_m];
tol=max(D.tol.time,1e-7);maxGap=0;minMargin=Inf;totalTime=0;
for i=1:numel(seg)
 s=seg(i);hit=find([C.route]==s.route & [C.t0]>=s.t0-tol & [C.t1]<=s.t1+tol);
 assert(~isempty(hit),'No certificate for route %d %s',s.route,s.phase);
 [~,o]=sort([C(hit).t0]);cc=C(hit(o));
 maxGap=max(maxGap,max(0,cc(1).t0-s.t0));
 maxGap=max(maxGap,max(0,s.t1-cc(end).t1));
 assert(cc(1).t0<=s.t0+tol && cc(end).t1>=s.t1-tol, ...
  'Certificate does not cover route %d phase %s endpoints',s.route,s.phase);
 for k=1:numel(cc)
  c=cc(k);assert(c.t0<=c.t1 && c.t0>=s.t0-tol && c.t1<=s.t1+tol);
  if k>1
   gap=max(0,c.t0-cc(k-1).t1);maxGap=max(maxGap,gap);
   assert(gap<=tol,'Certificate has a time gap in route %d',s.route);
  end
  a=s.A+((c.t0-s.t0)/(s.t1-s.t0))*(s.B-s.A);
  b=s.A+((c.t1-s.t0)/(s.t1-s.t0))*(s.B-s.A);
  if string(c.provider)=="G01"
   [yes,m]=q3_link_interval(a,b,G,'fixed',D,dem);
  else
   idx=[];
   for j=1:numel(relays)
    r=relays(j);
    if r.uavID==string(c.provider)&&r.serviceStart_s<=c.t0+tol ...
       &&r.serviceEnd_s>=c.t1-tol
     idx=j;break
    end
   end
   assert(~isempty(idx),'Relay certificate has no active sortie');
   r=relays(idx);
   [bh,~]=q3_link_interval(r.loc,r.loc,G,'backhaul',D,dem);
   assert(bh,'Relay certificate has no backhaul');
   [yes,m]=q3_link_interval(a,b,r.loc,'access',D,dem);
  end
  assert(yes && m>=-1e-8,'Unproved communication interval');
  minMargin=min(minMargin,m);totalTime=totalTime+(c.t1-c.t0);
 end
end
A=struct('status','PASS','segments',numel(seg),'intervals',numel(C), ...
 'maxUncoveredTime_s',maxGap,'minimumCertifiedMargin_dB',minMargin, ...
 'certifiedOperatingTime_s',totalTime,'method','interval bounds, no time sampling');
end
