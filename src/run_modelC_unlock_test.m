scriptFolder = fileparts(mfilename('fullpath'));
if isempty(scriptFolder)
    scriptFolder = pwd;
end

clear modelC_override
modelC_override = struct();
modelC_override.maxDutyMin = 99999;
modelC_override.exportFigures = false;
modelC_override.makeFigures = false;

fleet_sheduling_system_model_C

srcFile = fullfile(scriptFolder, 'ModelC_Results.mat');
dstFile = fullfile(scriptFolder, 'ModelC_Unlock_Results.mat');

if ~isfile(srcFile)
    error('ModelC_Results.mat was not created. Expected file:\n%s', srcFile);
end

copyfile(srcFile, dstFile);
fprintf('Saved unlock result to:\n%s\n', dstFile);

clear modelC_override
