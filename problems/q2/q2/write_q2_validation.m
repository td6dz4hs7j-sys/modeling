function write_q2_validation(V,path)
% Write an independently computed validation receipt.
fid=fopen(path,'w','n','UTF-8');assert(fid>=0,'Cannot write %s',path);
c=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s',jsonencode(V,'PrettyPrint',true));
end
