"""Plot missing route, physical-UAV stages and current Q2 workflow."""
import csv,json,hashlib,sys
from pathlib import Path
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import Patch
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'results/q2_strategy_scenarios';FIG=ROOT/'figures/q2_strategy_scenarios'
sys.path.insert(0,str(ROOT/'utils'))
from setup_style import setup_style
from export_figure import export_figure
from visual_qa import audit_layout
from figure_style import audit_design,_save_grayscale_preview
setup_style(journal='general',lang='zh',use_sciplots=False)
plt.rcParams.update({'font.size':9,'axes.labelsize':9,'xtick.labelsize':8,'ytick.labelsize':8,'svg.fonttype':'none'})
def read(n):
    with (OUT/n).open(encoding='utf-8-sig',newline='') as f:return list(csv.DictReader(f))
def main():
    FIG.mkdir(parents=True,exist_ok=True);rows=read('latest_route_timeline.csv');nodes={int(n['index']):n for n in read('latest_nodes.csv')}
    provenance=json.loads((OUT/'latest_plot_input_provenance.json').read_text(encoding='utf-8'))
    assert hashlib.sha256((OUT/'balanced_best_pass.mat').read_bytes()).hexdigest()==provenance['balanced_mat_sha256']
    assert hashlib.sha256((OUT/'Q2_综合均衡最终结果.xlsx').read_bytes()).hexdigest()==provenance['official_workbook_sha256']
    for name,digest in provenance['plot_csv_sha256'].items():
        assert hashlib.sha256((OUT/name).read_bytes()).hexdigest()==digest,name
    assert len(rows)==23 and abs(max(float(r['return_s']) for r in rows)/60-97.7058717164508)<1e-7
    for r in rows:
        for k in ('prep_start_s','prep_end_s','load_start_s','load_end_s','takeoff_s','return_s'):r[k]=float(r[k])
    colors={'A':'#0072B2','B':'#D55E00','C':'#009E73'};contracts=[]
    def save(fig,name,claim):
        fig.set_dpi(100)
        fig.canvas.draw();issues=audit_layout(fig);assert not issues,issues
        issues=audit_design(fig);assert not issues,issues
        export_figure(fig,str(FIG/name),formats=['png','svg'],dpi=300,size_inches=(7.2,4.8),grayscale_preview=False,tight=False)
        _save_grayscale_preview(FIG/(name+'.png'),300)
        plt.close(fig);contracts.append({'file':name,'conclusion':claim})
    fig,ax=plt.subplots(figsize=(7.2,4.8),layout='constrained')
    for r in rows:
        seq=[1,*[int(x) for x in r['nodes'].split(';')],1]
        ax.plot([float(nodes[i]['lon']) for i in seq],[float(nodes[i]['lat']) for i in seq],color=colors[r['type']],lw=.8,alpha=.75)
    for i,n in nodes.items():
        lon,lat=float(n['lon']),float(n['lat']);ax.scatter(lon,lat,s=45 if i==1 else 16,marker='*' if i==1 else 'o',color='black',zorder=5)
        ax.annotate(n['id'],(lon,lat),xytext=(3,3),textcoords='offset points',fontsize=7)
    ax.margins(.14);ax.set(xlabel='经度 (°E)',ylabel='纬度 (°N)');ax.ticklabel_format(useOffset=False)
    from matplotlib.ticker import MaxNLocator
    ax.xaxis.set_major_locator(MaxNLocator(5));ax.yaxis.set_major_locator(MaxNLocator(5))
    ax.legend(handles=[Patch(facecolor=c,label=t+'型') for t,c in colors.items()],frameon=False,loc='upper left')
    save(fig,'result_q2_latest_routes','最新综合均衡解的23架次实际访问顺序，线路重叠不代表只有一架次。')
    fig,ax=plt.subplots(figsize=(7.2,4.8),layout='constrained');uids=sorted({r['uav_id'] for r in rows})
    for r in rows:
        y=uids.index(r['uav_id'])
        for start,end,offset,color,height in [('takeoff_s','return_s',0,'#0072B2',.30),('prep_start_s','prep_end_s',.23,'#D55E00',.12),('load_start_s','load_end_s',-.23,'#009E73',.12)]:
            ax.barh(y+offset,(r[end]-r[start])/60,left=r[start]/60,height=height,color=color)
    ax.set(yticks=range(len(uids)),yticklabels=uids,xlabel='任务时刻 (min)',ylabel='实体运输无人机',xlim=(0,102));ax.invert_yaxis()
    ax.legend(handles=[Patch(facecolor=c,label=l) for c,l in [('#0072B2','飞行与投送'),('#D55E00','固定预准备'),('#009E73','装载')]],loc='upper center',bbox_to_anchor=(.5,1.13),ncol=3,frameon=False)
    save(fig,'process_q2_latest_uav_stages','最新实体机的预准备可提前，装载仍须等待上次返航；分层避免隐藏并行。')
    fig,ax=plt.subplots(figsize=(7.2,4.8),layout='constrained');ax.axis('off')
    steps=['题目数据、DEM与80箱需求','多点路线构造与共同种子池','多邻域搜索：架次 / 时间 / 能耗','实体机、电池与预准备排程','独立校验：80箱按期及物理资源','四组偏好结果与综合均衡选解']
    for i,s in enumerate(steps):
        y=.91-i*.16;ax.text(.5,y,s,ha='center',va='center',bbox=dict(boxstyle='round,pad=.35',fc='#EDF3F5',ec='#37474F'))
        if i<5:ax.annotate('',xy=(.5,y-.11),xytext=(.5,y-.04),arrowprops=dict(arrowstyle='->',color='#37474F'))
    save(fig,'flow_q2_latest_model','当前有界多邻域搜索与独立验证流程；不宣称全局最优。')
    sources={n:hashlib.sha256((OUT/n).read_bytes()).hexdigest() for n in ('balanced_best_pass.mat','latest_route_timeline.csv','latest_nodes.csv')}
    (OUT/'latest_supplement_figures.json').write_text(json.dumps({'source_sha256':sources,'figures':contracts},ensure_ascii=False,indent=2),encoding='utf-8')
if __name__=='__main__':main()
