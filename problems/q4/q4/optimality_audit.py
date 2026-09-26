"""Independent exhaustive optimality audit; does not import the Q4 solver."""
import argparse
import csv
import hashlib
import itertools
import json
import math
import sys
from pathlib import Path
import h5py
import numpy as np
import scipy
from scipy.sparse import csr_matrix
from scipy.sparse.csgraph import maximum_bipartite_matching

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'results/q3_overlay'
PREV = ROOT / 'results/q4_final'
OUT = ROOT / 'results/q4_optimality_audit'
TYPES = ('A_uav','B_uav','C_uav','A_battery','B_battery','C_battery','R_uav','R_component')
STOCK = (4,2,2,6,4,4,2,6)

def read(p):
    with p.open(encoding='utf-8-sig', newline='') as f:
        return list(csv.DictReader(f))

def canonical(groups):
    return tuple(sorted(tuple(sorted(g)) for g in groups))

def matching_count(tasks, kind):
    n = len(tasks)
    adj = np.zeros((n,n), dtype=np.int8)
    for i,a in enumerate(tasks):
        for j,b in enumerate(tasks):
            if i == j: continue
            ok = a['end'] <= b['start'] + 1e-5
            if kind in TYPES[:3]:
                ok = ok and a['takeoff'] <= b['prep'] + 1e-5
            if ok:
                assert a['start'] < b['start']  # Acyclic temporal graph.
                adj[i,j] = 1
    m = maximum_bipartite_matching(csr_matrix(adj), perm_type='column') if n else []
    return n - sum(int(v >= 0) for v in m)

def load():
    ts,rs,cs = [read(SRC/n) for n in ('transport_sorties.csv','relay_sorties.csv','continuous_communication_certificate.csv')]
    with h5py.File(SRC/'q3_final_solution.mat') as f:
        for i,t in enumerate(ts):
            for key in ('prepStart_s','loadStart_s','takeoff_s','return_s','batteryReady_s'):
                t[key] = float(f[f['S/routes'][key][0,i]][()].item())
            t['sites'] = set(t['service_order'].split('→'))
            t['relays'] = set()
    for c in cs:
        if c['provider'] == 'G01': continue
        hits = [r['id'] for r in rs if r['uav']==c['provider'] and float(r['serviceStart_s'])<=float(c['t0'])+1e-6 and float(r['serviceEnd_s'])>=float(c['t1'])-1e-6]
        assert len(hits)==1
        ts[int(c['route'])-1]['relays'].update(hits)
    # Independent set-merging construction of indivisible blocks.
    blocks = [{f'S{i:03d}'} for i in range(1,16)]
    for t in ts:
        hit = [b for b in blocks if b & t['sites']]
        blocks = [b for b in blocks if not b & t['sites']] + [set().union(*hit)]
    blocks = canonical(blocks)
    assert len(blocks)==8
    return ts,rs,blocks

def subgroup(sites, ts, rs):
    picked = [t for t in ts if t['sites'] <= set(sites)]
    assert all(not t['sites'] & set(sites) or t in picked for t in ts)
    relay_ids = set().union(*(t['relays'] for t in picked))
    relays = [r for r in rs if r['id'] in relay_ids]
    need=[]
    for kind in TYPES:
        tasks=[]
        if kind[0] in 'ABC':
            for t in picked:
                if t['uav_type'] != kind[0]: continue
                aircraft = kind.endswith('_uav')
                tasks.append(dict(start=t['loadStart_s'] if aircraft else t['takeoff_s'],
                                  end=t['return_s'] if aircraft else t['batteryReady_s'],
                                  takeoff=t['takeoff_s'], prep=t['prepStart_s']))
        else:
            tasks=[dict(start=float(r['start_s']),end=float(r['ready_s'] if kind=='R_uav' else r['componentReady_s'])) for r in relays]
        need.append(matching_count(tasks,kind))
    work = sum(float(t['operation_s']) for t in picked) + sum(float(r['return_s'])-float(r['start_s']) for r in relays)
    return dict(sites=sites, need=need, work=work, relay_copies=len(relays))

def brief(x):
    return {k:x[k] for k in ('groups','resources','gap','units','cv','relay_copies','by_type')}

def dominates(a,b):
    return all(x<=y+1e-10 for x,y in zip(a,b)) and any(x<y-1e-10 for x,y in zip(a,b))

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--smoke',action='store_true'); args=ap.parse_args()
    prior=json.loads((PREV/'q4_results.json').read_text(encoding='utf-8'))
    for n,h in prior['source_sha256'].items():
        assert hashlib.sha256((SRC/n).read_bytes()).hexdigest()==h
    ts,rs,blocks=load()
    if args.smoke:
        sample=[subgroup(tuple(s for b in blocks if ('S006' in b)==flag for s in b),ts,rs) for flag in (False,True)]
        assert tuple(sum(g['need'][i] for g in sample) for i in range(8))==(4,2,3,6,4,5,2,3)
        print('PASS: independently reconstructed blocks and two-group matching minima'); return
    cache={}
    for mask in range(1,1<<len(blocks)):
        sites=tuple(sorted(s for i,b in enumerate(blocks) if mask & (1<<i) for s in b))
        cache[sites]=subgroup(sites,ts,rs)
    outcomes={}; allrows={}
    for k in (2,3):
        partitions=set()
        # Enumerate every labeled assignment, remove empty groups and label permutations.
        for labels in itertools.product(range(k),repeat=len(blocks)):
            if len(set(labels))!=k: continue
            partitions.add(canonical([tuple(s for i,b in enumerate(blocks) if labels[i]==j for s in b) for j in range(k)]))
        stirling=sum((-1)**(k-j)*math.comb(k,j)*j**len(blocks) for j in range(k+1))//math.factorial(k)
        assert len(partitions)==stirling=={2:127,3:966}[k]
        rows=[]
        for groups in sorted(partitions):
            gs=[cache[g] for g in groups]
            by_type=tuple(sum(g['need'][i] for g in gs) for i in range(8))
            works=[g['work'] for g in gs]; mean=sum(works)/k
            rows.append(dict(groups=groups,by_type=by_type,
                             resources=(sum(by_type[:3]),sum(by_type[3:6]),*by_type[6:]),
                             gap=sum(max(0,a-b) for a,b in zip(by_type,STOCK)), units=sum(by_type),
                             cv=math.sqrt(sum((w-mean)**2 for w in works)/k)/mean,
                             relay_copies=sum(g['relay_copies'] for g in gs)))
        old=read(PREV/f'q4_{k}group_pooled_search.csv')
        saved={canonical(g.split(';') for g in r['groups'].split(' | ')):r for r in old}
        assert len(saved)==len(old)==len(rows) and set(saved)==partitions
        for x in rows:
            r=saved[x['groups']]
            assert x['by_type']==tuple(int(r['need_'+t]) for t in TYPES)
            assert x['gap']==int(r['gap_units']) and x['units']==int(r['total_units'])
            assert abs(x['cv']-float(r['work_cv']))<1e-12
            assert x['relay_copies']==int(r['relay_task_copies'])
        minima={key:min(x[key] for x in rows) for key in ('gap','units','cv')}
        compact_min=tuple(min(x['resources'][i] for x in rows) for i in range(4))
        selected={}
        for name in ('selected','resource_first'):
            prev=prior['target_comparison'][str(k)][name]
            x=next(r for r in rows if r['groups']==canonical(g['sites'] for g in prev['groups']))
            assert x['by_type']==tuple(prev['total'][t] for t in TYPES)
            vectors={'resources':lambda y:y['resources'], 'typed_resources':lambda y:y['by_type'],
                     'gap_units_cv':lambda y:(y['gap'],y['units'],y['cv'])}
            dom={key:[r for r in rows if dominates(fun(r),fun(x))] for key,fun in vectors.items()}
            selected[name]=dict(**brief(x),dominators={key:len(v) for key,v in dom.items()},
                                better_gap=sum(r['gap']<x['gap'] for r in rows),
                                better_units=sum(r['units']<x['units'] for r in rows),
                                better_cv=sum(r['cv']<x['cv']-1e-10 for r in rows))
        cap={2:(9,15,2,3),3:(12,17,2,3)}[k]
        hits=[x for x in rows if all(a<=b for a,b in zip(x['resources'],cap))]
        if hits:
            chosen=min(hits,key=lambda x:(x['cv'],x['gap'],x['units']))
        else:
            eligible=[x for x in rows if x['resources'][0]<=cap[0] and x['resources'][1]<=cap[1]]
            chosen=min(eligible,key=lambda x:(*x['resources'][2:],x['gap'],x['units'],x['cv']))
        resource_best=min(rows,key=lambda x:(x['gap'],x['units'],x['cv'],x['relay_copies'],x['groups']))
        assert resource_best['groups']==tuple(tuple(g) for g in selected['resource_first']['groups'])
        assert resource_best['groups']==tuple(tuple(g) for g in selected['selected']['groups'])
        balanced=[x for x in rows if x['cv']<=.25]
        outcomes[str(k)]=dict(partitions=len(rows),all_saved_rows_match=True, min_individual_resources=compact_min,
                             global_minima=minima, target_hits=len(hits), selected=selected,
                             min_gap_count=sum(x['gap']==minima['gap'] for x in rows),
                             min_units_count=sum(x['units']==minima['units'] for x in rows),
                             least_units=brief(min(rows,key=lambda x:(x['units'],x['gap'],x['cv']))),
                             best_balance=brief(min(rows,key=lambda x:x['cv'])),
                             balanced_resource_best=brief(min(balanced,key=lambda x:(x['gap'],x['units'],x['cv']))))
        allrows[k]=rows
    OUT.mkdir(exist_ok=True)
    payload=dict(status='PASS',scope='Frozen Q3 tasks/times; same-type group-local reassignment; no balance cutoff',
                 method='independent set merging + all labeled assignments + SciPy maximum bipartite matching',
                 blocks=blocks,nonempty_subsets_checked=len(cache),results=outcomes)
    (OUT/'optimality_certificate.json').write_text(json.dumps(payload,ensure_ascii=False,indent=2),encoding='utf-8')
    for k,rows in allrows.items():
        with (OUT/f'all_{k}group_partitions.csv').open('w',encoding='utf-8-sig',newline='') as f:
            w=csv.writer(f);w.writerow(['groups','transport','battery','relay','component','gap','units','cv',*TYPES])
            for x in rows:w.writerow([' | '.join(';'.join(g) for g in x['groups']),*x['resources'],x['gap'],x['units'],x['cv'],*x['by_type']])
    paths=[Path(__file__),PREV/'q4_results.json',SRC/'q3_final_solution.mat']
    paths += [SRC/n for n in prior['source_sha256']]
    paths += [PREV/f'q4_{k}group_pooled_search.csv' for k in (2,3)]
    manifest=dict(command='python q4/optimality_audit.py',python=sys.version,scipy=scipy.__version__,
                  input_sha256={str(p.relative_to(ROOT)).replace(chr(92),chr(47)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths})
    (OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(outcomes,ensure_ascii=False,indent=2))

if __name__=='__main__': main()
