%% Model C: Crew-Constrained Demand-Driven Network Simulation
% Integrated aircraft and pilot scheduling within a synthetic UAM network
% Loads the shared topology created by Model B
% 100-node UK-like network, 1500 aircraft, 1500 pilots, 7-day simulation horizon

clearvars -except modelC_override scriptFolder seeds i seedVal; clc; close all;
set(0,'DefaultFigureWindowStyle','normal');

%% -------------------------------------------------------------------------
% Configuration
%% -------------------------------------------------------------------------

cfg.seed                = 7;
rng(cfg.seed);

cfg.simDays             = 7;
cfg.simHours            = 24 * cfg.simDays;
cfg.dtMin               = 5;
cfg.timeGrid            = 0:cfg.dtMin:(cfg.simHours*60 - cfg.dtMin);
cfg.nSteps              = numel(cfg.timeGrid);

cfg.operatingStartHour  = 6;
cfg.operatingEndHour    = 22;

cfg.nAircraft           = 1500;
cfg.nPilots             = 1500;

cfg.cruiseKmh           = 150;
cfg.blockBufferMin      = 8;
cfg.maxRangeKm          = 300;
cfg.maxLegTimeMin       = 120;

cfg.turnaroundMin       = 20;
cfg.capDepPerNodeHour   = 8;
cfg.passengerCapacity   = 4;

cfg.maxDutyMin          = 8 * 60;
cfg.minRestMin          = 10 * 60; %#ok<NASGU>

cfg.minDemandScore      = 0.15;
cfg.baseDemandMult      = 10;
cfg.demandScale         = 0.20;

cfg.allowRepositioning  = true;
cfg.maxRepositionMin    = 60;
cfg.countRepositionTime = true;

cfg.focusDay            = 2;
cfg.topAircraftToPlot   = 18;
cfg.topPilotsToPlot     = 18;
cfg.maxAircraftLabels   = 28;
cfg.maxPilotLabels      = 32;
cfg.minAircraftLabelHr  = 0.70;
cfg.minPilotLabelHr     = 0.55;
cfg.aircraftRowHeight   = 0.72;
cfg.pilotRowHeight      = 0.72;

cfg.sharedNetworkFile   = 'ModelB_Shared_Network.mat';

% Export / figure behaviour
thisFile = mfilename('fullpath');
if isempty(thisFile)
    cfg.exportFolder = pwd;
else
    cfg.exportFolder = fileparts(thisFile);
end

cfg.exportFigures       = true;
cfg.makeFigures         = true;

cfg.figure6Number       = 6;
cfg.figure6Name         = 'Aircraft_Duty_Rota';

cfg.figure7Number       = 7;
cfg.figure7Name         = 'Pilot_Duty_Rota';

cfg.figure8Number       = 8;
cfg.figure8Name         = 'Hourly_Active_Aircraft_Active_Pilots_and_Completed_Flights';

cfg.figure9Number       = 9;
cfg.figure9Name         = 'Hourly_Demand_Served_and_Spill';

cfg.figure10Number      = 10;
cfg.figure10Name        = 'Flights_Per_Aircraft_Distribution';

cfg.figure11Number      = 11;
cfg.figure11Name        = 'Pilot_Duty_Hours_Distribution';

cfg.figure12Number      = 12;
cfg.figure12Name        = 'Served_Route_Activity_Map';

%% -------------------------------------------------------------------------
% Optional external overrides for validation / sensitivity runs
%% -------------------------------------------------------------------------

if evalin('base', 'exist(''modelC_override'',''var'')')
    override = evalin('base', 'modelC_override');
    overrideFields = fieldnames(override);

    for ii = 1:numel(overrideFields)
        cfg.(overrideFields{ii}) = override.(overrideFields{ii});
    end
end

rng(cfg.seed);

%% -------------------------------------------------------------------------
% Load Shared Network from Model B
%% -------------------------------------------------------------------------

sharedPath = fullfile(cfg.exportFolder, cfg.sharedNetworkFile);

if ~isfile(sharedPath)
    error('Shared network file not found. Run Model B first.\nExpected file: %s', sharedPath);
end

shared = load(sharedPath);

if ~isfield(shared, 'nodes') || ~isfield(shared, 'routes') || ~isfield(shared, 'majorHubIdx')
    error('Shared network file is missing required variables: nodes, routes, majorHubIdx');
end

nodes = shared.nodes;
routes = shared.routes;
majorHubIdx = shared.majorHubIdx;

cfg.nNodes      = height(nodes);
cfg.targetRoutes = height(routes);
actualRoutes    = height(routes);

%% -------------------------------------------------------------------------
% Route Checks / Compatibility
%% -------------------------------------------------------------------------

requiredRouteFields = {'RouteID','OriginIdx','DestIdx','Distance_km','BlockMin','DemandScore'};
for i = 1:numel(requiredRouteFields)
    if ~ismember(requiredRouteFields{i}, routes.Properties.VariableNames)
        error('routes table is missing required field: %s', requiredRouteFields{i});
    end
end

if ~ismember('OriginID', routes.Properties.VariableNames)
    routes.OriginID = nodes.NodeID(routes.OriginIdx);
end
if ~ismember('DestID', routes.Properties.VariableNames)
    routes.DestID = nodes.NodeID(routes.DestIdx);
end

%% -------------------------------------------------------------------------
% Demand Model
%% -------------------------------------------------------------------------

hourlyMultiplier = [ ...
    0.10 0.08 0.06 0.06 0.08 0.20 ...
    0.55 0.85 1.00 0.92 0.80 0.74 ...
    0.78 0.84 0.90 0.98 1.12 1.25 ...
    1.00 0.72 0.50 0.30 0.18 0.10];

routes.IsActive = routes.DemandScore >= cfg.minDemandScore;

routeHourDemand = zeros(actualRoutes, cfg.simDays, 24);

for r = 1:actualRoutes
    for d = 1:cfg.simDays
        for h = 1:24
            rawDemand = routes.DemandScore(r) * hourlyMultiplier(h);
            pax = round(cfg.baseDemandMult * cfg.demandScale * rawDemand);
            routeHourDemand(r,d,h) = max(0, pax);
        end
    end
end

remainingDemand = routeHourDemand;

%% -------------------------------------------------------------------------
% Outgoing Route Index
%% -------------------------------------------------------------------------

outgoing = cell(cfg.nNodes,1);
for r = 1:actualRoutes
    o = routes.OriginIdx(r);
    outgoing{o} = [outgoing{o}; r]; %#ok<AGROW>
end

%% -------------------------------------------------------------------------
% Aircraft and Pilot Initialisation
%% -------------------------------------------------------------------------

nodeWeights = ones(cfg.nNodes,1);
if ~isempty(majorHubIdx)
    nodeWeights(majorHubIdx) = 2.0;
end
nodeProb = nodeWeights / sum(nodeWeights);

aircraft.id               = (1:cfg.nAircraft)';
aircraft.baseNode         = randsample(cfg.nNodes, cfg.nAircraft, true, nodeProb);
aircraft.currentNode      = aircraft.baseNode;
aircraft.availableAtMin   = zeros(cfg.nAircraft,1);
aircraft.flightCount      = zeros(cfg.nAircraft,1);
aircraft.flightMinutes    = zeros(cfg.nAircraft,1);
aircraft.repositionCount  = zeros(cfg.nAircraft,1);

pilot.id                  = (1:cfg.nPilots)';
pilot.baseNode            = randsample(cfg.nNodes, cfg.nPilots, true, nodeProb);
pilot.currentNode         = pilot.baseNode;
pilot.availableAtMin      = zeros(cfg.nPilots,1);
pilot.dutyMinutesToday    = zeros(cfg.nPilots,1);
pilot.totalDutyMinutes    = zeros(cfg.nPilots,1);
pilot.flightMinutes       = zeros(cfg.nPilots,1);
pilot.flightCount         = zeros(cfg.nPilots,1);
pilot.dayLockedOut        = false(cfg.nPilots,1);

%% -------------------------------------------------------------------------
% Logging
%% -------------------------------------------------------------------------

maxLog = 350000;

flightLog.depMin          = nan(maxLog,1);
flightLog.arrMin          = nan(maxLog,1);
flightLog.aircraftID      = nan(maxLog,1);
flightLog.pilotID         = nan(maxLog,1);
flightLog.routeID         = nan(maxLog,1);
flightLog.originIdx       = nan(maxLog,1);
flightLog.destIdx         = nan(maxLog,1);
flightLog.blockMin        = nan(maxLog,1);
flightLog.repositionMin   = nan(maxLog,1);
flightLog.dayIdx          = nan(maxLog,1);

logCount = 0;

hourlyDemandPax   = zeros(cfg.simDays,24);
hourlyServedPax   = zeros(cfg.simDays,24);
hourlySpilledPax  = zeros(cfg.simDays,24);
hourlyFlights     = zeros(cfg.simDays,24);
hourlyActiveAC    = zeros(cfg.simDays,24);
hourlyActivePil   = zeros(cfg.simDays,24);

routeFlights      = zeros(actualRoutes,1);
depCount          = zeros(cfg.nNodes, cfg.simDays, 24);

%% -------------------------------------------------------------------------
% Main Scheduler
%% -------------------------------------------------------------------------

lastDayProcessed = 0;
fprintf('Starting Model C scheduler...\n');

for step = 1:cfg.nSteps
    if mod(step, 500) == 0
        fprintf('Model C progress: step %d / %d\n', step, cfg.nSteps);
    end

    tNow = cfg.timeGrid(step);

    dayNow     = floor(tNow / (24*60)) + 1;
    minOfDay   = mod(tNow, 24*60);
    hourOfDay  = floor(minOfDay / 60) + 1;
    hourValue  = minOfDay / 60;

    if dayNow ~= lastDayProcessed
        pilot.dutyMinutesToday(:) = 0;
        pilot.dayLockedOut(:)     = false;
        lastDayProcessed          = dayNow;
    end

    if mod(tNow,60) == 0
        hourlyDemandPax(dayNow, hourOfDay) = sum(remainingDemand(:,dayNow,hourOfDay));
    end

    if hourValue < cfg.operatingStartHour || hourValue >= cfg.operatingEndHour
        continue;
    end

    activeRoutes = find(routes.IsActive & remainingDemand(:,dayNow,hourOfDay) > 0);

    if isempty(activeRoutes)
        continue;
    end

    priority = zeros(numel(activeRoutes),1);
    for kk = 1:numel(activeRoutes)
        r = activeRoutes(kk);
        demandTerm = remainingDemand(r,dayNow,hourOfDay);
        shortTerm  = 1 / routes.BlockMin(r);
        priority(kk) = 0.8 * demandTerm + 0.2 * shortTerm;
    end

    [~, ord] = sort(priority, 'descend');
    activeRoutes = activeRoutes(ord);

    for idx = 1:numel(activeRoutes)
        r = activeRoutes(idx);

        origin = routes.OriginIdx(r);
        dest   = routes.DestIdx(r);
        blockT = routes.BlockMin(r);

        if depCount(origin, dayNow, hourOfDay) >= cfg.capDepPerNodeHour
            continue;
        end

        if remainingDemand(r,dayNow,hourOfDay) <= 0
            continue;
        end

        feasibleAircraft = find( ...
            aircraft.currentNode == origin & ...
            aircraft.availableAtMin <= tNow);

        repositionMin = 0;

        if isempty(feasibleAircraft)
            if ~cfg.allowRepositioning
                continue;
            end

            candidateAircraft = find(aircraft.availableAtMin <= tNow);
            if isempty(candidateAircraft)
                continue;
            end

            candidateNodes = aircraft.currentNode(candidateAircraft);
            repositionDist = zeros(numel(candidateAircraft),1);

            for ii = 1:numel(candidateAircraft)
                repositionDist(ii) = haversineKm( ...
                    nodes.Lat(candidateNodes(ii)), nodes.Lon(candidateNodes(ii)), ...
                    nodes.Lat(origin), nodes.Lon(origin));
            end

            repositionTime = (repositionDist / cfg.cruiseKmh) * 60 + cfg.blockBufferMin;

            [repositionMin, bestIdx] = min(repositionTime);
            a = candidateAircraft(bestIdx);

            if repositionMin > cfg.maxRepositionMin
                continue;
            end
        else
            [~, ia] = min(aircraft.flightCount(feasibleAircraft));
            a = feasibleAircraft(ia);
        end

        depMin = tNow + repositionMin;
        arrMin = depMin + blockT;

        depDayNow    = floor(depMin / (24*60)) + 1;
        depMinOfDay  = mod(depMin, 24*60);
        depHourValue = depMinOfDay / 60;
        depHourIdx   = floor(depMinOfDay / 60) + 1;

        if depDayNow ~= dayNow
            continue;
        end

        if depHourValue >= cfg.operatingEndHour || depHourValue < cfg.operatingStartHour
            continue;
        end

        if depCount(origin, depDayNow, depHourIdx) >= cfg.capDepPerNodeHour
            continue;
        end

        feasiblePilots = find( ...
            pilot.currentNode == origin & ...
            pilot.availableAtMin <= depMin & ...
            ~pilot.dayLockedOut);

        if isempty(feasiblePilots)
            continue;
        end

        validMask = false(numel(feasiblePilots),1);
        for pIdx = 1:numel(feasiblePilots)
            pTest = feasiblePilots(pIdx);
            if pilot.dutyMinutesToday(pTest) + blockT <= cfg.maxDutyMin
                validMask(pIdx) = true;
            end
        end
        feasiblePilots = feasiblePilots(validMask);

        if isempty(feasiblePilots)
            continue;
        end

        [~, ip] = min(pilot.dutyMinutesToday(feasiblePilots));
        p = feasiblePilots(ip);

        logCount = logCount + 1;
        if logCount > maxLog
            error('Flight log exceeded maxLog. Increase maxLog.');
        end

        flightLog.depMin(logCount)        = depMin;
        flightLog.arrMin(logCount)        = arrMin;
        flightLog.aircraftID(logCount)    = a;
        flightLog.pilotID(logCount)       = p;
        flightLog.routeID(logCount)       = routes.RouteID(r);
        flightLog.originIdx(logCount)     = origin;
        flightLog.destIdx(logCount)       = dest;
        flightLog.blockMin(logCount)      = blockT;
        flightLog.repositionMin(logCount) = repositionMin;
        flightLog.dayIdx(logCount)        = depDayNow;

        aircraft.currentNode(a)    = dest;
        aircraft.availableAtMin(a) = arrMin + cfg.turnaroundMin;
        aircraft.flightCount(a)    = aircraft.flightCount(a) + 1;

        if cfg.countRepositionTime
            aircraft.flightMinutes(a) = aircraft.flightMinutes(a) + blockT + repositionMin;
        else
            aircraft.flightMinutes(a) = aircraft.flightMinutes(a) + blockT;
        end

        if repositionMin > 0
            aircraft.repositionCount(a) = aircraft.repositionCount(a) + 1;
        end

        pilot.currentNode(p)       = dest;
        pilot.availableAtMin(p)    = arrMin;
        pilot.dutyMinutesToday(p)  = pilot.dutyMinutesToday(p) + blockT;
        pilot.totalDutyMinutes(p)  = pilot.totalDutyMinutes(p) + blockT;
        pilot.flightMinutes(p)     = pilot.flightMinutes(p) + blockT;
        pilot.flightCount(p)       = pilot.flightCount(p) + 1;

        if pilot.dutyMinutesToday(p) >= cfg.maxDutyMin - 1e-9
            pilot.dayLockedOut(p) = true;
        end

        depCount(origin, depDayNow, depHourIdx) = depCount(origin, depDayNow, depHourIdx) + 1;

        servedPax = min(cfg.passengerCapacity, remainingDemand(r,depDayNow,depHourIdx));
        remainingDemand(r,depDayNow,depHourIdx) = remainingDemand(r,depDayNow,depHourIdx) - servedPax;

        hourlyServedPax(depDayNow,depHourIdx) = hourlyServedPax(depDayNow,depHourIdx) + servedPax;
        hourlyFlights(depDayNow,depHourIdx)   = hourlyFlights(depDayNow,depHourIdx) + 1;
        routeFlights(r)                       = routeFlights(r) + 1;
    end
end

fprintf('Model C scheduler finished.\n');

%% -------------------------------------------------------------------------
% Post-Processing
%% -------------------------------------------------------------------------

fields = fieldnames(flightLog);
for f = 1:numel(fields)
    flightLog.(fields{f}) = flightLog.(fields{f})(1:logCount);
end

for d = 1:cfg.simDays
    for h = 1:24
        hourlySpilledPax(d,h) = sum(remainingDemand(:,d,h));

        t0 = ((d-1)*24 + (h-1)) * 60;
        t1 = t0 + 60;

        activeACMask = false(cfg.nAircraft,1);
        activePIMask = false(cfg.nPilots,1);

        if logCount > 0
            activeMask = (flightLog.depMin < t1) & (flightLog.arrMin > t0);

            if any(activeMask)
                activeACMask(unique(flightLog.aircraftID(activeMask))) = true;
                activePIMask(unique(flightLog.pilotID(activeMask)))   = true;
            end
        end

        hourlyActiveAC(d,h)  = sum(activeACMask);
        hourlyActivePil(d,h) = sum(activePIMask);
    end
end

meanHourlyDemand   = mean(hourlyDemandPax, 1)';
meanHourlyServed   = mean(hourlyServedPax, 1)';
meanHourlySpilled  = mean(hourlySpilledPax, 1)';
meanHourlyFlights  = mean(hourlyFlights, 1)';
meanHourlyActiveAC = mean(hourlyActiveAC, 1)';
meanHourlyActivePi = mean(hourlyActivePil, 1)';

totalDemandPax        = sum(routeHourDemand(:));
totalServedPax        = sum(hourlyServedPax(:));
totalSpilledPax       = sum(hourlySpilledPax(:));
routesServed          = sum(routeFlights > 0);
networkCoveragePct    = 100 * routesServed / actualRoutes;
demandSatisfactionPct = 100 * totalServedPax / max(1,totalDemandPax);
spillPct              = 100 * totalSpilledPax / max(1,totalDemandPax);

avgFlightsPerAircraft  = mean(aircraft.flightCount);
avgFlightHoursAircraft = mean(aircraft.flightMinutes) / 60;
avgPilotDutyHours      = mean(pilot.totalDutyMinutes) / 60;
activeAircraft         = sum(aircraft.flightCount > 0);
activePilots           = sum(pilot.flightCount > 0);

fprintf('\n================ MODEL C: RESULTS =======================\n');
fprintf('Simulation horizon                  : %d days\n', cfg.simDays);
fprintf('Nodes                               : %d\n', cfg.nNodes);
fprintf('Feasible routes                     : %d\n', actualRoutes);
fprintf('Aircraft                            : %d\n', cfg.nAircraft);
fprintf('Pilots                              : %d\n', cfg.nPilots);
fprintf('Flights completed                   : %d\n', logCount);
fprintf('Passengers served                   : %d\n', totalServedPax);
fprintf('Passengers spilled                  : %d\n', totalSpilledPax);
fprintf('Demand satisfaction                 : %.2f %%\n', demandSatisfactionPct);
fprintf('Spill rate                          : %.2f %%\n', spillPct);
fprintf('Routes served at least once         : %d\n', routesServed);
fprintf('Network coverage                    : %.2f %%\n', networkCoveragePct);
fprintf('Active aircraft                     : %d\n', activeAircraft);
fprintf('Active pilots                       : %d\n', activePilots);
fprintf('Average flights per aircraft        : %.2f\n', avgFlightsPerAircraft);
fprintf('Average aircraft flight hours       : %.2f hr\n', avgFlightHoursAircraft);
fprintf('Average pilot duty hours            : %.2f hr\n', avgPilotDutyHours);
fprintf('=========================================================\n\n');

%% -------------------------------------------------------------------------
% Figures
%% -------------------------------------------------------------------------

if cfg.makeFigures
    fprintf('Generating Model C figures...\n');

    focusStartMin = (cfg.focusDay - 1) * 24 * 60;
    aircraftOrder = sortrows([(1:cfg.nAircraft)' aircraft.flightCount], -2);
    pilotOrder    = sortrows([(1:cfg.nPilots)' pilot.flightCount], -2);

    plotAircraft = aircraftOrder(1:min(cfg.topAircraftToPlot, size(aircraftOrder,1)),1);
    plotPilots   = pilotOrder(1:min(cfg.topPilotsToPlot, size(pilotOrder,1)),1);

    % Figure 6
    fig6 = newFigure('Figure_6', [2 2 20 12.0]);
    ax6  = axes(fig6);
    styleAxes(ax6);
    hold(ax6,'on');

    selectedMask = ismember(flightLog.aircraftID, plotAircraft) & ...
                   flightLog.depMin >= focusStartMin & ...
                   flightLog.depMin < focusStartMin + 24*60;
    selectedIdx = find(selectedMask);

    if ~isempty(selectedIdx)
        [~, ord] = sortrows([flightLog.aircraftID(selectedIdx), flightLog.depMin(selectedIdx)], [1 2]);
        selectedIdx = selectedIdx(ord);
    end

    labelCount = 0;
    for ii = 1:numel(selectedIdx)
        i = selectedIdx(ii);
        a = flightLog.aircraftID(i);
        pos = find(plotAircraft == a, 1);
        if isempty(pos), continue; end

        x0  = (flightLog.depMin(i) - focusStartMin) / 60;
        dur = (flightLog.arrMin(i) - flightLog.depMin(i)) / 60;
        c   = routeColor(flightLog.routeID(i), actualRoutes);

        rectangle(ax6, 'Position', [x0, pos - cfg.aircraftRowHeight/2, dur, cfg.aircraftRowHeight], ...
            'FaceColor', c, 'EdgeColor', [0.15 0.15 0.15], 'LineWidth', 0.5);

        if dur >= cfg.minAircraftLabelHr && labelCount < cfg.maxAircraftLabels
            txt = "N" + string(flightLog.originIdx(i)) + "→N" + string(flightLog.destIdx(i));
            text(ax6, x0 + dur/2, pos, txt, ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
                'FontSize', 7, 'FontWeight', 'bold', 'FontName', 'Times New Roman', ...
                'Color', [0.10 0.10 0.10], 'BackgroundColor', 'w', 'Margin', 0.08, 'Clipping', 'on');
            labelCount = labelCount + 1;
        end
    end

    xlim(ax6, [0 24]); ylim(ax6, [0 numel(plotAircraft) + 1]);
    yticks(ax6, 1:numel(plotAircraft));
    yticklabels(ax6, "AC" + string(plotAircraft));
    set(ax6, 'YDir', 'reverse');
    xlabel(ax6, 'Time of day (hours)', 'FontName', 'Times New Roman', 'FontSize', 12);
    ylabel(ax6, 'Aircraft', 'FontName', 'Times New Roman', 'FontSize', 12);
    hold(ax6,'off');
    saveFigure(fig6, cfg.figure6Number, cfg.figure6Name, cfg.exportFolder, cfg.exportFigures);

    % Figure 7
    fig7 = newFigure('Figure_7', [2 2 20 12.0]);
    ax7  = axes(fig7);
    styleAxes(ax7);
    hold(ax7,'on');

    selectedMask = ismember(flightLog.pilotID, plotPilots) & ...
                   flightLog.depMin >= focusStartMin & ...
                   flightLog.depMin < focusStartMin + 24*60;
    selectedIdx = find(selectedMask);

    if ~isempty(selectedIdx)
        [~, ord] = sortrows([flightLog.pilotID(selectedIdx), flightLog.depMin(selectedIdx)], [1 2]);
        selectedIdx = selectedIdx(ord);
    end

    labelCount = 0;
    for ii = 1:numel(selectedIdx)
        i = selectedIdx(ii);
        p = flightLog.pilotID(i);
        pos = find(plotPilots == p, 1);
        if isempty(pos), continue; end

        x0  = (flightLog.depMin(i) - focusStartMin) / 60;
        dur = (flightLog.arrMin(i) - flightLog.depMin(i)) / 60;
        c   = routeColor(flightLog.routeID(i), actualRoutes);

        rectangle(ax7, 'Position', [x0, pos - cfg.pilotRowHeight/2, dur, cfg.pilotRowHeight], ...
            'FaceColor', c, 'EdgeColor', [0.15 0.15 0.15], 'LineWidth', 0.5);

        if dur >= cfg.minPilotLabelHr && labelCount < cfg.maxPilotLabels
            txt = "AC" + string(flightLog.aircraftID(i));
            text(ax7, x0 + dur/2, pos, txt, ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
                'FontSize', 7, 'FontWeight', 'bold', 'FontName', 'Times New Roman', ...
                'Color', [0.10 0.10 0.10], 'BackgroundColor', 'w', 'Margin', 0.08, 'Clipping', 'on');
            labelCount = labelCount + 1;
        end
    end

    xlim(ax7, [0 24]); ylim(ax7, [0 numel(plotPilots) + 1]);
    yticks(ax7, 1:numel(plotPilots));
    yticklabels(ax7, "P" + string(plotPilots));
    set(ax7, 'YDir', 'reverse');
    xlabel(ax7, 'Time of day (hours)', 'FontName', 'Times New Roman', 'FontSize', 12);
    ylabel(ax7, 'Pilots', 'FontName', 'Times New Roman', 'FontSize', 12);
    hold(ax7,'off');
    saveFigure(fig7, cfg.figure7Number, cfg.figure7Name, cfg.exportFolder, cfg.exportFigures);

    % Figure 8
    fig8 = newFigure('Figure_8', [2 2 18 10.5]);
    ax8  = axes(fig8);
    styleAxes(ax8);
    hold(ax8,'on');

    hours = 0:23;
    plot(ax8, hours, meanHourlyActiveAC, '-o', 'LineWidth', 2.0, 'MarkerSize', 6);
    plot(ax8, hours, meanHourlyActivePi, '-s', 'LineWidth', 2.0, 'MarkerSize', 6);
    plot(ax8, hours, meanHourlyFlights,  '-d', 'LineWidth', 2.0, 'MarkerSize', 6);

    xlabel(ax8, 'Hour of day', 'FontName', 'Times New Roman', 'FontSize', 12);
    ylabel(ax8, 'Average count', 'FontName', 'Times New Roman', 'FontSize', 12);
    legend(ax8, {'Active aircraft','Active pilots','Flights completed per hour'}, ...
        'Location', 'best', 'Box', 'off', 'FontName', 'Times New Roman', 'FontSize', 10);
    xlim(ax8, [0 23]); xticks(ax8, 0:2:23);
    hold(ax8,'off');
    saveFigure(fig8, cfg.figure8Number, cfg.figure8Name, cfg.exportFolder, cfg.exportFigures);

    % Figure 9
    fig9 = newFigure('Figure_9', [2 2 18 10.5]);
    ax9  = axes(fig9);
    styleAxes(ax9);
    hold(ax9,'on');

    plot(ax9, hours, meanHourlyDemand,  '-o', 'LineWidth', 2.0, 'MarkerSize', 6);
    plot(ax9, hours, meanHourlyServed,  '-s', 'LineWidth', 2.0, 'MarkerSize', 6);
    plot(ax9, hours, meanHourlySpilled, '-d', 'LineWidth', 2.0, 'MarkerSize', 6);

    xlabel(ax9, 'Hour of day', 'FontName', 'Times New Roman', 'FontSize', 12);
    ylabel(ax9, 'Average passengers', 'FontName', 'Times New Roman', 'FontSize', 12);
    legend(ax9, {'Demand','Served','Spill'}, ...
        'Location', 'best', 'Box', 'off', 'FontName', 'Times New Roman', 'FontSize', 10);
    xlim(ax9, [0 23]); xticks(ax9, 0:2:23);
    hold(ax9,'off');
    saveFigure(fig9, cfg.figure9Number, cfg.figure9Name, cfg.exportFolder, cfg.exportFigures);

    % Figure 10
    fig10 = newFigure('Figure_10', [2 2 16 10.5]);
    ax10  = axes(fig10);
    styleAxes(ax10);
    hold(ax10,'on');

    histogram(ax10, aircraft.flightCount, 'BinMethod', 'integers', ...
        'FaceColor', [0.20 0.45 0.75], 'EdgeColor', 'k', 'LineWidth', 0.6);
    xline(ax10, mean(aircraft.flightCount), '--k', 'LineWidth', 1.2);

    xlabel(ax10, 'Flights completed per aircraft (7-day total)', 'FontName', 'Times New Roman', 'FontSize', 12);
    ylabel(ax10, 'Number of aircraft', 'FontName', 'Times New Roman', 'FontSize', 12);
    hold(ax10,'off');
    saveFigure(fig10, cfg.figure10Number, cfg.figure10Name, cfg.exportFolder, cfg.exportFigures);

    % Figure 11
    fig11 = newFigure('Figure_11', [2 2 16 10.5]);
    ax11  = axes(fig11);
    styleAxes(ax11);
    hold(ax11,'on');

    histogram(ax11, pilot.totalDutyMinutes / 60, ...
        'FaceColor', [0.80 0.45 0.20], 'EdgeColor', 'k', 'LineWidth', 0.6);
    xline(ax11, mean(pilot.totalDutyMinutes / 60), '--k', 'LineWidth', 1.2);

    xlabel(ax11, 'Pilot accumulated duty hours (7-day total)', 'FontName', 'Times New Roman', 'FontSize', 12);
    ylabel(ax11, 'Number of pilots', 'FontName', 'Times New Roman', 'FontSize', 12);
    hold(ax11,'off');
    saveFigure(fig11, cfg.figure11Number, cfg.figure11Name, cfg.exportFolder, cfg.exportFigures);

    % Figure 12
    fig12 = newFigure('Figure_12', [2 2 18 14]);
    ax12  = axes(fig12);
    styleAxes(ax12);
    hold(ax12,'on');

    activeRouteIdx = find(routeFlights > 0);

    if isempty(activeRouteIdx)
        scatter(ax12, nodes.Lon, nodes.Lat, 20, 'filled');
    else
        maxPlotRoutes = min(180, numel(activeRouteIdx));
        [~, ord] = sort(routeFlights(activeRouteIdx), 'descend');
        plotRoutes = activeRouteIdx(ord(1:maxPlotRoutes));

        for i = 1:numel(plotRoutes)
            r = plotRoutes(i);
            o = routes.OriginIdx(r);
            d = routes.DestIdx(r);

            plot(ax12, [nodes.Lon(o) nodes.Lon(d)], [nodes.Lat(o) nodes.Lat(d)], ...
                '-', 'Color', [0.55 0.75 0.90], 'LineWidth', 0.8);
        end

        nodeTrafficServed = zeros(cfg.nNodes,1);
        for r = 1:actualRoutes
            if routeFlights(r) > 0
                nodeTrafficServed(routes.OriginIdx(r)) = nodeTrafficServed(routes.OriginIdx(r)) + routeFlights(r);
                nodeTrafficServed(routes.DestIdx(r))   = nodeTrafficServed(routes.DestIdx(r)) + routeFlights(r);
            end
        end

        if max(nodeTrafficServed) == 0
            nodeSize = 30 * ones(cfg.nNodes,1);
        else
            nodeSize = 18 + 260 * (nodeTrafficServed / max(nodeTrafficServed)).^1.15;
        end

        scatter(ax12, nodes.Lon, nodes.Lat, nodeSize, nodeTrafficServed, ...
            'filled', 'MarkerEdgeColor', 'k', 'LineWidth', 0.5);

        colormap(ax12, turbo);
        cb = colorbar(ax12);
        cb.Label.String   = 'Served route movements';
        cb.Label.FontName = 'Times New Roman';
        cb.Label.FontSize = 11;
        cb.FontName       = 'Times New Roman';
        cb.FontSize       = 10;
        cb.Color          = 'k';
    end

    xlabel(ax12, 'Longitude', 'FontName', 'Times New Roman', 'FontSize', 12);
    ylabel(ax12, 'Latitude',  'FontName', 'Times New Roman', 'FontSize', 12);
    xlim(ax12, [min(nodes.Lon) - 0.3, max(nodes.Lon) + 0.3]);
    ylim(ax12, [min(nodes.Lat) - 0.3, max(nodes.Lat) + 0.3]);
    hold(ax12,'off');
    saveFigure(fig12, cfg.figure12Number, cfg.figure12Name, cfg.exportFolder, cfg.exportFigures);
end

%% -------------------------------------------------------------------------
% Save Results for Validation
%% -------------------------------------------------------------------------

summary = struct();
summary.totalFlights = logCount;
summary.demandSatisfactionPct = demandSatisfactionPct;
summary.avgUtilisationPct = 100 * avgFlightHoursAircraft / (16 * 7);
summary.modelBFlightsCompleted = 134776;
summary.seed = cfg.seed;
summary.maxDutyMin = cfg.maxDutyMin;

resultsPath = fullfile(cfg.exportFolder, 'ModelC_Results.mat');

save(resultsPath, ...
    'flightLog', 'logCount', 'routeFlights', 'aircraft', 'pilot', 'summary');

fprintf('Model C results saved to: %s\n', resultsPath);

%% -------------------------------------------------------------------------
% Local Functions
%% -------------------------------------------------------------------------

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
    ax.MinorGridAlpha = 0.35;
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

function c = routeColor(routeId, nRoutes)
    cmap = turbo(max(16, nRoutes));
    idx = max(1, min(size(cmap,1), round(routeId)));
    c = cmap(idx,:);
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

