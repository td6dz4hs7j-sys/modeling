function outputs = export_publication_figure(fig, outputStem, dpi, grayscalePreview, strictDesign)
%EXPORT_PUBLICATION_FIGURE 通过设计门禁后输出 SVG、PNG 与灰度质检图。
arguments
    fig (1,1) matlab.ui.Figure
    outputStem (1,1) string
    dpi (1,1) double {mustBeInteger,mustBeGreaterThanOrEqual(dpi,300)} = 300
    grayscalePreview (1,1) logical = true
    strictDesign (1,1) logical = true
end

[folder, name, ~] = fileparts(outputStem);
if strlength(folder) == 0
    folder = ".";
end
if ~isfolder(folder)
    mkdir(folder);
end
stem = fullfile(folder, name);
svgPath = stem + ".svg";
pngPath = stem + ".png";
fig.PaperPositionMode = "auto";
drawnow;
designIssues = audit_publication_figure(fig);
if strictDesign && ~isempty(designIssues)
    error("出版设计预检未通过：%s", join(designIssues, "；"));
end
% MATLAB R2022a 的 exportgraphics 不接受 .svg 扩展名；print 是兼容的
% 原生矢量导出路径，并保留可编辑文字。
print(fig, svgPath, "-dsvg", "-painters");
print(fig, pngPath, "-dpng", sprintf("-r%d", dpi));
outputs = struct("svg", svgPath, "png", pngPath);
if grayscalePreview
    qaFolder = fullfile(folder, "_qa");
    if ~isfolder(qaFolder)
        mkdir(qaFolder);
    end
    image = imread(pngPath);
    rgb = double(image(:,:,1:3));
    if isinteger(image)
        rgb = rgb / double(intmax(class(image)));
    end
    gray = 0.2126 * rgb(:,:,1) + 0.7152 * rgb(:,:,2) + 0.0722 * rgb(:,:,3);
    grayPath = fullfile(qaFolder, name + "_grayscale.png");
    imwrite(gray, grayPath);
    outputs.grayscale = grayPath;
end
end
