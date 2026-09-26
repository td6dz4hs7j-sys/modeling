function S=baseline_batching(D,C)
% Greedy largest feasible box count, then least energy; no backtracking.
r=C.n;zlist=[];
while any(r)
 valid=find(all(C.patterns<=r,2));if isempty(valid),S=struct('feasible',false);return;end
 [~,ix]=sortrows([-sum(C.patterns(valid,:),2),C.cost(valid,2)],[1 2]);z=valid(ix(1));zlist(end+1)=z;r=r-C.patterns(z,:); %#ok<AGROW>
end
S=struct('feasible',true,'cost',sum(C.cost(zlist,:),1),'patterns',zlist,'uav',C.k(zlist)','box_ids',{{}});
used=zeros(size(C.n));
for z=zlist
 ids=strings(0,1);
 for c=1:numel(C.n)
  loc=find(C.group==c);take=C.patterns(z,c);ids=[ids;C.boxes.id(loc(used(c)+(1:take)))];used(c)=used(c)+take; %#ok<AGROW>
 end
 S.box_ids{end+1}=ids;
end
end
