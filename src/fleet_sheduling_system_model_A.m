%% Model A: Baseline Discrete-Event Simulation
% 5-node validation model
% - No demand weighting
% - No crew constraints
% - No operating window
% - Random feasible dispatch only
% - Event-driven baseline used to validate simulation mechanics

clear; clc; close all;
set(0,'DefaultFigureWindowStyle','normal');

%% -------------------------------------------------------------------------
% Configuration
%% -------------------------------------------------------------------------

cfg.seed                        = 1;
rng(cfg.seed);

cfg.simDays                     = 7;
cfg.startTime                   = datetime(2026,3,3,0,0,0);
cfg.endTime                     = cfg.startTime + days(cfg.simDays);

cfg.nAircraft                   = 120;
cfg.cruiseKmh                   = 250;
cfg.fixedOverheadMin            = 10;
cfg.turnaroundMin               = 25;
cfg.maxFlightsPerAircraftPerDay = 8;
cfg.maxRangeKm                  = 600;
cfg.maxLegTimeMin               = 180;

cfg.focusAircraftID             = 1;
cfg.focusDay                    = 2;   % 1..7

cfg.exportFolder                = pwd;
cfg.exportFigures               = true;

cfg.figure1Number               = 1;
cfg.figure1Name                 = 'Aircraft_Movement_Sequence';

cfg.figure2Number               = 2;
cfg.figure2Name                 = 'Node_Movement_Totals';

%% -------------------------------------------------------------------------
% Network Definition
%% -------------------------------------------------------------------------

nodes = table( ...
    ["GLA_01"; "BHM_01"; "MAN_01"; "LON_01"; "EDI_01"], ...
    ["Glasgow"; "Birmingham"; "Manchester"; "London"; "Edinburgh"], ...
    [55.8642; 52.4862; 53.4808; 51.5074; 55.9533], ...
    [-4.2518; -1.8904; -2.2426; -0.1278; -3.1883], ...
    'VariableNames', {'node_id','node_name','lat','lon'});

nNodes = height(nodes);

routes = generateRoutes(nodes, cfg);

if isempty(routes)
    error('No feasible routes generated. Check route constraints.');
end

adjacency = buildAdjacency(routes, nNodes);

hubIdx = find(nodes.node_id == "GLA_01", 1);
if isempty(hubIdx)
    error('Hub node not found.');
end

fprintf('\n================ MODEL A: NETWORK SUMMARY ================\n');
fprintf('Nodes                              : %d\n', nNodes);
fprintf('Feasible directed routes           : %d\n', height(routes));
fprintf('Aircraft                           : %d\n', cfg.nAircraft);
fprintf('Simulation horizon                 : %d days\n', cfg.simDays);
fprintf('==========================================================\n\n');

%% -------------------------------------------------------------------------
% Initialise Aircraft State
%% -------------------------------------------------------------------------

aircraftNode         = repmat(hubIdx, cfg.nAircraft, 1);
aircraftNextAvail    = repmat(cfg.startTime, cfg.nAircraft, 1);
aircraftFlightsToday = zeros(cfg.nAircraft, 1);
aircraftDayIndex     = ones(cfg.nAircraft, 1);

%% -------------------------------------------------------------------------
% Pre-allocate Flight Log
%% -------------------------------------------------------------------------

maxLog = cfg.nAircraft * cfg.maxFlightsPerAircraftPerDay * cfg.simDays + 1000;

logFlightID   = zeros(maxLog, 1);
logAircraftID = zeros(maxLog, 1);
logOriginIdx  = zeros(maxLog, 1);
logDestIdx    = zeros(maxLog, 1);
logDepTime    = NaT(maxLog, 1);
logArrTime    = NaT(maxLog, 1);
logFlightMin  = zeros(maxLog, 1);

logCount = 0;

%% -------------------------------------------------------------------------
% Discrete-Event Simulation Loop
%% -------------------------------------------------------------------------

while true
    [tNow, a] = min(aircraftNextAvail);

    if tNow >= cfg.endTime
        break;
    end

    dayNum = floor(days(tNow - cfg.startTime)) + 1;
    if dayNum ~= aircraftDayIndex(a)
        aircraftDayIndex(a)     = dayNum;
        aircraftFlightsToday(a) = 0;
    end

    if aircraftFlightsToday(a) >= cfg.maxFlightsPerAircraftPerDay
        aircraftNextAvail(a) = dateshift(tNow, 'start', 'day') + days(1);
        continue;
    end

    feasibleRows = adjacency{aircraftNode(a)};

    if isempty(feasibleRows)
        aircraftNextAvail(a) = tNow + minutes(60);
        continue;
    end

    chosenPos = randi(numel(feasibleRows));
    r         = feasibleRows(chosenPos);
    route     = routes(r,:);

    dep = tNow;
    arr = dep + minutes(route.flight_time_min);
    nxt = arr + minutes(cfg.turnaroundMin);

    logCount = logCount + 1;
    if logCount > maxLog
        error('Flight log exceeded preallocated size. Increase maxLog.');
    end

    logFlightID(logCount)   = logCount;
    logAircraftID(logCount) = a;
    logOriginIdx(logCount)  = route.orig_idx;
    logDestIdx(logCount)    = route.dest_idx;
    logDepTime(logCount)    = dep;
    logArrTime(logCount)    = arr;
    logFlightMin(logCount)  = route.flight_time_min;

    aircraftNode(a)         = route.dest_idx;
    aircraftNextAvail(a)    = nxt;
    aircraftFlightsToday(a) = aircraftFlightsToday(a) + 1;
end

sched = table( ...
    logFlightID(1:logCount), ...
    logAircraftID(1:logCount), ...
    logOriginIdx(1:logCount), ...
    logDestIdx(1:logCount), ...
    logDepTime(1:logCount), ...
    logArrTime(1:logCount), ...
    logFlightMin(1:logCount), ...
    'VariableNames', {'flight_id','aircraft_id','origin_idx','dest_idx','dep_time','arr_time','flight_time_min'});

%% -------------------------------------------------------------------------
% Performance Metrics
%% -------------------------------------------------------------------------

flightsPerAircraft = accumarray(sched.aircraft_id, 1, [cfg.nAircraft 1], @sum, 0);
blockHoursPerAC    = accumarray(sched.aircraft_id, sched.flight_time_min / 60, [cfg.nAircraft 1], @sum, 0);

totalFlights  = height(sched);
avgFlights    = mean(flightsPerAircraft);
maxFlights    = max(flightsPerAircraft);
avgBlockHours = mean(blockHoursPerAC);
maxBlockHours = max(blockHoursPerAC);
avgUtilPct    = 100 * avgBlockHours / (cfg.simDays * 24);

fprintf('================ MODEL A: RESULTS =======================\n');
fprintf('Total flights completed            : %d\n', totalFlights);
fprintf('Average flights per aircraft       : %.2f\n', avgFlights);
fprintf('Maximum flights by one aircraft    : %d\n', maxFlights);
fprintf('Average block hours per aircraft   : %.2f hr\n', avgBlockHours);
fprintf('Maximum block hours per aircraft   : %.2f hr\n', maxBlockHours);
fprintf('Average fleet utilisation          : %.2f %%\n', avgUtilPct);
fprintf('=========================================================\n\n');

%% -------------------------------------------------------------------------
% Figure 1: 24-hour Aircraft Movement Sequence
%% -------------------------------------------------------------------------

focusStart = cfg.startTime + days(cfg.focusDay - 1);
focusEnd   = focusStart + hours(24);

S = sched( ...
    sched.aircraft_id == cfg.focusAircraftID & ...
    sched.arr_time > focusStart & ...
    sched.dep_time < focusEnd, :);

S = sortrows(S, 'dep_time');

fig1 = newFigure('Figure_1', [2 2 18 10.5]);
ax1  = axes(fig1);
styleAxes(ax1);
hold(ax1, 'on');

xlabel(ax1, ['Time of day (' datestr(focusStart, 'dd-mmm-yyyy') ')'], ...
    'FontName', 'Times New Roman', 'FontSize', 12);
ylabel(ax1, 'Network node', ...
    'FontName', 'Times New Roman', 'FontSize', 12);

if isempty(S)
    text(ax1, 0.5, 0.5, 'No flights recorded for the selected aircraft in this 24-hour window.', ...
        'Units', 'normalized', ...
        'HorizontalAlignment', 'center', ...
        'FontName', 'Times New Roman', ...
        'FontSize', 11);
    axis(ax1, 'off');
else
    ws = datenum(focusStart);
    we = datenum(focusEnd);

    X = [];
    Y = [];

    for i = 1:height(S)
        depT = datenum(S.dep_time(i));
        arrT = datenum(S.arr_time(i));
        yO   = S.origin_idx(i);
        yD   = S.dest_idx(i);

        X = [X; depT; arrT]; %#ok<AGROW>
        Y = [Y; yO; yD];     %#ok<AGROW>

        if i < height(S)
            nextDep = datenum(S.dep_time(i + 1));
            X = [X; nextDep]; %#ok<AGROW>
            Y = [Y; yD];      %#ok<AGROW>
        end
    end

    plot(ax1, X, Y, '-', ...
        'LineWidth', 1.8, ...
        'Color', [0.05 0.35 0.75]);

    scatter(ax1, datenum(S.dep_time), S.origin_idx, 55, 'filled', ...
        'MarkerFaceColor', [0.20 0.70 0.20], ...
        'MarkerEdgeColor', 'k', ...
        'LineWidth', 0.6);

    scatter(ax1, datenum(S.arr_time), S.dest_idx, 55, 'filled', ...
        'MarkerFaceColor', [0.90 0.40 0.10], ...
        'MarkerEdgeColor', 'k', ...
        'LineWidth', 0.6);

    legend(ax1, {'Aircraft path','Departures','Arrivals'}, ...
        'Location', 'eastoutside', ...
        'Box', 'off', ...
        'FontName', 'Times New Roman', ...
        'FontSize', 10);

    xlim(ax1, [ws we]);
    ylim(ax1, [0.5 nNodes + 0.5]);

    yticks(ax1, 1:nNodes);
    yticklabels(ax1, string(nodes.node_name));

    tickTimes = linspace(ws, we, 7);
    set(ax1, 'XTick', tickTimes);
    datetick(ax1, 'x', 'HH:MM', 'keepticks', 'keeplimits');
end

hold(ax1, 'off');

saveFigure(fig1, cfg.figure1Number, cfg.figure1Name, cfg.exportFolder, cfg.exportFigures);

%% -------------------------------------------------------------------------
% Figure 2: Node Movement Totals
%% -------------------------------------------------------------------------

nodeMovements = zeros(nNodes, 1);

for i = 1:height(sched)
    nodeMovements(sched.origin_idx(i)) = nodeMovements(sched.origin_idx(i)) + 1;
    nodeMovements(sched.dest_idx(i))   = nodeMovements(sched.dest_idx(i)) + 1;
end

fig2 = newFigure('Figure_2', [2 2 16 10.5]);
ax2  = axes(fig2);
styleAxes(ax2);
hold(ax2, 'on');

bar(ax2, nodeMovements, ...
    'FaceColor', [0.20 0.45 0.75], ...
    'EdgeColor', 'k', ...
    'LineWidth', 0.6);

xticks(ax2, 1:nNodes);
xticklabels(ax2, string(nodes.node_name));

xlabel(ax2, 'Node', 'FontName', 'Times New Roman', 'FontSize', 12);
ylabel(ax2, 'Total movements', 'FontName', 'Times New Roman', 'FontSize', 12);

hold(ax2, 'off');

saveFigure(fig2, cfg.figure2Number, cfg.figure2Name, cfg.exportFolder, cfg.exportFigures);

%% -------------------------------------------------------------------------
% Local Functions
%% -------------------------------------------------------------------------

function routes = generateRoutes(nodes, cfg)
    n = height(nodes);

    orig_idx = [];
    dest_idx = [];
    flight_time_min = [];

    for i = 1:n
        for j = 1:n
            if i == j
                continue;
            end

            d = haversineKm(nodes.lat(i), nodes.lon(i), nodes.lat(j), nodes.lon(j));
            t = cfg.fixedOverheadMin + (d / cfg.cruiseKmh) * 60;

            if d <= cfg.maxRangeKm && t <= cfg.maxLegTimeMin
                orig_idx(end+1,1) = i; %#ok<AGROW>
                dest_idx(end+1,1) = j; %#ok<AGROW>
                flight_time_min(end+1,1) = t; %#ok<AGROW>
            end
        end
    end

    routes = table(orig_idx, dest_idx, flight_time_min, ...
        'VariableNames', {'orig_idx','dest_idx','flight_time_min'});
end

function adjacency = buildAdjacency(routes, nNodes)
    adjacency = cell(nNodes, 1);
    for i = 1:nNodes
        adjacency{i} = find(routes.orig_idx == i);
    end
end

function d = haversineKm(lat1, lon1, lat2, lon2)
    R  = 6371;
    dp = deg2rad(lat2 - lat1);
    dl = deg2rad(lon2 - lon1);
    a  = sin(dp/2)^2 + cos(deg2rad(lat1)) * cos(deg2rad(lat2)) * sin(dl/2)^2;
    d  = 2 * R * atan2(sqrt(a), sqrt(1 - a));
end

function fig = newFigure(name, pos)
    fig = figure( ...
        'Color', 'w', ...
        'Name', name, ...
        'Units', 'centimeters', ...
        'Position', pos, ...
        'Toolbar', 'none', ...
        'MenuBar', 'none');
end

function styleAxes(ax)
    ax.Color     = 'w';
    ax.FontName  = 'Times New Roman';
    ax.FontSize  = 11;
    ax.LineWidth = 1.0;
    grid(ax, 'on');
    box(ax, 'on');
end

function saveFigure(fig, num, name, folder, doExport)
    if ~doExport
        return;
    end

    if ~exist(folder, 'dir')
        mkdir(folder);
    end

    cleanName = regexprep(char(name), '[^\w\s-]', '');
    cleanName = strtrim(cleanName);
    cleanName = regexprep(cleanName, '\s+', '_');

    fileName = sprintf('Figure_%d_%s.png', num, cleanName);
    fullPath = fullfile(folder, fileName);

    exportgraphics(fig, fullPath, ...
        'Resolution', 300, ...
        'BackgroundColor', 'white');

    fprintf('Exported: %s\nSaved to: %s\n', fileName, fullPath);
end


