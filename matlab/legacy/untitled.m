%===================时间序列ARIMA模型优化代码===================%
clc; clear; close all;

% 1. 加载数据
load matlab.mat
data = btc.Value; % 确保这是列向量
% 如果数据过大，为了演示速度，可以先截取一部分
% data = data(1:200); 

size_data = size(data, 1);
start_predict_idx = 20; % 从第20个点开始向后滚动预测

%==================第一步：全局确定最佳 p, d, q (只运行一次)==================%
disp('正在进行平稳性检验和模型定阶...');

% A. 确定差分阶数 d
d = 0;
temp_data = data;
% 使用 log 形式通常对价格预测更稳健，这里暂时保持原样
while (kpsstest(temp_data) == 1) && (d < 2) % 限制最大差分次数防止过差分
    temp_data = diff(temp_data);
    d = d + 1;
end
fprintf('自动确定的差分阶数 d = %d\n', d);

% B. 确定最佳 p 和 q (基于前 start_predict_idx 个数据或全部数据)
% 为了速度，这里使用 AIC 准则遍历
max_ar = 3; max_ma = 3;
minAIC = inf;
best_p = 0; best_q = 0;

% 使用预处理的数据子集来定阶，节省时间
train_data_for_selection = data(1:min(100, size_data)); 

for p = 0:max_ar
    for q = 0:max_ma
        try
            % 创建模型，注意这里传入 d
            Mdl = arima(p, d, q); 
            % 'display','off' 关闭输出
            [~, ~, logL] = estimate(Mdl, train_data_for_selection, 'Display', 'off'); 
            aic = -2 * logL + 2 * (p + q + 1);
            if aic < minAIC
                minAIC = aic;
                best_p = p;
                best_q = q;
            end
        catch
            continue;
        end
    end
end
fprintf('最佳模型结构: ARIMA(%d, %d, %d)\n', best_p, d, best_q);

%==================第二步：滚动预测 (Rolling Forecast)==================%
disp('开始滚动预测...');

% 预分配内存，极大提升速度
predictMat = zeros(size_data, 1);
% 前面的数据直接用真实值填充（因为没有预测值）
predictMat(1:start_predict_idx-1) = data(1:start_predict_idx-1);

% 创建模型模板
Mdl_Template = arima(best_p, d, best_q);

% 进度条
hWait = waitbar(0, '正在滚动预测...');

for i = start_predict_idx : size_data
    % 更新进度条
    if mod(i, 10) == 0
        waitbar(i/size_data, hWait);
    end
    
    % 获取当前的训练窗口数据
    current_history = data(1:i-1);
    
    try
        % 策略 A (最准但慢): 每次都重新估计参数
        % EstMdl = estimate(Mdl_Template, current_history, 'Display', 'off');
        
        % 策略 B (极速平衡): 
        % 如果数据点很多，不需要每一步都estimate。
        % 这里为了演示正确性，我们使用 try-catch 保证运行
        
        % 为了比你的代码快，我们只在特定步数或者利用 estimate 的 'Y0' 
        % 但标准的滚动预测必须 estimate。
        % 下面这一行是耗时大户，但比你的代码快16倍（因为不用选p,q了）
        [EstMdl, ~] = estimate(Mdl_Template, current_history, 'Display', 'off');
        
        % 进行一步预测
        % forecast 会自动处理差分还原
        [fcast, ~] = forecast(EstMdl, 1, 'Y0', current_history);
        
        predictMat(i) = fcast;
        
    catch
        % 如果估计失败，沿用上一个值或使用简单的均值
        predictMat(i) = data(i-1);
    end
end
close(hWait);

%================================可视化================================%
figure(1);
plot(1:size_data, data, 'b-', 'LineWidth', 1.5); hold on;
plot(start_predict_idx:size_data, predictMat(start_predict_idx:end), 'r--', 'LineWidth', 1.5);
legend('真实值 (Real)', '滚动预测值 (One-step Forecast)');
title(['ARIMA(', num2str(best_p), ',', num2str(d), ',', num2str(best_q), ') 滚动预测结果']);
grid on;

% 计算误差指标
rmse = sqrt(mean((data(start_predict_idx:end) - predictMat(start_predict_idx:end)).^2));
fprintf('RMSE: %.4f\n', rmse);