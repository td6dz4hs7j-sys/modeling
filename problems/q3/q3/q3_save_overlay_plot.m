function q3_save_overlay_plot(f,folder,legacy,stem,caption)
if endsWith(string(folder),'q3_overlay')
 apply_publication_style(f,'en','report');title(caption);
 export_publication_figure(f,string(fullfile(folder,stem)),300);
else
 exportgraphics(f,fullfile(folder,legacy),'Resolution',230);
end
end
