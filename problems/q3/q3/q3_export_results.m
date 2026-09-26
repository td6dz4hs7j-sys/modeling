function q3_export_results(root,D,dem,legs,S,relays,V,outName)
assert(strcmp(V.status,'PASS'),'Exports require independent validator PASS');
if nargin<8,outName='q3';end
out=fullfile(root,'results',outName);if ~isfolder(out),mkdir(out);end
save(fullfile(out,'q3_final_solution.mat'),'S','relays','V','-v7.3');
writetable(S.sorties,fullfile(out,'transport_sorties.csv'));
writetable(S.boxDelivery,fullfile(out,'box_deliveries.csv'));
n=numel(relays);id=strings(n,1);uav=strings(n,1);component=strings(n,1); ...
 name=strings(n,1);lon=zeros(n,1);lat=lon;alt_m=lon;agl_m=lon; ...
 start_s=lon;serviceStart_s=lon;serviceEnd_s=lon;return_s=lon; ...
 ready_s=lon;componentReady_s=lon;energy_kWh=lon;returnSOC=lon;
for j=1:n
 r=relays(j);id(j)="Q3-R"+compose('%02d',j);uav(j)=r.uavID;
 component(j)=r.componentID;name(j)=r.name;
 lon(j)=r.loc(1);lat(j)=r.loc(2);alt_m(j)=r.loc(3);
 agl_m(j)=r.loc(3)-q3_dem_at(dem,r.loc(1:2));
 start_s(j)=r.start_s;serviceStart_s(j)=r.serviceStart_s;
 serviceEnd_s(j)=r.serviceEnd_s;return_s(j)=r.return_s;
 ready_s(j)=r.ready_s;componentReady_s(j)=r.componentReady_s;
 energy_kWh(j)=r.energy_kWh;returnSOC(j)=1-r.energy_kWh/D.relay.energy_kWh;
end
T=table(id,uav,component,name,lon,lat,alt_m,agl_m,start_s, ...
 serviceStart_s,serviceEnd_s,return_s,ready_s,componentReady_s, ...
 energy_kWh,returnSOC);
writetable(T,fullfile(out,'relay_sorties.csv'));
C=struct2table(V.continuousCertificate);
writetable(C,fullfile(out,'continuous_communication_certificate.csv'));
route=(1:numel(S.routes))';providers=strings(numel(route),1); ...
 gateway_s=zeros(numel(route),1);relay_s=zeros(numel(route),1);
for p=route'
 z=C.route==p;pp=unique(string(C.provider(z)));providers(p)=join(pp,' + ');
 d=C.t1(z)-C.t0(z);gateway_s(p)=sum(d(string(C.provider(z))=="G01"));
 relay_s(p)=sum(d(string(C.provider(z))~="G01"));
end
writetable(table(route,providers,gateway_s,relay_s), ...
 fullfile(out,'transport_communication_providers.csv'));
metric=table(numel(S.routes),n,V.transportEnergy_kWh,V.relayEnergy_kWh, ...
 V.jointEnergy_kWh,V.makespan_s,V.makespan_s/3600,S.metrics.W, ...
 'VariableNames',{'transport_sorties','relay_sorties','transport_energy_kWh', ...
 'relay_energy_kWh','joint_energy_kWh','makespan_s','makespan_h','weighted_lateness'});
writetable(metric,fullfile(out,'q3_metrics.csv'));
fid=fopen(fullfile(out,'validator_PASS.txt'),'w');
fprintf(fid,'validate_q3_solution: PASS\nTransport sorties: %d\nRelay sorties: %d\n',numel(S.routes),n);
fprintf(fid,'Transport energy: %.9f kWh\nRelay energy: %.9f kWh\n',V.transportEnergy_kWh,V.relayEnergy_kWh);
fprintf(fid,'Joint energy: %.9f kWh\nJoint makespan: %.9f s\n',V.jointEnergy_kWh,V.makespan_s);
fprintf(fid,'Continuous communication certificate intervals: %d\n',height(C));fclose(fid);
plot_q3_final(root,D,dem,legs,S,relays,V,C,T,outName);
if strcmp(outName,'q3_current')
 q3_export_submission_workbook(root,D,legs,S,relays,C,out);
end
end
