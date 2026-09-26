function test_svg_export()
root=fileparts(fileparts(mfilename('fullpath')));addpath(fullfile(root,'utils'));
f=figure('Visible','off');apply_publication_style(f,'zh','double');plot([0 1],[1 2],'-s');xlabel('载荷 (kg)');ylabel('能耗 (kWh)');legend('B');export_publication_figure(f,fullfile(root,'results','svg_test'),300);close(f);
end
