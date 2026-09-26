function R=verify_milp(D,C,S)
% Independent integer pattern multiplicities, three sequential objectives.
Aeq=C.patterns';beq=C.n';n=size(C.patterns,1);
opts=optimoptions('intlinprog','Display','off','RelativeGapTolerance',1e-9,'AbsoluteGapTolerance',1e-9,'ConstraintTolerance',1e-9,'MaxTime',120);
[x,nstar,f1,o1]=intlinprog(ones(n,1),1:n,[],[],Aeq,beq,zeros(n,1),[],opts);assert(f1==1);
nstar=round(nstar);Aeq=[Aeq;ones(1,n)];beq=[beq;nstar];
[x,estar,f2,o2]=intlinprog(C.cost(:,2),1:n,[],[],Aeq,beq,zeros(n,1),[],opts);assert(f2==1);
[x,tstar,f3,o3]=intlinprog(C.cost(:,3)/3600,1:n,C.cost(:,2)',estar+D.tol.milpEnergy,Aeq,beq,zeros(n,1),[],opts);assert(f3==1);
assert(max(abs(Aeq*round(x)-beq))<1e-8);
assert(abs(nstar-S.cost(1))<1e-8 && abs(estar-S.cost(2))<1e-7 && abs(tstar*3600-S.cost(3))<1e-4,'DP/MILP disagreement');
R=struct('service_area',C.area,'patterns',n,'states',size(C.states,1),'N_DP',S.cost(1),'N_MILP',nstar,'energy_DP_kWh',S.cost(2),'energy_MILP_kWh',estar,'time_DP_s',S.cost(3),'time_MILP_s',tstar*3600,'N_gap',o1.absolutegap,'E_gap',o2.absolutegap,'T_gap_h',o3.absolutegap,'E_lower_bound',estar-o2.absolutegap,'E_upper_bound',estar,'exit_N',f1,'exit_E',f2,'exit_T',f3);
end
