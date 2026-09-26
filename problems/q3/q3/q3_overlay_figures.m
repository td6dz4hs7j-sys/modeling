function q3_overlay_figures(root,D,S0,S)
out=fullfile(root,'figures','q3_overlay');if ~isfolder(out),mkdir(out);end
f=figure('Visible','off','Color','w','Position',[100 100 900 420]);
areas=unique(D.boxes.area,'stable');counts=zeros(numel(areas),1);
for k=1:numel(areas),counts(k)=sum(D.boxes.area==areas(k));end
bar(counts);xticks(1:numel(areas));xticklabels(areas);xlabel('Service area');ylabel('Boxes');title('Input: 80 indivisible boxes by area');grid on;
apply_publication_style(f,'en','report');title('Demand by area');export_publication_figure(f,string(fullfile(out,'raw_q3_boxes_by_area')),300);close(f);
f=figure('Visible','off','Color','w','Position',[100 100 900 420]);
slack=zeros(numel(S0.routes),1);
for k=1:numel(slack),r=S0.routes(k);slack(k)=min(min(D.boxes.expected_s(r.boxIdx),D.hardDeadline_s(r.boxIdx))-r.boxArrival_s(:))/60;end
bar(slack);xlabel('Original Q2 sortie');ylabel('Deadline slack (min)');title('Input: Q2 delivery slack before resource propagation');grid on;
apply_publication_style(f,'en','report');title('Q2 deadline slack');export_publication_figure(f,string(fullfile(out,'raw_q3_deadline_slack')),300);close(f);
f=figure('Visible','off','Color','w','Position',[100 100 900 420]);
bar(([S.routes.takeoff_s]-[S0.routes.takeoff_s])/60);xlabel('Original Q2 sortie');ylabel('Takeoff delay (min)');title('Process: relay overlay delays; groups and resources retained');grid on;
apply_publication_style(f,'en','report');title('Takeoff adjustment');export_publication_figure(f,string(fullfile(out,'process_q3_takeoff_adjustment')),300);close(f);
f=figure('Visible','off','Color','w','Position',[100 100 760 850]);axis([0 1 0 1]);axis off;hold on;
labels={sprintf('Verify current\nQ2 workbook'),sprintf('Retain routes\nand aircraft types'),sprintf('Resources and\nrelay scheduling'),sprintf('Continuous\nphysical validation'),sprintf('Export validated\nschedule')};
for k=1:5
 y=.82-(k-1)*.18;rectangle('Position',[.15,y,.7,.12],'FaceColor',[.9 .95 1],'EdgeColor',[.2 .4 .6]);
 text(.5,y+.06,labels{k},'HorizontalAlignment','center','FontSize',10,'Interpreter','none');
 if k<5,quiver(.5,y,0,-.06,0,'Color',[.2 .4 .6],'MaxHeadSize',1);end
end
title('Q2 transport optimum + concurrent relay coverage');
apply_publication_style(f,'en','report');title('Q2 to Q3');f.Position(4)=5;axis([0 1 0 1]);axis off;
export_publication_figure(f,string(fullfile(out,'flow_overall_model')),300);close(f);
end
