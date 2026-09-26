function q3_export_submission_workbook(root,D,legs,S,relays,C,out,source)
% Copy the user's Q2 workbook and make every submission sheet consistent
% with the final Q3 transport and relay schedule. The Q2 source is untouched.
if nargin<8,source=fullfile(root,'results','q2_current','Q2_结果提交.xlsx');end
dest=fullfile(out,'Q3_结果提交.xlsx');
copyfile(source,dest,'f');
T=S.sorties;rows=cell(height(T),8);
for k=1:height(T)
 rows(k,:)={char(T.sortie_id(k)),char(T.uav_id(k)), ...
  char(T.uav_type(k)),char(T.battery_id(k)),T.start_s(k), ...
  char(T.service_order(k)),T.return_s(k),T.energy_kWh(k)};
end
writecell(rows,dest,'Sheet','Q2_运输架次','Range','A2');
T=S.boxDelivery;rows=cell(height(T),4);
for k=1:height(T)
 rows(k,:)={char(T.box_id(k)),char(T.sortie_id(k)), ...
  char(T.area(k)),T.arrival_s(k)};
end
writecell(rows,dest,'Sheet','Q2_逐箱交付','Range','A2');
rows=cell(numel(relays),11);
for j=1:numel(relays)
 r=relays(j);
 rows(j,:)={char("Q3-R"+compose('%02d',j)),char(r.uavID), ...
  char(r.componentID),r.start_s,r.loc(1),r.loc(2),r.loc(3), ...
  r.serviceStart_s,r.serviceEnd_s,r.return_s,r.energy_kWh};
end
writecell(rows,dest,'Sheet','Q3_中继架次','Range','A2');
seg=q3_transport_segments(D,legs,S);
phaseName=containers.Map({'climb','cruise','descent','handover'}, ...
 {'爬升','巡航','下降','物资投送'});
rows=cell(height(C),6);
for k=1:height(C)
 p=C.route(k);t0=C.t0(k);t1=C.t1(k);
 ix=find([seg.route]==p&[seg.t0]<=t0+1e-6&[seg.t1]>=t1-1e-6,1);
 assert(~isempty(ix),'Certificate has no transport phase');
 provider=string(C.provider(k));relayID='';mode='固定网关直连';
 if provider~="G01"
  mode='中继';j=[];
  for h=1:numel(relays)
   r=relays(h);
   if r.uavID==provider&&r.serviceStart_s<=t0+1e-6 ...
     &&r.serviceEnd_s>=t1-1e-6,j=h;break;end
  end
  assert(~isempty(j),'Certificate has no serving relay sortie');
  relayID=char("Q3-R"+compose('%02d',j));
 end
 rows(k,:)={char("Q2-"+compose('%03d',p)),phaseName(seg(ix).phase), ...
  t0,t1,mode,relayID};
end
writecell(rows,dest,'Sheet','Q3_通信保障','Range','A2');
end
