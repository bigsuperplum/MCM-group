%% 1. 数据对齐与预处理
% ---------------------------------------------------------
% 假设输入：
% btc.Date, btc.Value, btcpredict (长度与btc.Date一致)
% gold_delnan.Date, gold_delnan.Value, goldpredict (长度与gold_delnan.Date一致)
% ---------------------------------------------------------

% 1.1 构建 TimeTable (这是处理时间对齐的神器)
tt_btc = timetable(btc.Date, btc.Value, btcpredict, ...
    'VariableNames', {'Price', 'Predict'});

tt_gold = timetable(gold_delnan.Date, gold_delnan.Value, goldpredict, ...
    'VariableNames', {'Price', 'Predict'});

% 1.2 同步时间轴 (Synchronize)
% 以两个时间的并集为准 (Union)，或者以 BTC 为主 (因为 BTC 时间最全)
% 这里我们使用 'union' 确保不漏掉任何信息，然后重新采样到 BTC 的频率（如果需要）
tt_aligned = synchronize(tt_btc, tt_gold, 'union');

% 变量重命名，方便后续操作
tt_aligned.Properties.VariableNames = {'BTC_Price', 'BTC_Predict', 'Gold_Price', 'Gold_Predict'};

% 1.3 核心逻辑：标记黄金的可交易状态
% 在填充缺失值之前，先判断哪些行原本是有黄金数据的
% 如果 Gold_Price 是 NaN，说明当天黄金休市
is_gold_tradable = ~isnan(tt_aligned.Gold_Price);

% 1.4 缺失值填充 (Fill Missing)
% BTC: 理论上不该缺，如果有缺则用前值填充
tt_aligned.BTC_Price = fillmissing(tt_aligned.BTC_Price, 'previous');
tt_aligned.BTC_Predict = fillmissing(tt_aligned.BTC_Predict, 'previous');

% Gold: 休市期间价格 = 上一个收盘价 (previous)
% 预测值也顺延，或者设为0 (这里顺延以便计算逻辑统一，但在策略里会屏蔽)
tt_aligned.Gold_Price = fillmissing(tt_aligned.Gold_Price, 'previous');
tt_aligned.Gold_Predict = fillmissing(tt_aligned.Gold_Predict, 'previous');

% ---------------------------------------------------------
% 此时 tt_aligned 包含每一天的 BTC 和 Gold 数据
% is_gold_tradable 标记了黄金当天是否开市
% ---------------------------------------------------------

%% 2. 准备策略所需的向量
% 提取对齐后的向量
vec_btc_price = tt_aligned.BTC_Price;
vec_btc_pred  = tt_aligned.BTC_Predict;
vec_gold_price = tt_aligned.Gold_Price;
vec_gold_pred  = tt_aligned.Gold_Predict;

% 按照上一段代码的逻辑，计算预期收益率 rexp
% 公式: (预测今天 - 昨天实际) / 昨天实际
% 注意：Matlab中 diff 操作会使长度 -1，需要注意索引对齐

% 我们模拟 t 时刻做决策，使用的是 t 时刻的预测值 和 t-1 时刻的真实值
% 因此数据从第 2 行开始才有"昨天"
N = height(tt_aligned);
start_idx = 2; 

% 初始化收益率向量
rexp_btc = zeros(N, 1);
rexp_gold = zeros(N, 1);

% 计算
% rexp[t] = (Predict[t] - Price[t-1]) / Price[t-1]
rexp_btc(start_idx:end) = (vec_btc_pred(start_idx:end) - vec_btc_price(start_idx-1:end-1)) ./ vec_btc_price(start_idx-1:end-1);
rexp_gold(start_idx:end) = (vec_gold_pred(start_idx:end) - vec_gold_price(start_idx-1:end-1)) ./ vec_gold_price(start_idx-1:end-1);

% 对应的可交易状态也需要对齐（第 t 天是否可以交易）
tradable_status = is_gold_tradable;

%% 3. 执行策略 (含交易摩擦与阈值过滤)
fee_btc = 0.02;     % 比特币手续费
fee_gold = 0.01;    % 黄金手续费
trade_threshold = 0.01; % 【新增】交易阈值 (0.5%)
% 含义：如果切换带来的预期收益增幅不超过 0.5%，则保持现状不动

signals = zeros(N, 1); 
current_pos = 0; % 0:Cash, 1:BTC, 2:Gold

% 从 start_idx 开始遍历
for i = start_idx:N
    
    r_b = rexp_btc(i);
    r_g = rexp_gold(i);
    gold_is_open = tradable_status(i); % 获取今日黄金市场状态
    
    % --- 步骤 A: 计算所有可能的归一化价值 (扣费后) ---
    % 我们计算如果选择该资产，资金会变成原来的多少倍 (Multiplier)
    
    % 1. 既然是做决策，先计算"如果不动"和"如果切换"分别的价值乘数
    
    % 假设当前持仓是 Cash
    if current_pos == 0
        v_cash = 1.0;                           % 继续持有现金，价值不变
        v_btc  = (1 - fee_btc) * (1 + r_b);     % 换BTC：扣手续费 + 涨跌幅
        if gold_is_open
            v_gold = (1 - fee_gold) * (1 + r_g);
        else
            v_gold = -Inf; % 关门，买不进
        end
        
    % 假设当前持仓是 BTC
    elseif current_pos == 1
        v_cash = (1 - fee_btc);                 % 卖BTC换现金：扣手续费
        v_btc  = (1 + r_b);                     % 继续持有BTC：无手续费，吃涨跌幅
        if gold_is_open
            % 卖BTC (扣费) -> 买Gold (扣费) -> 涨跌幅
            v_gold = (1 - fee_btc) * (1 - fee_gold) * (1 + r_g);
        else
            v_gold = -Inf;
        end
        
    % 假设当前持仓是 Gold
    elseif current_pos == 2
        if gold_is_open
            v_cash = (1 - fee_gold);            % 卖Gold换现金
            v_btc  = (1 - fee_gold) * (1 - fee_btc) * (1 + r_b);
            v_gold = (1 + r_g);                 % 继续持有
        else
            % 休市强制锁仓逻辑
            v_cash = -Inf;
            v_btc  = -Inf;
            v_gold = 1e9; % 必须持有，给一个极大值确保选中
        end
    end
    
    % --- 步骤 B: 应用阈值逻辑 (Inertia) ---
    % 逻辑：为了防止频繁震荡，我们给"当前持仓"的价值加上阈值优势。
    % 只有当挑战者的价值 > (当前价值 + 阈值) 时，max 才会选中挑战者。
    
    % 只有在不是强制锁仓的情况下才应用阈值
    if ~(current_pos == 2 && ~gold_is_open)
        if current_pos == 0
            v_cash = v_cash + trade_threshold;
        elseif current_pos == 1
            v_btc = v_btc + trade_threshold;
        elseif current_pos == 2
            v_gold = v_gold + trade_threshold;
        end
    end
    
    % --- 步骤 C: 决策 ---
    [~, best_idx] = max([v_cash, v_btc, v_gold]);
    
    % 映射回状态 0, 1, 2
    if best_idx == 1
        current_pos = 0;
    elseif best_idx == 2
        current_pos = 1;
    else
        current_pos = 2;
    end
    
    signals(i) = current_pos;
end
%% 4. 可视化检查
figure;
ax1 = subplot(3,1,1);
plot(tt_aligned.Time, vec_btc_price, 'b'); hold on;
yyaxis right;
plot(tt_aligned.Time, vec_gold_price, 'y');
title('对齐后的价格走势'); legend('BTC', 'Gold');

ax2 = subplot(3,1,2);
% 绘制可交易状态区域
area(tt_aligned.Time, double(tradable_status), 'FaceColor', [0.9 0.9 0.9], 'EdgeColor', 'none');
hold on;
stairs(tt_aligned.Time, signals, 'k', 'LineWidth', 1.5);
title('持仓状态 (灰色背景代表黄金开市)');
yticks([0 1 2]); yticklabels({'Cash', 'BTC', 'Gold'});

ax3 = subplot(3,1,3);
% 绘制收益率预测
plot(tt_aligned.Time, rexp_btc, 'b'); hold on;
plot(tt_aligned.Time, rexp_gold, 'y');
title('预期收益率 (休市时Gold通常为0)');

linkaxes([ax1, ax2, ax3], 'x');


%% 4. 账户回测 (Backtest)
% 初始化参数
initial_capital = 1000;
capital_curve = zeros(N, 1);    % 记录每天的资产净值
capital_curve(1:start_idx-1) = initial_capital; % 初始阶段保持本金不变

current_capital = initial_capital;
last_pos = 0; % 初始默认为持有现金 (0)

% 真实价格向量 (用于计算实际盈亏)
real_btc_price = tt_aligned.BTC_Price;
real_gold_price = tt_aligned.Gold_Price;

% --- 回测循环 ---
for i = start_idx:N
    % 1. 获取目标持仓信号
    target_pos = signals(i);
    
    % 2. 计算【换仓摩擦成本】 (Transaction Cost)
    cost_multiplier = 1.0; 
    
    if target_pos ~= last_pos
        % 如果持仓发生变化，根据变化类型扣费
        
        % 情况 A: 卖出旧资产 (如果之前不是现金)
        if last_pos == 1 % 卖BTC
            cost_multiplier = cost_multiplier * (1 - fee_btc);
        elseif last_pos == 2 % 卖Gold
            cost_multiplier = cost_multiplier * (1 - fee_gold);
        end
        
        % 情况 B: 买入新资产 (如果目标不是现金)
        if target_pos == 1 % 买BTC
            cost_multiplier = cost_multiplier * (1 - fee_btc);
        elseif target_pos == 2 % 买Gold
            cost_multiplier = cost_multiplier * (1 - fee_gold);
        end
    end
    
    % 扣除手续费后的本金
    current_capital = current_capital * cost_multiplier;
    
    % 3. 计算【持仓收益】 (Market Return)
    % 资金在这个时间段内经历了从 t-1 到 t 的价格波动
    market_multiplier = 1.0;
    
    switch target_pos
        case 0 % 现金
            market_multiplier = 1.0; % 现金无风险收益 (假设利率为0)
        case 1 % BTC
            % (今日价格 - 昨日价格) / 昨日价格 + 1  => 今日 / 昨日
            market_multiplier = real_btc_price(i) / real_btc_price(i-1);
        case 2 % Gold
            market_multiplier = real_gold_price(i) / real_gold_price(i-1);
            % 注意：如果黄金休市，fillmissing使得 price(i) == price(i-1)，
            % 所以 multiplier = 1.0，资产值不变，符合逻辑。
    end
    
    % 更新本金
    current_capital = current_capital * market_multiplier;
    
    % 记录
    capital_curve(i) = current_capital;
    last_pos = target_pos; % 更新当前持仓状态供下一次循环使用
end

%% 5. 高级绘图：资产走势与信号叠加
figure('Name', 'Backtest Result', 'Color', 'w', 'Position', [100, 100, 1000, 600]);

% --- 上半部分：资产净值曲线 ---
subplot(3, 1, [1 2]); % 占据 2/3 高度
plot(tt_aligned.Time, capital_curve, 'Color', [0.85, 0.33, 0.1], 'LineWidth', 2);
grid on; hold on;

% 标记买卖点 (为了图表整洁，我们只标记资产切换的时刻)
% 找出状态变化的索引
change_idx = find([0; diff(signals)] ~= 0 & (1:N)' >= start_idx);

for k = 1:length(change_idx)
    idx = change_idx(k);
    t = tt_aligned.Time(idx);
    val = capital_curve(idx);
    s = signals(idx);
    
    % 根据持仓类型画不同颜色的点
    if s == 0 % 卖出空仓 (灰点)
        plot(t, val, 'o', 'MarkerFaceColor', [0.5 0.5 0.5], 'MarkerEdgeColor', 'k', 'MarkerSize', 6);
    elseif s == 1 % 买入BTC (蓝三角)
        plot(t, val, '^', 'MarkerFaceColor', 'b', 'MarkerEdgeColor', 'none', 'MarkerSize', 6);
    elseif s == 2 % 买入Gold (黄钻)
        plot(t, val, 'd', 'MarkerFaceColor', [0.9 0.7 0.1], 'MarkerEdgeColor', 'k', 'MarkerSize', 6);
    end
end

% 添加图例和标签
title(['累计资产走势 (初始: $1000, 最终: $' num2str(current_capital, '%.2f') ')']);
ylabel('资产净值 ($)');
legend({'Total Asset', 'Switch Points'}, 'Location', 'best');

% 标注最大回撤 (可选)
current_max = 0;
max_drawdown = 0;
for i = 1:length(capital_curve)
    if capital_curve(i) > current_max, current_max = capital_curve(i); end
    dd = (current_max - capital_curve(i)) / current_max;
    if dd > max_drawdown, max_drawdown = dd; end
end
text(tt_aligned.Time(round(N/10)), initial_capital, ...
    sprintf('Max Drawdown: %.2f%%', max_drawdown*100), 'FontSize', 10, 'BackgroundColor', 'w');


% --- 下半部分：持仓色块图 ---
subplot(3, 1, 3);
% 使用 area 图来表示持仓状态背景
% 将 signals 转换为三个布尔矩阵分别画图，实现色块效果
s_cash = double(signals == 0);
s_btc  = double(signals == 1);
s_gold = double(signals == 2);

% 使用 area 堆叠图绘制背景色
h = area(tt_aligned.Time, [s_cash, s_btc, s_gold]);
h(1).FaceColor = [0.9 0.9 0.9]; % 现金: 灰色
h(1).EdgeColor = 'none';
h(2).FaceColor = [0.6 0.8 1.0]; % BTC: 浅蓝
h(2).EdgeColor = 'none';
h(3).FaceColor = [1.0 0.9 0.6]; % Gold: 浅黄
h(3).EdgeColor = 'none';

% 叠加实际的黄金休市区域（可选，用于验证）
% hold on; 
% bar(tt_aligned.Time, double(~tradable_status)*0.1, 'FaceColor', 'k', 'EdgeColor','none', 'FaceAlpha', 0.5);

axis tight;
ylim([0 1]);
yticks([]);
ylabel('持仓状态');
xlabel('时间');
legend(h, {'Cash', 'BTC', 'Gold'}, 'Location', 'eastoutside');
title('持仓分布 (灰色:空仓, 蓝色:BTC, 黄色:黄金)');


%% 6. 绩效评价与夏普比率计算
% ---------------------------------------------------------
% 步骤 A: 准备数据
% ---------------------------------------------------------
% 截取正式开始回测那一天之后的资金曲线
% capital_curve 的前 start_idx-1 个数据是初始资金，不动的部分不计入波动
valid_curve = capital_curve(start_idx:end);

% 计算每日收益率 (Daily Returns): (今天 - 昨天) / 昨天
daily_returns = diff(valid_curve) ./ valid_curve(1:end-1);

% ---------------------------------------------------------
% 步骤 B: 设置参数
% ---------------------------------------------------------
% 假设年化无风险利率 (Risk-Free Rate)，例如 3% (美国国债收益率)
rf_annual = 0; 

% 年化因子 (Annualization Factor)
% 传统股市用 252，加密货币用 365。由于本策略包含BTC和黄金，
% 且黄金休市时我们不产生波动，建议使用 252 比较符合传统金融标准，或者保守起见用 365
trading_days_per_year = 252;

% 将年化无风险利率转换为日无风险利率 (几何平均)
rf_daily = (1 + rf_annual)^(1/trading_days_per_year) - 1;

% ---------------------------------------------------------
% 步骤 C: 计算核心指标
% ---------------------------------------------------------
% 1. 超额收益 (Excess Returns)
excess_returns = daily_returns - rf_daily;

% 2. 计算夏普比率 (Sharpe Ratio)
% 公式: (平均超额收益 / 超额收益的标准差) * sqrt(年化天数)
sharpe_daily = mean(excess_returns) / std(excess_returns);
sharpe_ratio = sharpe_daily * sqrt(trading_days_per_year);

% 3. 重新计算最大回撤 (Max Drawdown) 用于报告
max_dd = 0;
peak = -Inf;
for k = 1:length(valid_curve)
    if valid_curve(k) > peak
        peak = valid_curve(k);
    end
    dd = (peak - valid_curve(k)) / peak;
    if dd > max_dd
        max_dd = dd;
    end
end

% 4. 计算总收益率
total_return = (valid_curve(end) - valid_curve(1)) / valid_curve(1);
% 简单年化收益率 (CAGR)
num_days = length(valid_curve);
annualized_return = (1 + total_return)^(trading_days_per_year / num_days) - 1;

% ---------------------------------------------------------
% 步骤 D: 打印策略体检报告
% ---------------------------------------------------------
fprintf('\n==================================================\n');
fprintf('               策略绩效评估报告               \n');
fprintf('==================================================\n');
fprintf('回测天数: \t%d 天\n', num_days);
fprintf('初始本金: \t$%.2f\n', valid_curve(1));
fprintf('最终资产: \t$%.2f\n', valid_curve(end));
fprintf('--------------------------------------------------\n');
fprintf('总收益率: \t%6.2f%%\n', total_return * 100);
fprintf('年化收益: \t%6.2f%% (CAGR)\n', annualized_return * 100);
fprintf('最大回撤: \t%6.2f%%\n', max_dd * 100);
fprintf('--------------------------------------------------\n');
fprintf('夏普比率: \t%6.4f  <-- (Sharpe Ratio)\n', sharpe_ratio);
fprintf('==================================================\n\n');


disp(sharpe_ratio)
% 判断评价
if sharpe_ratio > 2.0
    disp('评价: 表现非常优秀 (Excellent)');
elseif sharpe_ratio > 1.0
    disp('评价: 表现良好 (Good)');
elseif sharpe_ratio > 0
    disp('评价: 表现一般，存在风险 (Average)');
else
    disp('评价: 表现不佳，不如直接存银行 (Poor)');
end