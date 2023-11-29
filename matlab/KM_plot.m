%% 5) Plot outputs
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
figure; tl = tiledlayout(2,1);
title('Comparaison KBat/RefBat')
nexttile; box on; hold on;

for i = 1:length(simulations)
    KM_Bat_read = strsplit(simulations(i).application,'_');
    KM_Bat = KM_Bat_read{1};

    plot(simulations(i).results.t./365, simulations(i).results.q, 'LineWidth', 1.5)
    
    legendInfo{i} = ['Overall_',KM_Bat]; % Create legend

end
xlabel('Time (years)'); ylabel('Relative  discharge capacity');  axis([0 tYears 0.7 1.02])
legend(legendInfo, 'Location', 'southwest')

nexttile; box on; hold on;
for i = 1:length(simulations)
    KM_Bat_read = strsplit(simulations(i).application,'_');
    KM_Bat = KM_Bat_read{1};

    plot(simulations(i).results.t./365, simulations(i).results.r, 'LineWidth', 1.5)

end
xlabel('Time (years)'); ylabel('Relative DC resistance');  axis([0 tYears 0.98 4])
legend(legendInfo, 'Location', 'northwest')