function D=load_problem_data(root)
% Original workbooks are read with explicit ranges; no inferred headers.
p=fullfile(root,'input','数据','无人机应急物资运输基础数据');
if ~isfolder(p)
 p=fullfile(root,'data','raw','D题','数据','无人机应急物资运输基础数据');
end
assert(isfolder(p),'Q1 input data directory not found');
c=readcell(fullfile(p,'调度中心与服务区.xlsx'),'Sheet','数据','Range','A1:F21');
D.nodes=cell2table(c([3,7:21],1:5),'VariableNames',{'id','name','lon','lat','z'});
D.nodes.id=string(D.nodes.id); D.nodes.name=string(D.nodes.name);
c=readcell(fullfile(p,'运输无人机数据.xlsx'),'Sheet','数据','Range','A3:R5');
D.uav=cell2table(c,'VariableNames',{'id','name','mass','payload','volume','speed','range0','rangeF','energy','reserve','prep','load','handover','boxhandover','up','down','eta','etaDown'});
D.uav.id=string(D.uav.id);D.uav.name=string(D.uav.name);D.uav.reserve=D.uav.reserve/100;
c=readcell(fullfile(p,'物资需求与配送时限.xlsx'),'Sheet','逐箱货箱清单','Range','A2:I81');
D.boxes=cell2table(c(:,1:5),'VariableNames',{'id','area','category','mass','volume'});
D.boxes.id=string(D.boxes.id);D.boxes.area=string(D.boxes.area);D.boxes.category=string(D.boxes.category);
assert(height(D.boxes)==80 && numel(unique(D.boxes.id))==80);
assert(D.boxes.id(1)=="S001-MED-01" && D.boxes.id(end)=="S015-FOD-01");
assert(height(D.nodes)==16 && all(ismember(D.boxes.area,D.nodes.id(2:end))));
assert(all(D.boxes.mass>0 & D.boxes.volume>0));
C=physical_constants();D.g=C.g;D.clearance=C.clearance;D.deliveryHeight=C.deliveryHeight;
D.tol=struct('mass',1e-9,'volume',1e-12,'energy',1e-10,'objective',1e-10,'time',1e-6,'milpEnergy',1e-8);
D.root=root;
end
