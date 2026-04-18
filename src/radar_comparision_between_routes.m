%% MODEL B vs MODEL C - FINAL COMPARISON PACK
% Dissertation-ready comparison visuals
%
% Creates:
% Figure 9  - Normalised radar comparison
% Figure 10 - Horizontal delta / waterfall comparison
%
% Notes:
% - White background
% - Times New Roman
% - No MATLAB titles inside figures
% - Export-ready PNGs
% - Model B is treated as the unconstrained upper bound baseline
% - For demand satisfaction and low-spill performance, Model B = 100%


clear; clc; close all;
set(0,'DefaultFigureWindowStyle','normal');

%% ============================================================
% 1) EXPORT SETTINGS
% ============================================================

thisFile = mfilename('fullpath');
if isempty(thisFile)
    cfg.exportFolder = pwd;
else
    cfg.exportFolder = fileparts(thisFile);
end

cfg.exportFigures = true;

cfg.figRadarNum    = 9;
cfg.figRadarName   = "Normalised_Radar_Comparison_ModelB_ModelC";

cfg.figDeltaNum    = 10;
cfg.figDeltaName   = "Delta_Waterfall_Comparison_ModelB_ModelC";

%% ============================================================
% 2) INPUT RESULTS
% ============================================================

% ---------------- MODEL B ----------------
% Model B is the unconstrained upper bound baseline
modelB.flights_completed       = 134776;
modelB.num_aircraft            = 1500;
modelB.flights_per_aircraft    = 89.85;
modelB.avg_utilisation_pct     = 80.05;
modelB.avg_block_hours_per_ac  = 89.66;

% For comparison purposes, Model B is treated as:
modelB.network_coverage_pct       = 100.00;
modelB.demand_satisfaction_pct    = 100.00;
modelB.spill_rate_pct             = 0.00;
modelB.low_spill_performance_pct  = 100.00;

% ---------------- MODEL C ----------------
modelC.flights_completed          = 41362;
modelC.num_aircraft               = 1500;
modelC.passengers_served          = 42681;
modelC.passengers_spilled         = 155307;
modelC.demand_satisfaction_pct    = 21.56;
modelC.spill_rate_pct             = 78.44;
modelC.network_coverage_pct       = 46.43;
modelC.flights_per_aircraft       = 27.57;
modelC.avg_aircraft_flight_hr     = 21.35;
modelC.avg_pilot_duty_hr          = 20.34;

%% ============================================================
% 3) DERIVED METRICS
% ============================================================

% Same operating basis as Model B: 06:00–22:00 over 7 days
totalOperatingHours = 16 * 7;

modelC.avg_utilisation_pct        = 100 * modelC.avg_aircraft_flight_hr / totalOperatingHours;
modelC.low_spill_performance_pct  = 100 - modelC.spill_rate_pct;

%% ============================================================
% 4) NORMALISED METRICS FOR RADAR
% ============================================================

metricLabelsNorm = { ...
    'Flights per Aircraft', ...
    'Average Utilisation', ...
    'Aircraft Flight Hours', ...
    'Network Coverage', ...
    'Demand Satisfaction', ...
    'Low Spill Performance'};

normB = [1, 1, 1, 1, 1, 1];

normC = [ ...
    modelC.flights_per_aircraft / modelB.flights_per_aircraft, ...
    modelC.avg_utilisation_pct / modelB.avg_utilisation_pct, ...
    modelC.avg_aircraft_flight_hr / modelB.avg_block_hours_per_ac, ...
    modelC.network_coverage_pct / 100, ...
    modelC.demand_satisfaction_pct / 100, ...
    modelC.low_spill_performance_pct / 100];

%% ============================================================
% 5) DELTA / WATERFALL METRICS
% ============================================================

deltaLabels = { ...
    'Flights per Aircraft', ...
    'Fleet Utilisation (%)', ...
    'Aircraft Flight Hours', ...
    'Network Coverage (%)', ...
    'Demand Satisfaction (%)', ...
    'Spill Rate (%)'};

baselineB = [ ...
    modelB.flights_per_aircraft, ...
    modelB.avg_utilisation_pct, ...
    modelB.avg_block_hours_per_ac, ...
    modelB.network_coverage_pct, ...
    modelB.demand_satisfaction_pct, ...
    modelB.spill_rate_pct];

valueC = [ ...
    modelC.flights_per_aircraft, ...
    modelC.avg_utilisation_pct, ...
    modelC.avg_aircraft_flight_hr, ...
    modelC.network_coverage_pct, ...
    modelC.demand_satisfaction_pct, ...
    modelC.spill_rate_pct];

deltaVal = valueC - baselineB;

%% ============================================================
% 6) FIGURE 9 - RADAR CHART
% ============================================================

nMetrics = numel(metricLabelsNorm);
theta = linspace(0, 2*pi, nMetrics + 1);

rB = [normB, normB(1)];
rC = [normC, normC(1)];

fig9 = figure( ...
    'Color', 'w', ...
    'Name', sprintf('Figure_%d', cfg.figRadarNum), ...
    'Units', 'centimeters', ...
    'Position', [2 2 18 15], ...
    'Toolbar', 'none', ...
    'MenuBar', 'none', ...
    'Resize', 'off');

pax = polaraxes(fig9);
hold(pax, 'on');

pax.FontName = 'Times New Roman';
pax.FontSize = 11;
pax.LineWidth = 1.0;
pax.ThetaZeroLocation = 'top';
pax.ThetaDir = 'clockwise';
pax.RLim = [0 1.05];
pax.RTick = 0:0.2:1.0;
pax.GridAlpha = 0.35;

hB = polarplot(pax, theta, rB, ...
    'LineWidth', 2.2, ...
    'Color', [0.15 0.40 0.75]);

hC = polarplot(pax, theta, rC, ...
    'LineWidth', 2.2, ...
    'Color', [0.90 0.45 0.10]);

[xB, yB] = pol2cart(theta, rB);
[xC, yC] = pol2cart(theta, rC);

patch('XData', xB, 'YData', yB, ...
      'FaceColor', [0.15 0.40 0.75], ...
      'FaceAlpha', 0.10, ...
      'EdgeColor', 'none');

patch('XData', xC, 'YData', yC, ...
      'FaceColor', [0.90 0.45 0.10], ...
      'FaceAlpha', 0.13, ...
      'EdgeColor', 'none');

uistack(hB, 'top');
uistack(hC, 'top');

pax.ThetaTick = rad2deg(theta(1:end-1));
pax.ThetaTickLabel = metricLabelsNorm;

legend(pax, {'Model B','Model C'}, ...
    'Location', 'southoutside', ...
    'Orientation', 'horizontal', ...
    'Box', 'off', ...
    'FontName', 'Times New Roman', ...
    'FontSize', 10);

hold(pax, 'off');

%% ============================================================
% 7) FIGURE 10 - HORIZONTAL DELTA / WATERFALL STYLE CHART
% ============================================================

fig10 = figure( ...
    'Color', 'w', ...
    'Name', sprintf('Figure_%d', cfg.figDeltaNum), ...
    'Units', 'centimeters', ...
    'Position', [2 2 24 14], ...
    'Toolbar', 'none', ...
    'MenuBar', 'none', ...
    'Resize', 'off');

ax10 = axes(fig10);
hold(ax10, 'on');
box(ax10, 'on');

styleAxes(ax10);

yPos = 1:numel(deltaLabels);

% Baseline bars (Model B)
for i = 1:numel(deltaLabels)
    rectangle(ax10, ...
        'Position', [0, yPos(i)-0.32, baselineB(i), 0.22], ...
        'FaceColor', [0.15 0.40 0.75], ...
        'EdgeColor', 'k', ...
        'LineWidth', 0.6);
end

% Delta bars
for i = 1:numel(deltaLabels)
    x0 = min(baselineB(i), valueC(i));
    w  = abs(deltaVal(i));

    if strcmp(deltaLabels{i}, 'Spill Rate (%)')
        deltaColor = [0.20 0.65 0.25];   % improvement bar goes upward for spill increase visual distinction
    else
        deltaColor = [0.80 0.20 0.20];
    end

    rectangle(ax10, ...
        'Position', [x0, yPos(i)-0.08, w, 0.22], ...
        'FaceColor', deltaColor, ...
        'EdgeColor', 'k', ...
        'LineWidth', 0.6);
end

% Model C endpoint markers / small bars
for i = 1:numel(deltaLabels)
    rectangle(ax10, ...
        'Position', [valueC(i)-0.4, yPos(i)+0.16, 0.8, 0.16], ...
        'FaceColor', [0.90 0.45 0.10], ...
        'EdgeColor', 'k', ...
        'LineWidth', 0.6);
end

% Connector lines
for i = 1:numel(deltaLabels)
    plot(ax10, [baselineB(i) valueC(i)], [yPos(i)+0.03 yPos(i)+0.24], ...
        '-', 'Color', [0.35 0.35 0.35], 'LineWidth', 0.8);
end

% Text annotations
for i = 1:numel(deltaLabels)
    % Left baseline label
    text(ax10, baselineB(i), yPos(i)-0.42, sprintf('B: %.2f', baselineB(i)), ...
        'HorizontalAlignment', 'right', ...
        'VerticalAlignment', 'middle', ...
        'FontName', 'Times New Roman', ...
        'FontSize', 9, ...
        'Color', [0.10 0.10 0.10]);

    % Right endpoint label
    text(ax10, valueC(i), yPos(i)+0.46, sprintf('C: %.2f', valueC(i)), ...
        'HorizontalAlignment', 'left', ...
        'VerticalAlignment', 'middle', ...
        'FontName', 'Times New Roman', ...
        'FontSize', 9, ...
        'Color', [0.10 0.10 0.10]);

    % Delta label
    if deltaVal(i) >= 0
        deltaText = sprintf('\\Delta +%.2f', deltaVal(i));
    else
        deltaText = sprintf('\\Delta %.2f', deltaVal(i));
    end

    text(ax10, max(baselineB(i), valueC(i)) + 2.2, yPos(i)+0.06, deltaText, ...
        'HorizontalAlignment', 'left', ...
        'VerticalAlignment', 'middle', ...
        'FontName', 'Times New Roman', ...
        'FontSize', 9.5, ...
        'FontWeight', 'bold', ...
        'Color', [0.15 0.15 0.15]);
end

ax10.YTick = yPos;
ax10.YTickLabel = deltaLabels;
ax10.YDir = 'reverse';

xlabel(ax10, 'Absolute metric value', ...
    'FontName', 'Times New Roman', 'FontSize', 12);

% give extra room on right for delta labels
xmax = max([baselineB, valueC]) * 1.28;
xlim(ax10, [0 xmax]);

ax10.Position = [0.18 0.10 0.77 0.82];

% Legend using dummy lines
p1 = plot(ax10, nan, nan, '-', 'Color', [0.15 0.40 0.75], 'LineWidth', 6);
p2 = plot(ax10, nan, nan, '-', 'Color', [0.80 0.20 0.20], 'LineWidth', 6);
p3 = plot(ax10, nan, nan, '-', 'Color', [0.20 0.65 0.25], 'LineWidth', 6);
p4 = plot(ax10, nan, nan, '-', 'Color', [0.90 0.45 0.10], 'LineWidth', 6);

legend(ax10, [p1 p2 p3 p4], ...
    {'Model B baseline','Reduction delta','Spill increase','Model C endpoint'}, ...
    'Location', 'southoutside', ...
    'Orientation', 'horizontal', ...
    'Box', 'off', ...
    'FontName', 'Times New Roman', ...
    'FontSize', 10);

hold(ax10, 'off');

%% ============================================================
% 8) SUMMARY TABLE
% ============================================================

ResultsTable = table( ...
    deltaLabels', ...
    baselineB', ...
    valueC', ...
    deltaVal', ...
    'VariableNames', {'Metric','ModelB_Baseline','ModelC_Value','Delta_C_minus_B'});

disp(' ');
disp('================ COMPARISON SUMMARY =====================');
disp(ResultsTable);
disp('=========================================================');

%% ============================================================
% 9) EXPORT FIGURES
% ============================================================

if cfg.exportFigures
    exportFigurePNG(fig9,  cfg.figRadarNum, cfg.figRadarName, cfg.exportFolder);
    exportFigurePNG(fig10, cfg.figDeltaNum, cfg.figDeltaName, cfg.exportFolder);
end

%% ============================================================
% LOCAL FUNCTIONS
% ============================================================

function styleAxes(ax)
    ax.Color = 'w';
    ax.FontName = 'Times New Roman';
    ax.FontSize = 11;
    ax.LineWidth = 1.0;
    ax.XGrid = 'on';
    ax.YGrid = 'off';
    ax.GridColor = [0.84 0.84 0.84];
    ax.GridAlpha = 0.65;
    ax.Layer = 'top';
end

function exportFigurePNG(figHandle, figNumber, figName, exportFolder)
    if ~exist(exportFolder, 'dir')
        mkdir(exportFolder);
    end

    cleanName = regexprep(char(figName), '[^\w\s-]', '');
    cleanName = strtrim(cleanName);
    cleanName = regexprep(cleanName, '\s+', '_');

    fileName = sprintf('Figure_%d_%s.png', figNumber, cleanName);
    fullPath = fullfile(exportFolder, fileName);

    exportgraphics(figHandle, fullPath, ...
        'Resolution', 300, ...
        'BackgroundColor', 'white');

    fprintf('Exported: %s\n', fileName);
end


