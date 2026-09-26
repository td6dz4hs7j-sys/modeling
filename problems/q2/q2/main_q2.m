function main_q2(mode,runTag)
if nargin<1,mode='all_ontime';end
if nargin<2,runTag='';end
root=fileparts(fileparts(mfilename('fullpath')));
switch mode
 case 'minimal',run_q2_minimal(root,runTag);
 case 'full',run_q2_full(root);
 case 'sortie_first',run_q2_sortie_first(root);
 case 'all_ontime',run_q2_all_ontime(root);
 case 'figures'
  x=load(fullfile(root,'results/q2_all_ontime/q2_final_solution.mat'));
  V=validate_q2_solution(x.D,x.legs,x.S,'RequireAllExpectedOnTime',true);
  assert(strcmp(V.status,'PASS'),'Frozen all-on-time solution failed strict validation.');
  export_q2_results(x.D,x.legs,x.S,x.baseline,x.R,fullfile(root,'results/q2_all_ontime'));
  plot_q2_results(x.D,x.legs,x.S,x.baseline,x.R,fullfile(root,'figures/q2_all_ontime'));
 otherwise,error('Unknown mode: %s',mode);
end
end
