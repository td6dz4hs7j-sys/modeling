function h = q2_sha256(paths)
% SHA-256 over ordered relative paths and file bytes.
paths = string(paths(:)); paths = sort(paths);
md = java.security.MessageDigest.getInstance('SHA-256');
for i=1:numel(paths)
    p=char(paths(i)); md.update(uint8(unicode2native(p,'UTF-8')));
    fid=fopen(p,'rb'); assert(fid>=0,'Cannot read for SHA-256: %s',p);
    c=onCleanup(@()fclose(fid)); bytes=fread(fid,Inf,'*uint8'); clear c;
    md.update(bytes);
end
d=typecast(md.digest(),'uint8'); h=lower(reshape(dec2hex(d,2)',1,[]));
end
