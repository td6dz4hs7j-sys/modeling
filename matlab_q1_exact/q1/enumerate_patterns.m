function C=enumerate_patterns(D,p,rho)
if isscalar(rho),rho=repmat(rho,3,1);end
B=D.boxes(D.boxes.area==p.area,:);
[types,~,group]=unique([B.mass B.volume],'rows');n=accumarray(group,1)';
base=[1 cumprod(n(1:end-1)+1)];ns=prod(n+1);states=zeros(ns,numel(n));
for c=1:numel(n),states(:,c)=mod(floor((0:ns-1)'/base(c)),n(c)+1);end
patterns=zeros(0,numel(n));cost=zeros(0,3);kt=zeros(0,1);
for j=2:ns
 b=states(j,:);m=b*types(:,1);v=b*types(:,2);
 for k=1:3
  u=D.uav(k,:);
  if m<=u.payload+D.tol.mass && v<=u.volume+D.tol.volume
   E=flight_energy_model(u,p,m,D.g);
   if E<=(1-rho(k))*u.energy+D.tol.energy
    T=flight_time_model(u,p,sum(b));patterns(end+1,:)=b;cost(end+1,:)=[1 E T];kt(end+1,1)=k; %#ok<AGROW>
   end
  end
 end
end
C=struct('area',p.area,'p',p,'boxes',B,'types',types,'group',group,'n',n,'base',base,'states',states,'patterns',patterns,'cost',cost,'k',kt,'rho',rho);
end
