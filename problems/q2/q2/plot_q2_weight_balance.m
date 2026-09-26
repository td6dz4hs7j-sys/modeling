function plot_q2_weight_balance(root)
if nargin<1,root=fileparts(fileparts(mfilename('fullpath')));end
addpath(fullfile(root,'utils'));
out=fullfile(root,'results','q2_99_review');T=readtable(fullfile(out,'objective_normalization.csv'),'TextType','string');
ix=T.method=="22-sortie time-first search";assert(sum(ix)==1);q=T.normalized_energy(ix);
xcut=.5/(1-(1-q)/2);ycut=1-xcut;
fig=figure('Visible','off','Color','white');apply_publication_style(fig,'zh','double');fig.Position(3:4)=[7.5 5.2];hold on;
good=[.78 .91 .86];other=[.98 .87 .73];
patch([0 1 xcut 0],[0 0 ycut .5],good,'EdgeColor','none');
patch([0 0 xcut],[.5 1 ycut],other,'EdgeColor','none');
plot([0 xcut],[.5 ycut],'k-','LineWidth',1.2);
plot([0 1 0 0],[0 0 1 0],'Color',[.3 .3 .3],'LineWidth',.8);
scatter([.25 .7 1/3 .2 .1],[.1 .1 1/3 .6 .75],38,[.15 .25 .35],'filled');
labels={'时间优先','能耗优先','均衡','架次优先','强架次优先'};
xs=[.25 .7 1/3 .2 .1];ys=[.1 .1 1/3 .6 .75];
for i=1:5,text(xs(i)+.02,ys(i)+.018,labels{i},'FontSize',7);end
text(.13,.27,'23 架次最终方案优选','Color',[.03 .35 .25],'FontSize',8);
text(.03,.90,'22 架次方案优选','Color',[.57 .27 .03],'FontSize',8);
xlim([0 1]);ylim([0 1]);axis square;
xlabel('能耗权重 w_E');ylabel('架次权重 w_N');title('三目标权重分界');
text(.98,.97,sprintf('w_T=1-w_N-w_E;  E_{22}''=%.4f',q),'Units','normalized', ...
 'HorizontalAlignment','right','VerticalAlignment','top','FontSize',7);
export_publication_figure(fig,fullfile(out,'figures','weight_balance_region'),300,true,true);close(fig);
fprintf('Q2_WEIGHT_BALANCE_FIGURE PASS\n');
end
