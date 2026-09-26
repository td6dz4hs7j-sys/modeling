function q3_overlay_candidate_matlab()
root=fileparts(fileparts(mfilename('fullpath')));out=fullfile(root,'results','q3_overlay');
T=readtable(fullfile(out,'luna_flex_transport.csv'),'TextType','string');T=sortrows(T,'route');
assert(height(T)==23&&isequal(T.route,(1:23)'));
R=readtable(fullfile(out,'luna_flex_relays.csv'),'TextType','string');R=sortrows(R,'site_row');
q3_overlay_schedule(struct('transport',T,'relays',R));
end
