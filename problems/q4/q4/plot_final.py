"""Nine distinct Q4 evidence views and the actual model flow."""
import csv,json,sys,hashlib
from pathlib import Path
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'results/q4_final';FIG=ROOT/'figures/q4_final'
sys.path.insert(0,str(ROOT/'utils'))
from setup_style import setup_style
from export_figure import export_figure
from visual_qa import audit_layout
sys.path.insert(0,str(ROOT/'utils'))
from q4_plot_style import audit_design, _save_grayscale_preview
setup_style(journal='general',lang='zh',use_sciplots=False)
plt.rcParams.update({'font.size':9,'axes.titlesize':10,'axes.labelsize':9,'xtick.labelsize':8,'ytick.labelsize':8,'svg.fonttype':'none'})
COLORS=['#0072B2','#D55E00','#009E73']
def read(path):
    with path.open(encoding='utf-8-sig') as f:return list(csv.DictReader(f))

def main():
    FIG.mkdir(parents=True,exist_ok=True);d=json.loads((OUT/'q4_results.json').read_text(encoding='utf-8'))
    ts=read(ROOT/'results/q3_overlay/transport_sorties.csv');rs=read(ROOT/'results/q3_overlay/relay_sorties.csv')
    cs=read(ROOT/'results/q3_overlay/continuous_communication_certificate.csv')
    relay_routes={r['id']:set() for r in rs}
    for c in cs:
        if c['provider']=='G01':continue
        hits=[r for r in rs if r['uav']==c['provider'] and float(r['serviceStart_s'])<=float(c['t0'])+1e-6 and float(r['serviceEnd_s'])>=float(c['t1'])-1e-6]
        assert len(hits)==1
        relay_routes[hits[0]['id']].add(int(c['route']))
    assert len(ts)==23 and len(rs)==4 and len(cs)==296
    assert all(float(t['operation_s'])>0 and float(t['energy_kWh'])>0 for t in ts)
    contracts=[]
    def save(fig,name,claim):
        fig.set_dpi(100)
        fig.canvas.draw()
        issues=audit_layout(fig)
        assert not issues,(name,issues)
        design=audit_design(fig)
        assert not design,(name,design)
        export_figure(fig,str(FIG/name),formats=['svg','png'],dpi=300,size_inches=(7.2,4.4),grayscale_preview=False,tight=False)
        _save_grayscale_preview(FIG/f'{name}.png',300)
        contracts.append(dict(file=name,conclusion=claim,size_inches=[7.2,4.4],dpi=300,note='确定性任务数据；无抽样推断或误差棒'))
        plt.close(fig)
    def new():return plt.subplots(figsize=(7.2,4.4))
    fig,ax=new();ax.hist([float(t['operation_s'])/60 for t in ts],bins=8,color=COLORS[0],edgecolor='white')
    ax.set(xlabel='运输作业时长 (min)',ylabel='运输架次数 (n=23)');save(fig,'raw_q4_duration','任务时长差异是均衡分区的输入依据。')
    fig,ax=new()
    for typ,col,mark in zip('ABC',COLORS,['o','s','^']):
        sel=[t for t in ts if t['uav_type']==typ];ax.scatter([float(t['mass_kg']) for t in sel],[float(t['energy_kWh']) for t in sel],label=typ,color=col,marker=mark)
    ax.set(xlabel='架次载荷 (kg)',ylabel='架次运输能耗 (kWh)');ax.legend(title='运输机型',frameon=False)
    save(fig,'raw_q4_payload_energy','运输任务的载荷与能耗随机型不同，资源不可跨型号抵扣。')
    fig,ax=new();xs=[float(r['serviceStart_s'])/60 for r in rs];width=[(float(r['serviceEnd_s'])-float(r['serviceStart_s']))/60 for r in rs]
    ax.barh(range(4),width,left=xs,color=COLORS[0]);ax.set_yticks(range(4),[r['id'] for r in rs]);ax.set(xlabel='通信服务时刻 (min)',ylabel='原中继任务',xlim=(0,100))
    save(fig,'raw_q4_relay_windows','原中继窗口固定，跨组复制必须保持同一服务时段。')
    for k in ('2','3'):
        search=read(OUT/f'q4_{k}group_pooled_search.csv');fig,ax=new()
        ax.scatter([float(x['work_cv']) for x in search],[int(x['gap_units']) for x in search],s=12,color='#999999',alpha=.35)
        rec=d['pooled_results'][k]['recommended'];ax.scatter(rec['work_cv'],rec['gap_units'],marker='*',s=110,color=COLORS[1],label='资源优先最终方案')
        ax.set(xlabel='工作量 CV',ylabel='库存缺口 (件)');ax.legend(frameon=False)
        save(fig,f'process_q4_{k}group_tradeoff',f'{k}组穷举揭示资源缺口与工作量均衡的权衡。')
    fig,ax=new();matrix=[[len(set(g['sorties'])&set(relay_routes[r['id']])) for r in rs] for g in d['pooled_results']['3']['recommended']['groups']]
    im=ax.pcolormesh(np.arange(5)-.5,np.arange(4)-.5,np.array(matrix),cmap='Blues',vmin=0,rasterized=False);ax.invert_yaxis();ax.set_xticks(range(4),[r['id'] for r in rs]);ax.set_yticks(range(3),['G1','G2','G3'])
    ax.set(xlabel='原中继任务',ylabel='三组独立配置方案')
    for i,row in enumerate(matrix):
        for j,v in enumerate(row):ax.text(j,i,str(v),ha='center',va='center',color='white' if v>max(map(max,matrix))/2 else 'black')
    cb=fig.colorbar(im,ax=ax,label='被保障运输架次数');cb.solids.set_rasterized(False)
    save(fig,'process_q4_relay_dependency','同一中继任务关联多个组，造成中继任务复制。')
    labels=['A机','B机','C机','A电池','B电池','C电池','中继机','组件'];typ=list(d['inventory']);pos=np.arange(8)
    fig,ax=new()
    for shift,k,col in zip([-.18,.18],['2','3'],COLORS):ax.bar(pos+shift,[d['pooled_results'][k]['recommended']['total'][t] for t in typ],width=.32,color=col,label=f'{k}组独立配置')
    ax.scatter(pos,list(d['inventory'].values()),marker='_',s=150,color='black',label='库存');ax.set_xticks(pos,labels);ax.set(ylabel='资源需求 (件)',xlabel='资源类型');ax.legend(frameon=False)
    save(fig,'result_q4_resource_inventory','两组配置9/15/2/3，三组9/15/4/6；三组增加中继隔离资源。')
    fig,ax=new();p=0;names=[];positions=[]
    for k in ('2','3'):
        for i,g in enumerate(d['pooled_results'][k]['recommended']['groups'],1):
            ax.bar(p,g['transport_work_s']/3600,color=COLORS[0]);ax.bar(p,g['relay_work_s']/3600,bottom=g['transport_work_s']/3600,color=COLORS[1])
            names.append(f'{k}组-G{i}');positions.append(p);p+=1
        p+=.5
    ax.set_xticks(positions,names);ax.set(ylabel='组工作量 (h)',xlabel='任务组');ax.legend(handles=[plt.Rectangle((0,0),1,1,color=COLORS[0],label='运输'),plt.Rectangle((0,0),1,1,color=COLORS[1],label='中继副本')],frameon=False)
    save(fig,'result_q4_workload','资源最少方案工作量明显不均衡，不能解释为均衡最优。')
    fig,ax=new()
    for shift,k,col in zip([-.18,.18],['2','3'],COLORS):ax.bar(pos+shift,[d['pooled_results'][k]['recommended']['gap'][t] for t in typ],width=.32,color=col,label=f'{k}组同型重分配')
    ax.set_xticks(pos,labels);ax.set(ylabel='需补充资源 (件)',xlabel='资源类型');ax.legend(frameon=False)
    save(fig,'result_q4_pooled_gap','两组缺C型机和C型电池各1件；三组另缺2架中继机。')
    fig,ax=new();ax.axis('off')
    nodes=['最新Q3与原库存','共访闭包与保障映射','127/966分区穷举','组内同型最少路径覆盖','缺口 → 总件数 → CV','独立核验与输出']
    for i,name in enumerate(nodes):
        y=.91-i*.16;ax.text(.5,y,name,ha='center',va='center',bbox=dict(boxstyle='round,pad=.4',facecolor='#EDF3F5',edgecolor='#37474F'))
        if i<5:ax.annotate('',xy=(.5,y-.11),xytext=(.5,y-.04),arrowprops=dict(arrowstyle='->',color='#37474F'))
    save(fig,'flow_overall_model','本轮Q4流程继承Q3后完成分区、资源核算与独立验证。')
    (OUT/'figure_contract.json').write_text(json.dumps(contracts,ensure_ascii=False,indent=2),encoding='utf-8')
    source_files=[OUT/'q4_results.json',OUT/'q4_2group_pooled_search.csv',OUT/'q4_3group_pooled_search.csv',ROOT/'results/q3_overlay/transport_sorties.csv',ROOT/'results/q3_overlay/relay_sorties.csv',ROOT/'results/q3_overlay/continuous_communication_certificate.csv']
    provenance={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in source_files}
    (OUT/'figure_source_sha256.json').write_text(json.dumps(provenance,ensure_ascii=False,indent=2),encoding='utf-8')
    (OUT/'figure_data_profile.json').write_text(json.dumps(dict(transport_rows=23,relay_rows=4,certificate_rows=296,two_group_partitions=127,three_group_partitions=966,missing_core_values=0,semantics='deterministic complete enumeration; no inferential error bars'),indent=2),encoding='utf-8')
    print('9 current-result figures and 1 flow exported')

if __name__=='__main__':main()
