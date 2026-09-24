function matlab_q1_batch()
%MATLAB_Q1_BATCH 供 MATLAB -batch 调用，保留完整错误与运行日志。
projectRoot = fileparts(fileparts(mfilename("fullpath")));
logPath = fullfile(projectRoot, "results", "matlab_q1_latest.log");
errorPath = fullfile(projectRoot, "results", "matlab_q1_batch_error.txt");
fid = fopen(logPath, "w", "n", "UTF-8");
if fid >= 0
    fprintf(fid, "MATLAB Q1 batch started: %s\n", datestr(now, 31));
    fclose(fid);
end
diary(logPath);
try
    report = matlab_validate_q1();
    disp(jsonencode(report));
    fid = fopen(errorPath, "w", "n", "UTF-8");
    if fid >= 0
        fprintf(fid, "No error; MATLAB Q1 validation and figure export passed.\n");
        fclose(fid);
    end
    diary off;
catch exception
    errorText = getReport(exception, "extended", "hyperlinks", "off");
    disp(errorText);
    fid = fopen(errorPath, "w", "n", "UTF-8");
    if fid >= 0
        fprintf(fid, "%s", errorText);
        fclose(fid);
    end
    diary off;
    rethrow(exception);
end
end
