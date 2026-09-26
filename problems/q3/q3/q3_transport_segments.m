function seg=q3_transport_segments(D,legs,S)
% Piecewise affine 3-D transport motion, including each handover interval.
seg=struct('route',{},'phase',{},'t0',{},'t1',{},'A',{},'B',{});
for p=1:numel(S.routes)
 r=S.routes(p);u=D.uav(r.typeIdx,:);ix=r.boxIdx(:);nodes=[1,r.nodeOrder(:)',1];
 % Q2 pre-staged sorties launch when the fixed prep/load work is complete;
 % their flight trajectory starts at takeoff, which is already start_s.
 if isfield(r,'takeoff_s')
  t=r.takeoff_s;
  assert(abs(t-r.start_s)<1e-6,'Q3 trajectory must begin at Q2 takeoff');
 else
  t=r.start_s+u.prep+numel(ix)*u.load;
 end
 for j=1:numel(nodes)-1
  a=nodes(j);b=nodes(j+1);P=q3_get_leg(legs,a,b);
  za=D.nodes.z(a)+double(a~=1)*D.deliveryHeight;
  zb=D.nodes.z(b)+double(b~=1)*D.deliveryHeight;
  A=[D.nodes.lon(a),D.nodes.lat(a),za];B=[D.nodes.lon(b),D.nodes.lat(b),zb];
  C=[A(1:2),P.cruise_m];E=[B(1:2),P.cruise_m];
  [seg,t]=append(seg,p,'climb',t,P.up_m/u.up,A,C);
  [seg,t]=append(seg,p,'cruise',t,P.distance_m/u.speed,C,E);
  [seg,t]=append(seg,p,'descent',t,P.down_m/u.down,E,B);
  if b~=1
   n=sum(D.boxNodeIndex(ix)==b);
   [seg,t]=append(seg,p,'handover',t,u.handover+n*u.boxhandover,B,B);
  end
 end
 assert(abs(t-r.return_s)<1e-5,'Q3 trajectory/Q2 route time mismatch');
end
end

function [s,t]=append(s,p,phase,t,dur,A,B)
if dur<=0,return;end
s(end+1)=struct('route',p,'phase',phase,'t0',t,'t1',t+dur,'A',A,'B',B);
t=t+dur;
end

function P=q3_get_leg(legs,a,b)
n=16;g=(a-1)*(n-1)+b-double(b>a);P=legs(g);
end
