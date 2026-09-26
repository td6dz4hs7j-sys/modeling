function D = load_q2_data(root)
% Read Q2 source workbooks using fixed worksheet names and physical ranges.
if nargin < 1, root = fileparts(fileparts(mfilename('fullpath'))); end
p = fullfile(root,'input','数据','无人机应急物资运输基础数据');

c = readcell(fullfile(p,'调度中心与服务区.xlsx'),'Sheet','数据','Range','A1:F21');
D.nodes = cell2table(c([3,7:21],1:5),'VariableNames',{'id','name','lon','lat','z'});
D.nodes.id = string(D.nodes.id); D.nodes.name = string(D.nodes.name);

c = readcell(fullfile(p,'运输无人机数据.xlsx'),'Sheet','数据','Range','A3:R5');
D.uav = cell2table(c,'VariableNames',{'id','name','mass','payload','volume','speed','range0','rangeF','energy','reserve','prep','load','handover','boxhandover','up','down','eta','etaDown'});
D.uav.id = string(D.uav.id); D.uav.name = string(D.uav.name); D.uav.reserve = D.uav.reserve/100;
c = readcell(fullfile(p,'运输无人机数据.xlsx'),'Sheet','数据','Range','A9:C16');
D.uavInventory = cell2table(c,'VariableNames',{'id','type','initialNode'});
D.uavInventory.id = string(D.uavInventory.id); D.uavInventory.type = string(D.uavInventory.type); D.uavInventory.initialNode = string(D.uavInventory.initialNode);
c = readcell(fullfile(p,'运输无人机数据.xlsx'),'Sheet','数据','Range','A20:C22');
D.batteryInventory = cell2table(c,'VariableNames',{'type','count','fullCharge_s'});
D.batteryInventory.type = string(D.batteryInventory.type);

c = readcell(fullfile(p,'物资需求与配送时限.xlsx'),'Sheet','逐箱货箱清单','Range','A2:I81');
D.boxes = cell2table(c,'VariableNames',{'id','area','category','mass','volume','firstBatch','firstDeadline_s','expected_s','priority'});
D.boxes.id = string(D.boxes.id); D.boxes.area = string(D.boxes.area); D.boxes.category = string(D.boxes.category);
D.boxes.firstBatch = string(D.boxes.firstBatch)=="是";
D.boxes.firstDeadline_s = cellfun(@q2_num_or_nan,c(:,7));
D.boxes.expected_s = cellfun(@q2_num_or_nan,c(:,8));
D.boxes.priority = cellfun(@q2_num_or_nan,c(:,9));

c = readcell(fullfile(p,'物资需求与配送时限.xlsx'),'Sheet','数据','Range','A1:I54');
D.demandSummary = c;
D.nodeIndex = containers.Map(cellstr(D.nodes.id),num2cell(1:height(D.nodes)));
D.boxNodeIndex = zeros(height(D.boxes),1);
for b=1:height(D.boxes), D.boxNodeIndex(b)=D.nodeIndex(char(D.boxes.area(b))); end
D.boxMass = D.boxes.mass; D.boxVolume = D.boxes.volume;
D.isMedical = D.boxes.category=="医疗物资";
D.isHard = D.isMedical | D.boxes.firstBatch;
D.hardDeadline_s = inf(height(D.boxes),1);
D.hardDeadline_s(D.isMedical) = D.boxes.expected_s(D.isMedical);
f = D.boxes.firstBatch; D.hardDeadline_s(f)=min(D.hardDeadline_s(f),D.boxes.firstDeadline_s(f));

D.inventory = struct('uav',D.uavInventory,'battery',D.batteryInventory);
C=physical_constants();D.g = C.g; D.tol = struct('energy',1e-8,'time',1e-6,'mass',1e-9,'volume',1e-12);
D.clearance=C.clearance; D.deliveryHeight=C.deliveryHeight;
D.root = root;
assert(height(D.nodes)==16 && height(D.boxes)==80 && height(D.uavInventory)==8);
assert(numel(unique(D.boxes.id))==80 && all(D.boxes.mass>0 & D.boxes.volume>0));
assert(sum(D.batteryInventory.count)==14 && all(D.batteryInventory.count>=1));
assert(all(ismember(D.boxes.area,D.nodes.id(2:end))));
assert(all(isfinite(D.hardDeadline_s(D.isHard)) & D.hardDeadline_s(D.isHard)>0));
assert(all(isfinite(D.boxes.expected_s(D.isMedical)) & D.boxes.expected_s(D.isMedical)>0));
assert(all(D.uavInventory.initialNode=="O01"));
end

function x=q2_num_or_nan(v)
if isempty(v), x=NaN; elseif isnumeric(v), x=double(v); else, x=str2double(string(v)); end
end
