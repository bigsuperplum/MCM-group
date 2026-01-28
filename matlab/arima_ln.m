%=================== 高性能优化版 ARIMA (对数差分版) ===================%
clc; clear; close all;

%% 1. 数据准备
disp('1. 正在加载与预处理数据...');
load rawdata.mat
% 原始价格数据
raw_prices = gold_delnan.Value; 
% raw_prices = raw_prices(1:500); % 演示用

% [核心修改 1] 计算对数收益率 (Log Returns)
% 公式: r_t = ln(P_t) - ln(P_{t-1})
% 注意: diff 后数据长度会少 1
log_returns = diff(log(raw_prices)); 

% 之后的模型将全部基于 log_returns 进行
data_model = log_returns; 
size_data = size(data_model, 1);

% 设定从哪里开始预测
start_idx = 100; 

%% 2. 模型定阶 (Grid Search) - 基于收益率数据
disp('2. 正在进行平稳性检验与模型定阶 (Grid Search)...');

% --- A. 自动确定差分阶数 d ---
% 通常对数收益率已经是平稳的，d 很大几率是 0
d = 0;
temp_data = data_model(1:start_idx);
while (kpsstest(temp_data) == 1) && (d < 2)
    temp_data = diff(temp_data);
    d = d + 1;
end
fprintf('   -> 自动判定差分阶数 d = %d (通常为0)\n', d);

% --- B. 自动确定最佳 p 和 q ---
train_data = data_model(1:start_idx);
max_ar = 5; % 对收益率来说，阶数通常不需要太高，设为5能加快速度
max_ma = 5;
minAIC = inf;
best_p = 0; best_q = 0;

for p = 0:max_ar
    for q = 0:max_ma
        try
            Mdl = arima(p, d, q);
            [~, ~, logL] = estimate(Mdl, train_data, 'Display', 'off');
            aic = -2 * logL + 2 * (p + q + 1);
            if aic < minAIC
                minAIC = aic;
                best_p = p; best_q = q;
            end
        catch
            continue;
        end
    end
end
fprintf('   -> 最佳模型结构: ARIMA(%d, %d, %d)\n', best_p, d, best_q);

%% 3. 极速滚动预测 (Rolling Forecast)
disp('3. 开始滚动预测...');

% 存储预测的"收益率"
pred_returns = zeros(size_data, 1);
pred_returns(1:start_idx-1) = data_model(1:start_idx-1);

% 存储还原后的"预测价格" (长度需与原始价格一致)
pred_prices = zeros(length(raw_prices), 1);
% 初始部分无法预测，直接填入真实值
pred_prices(1:start_idx) = raw_prices(1:start_idx);

Update_Freq = 10; % 更新频率
Mdl_Template = arima(best_p, d, best_q);

try
    EstMdl = estimate(Mdl_Template, data_model(1:start_idx-1), 'Display', 'off');
catch
    EstMdl = arima(best_p, d, best_q); 
end

hWait = waitbar(0, '正在高速预测中...');
tic;

% 注意：data_model 的索引 i 对应 raw_prices 的 i+1 (因为差分少了一位)
for i = start_idx : size_data
    
    if mod(i, 50) == 0
        waitbar((i-start_idx)/(size_data-start_idx), hWait, ...
            sprintf('进度: %.1f%%', (i-start_idx)/(size_data-start_idx)*100));
    end
    
    % 历史收益率数据
    history_ret = data_model(1:i-1);
    
    % 稀疏更新参数
    if mod(i, Update_Freq) == 0
        try
            EstMdl = estimate(Mdl_Template, history_ret, 'Display', 'off');
        catch
        end
    end
    
    % [预测收益率]
    [fcast_ret, ~] = forecast(EstMdl, 1, 'Y0', history_ret);
    pred_returns(i) = fcast_ret;
    
    % [核心修改 2] 价格还原 (Inverse Transform)
    % 预测的价格(t) = 真实价格(t-1) * exp(预测收益率(t))
    % data_model 的第 i 个点，对应 raw_prices 的第 i+1 个时刻
    % 所以我们要预测 raw_prices(i+1)
    
    last_real_price = raw_prices(i); % 这里是 i，因为 diff 导致错位
    pred_prices(i+1) = last_real_price * exp(fcast_ret);
end
t_cost = toc;
close(hWait);

fprintf('   -> 预测完成，耗时: %.2f 秒\n', t_cost);

%% 4. 可视化与评估 (对比价格)
% 对齐数据用于绘图
% 预测是从 start_idx 对应的收益率开始的，对应价格是 start_idx + 1
plot_start_idx = start_idx + 1;
real_y = raw_prices(plot_start_idx:end);
pred_y = pred_prices(plot_start_idx:end);

figure('Color', 'w');
subplot(2,1,1);
plot(plot_start_idx:length(raw_prices), real_y, 'b-', 'LineWidth', 1.2); hold on;
plot(plot_start_idx:length(raw_prices), pred_y, 'r--', 'LineWidth', 1.5);
xlim([plot_start_idx, length(raw_prices)]);
title(sprintf('基于对数差分的 ARIMA 价格预测 (Update Freq: %d)', Update_Freq));
legend('真实价格', '预测价格');
grid on; ylabel('价格');

subplot(2,1,2);
% 这里画预测的收益率 vs 真实收益率，看波动捕捉情况
plot(start_idx:size_data, data_model(start_idx:end), 'Color', [0.5 0.5 0.5]); hold on;
plot(start_idx:size_data, pred_returns(start_idx:end), 'r', 'LineWidth', 1);
title('收益率预测对比 (Volatility Clustering)');
legend('真实收益率', '预测收益率');
xlim([start_idx, size_data]);
grid on; ylabel('Log Return');

% 计算 RMSE (基于价格)
rmse_price = sqrt(mean((real_y - pred_y).^2));
fprintf('   -> 价格均方根误差 (RMSE): %.4f\n', rmse_price);

% 计算方向预测准确率 (作为金融指标参考)
real_dir = sign(data_model(start_idx:end));
pred_dir = sign(pred_returns(start_idx:end));
acc = sum(real_dir == pred_dir) / length(real_dir) * 100;
fprintf('   -> 涨跌方向预测准确率: %.2f%%\n', acc);

%%
data = raw_prices
predictMat = [data(1:start_idx);pred_y]