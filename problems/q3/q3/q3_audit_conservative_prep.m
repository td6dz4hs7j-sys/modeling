function A = q3_audit_conservative_prep(D,S)
% Audit the timing contract that does not rely on preparation before return.
% Fixed preparation and loading may overlap after the previous return.
issues = strings(0,1);
tol = D.tol.time;
for p = 1:numel(S.routes)
    r = S.routes(p);
    if ~all(isfield(r,{'prepStart_s','loadStart_s','takeoff_s'}))
        issues(end+1) = sprintf('route %d has no separate preparation/loading times',p); %#ok<AGROW>
        continue
    end
    u = D.uav(r.typeIdx,:);
    if r.prepStart_s < -tol || r.loadStart_s < -tol || ...
            r.prepStart_s + u.prep > r.takeoff_s + tol || ...
            r.loadStart_s + numel(r.boxIdx)*u.load > r.takeoff_s + tol
        issues(end+1) = sprintf('route %d preparation/loading incomplete at takeoff',p); %#ok<AGROW>
    end
end
ids = unique(string({S.routes.uavID}));
for a = 1:numel(ids)
    ix = find(string({S.routes.uavID}) == ids(a));
    if isfield(S.routes,'takeoff_s')
        [~,ord] = sort([S.routes(ix).takeoff_s]);
    else
        [~,ord] = sort([S.routes(ix).start_s]);
    end
    ix = ix(ord);
    for k = 2:numel(ix)
        prev = S.routes(ix(k-1));
        cur = S.routes(ix(k));
        if ~all(isfield(cur,{'prepStart_s','loadStart_s'}))
            continue
        end
        if cur.prepStart_s < prev.return_s - tol
            issues(end+1) = sprintf('route %d fixed preparation starts before UAV %s returned',ix(k),ids(a)); %#ok<AGROW>
        end
        if cur.loadStart_s < prev.return_s - tol
            issues(end+1) = sprintf('route %d loading starts before UAV %s returned',ix(k),ids(a)); %#ok<AGROW>
        end
    end
end
A = struct('status','PASS','issues',issues);
if ~isempty(issues), A.status = 'FAIL'; end
end
