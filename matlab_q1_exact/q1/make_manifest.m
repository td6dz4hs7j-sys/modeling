function make_manifest(D,elapsed,out)
% Pure-MATLAB reproducibility metadata; no Python dependency to reproduce Q1.
if nargin<3,out=fullfile(D.root,'results','q1_exact_dp');end
root=D.root;inputRoot=fullfile(root,'input');
if ~isfolder(inputRoot),inputRoot=fullfile(root,'data','raw','D题');end
files=dir(fullfile(inputRoot,'**','*'));inputs=struct([]);
for k=1:numel(files)
 if files(k).isdir,continue;end
 p=fullfile(files(k).folder,files(k).name);[~,~,ext]=fileparts(p);if strcmp(ext,'.txt'),continue;end
 md=java.security.MessageDigest.getInstance('SHA-256');fid=fopen(p,'rb');bytes=fread(fid,Inf,'*uint8');fclose(fid);md.update(bytes);
 digest=typecast(md.digest(),'uint8');hash=lower(reshape(dec2hex(digest,2)',1,[]));
 inputs=[inputs;struct('path',strrep(p,[root filesep],''),'sha256',hash)]; %#ok<AGROW>
end
M=struct('seed',20260924,'runtime','MATLAB','runtime_version',version,'dependencies',ver,'elapsed_seconds',elapsed,'input_files',inputs,'parameters',struct('gravity',D.g,'clearance_m',50,'delivery_height_m',30,'reserve',D.uav.reserve,'objective','lexicographic N E T plus normalized joint weights over N/E/T','joint_weight_formula','J=wN*N/N0+wE*E/E0+wT*T/T0; wN+wE+wT=1','tolerances',D.tol),'command','powershell -NoProfile -ExecutionPolicy Bypass -File .\matlab_q1_exact\run_q1.ps1 -Mode full','optimality_scope','exact pattern-count DP, cross-checked MILP; conditional physical interpretation and numerical tolerance');
f=fopen(fullfile(out,'复现清单.json'),'w','n','UTF-8');c=onCleanup(@()fclose(f));fprintf(f,'%s',jsonencode(M,'PrettyPrint',true));
end
