"""Q4 exhaustive partitions of the user's frozen Q3 overlay (no retiming)."""
import argparse
import csv
import hashlib
import json
import math
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'results/q3_overlay'
OUT = ROOT / 'results/q4_overlay'
os.environ['Q4_Q3_SOURCE'] = str(SOURCE)
import main_q4 as base
import h5py

TYPES, STOCK = base.TYPES, base.STOCK

def minimum_chains(tasks, compatible):
    """Minimum path cover in a temporal DAG via maximum bipartite matching."""
    edges = {a: [b for b in tasks if a != b and compatible(a,b)] for a in tasks}
    matched = {}
    def augment(a, seen):
        for b in edges[a]:
            if b in seen: continue
            seen.add(b)
            if b not in matched or augment(matched[b],seen):
                matched[b]=a;return True
        return False
    for a in tasks:augment(a,set())
    following={a:b for b,a in matched.items()}; starts=[a for a in tasks if a not in matched]
    assignment={}
    for i,a in enumerate(starts,1):
        while True:
            assert a not in assignment
            assignment[a]=i
            if a not in following: break
            a=following[a]
    assert len(assignment)==len(tasks)
    return len(starts),assignment

def write_csv(name, rows):
    with (OUT / name).open('w', encoding='utf-8-sig', newline='') as f:
        w = csv.writer(f)
        w.writerows(rows)

def inputs():
    transport, relays, cert, boxes = base.load_inputs()
    with h5py.File(SOURCE / 'q3_final_solution.mat') as f:
        r = f['S/routes']
        for i, t in enumerate(transport):
            for key in ('prepStart_s', 'loadStart_s', 'takeoff_s', 'return_s', 'batteryReady_s'):
                value = float(f[r[key][0, i]][()].item())
                if key in ('return_s',):
                    assert abs(value - float(t[key])) < 1e-6
                t[key] = value
            assert abs(t['takeoff_s'] - float(t['start_s'])) < 1e-6
            assert 0 <= t['loadStart_s'] <= t['takeoff_s']
            assert abs(t['batteryReady_s'] - (t['return_s'] + base.charge_s(t['uav_type'], float(t['energy_kWh'])))) < 1e-5
    return transport, relays, cert, boxes

def group(sites, ts, rs, rm, boxes):
    g = base.group_data(sites, ts, rs, rm, boxes)
    intervals = {key: [] for key in TYPES}
    for p in g['sorties']:
        t = ts[p-1]; typ = t['uav_type']; task = t['sortie_id']
        intervals[typ+'_uav'].append((t['loadStart_s'], t['return_s'], task))
        intervals[typ+'_battery'].append((t['takeoff_s'], t['batteryReady_s'], task))
    for r in rs:
        if r['id'] in g['relay_ids']:
            intervals['R_uav'].append((float(r['start_s']), float(r['ready_s']), r['id']))
            intervals['R_component'].append((float(r['start_s']), float(r['componentReady_s']), r['id']))
    g['peak_lower_bound'] = {key: base.peak_overlap(intervals[key]) for key in TYPES}
    g['intervals'] = intervals
    pooled={}; mapping={}
    lookup={t['sortie_id']:t for t in ts}
    for key in TYPES:
        seq=intervals[key]; byid={v[2]:v for v in seq};tasks=list(byid)
        if key.endswith('_uav') and key!='R_uav':
            compatible=lambda a,b: lookup[a]['return_s']<=lookup[b]['loadStart_s']+1e-5 and lookup[a]['takeoff_s']<=lookup[b]['prepStart_s']+1e-5
        else:
            compatible=lambda a,b: byid[a][1]<=byid[b][0]+1e-5
        pooled[key],mapping[key]=minimum_chains(tasks,compatible)
    g['pooled_resources']=pooled;g['pooled_assignment']=mapping
    return g

def evaluate(labels, blocks, ts, rs, rm, boxes, pooled=False):
    groups = [group([s for j,b in enumerate(blocks) if labels[j] == i for s in b], ts, rs, rm, boxes)
              for i in range(max(labels)+1)]
    if pooled:
        for g in groups:g['resources']=dict(g['pooled_resources'])
    total = {key: sum(g['resources'][key] for g in groups) for key in TYPES}
    peak = {key: sum(g['peak_lower_bound'][key] for g in groups) for key in TYPES}
    works = [g['work_s'] for g in groups]; mean = sum(works)/len(works)
    return dict(labels=labels, groups=groups, total=total,
                total_units=sum(total.values()), gap={key:max(0,total[key]-STOCK[key]) for key in TYPES},
                gap_units=sum(max(0,total[key]-STOCK[key]) for key in TYPES),
                work_cv=math.sqrt(sum((w-mean)**2 for w in works)/len(works))/mean,
                work_ratio=max(works)/min(works), relay_task_copies=sum(len(g['relay_ids']) for g in groups),
                redundancy={key: total[key]-peak[key] for key in TYPES}, peak_lower_bound=peak)

def search(ts, rs, rm, boxes, blocks, k, pooled=False):
    candidates = [evaluate(labels, blocks, ts, rs, rm, boxes,pooled) for labels in base.partitions(len(blocks), k)]
    # No arbitrary unit-weight score: lexicographic resource preference,
    # with an explicitly disclosed balance preference.
    key = lambda x: (x['gap_units'], x['total_units'], x['work_cv'], x['relay_task_copies'], x['labels'])
    balanced = [x for x in candidates if x['work_cv'] <= .25]
    chosen = min(balanced or candidates, key=key)
    resource = min(candidates, key=key)
    return dict(searched=len(candidates), balance_cap=.25, balanced_exists=bool(balanced),
                recommended=chosen, resource_first=resource,
                minimum_gap_units=resource['gap_units']), candidates

def main():
    ap = argparse.ArgumentParser(); ap.add_argument('--smoke', action='store_true'); args=ap.parse_args()
    ts, rs, cert, boxes = inputs(); blocks=base.connected_components(ts); rm=base.relay_route_map(rs,cert)
    if args.smoke:
        x = evaluate((0,)+(1,)*(len(blocks)-1), blocks, ts, rs, rm, boxes)
        assert sum(g['boxes'] for g in x['groups']) == 80
        print(json.dumps(dict(blocks=blocks, total=x['total'], gap=x['gap']),ensure_ascii=False)); return
    OUT.mkdir(exist_ok=True)
    result={}; pooled_result={}
    for k in (2,3):
        result[str(k)], candidates = search(ts,rs,rm,boxes,blocks,k)
        pooled_result[str(k)], pool_candidates = search(ts,rs,rm,boxes,blocks,k,True)
        rows=[['gap_units','total_units','work_cv','relay_task_copies','groups',*['need_'+t for t in TYPES]]]
        for x in sorted(candidates,key=lambda x:(x['gap_units'],x['total_units'],x['work_cv'])):
            rows.append([x['gap_units'],x['total_units'],x['work_cv'],x['relay_task_copies'],
                         ' | '.join(';'.join(g['sites']) for g in x['groups']),*[x['total'][t] for t in TYPES]])
        write_csv(f'q4_{k}group_search.csv',rows)
        write_csv(f'q4_{k}group_pooled_search.csv',[rows[0]]+[
            [x['gap_units'],x['total_units'],x['work_cv'],x['relay_task_copies'],
             ' | '.join(';'.join(g['sites']) for g in x['groups']),*[x['total'][t] for t in TYPES]]
            for x in sorted(pool_candidates,key=lambda x:(x['gap_units'],x['total_units'],x['work_cv']))])
    names=['transport_sorties.csv','relay_sorties.csv','continuous_communication_certificate.csv',
           'box_deliveries.csv','q3_final_solution.mat','q3_metrics.csv','validator_PASS.txt','问题三_优化结果.md']
    payload=dict(q3_source=str(SOURCE),source_sha256={n:hashlib.sha256((SOURCE/n).read_bytes()).hexdigest() for n in names},
                 components=blocks,inventory=STOCK,relay_routes={k:sorted(v) for k,v in rm.items()},results=result,
                 pooled_results=pooled_result,
                 resource_policy='Frozen Q3 task-to-original-resource relationships; group-local copies of every used ID')
    (OUT/'q4_results.json').write_text(json.dumps(payload,ensure_ascii=False,indent=2),encoding='utf-8')
    write_csv('transport_resource_times.csv',[['sortie_id','prepStart_s','loadStart_s','takeoff_s','return_s','batteryReady_s']]+
              [[t['sortie_id'],*[t[c] for c in ('prepStart_s','loadStart_s','takeoff_s','return_s','batteryReady_s')]] for t in ts])
    rows=[['K','group','sites','boxes','transport_sorties','relay_copies',*TYPES,'work_h','return_min','transport_kWh','relay_kWh']]
    for k,d in result.items():
        for i,g in enumerate(d['recommended']['groups'],1):
            rows.append([k,i,';'.join(g['sites']),g['boxes'],len(g['sorties']),len(g['relay_ids']),
                         *[g['resources'][t] for t in TYPES],g['work_s']/3600,g['makespan_s']/60,
                         g['transport_energy_kWh'],g['relay_energy_kWh']])
    write_csv('q4_group_resources.csv',rows)
    print(json.dumps({k:{'searched':d['searched'],'groups':[g['sites'] for g in d['recommended']['groups']],
                        'total':d['recommended']['total'],'gap':d['recommended']['gap'],
                        'cv':d['recommended']['work_cv']} for k,d in result.items()},ensure_ascii=False))

if __name__ == '__main__': main()
