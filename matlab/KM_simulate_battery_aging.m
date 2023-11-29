% K-Motors adaptation
% Downsampling modified only with NMC
% output plot modified 

clear; clc;
path(path,'Functions')
addpath(genpath('Aging scenarios'))
% Downsampling variable
KM_Dwonsampling = 1;
KM_dt = 24*3600 ; % by day = 24*3600 ; by hours = 3600 ; by min = 60

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 0) Select model and load parameters for battery life (degradation),
%    performance (ocv relationships), and load aging test data
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
validModels = {...
    'NMC|Gr',...
    'LFP|Gr'...
    };

idxModels = listdlg('ListString', validModels,...
    'PromptString', "Specify battery models.",...
    'Name', 'Specify model',...
    'ListSize', [300 300]);
assert(~isempty(idxModels), "Must select a model.")

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 1) Select application profile to simulate
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
applicationProfiles =  dir('Application profiles/*.mat');
driveCycles = dir('Application profiles\*.csv');
applicationProfiles = {applicationProfiles.name, driveCycles.name};
idx = listdlg('ListString', applicationProfiles,...
    'PromptString', "Pick an application profile.",...
    'ListSize', [300 300]);
assert(~isempty(idx), "Must select an application profile.")

% Ask for user options
inputs = {'Ambient temperature in Celsius (-Inf to select a climate):', 'Simulation length in years:'};
dims = [1 50];
defaults = {'20', '5'};
out = inputdlg(inputs, 'Specify simulation options.', dims, defaults);
TdegC = str2double(out{1});
dtdays = 1; 
tYears = str2double(out{2});
if TdegC == -Inf
    load('Climate data\Top100MSA_hourlyClimateData.mat', 'TMY_data_locations','TMY_ambTemp_degC')
    idxClimate = listdlg('ListString', TMY_data_locations',...
        'PromptString', "Specify climate(s) for battery life simulation:",...
        'ListSize', [300 300]);
    TdegC = cell(length(idxClimate), 1);
    for i = 1:length(TdegC)
        TdegC{i} = TMY_ambTemp_degC(:, idxClimate(i));
    end
    climates = TMY_data_locations(idxClimate);
end
% Thermal management
thermalManagement = questdlg('Specify thermal management strategy:',...
    'Thermal management',...
    'None', 'During charge/discharge', 'Always',...
    'None');
switch thermalManagement
    case {'During charge/discharge'; 'Always'}
        out = inputdlg(...
            {'Minimum allowed temperature (C)', 'Maximum allowed temperature (C)'},...
            'Specify temperature limits.', ...
            [1 50],...
            {'10', '40'});
        thermalManagement_MinT = str2double(out{1});
        thermalManagement_MaxT = str2double(out{2});
        assert(thermalManagement_MinT < thermalManagement_MaxT, "Max temperature must be greater than min temperature.")
end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 2) Loop through selected data
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% struct to store outputs:
simulations = struct(); simIdx = 1;
for scenarioIdx = idx
    scenario = applicationProfiles{scenarioIdx};
    fprintf("Application profile: %s\n", scenario)
    disp("Loading application profile...")
    if contains(scenario, '.mat')
        switch scenario
            case 'FCR_1PE_LFP.mat'
                load(['Application profiles/', scenario], 'reference_soc');
                soc = reference_soc./100; clearvars reference_soc
                tsec = [0:1:length(soc)-1]';
                cycle = table(tsec, soc);
                clearvars t tsec soc
                % Downsample the data from 1 second resolution
                cycle = cycle(1:30:height(cycle), :);
            case 'PS_3Cluster_1.mat'
                load(['Application profiles/', scenario], 'reference_soc');
                soc = reference_soc./100; clearvars reference_soc
                tsec = [0:1:length(soc)-1]';
                cycle = table(tsec, soc);
                clearvars t tsec soc
                % Downsample the data from 1 second resolution
                cycle = cycle(1:30:height(cycle), :);
            case 'PVBESS_FeedInDamp.mat'
                load(['Application profiles/', scenario], 'reference_soc');
                soc = reference_soc./100; clearvars reference_soc
                tsec = [0:1:length(soc)-1]';
                cycle = table(tsec, soc);
                clearvars t tsec soc
                % Downsample the data from 1 second resolution
                cycle = cycle(1:30:height(cycle), :);
                % For the BESS system, apply a 5% minimum SOC
                cycle.soc = cycle.soc.*0.95 + 0.05;
        end
    elseif contains(scenario, '.csv')
        % FastSim input profile
        opts = delimitedTextImportOptions("NumVariables", 2);
        % Specify range and delimiter
        opts.DataLines = [2, Inf];
        opts.Delimiter = ",";
        % Specify column names and types
        opts.VariableNames = ["tsec", "soc"];
        opts.VariableTypes = ["double", "double"];
        % Specify file level properties
        opts.ExtraColumnsRule = "ignore";
        opts.EmptyLineRule = "read";
        % Import the data
        cycle = readtable(['Application profiles/', scenario], opts);

        % Downsampling variable
        cycle = cycle(1:KM_Dwonsampling:height(cycle), :);
        % Ensure SOC beginning and end points are identical
        assert(cycle.soc(1) - cycle.soc(end) < 1e-2, "Start and end SOC of application profile must be within 1% for realistic simulation.")
        % Repeat the profile for 1 year
        cycle = repmat(cycle, ceil((3600*24*365)/cycle.tsec(end)), 1);
        cycle.tsec(:) = 0:KM_Dwonsampling:(KM_Dwonsampling*(height(cycle)-1));
        cycle = cycle(cycle.tsec <= 3600*24*365, :);
    else
        error('Application file-type not recognized.')
    end

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %% Extract stress statistics for this scenario
    cycleLengthDays = round(cycle.tsec(end)./(KM_dt));

    for iClimate = 1:length(TdegC)
        % 7 output stressors x number of days
        stressors = zeros(ceil(cycleLengthDays/dtdays), 7);
        % temperature  
        if iscell(TdegC)
            % interpolation by sec from hourly report data on a year
            TdegC_cycle = TdegC{iClimate};
            t_sec_TdegC = [1:8760].*3600;
            cycle.TdegC = makima(t_sec_TdegC, TdegC_cycle, cycle.tsec);
        else
            cycle.TdegC = repmat(TdegC, length(cycle.tsec), 1);
        end
        disp("Processing application data...")
        if height(cycle) > 1e5
            flagwb = 1;
            wb = waitbar(0, "Processing application data..."); pause(1e-9);
            tic;
        else
            flagwb = 0;
        end

        for iDay=1:dtdays:cycleLengthDays
            if flagwb
                secs_elapsed = toc;
                waitbar(iDay/cycleLengthDays, wb, "Calculating daily battery stress...")
            end
            % Break the long supercycle up into a smaller cycle for this timestep
            startDaySubcycle = mod(iDay-1, cycleLengthDays);
            [~, ind_start] = min(abs(cycle.tsec - startDaySubcycle*KM_dt));
            [~, ind_end] = min(abs(cycle.tsec - (startDaySubcycle + dtdays)*KM_dt));
            subcycle = struct();
            subcycle.tsec  = cycle.tsec(ind_start:ind_end) - cycle.tsec(ind_start);
            subcycle.t = subcycle.tsec ./ (KM_dt);
            subcycle.soc   = cycle.soc(ind_start:ind_end);
            subcycle.TdegC   = cycle.TdegC(ind_start:ind_end);
            if length(subcycle.t) == 1
                error('help!')
            end
            % Thermal management
            switch thermalManagement
                case 'During charge/discharge'
                    mask = abs([0; diff(subcycle.soc)]) > 1e-6;
                    mask_lowT = mask & subcycle.TdegC < thermalManagement_MinT;
                    mask_highT = mask & subcycle.TdegC > thermalManagement_MaxT;
                    subcycle.TdegC(mask_lowT) = thermalManagement_MinT;
                    subcycle.TdegC(mask_highT) = thermalManagement_MaxT;
                case 'Always'
                    subcycle.TdegC(subcycle.TdegC < thermalManagement_MinT) = thermalManagement_MinT;
                    subcycle.TdegC(subcycle.TdegC > thermalManagement_MaxT) = thermalManagement_MaxT;
            end
            % Extract stressors for this timestep
            subcycle = struct2table(subcycle);
            subcycle = func_LifeMdl_StressStatistics(subcycle);
            % input stressors into the matrix
            stressors(ceil(iDay/dtdays), :) = [subcycle.dt, subcycle.dEFC, subcycle.TdegK, subcycle.soc, subcycle.Ua, subcycle.dod, subcycle.Crate];
        end
        % Fix last day (dt != dtdays, if cycle length isn't perfect)
        if iDay == cycleLengthDays
            subcycle.dt = dtdays;
        end
        stressors = array2table(stressors, 'VariableNames', {'dt','dEFC','TdegK','soc','Ua','dod','Crate'});
        if flagwb
            % close the wait bar
            close(wb);
        end
            
        % Step through battery types
        for iModel = idxModels
            model = validModels{iModel};
            disp("Running " + model + " battery life simulation...")
            lifeMdl = func_LifeMdl_LoadParameters(model);

            %% Run life simulation
            lifeSim = runLifeSim(lifeMdl, stressors, tYears);
    
            %% 5) Store outputs in struct
            %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            simulations(simIdx).model = model;
            simulations(simIdx).application = scenario;
            if iscell(TdegC)
                simulations(simIdx).climate = climates{iClimate};
            else
                simulations(simIdx).climate = sprintf("%d Celcius", TdegC);
            end
            simulations(simIdx).thermalManagement = thermalManagement;
            switch thermalManagement
                case {'During charge/discharge'; 'Always'}
                    simulations(simIdx).MaxT = thermalManagement_MaxT;
                    simulations(simIdx).MinT = thermalManagement_MinT;
            end
            simulations(simIdx).results = lifeSim;
            simIdx = simIdx + 1;
        end
    end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Export result in Excel File
disp(" ")
disp('Exporting simulation results to file.')
fnameout = "Simulation results\BLAST_result_" + string(datetime("now", "Format", "yyyy-MM-dd-HH-mm-ss")) + ".xls";
warning('off')
for i = 1:length(simulations)
    c = {...
        'Model:', simulations(i).model;...
        'Application:', simulations(i).application;...
        'Climate:', simulations(i).climate;...
        'Thermal Management:', simulations(i).thermalManagement};
    switch thermalManagement
        case {'During charge/discharge', 'Always'}
            c = [c; {'Min Temp.:', simulations(i).MinT;...
                     'Max Temp.:', simulations(i).MaxT}];
    end
    if i == 1
        writecell(c, fnameout, 'Sheet', i)
    else
        writecell(c, fnameout, 'Sheet', i, 'WriteMode', 'append')
    end
    switch simulations(i).model
        case 'NMC|Gr'
            KM_Bat_read = strsplit(simulations(i).application,'_');
            KM_Bat = KM_Bat_read{1};
            columnheaders = {['t_',KM_Bat],['EFC_',KM_Bat],['q_',KM_Bat],...
                ['q_LLI_',KM_Bat],['q_LAM_',KM_Bat],['r_',KM_Bat],['r_LLI_',KM_Bat],['r_LAM_',KM_Bat]};

            writecell(columnheaders, fnameout, 'Sheet', i, 'WriteMode', 'append')
            columnvalues = [...
                simulations(i).results.t';...
                simulations(i).results.EFC';...
                simulations(i).results.q';...
                simulations(i).results.q_LLI';...
                simulations(i).results.q_LAM';...
                simulations(i).results.r';...
                simulations(i).results.r_LLI';...
                simulations(i).results.r_LAM';...
                ]';
            writematrix(columnvalues, fnameout, 'Sheet', i, 'WriteMode', 'append')
        case 'LFP|Gr'
            columnheaders = {'t','EFC','q','qLossCal','qLossCyc','r','rGainCal','rGainCyc'};
            writecell(columnheaders, fnameout, 'Sheet', i, 'WriteMode', 'append')
            columnvalues = [...
                simulations(i).results.t';...
                simulations(i).results.EFC';...
                simulations(i).results.q';...
                simulations(i).results.qLossCal';...
                simulations(i).results.qLossCyc';...
                simulations(i).results.r';...
                simulations(i).results.rGainCal';...
                simulations(i).results.rGainCyc';...
                ]';
            writematrix(columnvalues, fnameout, 'Sheet', i, 'WriteMode', 'append')
    end
end
%% 5) Plot outputs
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
run KM_plot.m

%% Helper functions:
function lifeSim = runLifeSim(lifeMdl, stressors, t_years)
lifeSim.t = [0:stressors.dt(1):(t_years*365)]';
lifeSim.EFC = zeros(size(lifeSim.t));
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 5) Life simulation
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
xx0 = zeros(lifeMdl.n_states, 1);                             % initialize life model states to zero at beginning of life
xx0(3) = 1e-8;
xx  = zeros(lifeMdl.n_states, length(lifeSim.t)); % initialize memory for storing states throughout life
yy = ones(lifeMdl.n_outputs, length(lifeSim.t)); % initialize memory for storing outputs throughout life
% customize initial states/outputs for each model
switch lifeMdl.model
    case 'NMC|Gr'
        yy(5, :) = 1.01; % Initialize LAM for NMC|Gr model
    case 'LFP|Gr'
        yy([2,3,5,6], :) = 0;
end
% wait bar
wb = waitbar(0, sprintf('Running %s simulation', lifeMdl.model)); pause(1e-9);
tic;
% time marching loop
steps_life_sim = length(lifeSim.t)-1;
for j=1:steps_life_sim
    secs_elapsed = toc;
    waitbar(j/steps_life_sim, wb,...
        sprintf('Running simulation (step %d/%d, %d seconds left)', j, steps_life_sim, floor(((secs_elapsed/j)*steps_life_sim)-secs_elapsed))); 
    pause(1e-9);
    
    % Extract stressors for this timestep
    idxRow = mod(j-1, size(stressors, 1)) + 1;
    
    % Cumulatively sum equivalent full cycles
    lifeSim.EFC(j+1) = lifeSim.EFC(j) + stressors.dEFC(idxRow);
    
    % integrate state equations to get updated states, xx
    xx(:,j+1) = func_LifeMdl_UpdateStates(lifeMdl, stressors(idxRow, :), xx0(:, 1));
    
    % calculate output equations to get life model outputs, yy
    yy(:,j+1) = func_LifeMdl_UpdateOutput(lifeMdl, xx(:, j+1));
    
    % store states for next timestep
    xx0(:,1) = xx(:,j+1); 
end
% Store results
switch lifeMdl.model
    case 'NMC|Gr'
        lifeSim.q           = yy(1,:)';
        lifeSim.q_LLI       = yy(2,:)';
        lifeSim.q_LLI_t     = yy(3,:)';
        lifeSim.q_LLI_EFC   = yy(4,:)';
        lifeSim.q_LAM       = yy(5,:)';
        lifeSim.r           = yy(6,:)';
        lifeSim.r_LLI       = yy(7,:)';
        lifeSim.r_LLI_t     = yy(8,:)';
        lifeSim.r_LLI_EFC   = yy(9,:)';
        lifeSim.r_LAM       = yy(10,:)';
    case 'LFP|Gr'
        lifeSim.q           = yy(1,:)';
        lifeSim.qLossCal    = yy(2,:)';
        lifeSim.qLossCyc    = yy(3,:)';
        lifeSim.r           = yy(4,:)';
        lifeSim.rGainCal    = yy(5,:)';
        lifeSim.rGainCyc    = yy(6,:)';
end
% close the wait bar
close(wb);
end