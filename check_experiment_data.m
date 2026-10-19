%% check_experiment_data.m
% 正式交付前的四层检查脚本，与 extract_experiment_data.m 配套使用。
%
% 第1层 自动化断言：表头、通道数、首行归零、时间步长、时长、数值有效性
% 第2层 对照《实验数据说明.md》处理记录表：样本数、归零后时长逐文件核对
% 第3层 文件名解析：受试者/次数范围、文件名回环、每名受试者 18 份且 9 种模式
% 第4层 目视检查：输出代表性波形图 PNG 到 check_plots/
%
% 运行后会在命令行打印 PASS/FAIL 汇总，并在 check_plots/ 下生成
% layer4_waveforms.png 和 check_report.txt。

clear; clc;

dataDir = 'C:\Users\nanshemgjimemg\OneDrive\Desktop\实验数据\归零数据';
scriptDir = fileparts(mfilename('fullpath'));
if isempty(scriptDir), scriptDir = pwd; end
outDir = fullfile(scriptDir, 'check_plots');
if ~exist(outDir, 'dir'), mkdir(outDir); end

%% 第2层对照表（来自《实验数据说明.md》处理记录：文件 -> 样本数, 时长/s）
expected = { ...
    'FT上楼1.csv',              1229,  24.56; ...
    'FT上楼2.csv',              1433,  28.64; ...
    'FT上楼梯-行走1.csv',       2035,  40.68; ...
    'FT上楼梯-行走2.csv',       2092,  41.82; ...
    'FT下楼-行走1.csv',         2333,  46.64; ...
    'FT下楼-行走2.csv',         2229,  44.56; ...
    'FT下楼1.csv',              1275,  25.48; ...
    'FT下楼2.csv',              1319,  26.36; ...
    'FT行走-上楼1.csv',         1931,  38.60; ...
    'FT行走-上楼2.csv',         2059,  41.16; ...
    'FT行走-下楼1.csv',         2096,  41.90; ...
    'FT行走-下楼2.csv',         2102,  42.02; ...
    'FT行走-急停-行走1.csv',    1800,  35.98; ...
    'FT行走-急停-行走2.csv',    1623,  32.44; ...
    'FT行走1.csv',              5063, 101.24; ...
    'FT行走2.csv',              6018, 120.34; ...
    'FT行走，急停，上下楼梯1.csv', 2180, 43.58; ...
    'FT行走，急停，上下楼梯2.csv', 2403, 48.04; ...
    'LSR上楼1.csv',             1284,  25.66; ...
    'LSR上楼2.csv',             1233,  24.64; ...
    'LSR上楼梯–行走1.csv',      1882,  37.62; ...
    'LSR上楼梯–行走2.csv',      1901,  38.00; ...
    'LSR下楼1.csv',             1119,  22.36; ...
    'LSR下楼2.csv',             1135,  22.68; ...
    'LSR下楼梯—行走1.csv',      1663,  33.24; ...
    'LSR下楼梯—行走2.csv',      1763,  35.24; ...
    'LSR行走1.csv',             3701,  74.00; ...
    'LSR行走2.csv',             3682,  73.62; ...
    'LSR行走–下楼梯1.csv',      2014,  40.26; ...
    'LSR行走–下楼梯2.csv',      1883,  37.64; ...
    'LSR行走—上楼梯1.csv',      1516,  30.30; ...
    'LSR行走—上楼梯2.csv',      1661,  33.20; ...
    'LSR行走—急停—行走1.csv',   2028,  40.54; ...
    'LSR行走—急停—行走2.csv',   1914,  38.26; ...
    'LSR行走，急停，上下楼梯1.csv', 2139, 42.76; ...
    'LSR行走，急停，上下楼梯2.csv', 2193, 43.84  ...
};
expName     = expected(:,1);
expSamples  = cell2mat(expected(:,2));
expDuration = cell2mat(expected(:,3));

%% 读取全部 CSV
files  = dir(fullfile(dataDir, '*.csv'));
nFiles = numel(files);

subjList  = cell(1, nFiles);
modeList  = cell(1, nFiles);
trialList = zeros(1, nFiles);

pass   = true;
report = {};

for i = 1:nFiles
    fname = files(i).name;
    [~, stem] = fileparts(fname);

    subject = regexp(stem, '^[A-Z]+', 'match', 'once');
    trial   = str2double(stem(end));
    mode    = stem(numel(subject)+1:end-1);

    subjList{i}  = subject;
    modeList{i}  = mode;
    trialList(i) = trial;

    T = readtable(fullfile(dataDir, fname));
    t = T.Time;
    v = table2array(T(:, 2:end));

    issues = {};

    % ---- 第1层：自动化断言 ----
    expectHeader = [{'Time'}, arrayfun(@(k) sprintf('CH%d', k), 0:9, 'UniformOutput', false)];
    if ~isequal(T.Properties.VariableNames, expectHeader)
        issues{end+1} = '表头异常';
    end
    if size(v,2) ~= 10,                        issues{end+1} = '通道数!=10'; end
    if numel(t) ~= size(v,1),                  issues{end+1} = '时间/数据行数不一致'; end
    if abs(t(1)) > 1e-12,                      issues{end+1} = '首行Time!=0'; end
    if any(abs(v(1,1:8)) > 1e-12),             issues{end+1} = '首行CH0~7未归零'; end
    if any(abs(diff(t) - 0.02) > 1e-9),        issues{end+1} = '步长!=0.02'; end
    if abs(t(end) - (numel(t)-1)*0.02) > 1e-6, issues{end+1} = '末尾时长异常'; end
    if ~all(isfinite(v(:))),                   issues{end+1} = '存在NaN/Inf'; end
    if any(v(:,9) ~= round(v(:,9))),           issues{end+1} = 'CH8非整数'; end
    if any(v(:,10) < 0 | v(:,10) > 100),       issues{end+1} = 'CH9电量越界'; end

    % ---- 第2层：对照处理记录表 ----
    k = find(strcmp(expName, fname), 1);
    if isempty(k)
        issues{end+1} = '处理记录表缺失该文件';
    else
        if numel(t) ~= expSamples(k),              issues{end+1} = '样本数与记录不符'; end
        if abs(t(end) - expDuration(k)) > 1e-3,    issues{end+1} = '时长与记录不符'; end
    end

    % ---- 第3层：文件名解析 ----
    if ~ismember(subject, {'FT', 'LSR'}),     issues{end+1} = '受试者解析错误'; end
    if ~ismember(trial, [1 2]),               issues{end+1} = '次数解析错误'; end
    if ~strcmp([subject mode num2str(trial)], stem), issues{end+1} = '文件名回环失败'; end

    if ~isempty(issues)
        pass = false;
        report{end+1} = sprintf('[FAIL] %s: %s', fname, strjoin(issues, ', '));
    end
end

% ---- 第3层：分组统计 ----
if size(expected,1) ~= 36,   report{end+1} = '[FAIL] 对照表条目数 != 36'; pass = false; end
if nFiles ~= 36,             report{end+1} = '[FAIL] CSV 文件数 != 36';   pass = false; end
for s = {'FT', 'LSR'}
    subj = s{1};
    idx  = strcmp(subjList, subj);
    if sum(idx) ~= 18, report{end+1} = sprintf('[FAIL] %s 文件数 != 18', subj); pass = false; end
    if numel(unique(modeList(idx))) ~= 9
        report{end+1} = sprintf('[FAIL] %s 运动模式数 != 9', subj); pass = false;
    end
    combo = cellfun(@(m, tr) [m '_' num2str(tr)], modeList(idx), ...
                    num2cell(trialList(idx)), 'UniformOutput', false);
    if numel(unique(combo)) ~= 18
        report{end+1} = sprintf('[FAIL] %s 存在重复的模式+次数', subj); pass = false;
    end
end

%% ---- 第4层：生成代表性波形图 ----
repFiles = {'FT上楼1.csv', ...
            'FT行走1.csv', ...
            'LSR行走—急停—行走1.csv', ...
            'LSR行走，急停，上下楼梯2.csv'};

fig = figure('Color', 'w', 'Position', [80 80 1200 760], 'Name', 'Layer4 visual check');
for p = 1:numel(repFiles)
    fname = repFiles{p};
    T = readtable(fullfile(dataDir, fname));
    t = T.Time;
    v = table2array(T(:, 2:end));
    subplot(2, 2, p);
    plot(t, v(:,1), 'b-', 'LineWidth', 1.0); hold on;
    plot(t, v(:,4), 'r-', 'LineWidth', 1.0);
    xlabel('时间 / s'); ylabel('髋关节角度 / rad');
    title(fname, 'Interpreter', 'none');
    legend({'左髋 CH0', '右髋 CH3'}, 'Location', 'best');
    grid on;
end
print(fig, fullfile(outDir, 'layer4_waveforms.png'), '-dpng', '-r150');
close(fig);

%% ---- 输出结果 ----
fprintf('================ 四层检查结果 ================\n');
if pass
    fprintf('第1层(断言)、第2层(对照表)、第3层(文件名解析) 全部通过。\n');
else
    fprintf('共发现 %d 个问题：\n', numel(report));
    fprintf('%s\n', report{:});
end
fprintf('第4层波形图：%s\n', fullfile(outDir, 'layer4_waveforms.png'));
fprintf('OVERALL = %s\n', string(pass));

% 写出报告文本（UTF-8）
reportFile = fullfile(outDir, 'check_report.txt');
fid = fopen(reportFile, 'w', 'n', 'UTF-8');
fprintf(fid, 'extract_experiment_data.m 四层检查报告\n');
fprintf(fid, '生成时间：%s\n', datestr(now, 31));
fprintf(fid, '数据目录：%s\n', dataDir);
fprintf(fid, '文件总数：%d\n', nFiles);
fprintf(fid, 'OVERALL = %s\n', string(pass));
if pass
    fprintf(fid, '第1/2/3层全部通过；第4层波形图见 layer4_waveforms.png。\n');
else
    for r = 1:numel(report), fprintf(fid, '%s\n', report{r}); end
end
fclose(fid);
