%% 1. 数据准备 (如果您已有数据，请跳过此节，直接加载您的数据)
% 假设您的数据结构为结构体或Table，分别为 BTC 和 Gold
% 包含字段: .Date (datetime格式) 和 .Value (double格式)

% --- 模拟生成数据 (开始) ---
load rawdata.mat
% 模拟 BTC: 全程在线 (365天)
BTC.Date = btc.Date ;
BTC.Value = btc.Value ; % 随机漫步

% 模拟 Gold: 剔除周末 (模拟休市)
Gold.Date = gold_delnan.Date; 
Gold.Value = gold_delnan.Value; % 随机漫步
% --- 模拟生成数据 (结束) ---


%% 2. 绘图设置 (绝对价格 + 英文/数字日期格式)

% 创建高清白色背景窗口
fig = figure('Color', 'w', 'Position', [100, 100, 1200, 700]);
t = tiledlayout(1,1, 'Padding', 'compact');
ax = nexttile;

% === 左轴：Bitcoin (绝对价格) ===
yyaxis left
% 设置比特币颜色 (经典橙色)
colorBTC = [0.96, 0.50, 0.09]; 
h1 = plot(BTC.Date, BTC.Value, '-', 'LineWidth', 1.8, 'Color', [colorBTC, 0.9]);

% Y轴格式化：使用逗号分隔千分位 (例如 30,000)
ax.YAxis(1).TickLabelFormat = '%,.0f'; 
ylabel('Bitcoin Price (USD)', 'FontWeight', 'bold', 'FontSize', 12);
ax.YColor = colorBTC; % 轴颜色同步

% === 右轴：Gold (绝对价格) ===
yyaxis right
% 设置黄金颜色 (深金属金)
colorGold = [0.72, 0.53, 0.04]; 
h2 = plot(Gold.Date, Gold.Value, '-', 'LineWidth', 1.8, 'Color', [colorGold, 0.9]);

% Y轴格式化
ax.YAxis(2).TickLabelFormat = '%,.0f';
ylabel('Gold Price (USD)', 'FontWeight', 'bold', 'FontSize', 12);
ax.YColor = colorGold;

% === 核心调整：X轴 (日期格式) ===
xlabel('Date', 'FontSize', 12);

% 【关键点】强制不显示中文月份
% 方法1：使用国际标准数字格式 'yyyy-MM' (推荐，最整洁)
xtickformat('yyyy-MM'); 

% 方法2：如果您坚持要英文月份 (如 Jan, Feb)，请取消注释下面这行
% xtickformat('MMM-yyyy'); % 注意：在中文系统下这可能仍显示中文，除非更改系统Locale
% 如果必须在中文系统强制显示英文月份，建议使用上面的 'yyyy-MM' 最为保险。

% 限制 X 轴范围紧贴数据
xlim([min(BTC.Date), max(BTC.Date)]);

% === 美化细节 ===
title('Bitcoin vs. Gold', 'FontSize', 16, 'FontWeight', 'bold');

% 网格设置
grid on;
ax.GridAlpha = 0.1;       % 网格线更淡，突出曲线
ax.MinorGridAlpha = 0.05;
ax.LineWidth = 1.2;       % 坐标轴加粗

% 强制关闭科学计数法 (防止价格显示为 3x10^4)
ax.YAxis(1).Exponent = 0; 
ax.YAxis(2).Exponent = 0;

% === 图例设置 ===
% 设置图例背景半透明，不遮挡曲线
lgd = legend([h1, h2], {'BTC (USD)', 'Gold (USD)'}, ...
    'Location', 'northwest', 'FontSize', 11);
lgd.EdgeColor = 'none'; % 去除图例边框
lgd.Color = [1 1 1 0.8]; % 白色背景，带一点透明度

% 开启上方和右侧边框框线，使图表封闭
box on;