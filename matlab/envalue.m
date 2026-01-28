%% 修正后的代码
% 保持原始数据，用正确的索引
test_data = data(start_idx:end);           % 测试期真实价格
test_pred = predictMat(start_idx:end);     % 对应的预测值
prev_data = data(start_idx-1:end-1);       % 前一天的真实价格（用于计算预测涨幅）

size_test = length(test_data);
money = zeros(size_test, 1);
money(1) = 1000;

threshold = 0.05;
cost = 0.01;  % 手续费建议用更合理的值
have = 0;

% 计算预测的涨跌幅：(预测今天 - 昨天实际) / 昨天实际
rexp = (test_pred - prev_data) ./ prev_data;
buy_signal = (rexp > threshold);
sell_signal = (rexp < -threshold);

for i = 2:size_test
    money(i) = money(i-1);
    
    % 【关键修正】使用 i 天的收益（信号在 i-1 天收盘产生，i 天开盘执行）
    % 但我们用的是收盘价数据，所以需要滞后一天
    current_return = test_data(i) / test_data(i-1);
    
    % 信号 buy_signal(i-1) 是基于 i-1 天的预测，在 i 天开盘执行
    % 这里假设开盘价≈前一天收盘价（如果有开盘价数据会更准确）
    if buy_signal(i-1) && have == 0
        money(i) = money(i) * (1 - cost);
        have = 1;
        % 买入后当天的收益需要用 test_data(i)/test_data(i-1)
        % 但更准确的做法是用 收盘/开盘
        money(i) = money(i) * current_return;
        
    elseif sell_signal(i-1) && have == 1
        money(i) = money(i) * (1 - cost);
        have = 0;
        
    elseif have == 1
        money(i) = money(i) * current_return;
    end
end

hold on
plot(1:size_test,money,"-r")
xlabel("Day")
ylabel("Money")
hold off