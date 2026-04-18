scriptFolder = fileparts(mfilename('fullpath'));
if isempty(scriptFolder)
    scriptFolder = pwd;
end

seeds = [7 13 21 42 99];

for i = 1:numel(seeds)

    seedVal = seeds(i);

    % Check target file first, before running
    targetFile = fullfile(scriptFolder, sprintf('ModelC_seed_%d.mat', seedVal));
    if isfile(targetFile)
        fprintf('Skipping seed %d (already exists)\n', seedVal);
        continue;
    end

    clear modelC_override

    modelC_override = struct();
    modelC_override.seed = seedVal;
    modelC_override.exportFigures = false;
    modelC_override.makeFigures = false;

    fprintf('\nRunning Model C with seed %d...\n', seedVal);

    fleet_sheduling_system_model_C

    % Define these AFTER Model C returns, because Model C clears workspace vars
    srcFile = fullfile(scriptFolder, 'ModelC_Results.mat');
    dstFile = fullfile(scriptFolder, sprintf('ModelC_seed_%d.mat', seedVal));

    if ~isfile(srcFile)
        error('ModelC_Results.mat was not created for seed %d. Expected file:\n%s', seedVal, srcFile);
    end

    copyfile(srcFile, dstFile);
    fprintf('Saved seed %d -> %s\n', seedVal, dstFile);
end    

