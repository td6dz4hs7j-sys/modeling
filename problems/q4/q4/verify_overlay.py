"""Independent saved-output check, including frozen preparations and chain rules."""
import csv
import hashlib
import json
import math
from collections import defaultdict
from pathlib import Path
import h5py
import numpy as np
from scipy.sparse import csr_matrix
from scipy.sparse.csgraph import maximum_bipartite_matching

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'results/q3_overlay'; OUT=ROOT/'results/q4_overlay'

def read(path):
    with path.open(encoding='utf-8-sig',newline='') as f: return list(csv.DictReader(f))

def main():
    d=json.loads((OUT/'q4_results.json').read_text(encoding='utf-8'))
    for name,digest in d['source_sha256'].items(): assert hashlib.sha256((SOURCE/name).read_bytes()).hexdigest()==digest
    ts=read(SOURCE/'transport_sorties.csv'); rs=read(SOURCE/'relay_sorties.csv')
    cs=read(SOURCE/'continuous_communication_certificate.csv'); bs=read(SOURCE/'box_deliveries.csv')
    timing={}
    with h5py.File(SOURCE/'q3_final_solution.mat') as f:
        for i,t in enumerate(ts):
            timing[t['sortie_id']]={key:float(f[f['S/routes'][key][0,i]][()].item())
                                  for key in ('loadStart_s','prepStart_s','takeoff_s','return_s','batteryReady_s')}
    rows=[['K','group','resource_type','q3_task','local_resource','start_s','end_s']]
    comm=[['K','group','route','t0_s','t1_s','q3_provider','relay_task','local_provider','margin_dB']]
    checks=[]
    stock={'A_uav':4,'B_uav':2,'C_uav':2,'A_battery':6,'B_battery':4,'C_battery':4,'R_uav':2,'R_component':6}
    for k,entry in d['results'].items():
        x=entry['recommended']; sites=set(); routes=set(); boxes=set(); totals=defaultdict(int)
        for gi,g in enumerate(x['groups'],1):
            assert not sites.intersection(g['sites']);sites.update(g['sites'])
            intervals=defaultdict(list)
            for p in g['sorties']:
                assert p not in routes;routes.add(p);t=ts[p-1];a=timing[t['sortie_id']];typ=t['uav_type']
                assert set(t['service_order'].split('→')) <= set(g['sites'])
                assert abs(a['takeoff_s']-float(t['start_s']))<1e-6
                assert abs(a['return_s']-float(t['return_s']))<1e-6
                energy=float(t['energy_kWh']);cap,full={'A':(4.5,1800),'B':(4,2400),'C':(8,3000)}[typ]
                soc=1-energy/cap;assert soc>=.2-1e-8
                charge=full*(.65*(.9-soc)/.9+.35) if soc<.9 else full*.35*(1-soc)/.1
                assert abs(a['batteryReady_s']-a['return_s']-charge)<1e-5
                intervals[typ+'_uav'].append((a['loadStart_s'],a['return_s'],t['sortie_id'],t['uav_id']))
                intervals[typ+'_battery'].append((a['takeoff_s'],a['batteryReady_s'],t['sortie_id'],t['battery_id']))
            for typ in ('A','B','C'):
                selected=[ts[p-1] for p in g['sorties'] if ts[p-1]['uav_type']==typ]
                for uid in {t['uav_id'] for t in selected}:
                    seq=sorted([t for t in selected if t['uav_id']==uid],key=lambda t:float(t['start_s']))
                    for prev,cur in zip(seq,seq[1:]):
                        a,b=timing[prev['sortie_id']],timing[cur['sortie_id']]
                        assert b['prepStart_s']>=a['takeoff_s']-1e-5
                        assert b['loadStart_s']>=a['return_s']-1e-5
            for r in rs:
                if r['id'] in g['relay_ids']:
                    intervals['R_uav'].append((float(r['start_s']),float(r['ready_s']),r['id'],r['uav']))
                    intervals['R_component'].append((float(r['start_s']),float(r['componentReady_s']),r['id'],r['component']))
            for typ in stock:
                seq=intervals[typ];ids={v[3] for v in seq}
                assert len(ids)==g['resources'][typ];totals[typ]+=len(ids)
                for a,b,task,uid in seq:
                    assert b>a
                    rows.append([k,gi,typ,task,f'K{k}-G{gi}-{uid}',a,b])
                for i,(a,b,_,uid) in enumerate(seq):
                    for c,e,_,vid in seq[i+1:]:
                        if uid==vid: assert max(a,c)>=min(b,e)-1e-5
            expected=set()
            for c in cs:
                if int(c['route']) not in g['sorties']: continue
                provider=c['provider'];rid=''
                if provider!='G01':
                    hits=[r for r in rs if r['uav']==provider and float(r['serviceStart_s'])<=float(c['t0'])+1e-6
                          and float(r['serviceEnd_s'])>=float(c['t1'])-1e-6]
                    assert len(hits)==1;rid=hits[0]['id'];expected.add(rid)
                    assert rid in g['relay_ids'];provider=f'K{k}-G{gi}-{provider}'
                comm.append([k,gi,c['route'],c['t0'],c['t1'],c['provider'],rid,provider,c['margin_dB']])
            assert expected==set(g['relay_ids'])
            for b in bs:
                if b['area'] in g['sites']:
                    assert b['box_id'] not in boxes; boxes.add(b['box_id'])
        assert len(sites)==15 and len(routes)==23 and len(boxes)==80
        assert dict(totals)==x['total'] and x['gap']=={t:max(0,totals[t]-stock[t]) for t in stock}
        count=sum((-1)**(int(k)-j)*math.comb(int(k),j)*j**len(d['components']) for j in range(int(k)+1))//math.factorial(int(k))
        search=read(OUT/f'q4_{k}group_search.csv');assert len(search)==entry['searched']==count
        assert entry['minimum_gap_units']==min(int(r['gap_units']) for r in search)
        assert sum(str(r[0])==k for r in comm[1:])==len(cs)==296
        checks.append(dict(K=int(k),status='PASS',partitions=count,sites=15,boxes=80,transport=23,
                           continuous_intervals=296,source_hashes_match=True,resources=dict(totals)))
    pooled_rows=[['K','variant','group','resource_type','q3_task','local_resource','start_s','end_s']]
    for mode,result in [('fixed',d['results']),('pooled',d['pooled_results'])]:
        for k,entry in result.items():
            search=read(OUT/f'q4_{k}group{ "_pooled" if mode=="pooled" else ""}_search.csv')
            assert len(search)==entry['searched']
            assert min(int(r['gap_units']) for r in search)==entry['minimum_gap_units']
            for variant in ('recommended','resource_first'):
                x=entry[variant];seen_s=set();seen_p=set();sum_resources=defaultdict(int)
                for gi,g in enumerate(x['groups'],1):
                    assert not seen_s.intersection(g['sites']);seen_s.update(g['sites'])
                    assert not seen_p.intersection(g['sorties']);seen_p.update(g['sorties'])
                    for p in g['sorties']:assert set(ts[p-1]['service_order'].split('→'))<=set(g['sites'])
                    expected=set()
                    for c in cs:
                        if int(c['route']) not in g['sorties'] or c['provider']=='G01':continue
                        hits=[r for r in rs if r['uav']==c['provider'] and float(r['serviceStart_s'])<=float(c['t0'])+1e-6 and float(r['serviceEnd_s'])>=float(c['t1'])-1e-6]
                        assert len(hits)==1;expected.add(hits[0]['id'])
                    assert expected==set(g['relay_ids'])
                    if mode=='pooled':
                        for typ in stock:
                            original=[]
                            if typ.startswith(('A_','B_','C_')):
                                for p in g['sorties']:
                                    t=ts[p-1]
                                    if t['uav_type']!=typ[0]:continue
                                    a=timing[t['sortie_id']]
                                    original.append((a['loadStart_s'] if typ.endswith('_uav') else a['takeoff_s'],
                                                     a['return_s'] if typ.endswith('_uav') else a['batteryReady_s'],t['sortie_id']))
                            else:
                                for r in rs:
                                    if r['id'] in g['relay_ids']:original.append((float(r['start_s']),float(r['ready_s'] if typ=='R_uav' else r['componentReady_s']),r['id']))
                            n=len(original);adj=np.zeros((n,n),dtype=int)
                            for i,a in enumerate(original):
                                for j,b in enumerate(original):
                                    if i==j:continue
                                    allowed=a[1]<=b[0]+1e-5
                                    if typ.endswith('_uav') and typ!='R_uav':allowed=allowed and timing[a[2]]['takeoff_s']<=timing[b[2]]['prepStart_s']+1e-5
                                    if allowed:adj[i,j]=1
                            match=maximum_bipartite_matching(csr_matrix(adj),perm_type='column') if n else []
                            need=n-sum(v>=0 for v in match)
                            mapping=g['pooled_assignment'][typ];assert need==g['resources'][typ]==len(set(mapping.values()))
                            for a in original:
                                pooled_rows.append([k,variant,gi,typ,a[2],f'K{k}-{variant}-G{gi}-{typ}-{mapping[a[2]]}',a[0],a[1]])
                            for i,a in enumerate(original):
                                for b in original[i+1:]:
                                    if mapping[a[2]]!=mapping[b[2]]:continue
                                    prev,cur=sorted([a,b],key=lambda v:v[0]);assert prev[1]<=cur[0]+1e-5
                                    if typ.endswith('_uav') and typ!='R_uav':assert timing[prev[2]]['takeoff_s']<=timing[cur[2]]['prepStart_s']+1e-5
                    for typ in stock:sum_resources[typ]+=g['resources'][typ]
                assert len(seen_s)==15 and len(seen_p)==23
                assert dict(sum_resources)==x['total']
                assert x['gap']=={t:max(0,sum_resources[t]-stock[t]) for t in stock}
                checks.append(dict(K=int(k),mode=mode,variant=variant,status='PASS',resources=dict(sum_resources),matching_minima_checked=mode=='pooled'))
    for name,content in [('comparison_original_id_resources.csv',rows),('comparison_original_id_communication.csv',comm),('q4_pooled_resource_assignments.csv',pooled_rows)]:
        with (OUT/name).open('w',encoding='utf-8-sig',newline='') as f:csv.writer(f).writerows(content)
    (OUT/'verification.json').write_text(json.dumps(checks,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(checks,ensure_ascii=False))

if __name__=='__main__':main()
