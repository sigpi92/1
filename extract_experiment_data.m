%% extract_experiment_data.m
% 功能：递归读取「实验数据」目录下所有 CSV（包括 归零数据/ 及今后加入的任何
%       原始数据子目录），自动识别“原始数据 / 已归零数据”，对原始数据按
%       《实验数据说明.md》的规则自动归零，统一提取为结构体数组 data 并保存 .mat。
%       运行结束后会为每名受试者生成一张“全部文件”的汇总波形图。
%
% 识别与处理逻辑：
%   1) 递归查找 dataRoot 下所有 *.csv（自带的 listCsvRecursive 本地函数，不依赖 '**'）；
%   2) 原始数据识别：文件开头存在“整行全零”（Time 与 CH0~CH9 均为 0）的
%      VOFA+ 占位行。若存在，则视为原始数据并执行归零：
%         - 以第一个非全零回传帧作为本次采集起点，删除其之前的占位行；
%         - Time 减去该帧时间，使起点为 0；
%         - CH0~CH7 分别减去该帧对应通道值；
%         - CH8(故障码)、CH9(电量) 为状态量，保留绝对原始值，不参与归零；
%   3) 已归零数据（首行 Time=0 且 CH9≠0，无前导全零行）直接读取，不做二次处理；
%   4) 文件名解析：开头连续英文字母 = 受试者（FT / LSR），
%                  末尾数字（.csv 之前）= 采集次数（1 / 2），
%                  中间部分 = 运动模式。
%
% 输出结构体 data 的字段：
%   subject 受试者、mode 运动模式、trial 采集次数、filename 文件名、
%   folder 相对数据根目录的子目录、processed 是否执行了归零、
%   time 时间列(s)、values CH0~CH9 矩阵。
%
% 运行后会在工作区得到 data（1×N 结构体数组），并保存到
% extracted_experiment_data.mat；每名受试者生成一张 overview_<受试者>.png。

clear; clc;

%% ===== 1. 配置 =====
dataRoot = 'C:\Users\nanshemgjimemg\OneDrive\Desktop\实验数据';

% 输出文件保存到本脚本所在目录（若无法定位则保存在当前目录）
scriptDir = fileparts(mfilename('fullpath'));
if isempty(scriptDir)
    scriptDir = pwd;
end
outMat = fullfile(scriptDir, 'extracted_experiment_data.mat');

% 汇总图显示方式：true = 图片窗口保持打开，由你手动关闭；
%                false = 保存 PNG 后自动关闭（只保留文件）。
keepFiguresOpen = true;

%% ===== 2. 递归列出所有 CSV 文件 =====
fileList = listCsvRecursive(dataRoot);
nFiles = numel(fileList);
if nFiles == 0
    error('在 %s 下未找到任何 CSV 文件，请检查 dataRoot 路径。', dataRoot);
end

%% ===== 3. 批量读取 + 自动归零 + 文件名解析 =====
data = struct('subject', {}, 'mode', {}, 'trial', {}, 'filename', {}, ...
              'folder', {}, 'processed', {}, 'time', {}, 'values', {});

for i = 1:nFiles
    fname = fileList(i).name;
    fpath = fullfile(fileList(i).folder, fname);

    T = readtable(fpath);                        % 自动识别表头
    time = T.Time;                               % 时间列
    vals = table2array(T(:, 2:end));             % CH0~CH9

    % ---- 自动识别原始数据：前导“整行全零”占位行 ----
    allZero    = all([time, vals] == 0, 2);      % Time 与 10 个通道同时为 0
    firstValid = find(~allZero, 1, 'first');

    processed = false;
    if isempty(firstValid)
        error('文件 %s 全部为占位行，未找到有效数据。', fname);
    elseif firstValid > 1
        processed = true;                        % 原始数据，执行归零
        time = time(firstValid:end);
        vals = vals(firstValid:end, :);
        time = time - time(1);                   % 时间起点归零
        vals(:, 1:8) = vals(:, 1:8) - vals(1, 1:8);  % CH0~CH7 归零
        % CH8、CH9 保持绝对原始值
    end

    % ---- 解析文件名 ----
    [~, stem] = fileparts(fname);
    subject = regexp(stem, '^[A-Z]+', 'match', 'once');
    trial   = str2double(stem(end));
    mode    = stem(numel(subject)+1:end-1);

    % ---- 相对子目录（如 '归零数据'；直接位于根目录则为空）----
    rel = strrep(fileList(i).folder, dataRoot, '');
    rel = regexprep(rel, '^[\\/]+', '');

    data(i).subject   = subject;
    data(i).mode      = mode;
    data(i).trial     = trial;
    data(i).filename  = fname;
    data(i).folder    = rel;
    data(i).processed = processed;
    data(i).time      = time;
    data(i).values    = vals;
end

%% ===== 4. 打印汇总信息 =====
fprintf('共读取 %d 份 CSV 文件：\n', nFiles);
for i = 1:nFiles
    state = '已归零';
    if data(i).processed, state = '原始->已归零'; end
    fprintf('  %-30s | %-8s | 受试者=%-3s | 模式=%-16s | 第%d次 | 样本=%d | 时长=%.2f s | %s\n', ...
        data(i).filename, data(i).folder, data(i).subject, data(i).mode, ...
        data(i).trial, numel(data(i).time), data(i).time(end), state);
end

%% ===== 5. 通道含义（供后续分析对照） =====
channelNames = {'CH0 左髋输出角度 (rad)', ...
                'CH1 左髋输出角速度 (rad/s)', ...
                'CH2 左髋反馈力矩 (N·m)', ...
                'CH3 右髋输出角度 (rad)', ...
                'CH4 右髋输出角速度 (rad/s)', ...
                'CH5 右髋反馈力矩 (N·m)', ...
                'CH6 IMU俯仰角 pitch (°)', ...
                'CH7 IMU横滚角 roll (°)', ...
                'CH8 左电机故障码', ...
                'CH9 电池电量 (%)'};

%% ===== 6. 保存提取结果 =====
save(outMat, 'data', 'channelNames', 'dataRoot');
fprintf('提取结果已保存到：%s\n', outMat);

%% ===== 7. 汇总绘图：为每名受试者绘制全部文件的波形 =====
% 每个子图：蓝线=左髋角度(CH0)，红线=右髋角度(CH3)，标题为文件名。
subjects = unique({data.subject});
for si = 1:numel(subjects)
    subj = subjects{si};
    idx = find(strcmp({data.subject}, subj));
    nSubj = numel(idx);
    cols = 6;
    rows = ceil(nSubj / cols);

    fig = figure('Color', 'w', 'Position', [60 60 1500 780], ...
                 'Name', sprintf('%s 全部数据', subj));
    for j = 1:nSubj
        k = idx(j);
        subplot(rows, cols, j);
        plot(data(k).time, data(k).values(:, 1), 'b-', 'LineWidth', 1.0); hold on;
        plot(data(k).time, data(k).values(:, 4), 'r-', 'LineWidth', 1.0);
        xlabel('t / s'); ylabel('髋角度 / rad');
        title(data(k).filename, 'Interpreter', 'none', 'FontSize', 7);
        grid on; axis tight;
    end

    pngPath = fullfile(scriptDir, sprintf('overview_%s.png', subj));
    print(fig, pngPath, '-dpng', '-r120');
    if ~keepFiguresOpen
        close(fig);
    end
    fprintf('已生成 %s 的汇总波形图：%s\n', subj, pngPath);
end

%% ===== 本地函数：递归列出所有 CSV =====
function fileList = listCsvRecursive(root)
% 递归列出 root 下所有 .csv 文件，返回含 name / folder 字段的结构体数组。
fileList = struct('name', {}, 'folder', {});
if ~exist(root, 'dir')
    return;
end

items = dir(root);
for k = 1:numel(items)
    nm = items(k).name;
    if strcmp(nm, '.') || strcmp(nm, '..')
        continue;
    end
    p = fullfile(root, nm);
    if items(k).isdir
        fileList = [fileList, listCsvRecursive(p)]; %#ok<AGROW>
    elseif numel(nm) >= 4 && strcmpi(nm(end-3:end), '.csv')
        fileList(end+1).name = nm; %#ok<AGROW>
        fileList(end).folder = root;
    end
end
end
