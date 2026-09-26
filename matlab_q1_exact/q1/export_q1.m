function export_q1(D,P,T,U,G,payload,proof,validation,physics,mutations,out)
writetable(payload,fullfile(out,'max_safe_payload.csv'));writetable(T,fullfile(out,'sortie_batches.csv'));writetable(U,fullfile(out,'service_summary.csv'));writetable(proof,fullfile(out,'optimality_certificates.csv'));writetable(mutations,fullfile(out,'validator_mutations.csv'));
writejson(fullfile(out,'overall_metrics.json'),G);writejson(fullfile(out,'validation.json'),validation);writejson(fullfile(out,'physics_checks.json'),physics);
writetable(D.boxes,fullfile(out,'box_inventory.csv'));
rr=cell(numel(P),9);
for i=1:numel(P),p=P(i);rr(i,:)={p.area,p.distance,p.terrainMax,p.cruise,p.outUp,p.backUp,size(p.cells,1),p.nodeZ-p.nodeDEM,p.localDistance-p.distance};end
writetable(cell2table(rr,'VariableNames',{'area','distance_m','terrain_max_m','cruise_m','outbound_climb_m','return_climb_m','intersected_cells','node_minus_dem_m','local_minus_geodesic_m'}),fullfile(out,'terrain_audit.csv'));
target=fullfile(out,'Q1_结果提交.xlsx');
template=fullfile(D.root,'input','结果提交模板.xlsx');
if ~isfile(template),template=fullfile(D.root,'data','raw','D题','结果提交模板.xlsx');end
assert(isfile(template),'Q1 submission template not found');copyfile(template,target,'f');
body=[cellstr(T.sortie_id),cellstr(T.service_area),cellstr(T.uav_type),cellstr(T.box_ids),num2cell([T.total_mass_kg,T.total_volume_m3,T.operation_time_s,T.energy_kWh,100*T.return_SOC])];
writecell(body,target,'Sheet','Q1_单点组批','Range','A2');
end
function writejson(path,value)
f=fopen(path,'w','n','UTF-8');c=onCleanup(@()fclose(f));fprintf(f,'%s',jsonencode(value,'PrettyPrint',true));
end
