%% MODEL C VALIDATION
% Post-processing validation for the crew-constrained UAM model
%
% Checks:
% 1. Aircraft non-overlap
% 2. Pilot non-overlap
% 3. Pilot daily duty compliance
% 4. Operating window compliance
% 5. Departure cap compliance
% 6. Route feasibility / block-time consistency
% 7. Full-unlock sensitivity recovery
% 8. Multi-run statistical stability

clear; clc; close all;

%% ============================================================
% 1) CONFIGURATION
% ============================================================

thisFile = mfilename('fullpath');
if isempty(thisFile)
    cfg.exportFolder = pwd;
else
    cfg.exportFolder = fileparts(thisFile);
end

cfg.networkFileName      = 'ModelB_Shared_Network.mat';
cfg.modelCResultsFile    = 'ModelC_Results.mat';
cfg.unlockResultsFile    = 'ModelC_Unlock_Results.mat';

cfg.networkPath          = fullfile(cfg.exportFolder, cfg.networkFileName);
cfg.modelCResultsPath    = fullfile(cfg.exportFolder, cfg.modelCResultsFile);
cfg.unlockResultsPath    = fullfile(cfg.exportFolder, cfg.unlockResultsFile);

cfg.operatingStartHour   = 6;
cfg.operatingEndHour     = 22;
cfg.capDepPerNodeHour    = 8;
cfg.maxDutyMin           = 8 * 60;
cfg.turnaroundMin        = 20;

cfg.runFullUnlockTest    = true;
cfg.runStabilityTest     = true;
cfg.stabilitySeeds       = [7 13 21 42 99];

cfg.modelBFlightsDefault = 134776;

%% ============================================================
% 2) LOAD REQUIRED DATA
% ============================================================

if ~isfile(cfg.networkPath)
    error('Shared network file not found. Expected:%s%s', newline, cfg.networkPath);
end

if ~isfile(cfg.modelCResultsPath)
    error('Model C results file not found. Expected:%s%s', newline, cfg.modelCResultsPath);
end

Net = load(cfg.networkPath);
Res = load(cfg.modelCResultsPath);

if ~isfield(Net, 'routes')
    error('Shared network file must contain variable: routes');
end
if ~isfield(Net, 'nodes')
    error('Shared network file must contain variable: nodes');
end

routes = Net.routes;
nodes  = Net.nodes; %#ok<NASGU>

requiredFields = {'flightLog','logCount','routeFlights','aircraft','pilot','summary'};
for i = 1:numel(requiredFields)
    if ~isfield(Res, requiredFields{i})
        warning('Model C results MAT missing expected field: %s', requiredFields{i});
    end
end

if ~isfield(Res, 'flightLog') || ~isfield(Res, 'logCount')
    error('Model C results must contain at least: flightLog and logCount');
end

flightLog = Res.flightLog;
logCount  = Res.logCount;

fields = fieldnames(flightLog);
for f = 1:numel(fields)
    flightLog.(fields{f}) = flightLog.(fields{f})(1:logCount);
end

if isfield(Res, 'summary')
    summary = Res.summary;
else
    summary = struct();
end

if isfield(summary, 'modelBFlightsCompleted')
    modelBFlightsCompleted = summary.modelBFlightsCompleted;
else
    modelBFlightsCompleted = cfg.modelBFlightsDefault;
end

%% ============================================================
% 3) CHECK 1 — AIRCRAFT NON-OVERLAP
% ============================================================

aircraftViolations = 0;
aircraftViolationDetails = {};

aircraftIDs = unique(flightLog.aircraftID(~isnan(flightLog.aircraftID)));

for a = aircraftIDs(:)'
    idx = find(flightLog.aircraftID == a);

    if numel(idx) < 2
        continue;
    end

    [~, ord] = sort(flightLog.depMin(idx));
    idx = idx(ord);

    for k = 1:(numel(idx)-1)
        i1 = idx(k);
        i2 = idx(k+1);

        if flightLog.depMin(i2) < flightLog.arrMin(i1) + cfg.turnaroundMin
            aircraftViolations = aircraftViolations + 1;
            aircraftViolationDetails{end+1,1} = sprintf( ...
                'Aircraft %d overlap: flight %d to %d, dep %.2f < arr %.2f + turnaround', ...
                a, i1, i2, flightLog.depMin(i2), flightLog.arrMin(i1)); %#ok<AGROW>
        end
    end
end

%% ============================================================
% 4) CHECK 2 — PILOT NON-OVERLAP
% ============================================================

pilotViolations = 0;
pilotViolationDetails = {};

pilotIDs = unique(flightLog.pilotID(~isnan(flightLog.pilotID)));

for p = pilotIDs(:)'
    idx = find(flightLog.pilotID == p);

    if numel(idx) < 2
        continue;
    end

    [~, ord] = sort(flightLog.depMin(idx));
    idx = idx(ord);

    for k = 1:(numel(idx)-1)
        i1 = idx(k);
        i2 = idx(k+1);

        if flightLog.depMin(i2) < flightLog.arrMin(i1)
            pilotViolations = pilotViolations + 1;
            pilotViolationDetails{end+1,1} = sprintf( ...
                'Pilot %d overlap: flight %d to %d, dep %.2f < arr %.2f', ...
                p, i1, i2, flightLog.depMin(i2), flightLog.arrMin(i1)); %#ok<AGROW>
        end
    end
end

%% ============================================================
% 5) CHECK 3 — PILOT DAILY DUTY COMPLIANCE
% ============================================================

dutyViolations = 0;
dutyViolationDetails = {};
pilotDaysChecked = 0;

for p = pilotIDs(:)'
    idx = find(flightLog.pilotID == p);

    if isempty(idx)
        continue;
    end

    depDays = floor(flightLog.depMin(idx) / (24*60)) + 1;
    daysForPilot = unique(depDays);

    for d = daysForPilot(:)'
        pilotDaysChecked = pilotDaysChecked + 1;
        use = idx(depDays == d);
        dutySum = sum(flightLog.blockMin(use));

        if dutySum > cfg.maxDutyMin + 1e-9
            dutyViolations = dutyViolations + 1;
            dutyViolationDetails{end+1,1} = sprintf( ...
                'Pilot %d exceeded duty on day %d: %.2f min', p, d, dutySum); %#ok<AGROW>
        end
    end
end

%% ============================================================
% 6) CHECK 4 — OPERATING WINDOW COMPLIANCE
% ============================================================

windowViolations = 0;
windowViolationDetails = {};

depHour = mod(flightLog.depMin, 24*60) / 60;
badWindow = depHour < cfg.operatingStartHour | depHour >= cfg.operatingEndHour;
windowViolations = sum(badWindow);

if windowViolations > 0
    badIdx = find(badWindow);
    showN = min(10, numel(badIdx));

    for i = 1:showN
        j = badIdx(i);
        windowViolationDetails{end+1,1} = sprintf( ...
            'Flight %d departs at %.2f hr of day', j, depHour(j)); %#ok<AGROW>
    end
end

%% ============================================================
% 7) CHECK 5 — DEPARTURE CAP COMPLIANCE
% ============================================================

capViolations = 0;
capViolationDetails = {};

nodeDayHour = containers.Map('KeyType','char','ValueType','double');

for i = 1:logCount
    node = flightLog.originIdx(i);
    day  = floor(flightLog.depMin(i) / (24*60)) + 1;
    hr   = floor(mod(flightLog.depMin(i), 24*60) / 60) + 1;

    key = sprintf('%d_%d_%d', node, day, hr);

    if isKey(nodeDayHour, key)
        nodeDayHour(key) = nodeDayHour(key) + 1;
    else
        nodeDayHour(key) = 1;
    end
end

allKeys = keys(nodeDayHour);

for i = 1:numel(allKeys)
    key = allKeys{i};
    countVal = nodeDayHour(key);

    if countVal > cfg.capDepPerNodeHour
        capViolations = capViolations + 1;
        capViolationDetails{end+1,1} = sprintf( ...
            'Node-day-hour %s exceeded cap with %d departures', key, countVal); %#ok<AGROW>
    end
end

%% ============================================================
% 8) CHECK 6 — ROUTE FEASIBILITY / BLOCK CONSISTENCY
% ============================================================

routeViolations = 0;
routeViolationDetails = {};

if ~ismember('RouteID', routes.Properties.VariableNames)
    error('Shared routes table must contain RouteID');
end
if ~ismember('BlockMin', routes.Properties.VariableNames)
    error('Shared routes table must contain BlockMin');
end

routeMap = containers.Map('KeyType','double','ValueType','double');

for i = 1:height(routes)
    routeMap(routes.RouteID(i)) = routes.BlockMin(i);
end

for i = 1:logCount
    r = flightLog.routeID(i);

    if ~isKey(routeMap, r)
        routeViolations = routeViolations + 1;
        routeViolationDetails{end+1,1} = sprintf( ...
            'Flight %d uses missing route ID %d', i, r); %#ok<AGROW>
        continue;
    end

    expectedBlock = routeMap(r);
    actualBlock   = flightLog.blockMin(i);

    if abs(expectedBlock - actualBlock) > 1e-9
        routeViolations = routeViolations + 1;
        routeViolationDetails{end+1,1} = sprintf( ...
            'Flight %d route %d block mismatch: expected %.4f, got %.4f', ...
            i, r, expectedBlock, actualBlock); %#ok<AGROW>
    end
end

%% ============================================================
% 9) CHECK 7 — FULL-UNLOCK SENSITIVITY TEST
% ============================================================

unlockRecoveryPct = NaN;

if cfg.runFullUnlockTest
    fprintf('\nReading full-unlock sensitivity test result...\n');

    if isfile(cfg.unlockResultsPath)
        U = load(cfg.unlockResultsPath);

        if isfield(U, 'summary') && isfield(U.summary, 'totalFlights')
            unlockRecoveryPct = 100 * U.summary.totalFlights / modelBFlightsCompleted;
        else
            warning('Full-unlock results file found, but summary.totalFlights is missing.');
        end
    else
        warning('Full-unlock results file not found: %s', cfg.unlockResultsPath);
    end
end

%% ============================================================
% 10) CHECK 8 — MULTI-RUN STATISTICAL STABILITY
% ============================================================

sigmaFlightsPct   = NaN;
sigmaUtilPct      = NaN;
sigmaDemandSatPct = NaN;

if cfg.runStabilityTest
    fprintf('Reading stability results across seeds: %s\n', mat2str(cfg.stabilitySeeds));

    totalFlightsVec = nan(numel(cfg.stabilitySeeds),1);
    utilVec         = nan(numel(cfg.stabilitySeeds),1);
    demandSatVec    = nan(numel(cfg.stabilitySeeds),1);

    for s = 1:numel(cfg.stabilitySeeds)
        seedVal  = cfg.stabilitySeeds(s);
        seedPath = fullfile(cfg.exportFolder, sprintf('ModelC_seed_%d.mat', seedVal));

        if isfile(seedPath)
            R = load(seedPath);

            if isfield(R, 'summary')
                if isfield(R.summary, 'totalFlights')
                    totalFlightsVec(s) = R.summary.totalFlights;
                end
                if isfield(R.summary, 'avgUtilisationPct')
                    utilVec(s) = R.summary.avgUtilisationPct;
                end
                if isfield(R.summary, 'demandSatisfactionPct')
                    demandSatVec(s) = R.summary.demandSatisfactionPct;
                end
            else
                warning('Seed file %d found but summary struct is missing.', seedVal);
            end
        else
            warning('Seed results file not found for seed %d: %s', seedVal, seedPath);
        end
    end

    goodFlights = ~isnan(totalFlightsVec);
    goodUtil    = ~isnan(utilVec);
    goodDemand  = ~isnan(demandSatVec);

    if nnz(goodFlights) >= 2
        sigmaFlightsPct = 100 * std(totalFlightsVec(goodFlights)) / mean(totalFlightsVec(goodFlights));
    end
    if nnz(goodUtil) >= 2
        sigmaUtilPct = 100 * std(utilVec(goodUtil)) / mean(utilVec(goodUtil));
    end
    if nnz(goodDemand) >= 2
        sigmaDemandSatPct = 100 * std(demandSatVec(goodDemand)) / mean(demandSatVec(goodDemand));
    end
end

%% ============================================================
% 11) PRINT VALIDATION SUMMARY
% ============================================================

fprintf('\n================ VALIDATION RESULTS ================\n');
printCheck('Check 1 — Aircraft non-overlap', aircraftViolations == 0, ...
    sprintf('(%d violations / %d flights)', aircraftViolations, logCount));

printCheck('Check 2 — Pilot non-overlap', pilotViolations == 0, ...
    sprintf('(%d violations / %d flights)', pilotViolations, logCount));

printCheck('Check 3 — Daily duty compliance', dutyViolations == 0, ...
    sprintf('(%d violations / %d pilot-days)', dutyViolations, pilotDaysChecked));

printCheck('Check 4 — Operating window', windowViolations == 0, ...
    sprintf('(%d violations / %d flights)', windowViolations, logCount));

printCheck('Check 5 — Departure cap', capViolations == 0, ...
    sprintf('(%d violations / %d node-day-hours checked)', capViolations, numel(allKeys)));

printCheck('Check 6 — Route feasibility', routeViolations == 0, ...
    sprintf('(%d violations / %d flights)', routeViolations, logCount));

if ~isnan(unlockRecoveryPct)
    fprintf('Check 7 — Full-unlock recovery      : %.2f %% of Model B throughput recovered\n', unlockRecoveryPct);
else
    fprintf('Check 7 — Full-unlock recovery      : NOT RUN / NOT AVAILABLE\n');
end

if ~isnan(sigmaFlightsPct) || ~isnan(sigmaUtilPct) || ~isnan(sigmaDemandSatPct)
    fprintf('Check 8 — Statistical stability     : sigma(flights)=%.2f %% | sigma(util)=%.2f %% | sigma(demand_sat)=%.2f %%\n', ...
        sigmaFlightsPct, sigmaUtilPct, sigmaDemandSatPct);
else
    fprintf('Check 8 — Statistical stability     : NOT RUN / NOT AVAILABLE\n');
end

fprintf('====================================================\n\n');

%% ============================================================
% 12) OPTIONAL: SHOW FIRST FEW VIOLATIONS
% ============================================================

showFirstFew('Aircraft overlap examples', aircraftViolationDetails);
showFirstFew('Pilot overlap examples', pilotViolationDetails);
showFirstFew('Duty violation examples', dutyViolationDetails);
showFirstFew('Operating window examples', windowViolationDetails);
showFirstFew('Departure cap examples', capViolationDetails);
showFirstFew('Route feasibility examples', routeViolationDetails);

%% ============================================================
% LOCAL FUNCTIONS
% ============================================================

function printCheck(label, isPass, detail)
    if isPass
        fprintf('%-38s : PASS %s\n', label, detail);
    else
        fprintf('%-38s : FAIL %s\n', label, detail);
    end
end

function showFirstFew(titleStr, cellArrayIn)
    if isempty(cellArrayIn)
        return;
    end

    fprintf('%s:\n', titleStr);
    n = min(5, numel(cellArrayIn));

    for i = 1:n
        fprintf('  - %s\n', cellArrayIn{i});
    end

    fprintf('\n');
end
