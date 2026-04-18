%% Model B: Demand-Driven Network Expansion
% Demand-driven fleet simulation within an expanded synthetic UAM network
% 100-node UK-like network, 1500 aircraft, 7-day simulation horizon
%
% Purpose of Model B:
% - Introduce demand-driven routing beyond the random baseline of Model A
% - Establish the unconstrained upper bound of fleet performance
% - Show emergent route concentration and hub-like node activity
%
% Model B deliberately excludes:
% - pilot / crew entities
% - duty limits
% - departure caps
% - passenger served / spill accounting
% - repositioning logic

clear; clc; close all;
set(0,'DefaultFigureWindowStyle','normal');

%% ------------------------------------------------------------------------
% Configuration
%% ------------------------------------------------------------------------

cfg.seed                    = 7;
rng(cfg.seed);

cfg.numNodes                = 100;
cfg.numAircraft             = 1500;
cfg.targetRoutes            = 3000;

cfg.simDays                 = 7;
cfg.dayStartHr              = 6;
cfg.dayEndHr                = 22;      % departures must satisfy start <= dep < end

cfg.turnaroundMin           = 12;
cfg.cruiseKmh               = 150;
cfg.taxiMin                 = 2;
cfg.blockPadMin             = 3;

cfg.choiceMode              = "weighted";   % "weighted" or "softmax"
cfg.softmaxTau              = 0.7;
cfg.demandPower             = 1.15;

cfg.minLegKm                = 20;
cfg.maxLegKm                = 300;

cfg.initialHubNode          = 1;
cfg.staggerInitialDepartures = false;  % optional; set true to reduce the hour-6 burst
cfg.initialDepartureSpreadMin = 30;

cfg.topRouteCount           = 15;
cfg.topLabelCount           = 5;

cfg.saveNetworkForModelC    = true;
cfg.networkFileName         = 'ModelB_Shared_Network.mat';

% Export settings
thisFile = mfilename('fullpath');
if isempty(thisFile)
    cfg.exportFolder = pwd;
else
    cfg.exportFolder = fileparts(thisFile);
end

cfg.exportFigures           = true;

cfg.figure2Number           = 2;
cfg.figure2Name             = 'ModelB_Route_Utilisation_Ranking';

cfg.figure3Number           = 3;
cfg.figure3Name             = 'ModelB_Spatial_Distribution_of_Node_Traffic_Intensity';

cfg.figure4Number           = 4;
cfg.figure4Name             = 'ModelB_Flights_Per_Aircraft_Distribution';

cfg.figure5Number           = 5;
cfg.figure5Name             = 'ModelB_Hourly_Flight_Activity';

%% ------------------------------------------------------------------------
% Time Settings
%% ------------------------------------------------------------------------

tEnd       = cfg.simDays * 24 * 60;
opStart    = cfg.dayStartHr * 60;
opEnd      = cfg.dayEndHr   * 60;
totalOpMin = cfg.simDays * (cfg.dayEndHr - cfg.dayStartHr) * 60;

%% ------------------------------------------------------------------------
% Network Generation
%% ------------------------------------------------------------------------

nodes = table;
nodes.NodeID = (1:cfg.numNodes)';
nodes.NodeName = "N" + string(nodes.NodeID);

% UK-like coordinate envelope
nodes.Lat = 50.0 + 8.5 * rand(cfg.numNodes,1);
nodes.Lon = -6.5 + 5.5 * rand(cfg.numNodes,1);

% Seed major hubs with representative UK cities
majorHubIdx = [1 2 3 4 5];
nodes.Lat(majorHubIdx) = [55.8642; 55.9533; 53.4808; 52.4862; 54.5973];
nodes.Lon(majorHubIdx) = [-4.2518; -3.1883; -2.2426; -1.8904; -5.9301];

%% ------------------------------------------------------------------------
% Feasible Route Set
%% ------------------------------------------------------------------------

originList = zeros(cfg.numNodes * (cfg.numNodes - 1), 1);
destList   = zeros(cfg.numNodes * (cfg.numNodes - 1), 1);
distList   = zeros(cfg.numNodes * (cfg.numNodes - 1), 1);

k = 0;
for i = 1:cfg.numNodes
    for j = 1:cfg.numNodes
        if i == j
            continue;
        end

        dkm = haversineKm(nodes.Lat(i), nodes.Lon(i), nodes.Lat(j), nodes.Lon(j));

        if dkm >= cfg.minLegKm && dkm <= cfg.maxLegKm
            k = k + 1;
            originList(k) = i;
            destList(k)   = j;
            distList(k)   = dkm;
        end
    end
end

originList = originList(1:k);
destList   = destList(1:k);
distList   = distList(1:k);

if isempty(originList)
    error('No feasible routes generated. Adjust minimum or maximum leg distance.');
end

numCandidates = numel(originList);
actualRoutes  = min(cfg.targetRoutes, numCandidates);

if actualRoutes < cfg.targetRoutes
    warning('Requested %d routes, but only %d feasible routes exist. Using %d.', ...
        cfg.targetRoutes, numCandidates, actualRoutes);
end

pick = randperm(numCandidates, actualRoutes);

routes = table;
routes.RouteID      = (1:actualRoutes)';
routes.OriginIdx    = originList(pick);
routes.DestIdx      = destList(pick);
routes.Distance_km  = distList(pick);
routes.OriginID     = nodes.NodeID(routes.OriginIdx);
routes.DestID       = nodes.NodeID(routes.DestIdx);

% Flight / block time stored directly in route table
routes.FlightMin    = (routes.Distance_km ./ cfg.cruiseKmh) * 60;
routes.BlockMin     = cfg.taxiMin + cfg.blockPadMin + routes.FlightMin;

%% ------------------------------------------------------------------------
% Demand Representation
%% ------------------------------------------------------------------------
% This demand structure is deliberately simple but should match the same
% underlying logic used in Model C for clean comparison.

hubWeight = ones(height(routes),1);

for r = 1:height(routes)
    if any(routes.OriginIdx(r) == majorHubIdx)
        hubWeight(r) = hubWeight(r) * 1.7;
    end
    if any(routes.DestIdx(r) == majorHubIdx)
        hubWeight(r) = hubWeight(r) * 1.7;
    end
end

distanceEffect = 220 ./ routes.Distance_km;
stochasticTerm = 0.7 + 0.8 * rand(height(routes),1);

rawScore = hubWeight .* distanceEffect .* stochasticTerm;
routes.DemandScore = max(0.1, rawScore) .^ cfg.demandPower;

%% ------------------------------------------------------------------------
% Save Shared Topology for Model C
%% ------------------------------------------------------------------------

if cfg.saveNetworkForModelC
    networkPath = fullfile(cfg.exportFolder, cfg.networkFileName);
    save(networkPath, 'nodes', 'routes', 'majorHubIdx', 'cfg');
    fprintf('Shared network saved for Model C:\n%s\n\n', networkPath);
end

%% ------------------------------------------------------------------------
% Outgoing Route Index
%% ------------------------------------------------------------------------

outgoing = cell(cfg.numNodes,1);
for r = 1:height(routes)
    o = routes.OriginIdx(r);
    outgoing{o} = [outgoing{o}; r]; 
end

%% ------------------------------------------------------------------------
% Aircraft Initialisation
%% ------------------------------------------------------------------------

aircraftLocIdx = ones(cfg.numAircraft,1) * cfg.initialHubNode;

if cfg.staggerInitialDepartures
    aircraftNextMin = rand(cfg.numAircraft,1) * cfg.initialDepartureSpreadMin;
else
    aircraftNextMin = zeros(cfg.numAircraft,1);
end

%% ------------------------------------------------------------------------
% Log Storage
%% ------------------------------------------------------------------------

estimatedFlightsPerAircraft = 100;
cap = cfg.numAircraft * estimatedFlightsPerAircraft;

logAircraft = zeros(cap,1);
logOIdx     = zeros(cap,1);
logDIdx     = zeros(cap,1);
logDep      = zeros(cap,1);
logArr      = zeros(cap,1);
logDist     = zeros(cap,1);
logBlock    = zeros(cap,1);
logRouteID  = zeros(cap,1);

logCount = 0;

%% ------------------------------------------------------------------------
% Demand-Driven Simulation
%% ------------------------------------------------------------------------

while true
    [tNow, a] = min(aircraftNextMin);

    if tNow >= tEnd
        break;
    end

    tNow = pushToOperatingWindow(tNow, opStart, opEnd);
    if tNow >= tEnd
        break;
    end

    oIdx = aircraftLocIdx(a);
    candidateRows = outgoing{oIdx};

    if isempty(candidateRows)
        aircraftNextMin(a) = tNow + 30;
        continue;
    end

    chosenRow = chooseRouteRow(routes, candidateRows, cfg);

    dIdx     = routes.DestIdx(chosenRow);
    dist     = routes.Distance_km(chosenRow);
    blockMin = routes.BlockMin(chosenRow);
    dep      = tNow;

    % Enforce departure window strictly: start <= dep < end
    if minutesOfDay(dep) + blockMin > opEnd || minutesOfDay(dep) >= opEnd
        dep = nextDayStart(dep, opStart);
        if dep >= tEnd
            aircraftNextMin(a) = dep;
            break;
        end
    end

    arr = dep + blockMin;

    aircraftLocIdx(a)  = dIdx;
    aircraftNextMin(a) = arr + cfg.turnaroundMin;

    logCount = logCount + 1;

    if logCount > numel(logAircraft)
        growBy = max(round(cap * 0.40), 50000);

        logAircraft = [logAircraft; zeros(growBy,1)]; %#ok<AGROW>
        logOIdx     = [logOIdx;     zeros(growBy,1)]; %#ok<AGROW>
        logDIdx     = [logDIdx;     zeros(growBy,1)]; %#ok<AGROW>
        logDep      = [logDep;      zeros(growBy,1)]; %#ok<AGROW>
        logArr      = [logArr;      zeros(growBy,1)]; %#ok<AGROW>
        logDist     = [logDist;     zeros(growBy,1)]; %#ok<AGROW>
        logBlock    = [logBlock;    zeros(growBy,1)]; %#ok<AGROW>
        logRouteID  = [logRouteID;  zeros(growBy,1)]; %#ok<AGROW>
    end

    logAircraft(logCount) = a;
    logOIdx(logCount)     = oIdx;
    logDIdx(logCount)     = dIdx;
    logDep(logCount)      = dep;
    logArr(logCount)      = arr;
    logDist(logCount)     = dist;
    logBlock(logCount)    = blockMin;
    logRouteID(logCount)  = routes.RouteID(chosenRow);
end

if logCount == 0
    error('Simulation produced zero flights.');
end

%% ------------------------------------------------------------------------
% Flights Table
%% ------------------------------------------------------------------------

logAircraft = logAircraft(1:logCount);
logOIdx     = logOIdx(1:logCount);
logDIdx     = logDIdx(1:logCount);
logDep      = logDep(1:logCount);
logArr      = logArr(1:logCount);
logDist     = logDist(1:logCount);
logBlock    = logBlock(1:logCount);
logRouteID  = logRouteID(1:logCount);

flights = table( ...
    logAircraft, logOIdx, logDIdx, logDep, logArr, logDist, logBlock, logRouteID, ...
    'VariableNames', {'Aircraft','OriginIdx','DestIdx','Dep_min','Arr_min','Distance_km','Block_min','RouteID'});

flights.OriginID = nodes.NodeID(flights.OriginIdx);
flights.DestID   = nodes.NodeID(flights.DestIdx);

%% ------------------------------------------------------------------------
% Metrics
%% ------------------------------------------------------------------------

utilMin  = accumarray(flights.Aircraft, flights.Block_min, [cfg.numAircraft 1], @sum, 0);
numFlts  = accumarray(flights.Aircraft, 1, [cfg.numAircraft 1], @sum, 0);
utilPct  = 100 * utilMin / totalOpMin;

avgBlockHoursPerAircraft = mean(utilMin) / 60;
fleetTotalBlockHours     = sum(utilMin) / 60;
fleetProductivity        = height(flights) / cfg.numAircraft;

%% ------------------------------------------------------------------------
% Route Frequency Analysis
%% ------------------------------------------------------------------------

routeCounts = accumarray(flights.RouteID, 1, [height(routes) 1], @sum, 0);
[routeCountsSorted, routeOrder] = sort(routeCounts, 'descend');

topRouteN = min(cfg.topRouteCount, sum(routeCountsSorted > 0));
topRouteRows = routeOrder(1:topRouteN);

topRouteLabels = "N" + string(routes.OriginIdx(topRouteRows)) + "→N" + string(routes.DestIdx(topRouteRows));

%% ------------------------------------------------------------------------
% Node Traffic Analysis
%% ------------------------------------------------------------------------

nodeDepartures = accumarray(flights.OriginIdx, 1, [cfg.numNodes 1], @sum, 0);
nodeArrivals   = accumarray(flights.DestIdx,   1, [cfg.numNodes 1], @sum, 0);
nodeTraffic    = nodeDepartures + nodeArrivals;

[nodeTrafficSorted, nodeOrder] = sort(nodeTraffic, 'descend');
labelNodeN   = min(cfg.topLabelCount, numel(nodeTrafficSorted));
labelNodeIDs = nodeOrder(1:labelNodeN);

%% ------------------------------------------------------------------------
% Hourly Flight Activity
%% ------------------------------------------------------------------------

hourOfDay = floor(mod(flights.Dep_min, 24*60) / 60);
hourlyFlightActivity = accumarray(hourOfDay + 1, 1, [24 1], @sum, 0);
hourlyFlightActivity = hourlyFlightActivity / cfg.simDays;

%% ------------------------------------------------------------------------
% Summary
%% ------------------------------------------------------------------------

fprintf('\n================ MODEL B: RESULTS =======================\n');
fprintf('Nodes                              : %d\n', cfg.numNodes);
fprintf('Feasible routes used               : %d\n', height(routes));
fprintf('Aircraft                           : %d\n', cfg.numAircraft);
fprintf('Flights completed                  : %d\n', height(flights));
fprintf('Average block hours per aircraft   : %.2f hr\n', avgBlockHoursPerAircraft);
fprintf('Overall fleet block hours          : %.1f hr\n', fleetTotalBlockHours);
fprintf('Flights per aircraft               : %.2f\n', fleetProductivity);
fprintf('Average utilisation                : %.2f %%\n', mean(utilPct));
fprintf('Maximum utilisation                : %.2f %%\n', max(utilPct));
fprintf('=========================================================\n\n');

%% ------------------------------------------------------------------------
% Figure 2: Route Utilisation Ranking
%% ------------------------------------------------------------------------

fig2 = newFigure('Figure_2', [2 2 18 12]);
ax2 = axes(fig2);
styleAxes(ax2);
hold(ax2,'on');

bar(ax2, routeCountsSorted(1:topRouteN), ...
    'FaceColor', [0.20 0.45 0.80], ...
    'EdgeColor', [0.10 0.25 0.45], ...
    'LineWidth', 0.8);

for i = 1:topRouteN
    text(ax2, i, routeCountsSorted(i) + max(routeCountsSorted(1:topRouteN))*0.015, ...
        sprintf('%d', routeCountsSorted(i)), ...
        'HorizontalAlignment', 'center', ...
        'FontName', 'Times New Roman', ...
        'FontSize', 9);
end

xlabel(ax2, 'Route', 'FontName', 'Times New Roman', 'FontSize', 12);
ylabel(ax2, 'Number of flights', 'FontName', 'Times New Roman', 'FontSize', 12);

xticks(ax2, 1:topRouteN);
xticklabels(ax2, topRouteLabels);
xtickangle(ax2, 35);
xlim(ax2, [0.4 topRouteN + 0.6]);

hold(ax2,'off');

saveFigure(fig2, cfg.figure2Number, cfg.figure2Name, cfg.exportFolder, cfg.exportFigures);

%% ------------------------------------------------------------------------
% Figure 3: Spatial Distribution of Node Traffic Intensity
%% ------------------------------------------------------------------------

if max(nodeTraffic) == 0
    nodeSize = 40 * ones(size(nodeTraffic));
else
    nodeSize = 20 + 360 * (nodeTraffic / max(nodeTraffic)).^1.15;
end

fig3 = newFigure('Figure_3', [2 2 18 14]);
ax3 = axes(fig3);
styleAxes(ax3);
hold(ax3,'on');

% Faint background node layer
scatter(ax3, nodes.Lon, nodes.Lat, 18, ...
    'MarkerFaceColor', [0.88 0.88 0.88], ...
    'MarkerEdgeColor', [0.72 0.72 0.72], ...
    'LineWidth', 0.35);

% Main traffic-intensity layer
scatter(ax3, nodes.Lon, nodes.Lat, nodeSize, nodeTraffic, ...
    'filled', ...
    'MarkerEdgeColor', 'k', ...
    'LineWidth', 0.6);

colormap(ax3, turbo);

cb = colorbar(ax3);
cb.Label.String   = 'Total movements';
cb.Label.FontName = 'Times New Roman';
cb.Label.FontSize = 11;
cb.FontName       = 'Times New Roman';
cb.FontSize       = 10;
cb.Color          = 'k';

for i = 1:labelNodeN
    n = labelNodeIDs(i);
    text(ax3, nodes.Lon(n) + 0.045, nodes.Lat(n) + 0.045, ...
        "N" + string(nodes.NodeID(n)), ...
        'FontName', 'Times New Roman', ...
        'FontSize', 11, ...
        'FontWeight', 'bold', ...
        'Color', 'k', ...
        'BackgroundColor', 'w', ...
        'Margin', 0.25);
end

xlabel(ax3, 'Longitude', 'FontName', 'Times New Roman', 'FontSize', 12);
ylabel(ax3, 'Latitude',  'FontName', 'Times New Roman', 'FontSize', 12);

xlim(ax3, [min(nodes.Lon) - 0.3, max(nodes.Lon) + 0.3]);
ylim(ax3, [min(nodes.Lat) - 0.3, max(nodes.Lat) + 0.3]);

hold(ax3,'off');

saveFigure(fig3, cfg.figure3Number, cfg.figure3Name, cfg.exportFolder, cfg.exportFigures);

%% ------------------------------------------------------------------------
% Figure 4: Flights Per Aircraft Distribution
%% ------------------------------------------------------------------------

fig4 = newFigure('Figure_4', [2 2 16 10.5]);
ax4 = axes(fig4);
styleAxes(ax4);
hold(ax4,'on');

histogram(ax4, numFlts, ...
    'BinMethod', 'integers', ...
    'FaceColor', [0.20 0.45 0.75], ...
    'EdgeColor', 'k', ...
    'LineWidth', 0.6);

xline(ax4, mean(numFlts), '--k', 'LineWidth', 1.2);

xlabel(ax4, 'Flights completed per aircraft (7-day total)', ...
    'FontName', 'Times New Roman', 'FontSize', 12);
ylabel(ax4, 'Number of aircraft', ...
    'FontName', 'Times New Roman', 'FontSize', 12);

hold(ax4,'off');

saveFigure(fig4, cfg.figure4Number, cfg.figure4Name, cfg.exportFolder, cfg.exportFigures);

%% ------------------------------------------------------------------------
% Figure 5: Hourly Flight Activity
%% ------------------------------------------------------------------------

fig5 = newFigure('Figure_5', [2 2 16 10.5]);
ax5 = axes(fig5);
styleAxes(ax5);
hold(ax5,'on');

plot(ax5, 0:23, hourlyFlightActivity, '-o', ...
    'LineWidth', 1.8, ...
    'MarkerSize', 5.5, ...
    'Color', [0.05 0.35 0.75], ...
    'MarkerFaceColor', [0.05 0.35 0.75]);

xlabel(ax5, 'Hour of day', 'FontName', 'Times New Roman', 'FontSize', 12);
ylabel(ax5, 'Average flights completed per hour', ...
    'FontName', 'Times New Roman', 'FontSize', 12);

xlim(ax5, [0 23]);
xticks(ax5, 0:2:23);

hold(ax5,'off');

saveFigure(fig5, cfg.figure5Number, cfg.figure5Name, cfg.exportFolder, cfg.exportFigures);

%% ------------------------------------------------------------------------
% Local Functions
%% ------------------------------------------------------------------------

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
    ax.GridColor = [0.85 0.85 0.85];
    ax.GridAlpha = 0.55;
    box(ax, 'on');
    grid(ax, 'on');
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

function chosenRow = chooseRouteRow(routes, candidateRows, cfg)
    d = routes.DemandScore(candidateRows);
    d = max(d, 0.01);

    switch lower(cfg.choiceMode)
        case "weighted"
            p = d / sum(d);
        case "softmax"
            x = d / max(d);
            p = exp(x / max(cfg.softmaxTau, 1e-6));
            p = p / sum(p);
        otherwise
            p = ones(size(d)) / numel(d);
    end

    k = sampleDiscrete(p);
    chosenRow = candidateRows(k);
end

function k = sampleDiscrete(p)
    r = rand;
    c = cumsum(p(:));
    k = find(r <= c, 1, 'first');
    if isempty(k)
        k = numel(p);
    end
end

function t2 = pushToOperatingWindow(t, opStart, opEnd)
    modDay = mod(t, 24*60);

    if modDay < opStart
        t2 = t + (opStart - modDay);
    elseif modDay >= opEnd
        t2 = t + ((24*60 - modDay) + opStart);
    else
        t2 = t;
    end
end

function m = minutesOfDay(t)
    m = mod(t, 24*60);
end

function t = nextDayStart(tNow, opStart)
    modDay = mod(tNow, 24*60);
    t = tNow + (24*60 - modDay) + opStart;
end

function d = haversineKm(lat1, lon1, lat2, lon2)
    R = 6371;
    p1 = deg2rad(lat1);
    p2 = deg2rad(lat2);
    dp = deg2rad(lat2 - lat1);
    dl = deg2rad(lon2 - lon1);

    a = sin(dp/2).^2 + cos(p1).*cos(p2).*sin(dl/2).^2;
    c = 2 * atan2(sqrt(a), sqrt(1-a));
    d = R * c;
end


