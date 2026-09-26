function S=solve_batching(D,C,order,weight)
% Exhaustive count-state dynamic program; no pruning or random decisions.
if nargin<3,order=[1 2 3];end
if nargin<4,weight=[];end
ns=size(C.states,1);F=inf(ns,3);F(1,:)=0;choice=zeros(ns,1);
for j=2:ns
 valid=find(all(C.patterns<=C.states(j,:),2));
 for z=valid'
  prev=j-C.patterns(z,:)*C.base';v=C.cost(z,:)+F(prev,:);
  if ~all(isfinite(v)),continue;end
  if isempty(weight),key=v(order);old=F(j,order);
  else,key=[v*weight(:),v(order)];old=[F(j,:)*weight(:),F(j,order)];end
  d=key-old;h=find(abs(d)>D.tol.objective | isnan(d),1);
  if ~all(isfinite(F(j,:))),better=true;
  elseif isempty(h),better=false;else,better=key(h)<old(h);end
  if better,F(j,:)=v;choice(j)=z;end
 end
end
S=struct('feasible',all(isfinite(F(end,:))),'cost',F(end,:),'patterns',[],'uav',[],'box_ids',{{}},'state_count',ns,'pattern_count',size(C.patterns,1));
if ~S.feasible,return;end
j=ns;used=zeros(size(C.n));
while j>1
 z=choice(j);assert(z>0);ids=strings(0,1);
 for c=1:numel(C.n)
  loc=find(C.group==c);take=C.patterns(z,c);ids=[ids;C.boxes.id(loc(used(c)+(1:take)))];used(c)=used(c)+take; %#ok<AGROW>
 end
 S.patterns(end+1)=z;S.uav(end+1)=C.k(z);S.box_ids{end+1}=ids;
 j=j-C.patterns(z,:)*C.base';
end
end
