function HI_loadHEKAFile(obj)
% CHECK IF FILE EXISTS

% P=inputParser;
% P.addParameter('update',false,@islogical)
% P.addParameter('fromVersion',[],@isnumeric)

% P.parse(varargin{:});
% opt = P.Results;


if ~exist(obj.opt.filepath,'file')
    warning('File not found'); return
end

   
    
    % CREATE PRELIM STRUCTURE FOR EPHYS DATA
    ephysData = struct();
    
    %% CALL IMPORT FUNCTION
    [tree, data,stimTree, solTree] = obj.HI_ImportHEKAtoMat;
    
    for i = length(data):-1:1
        dCollapse(1:length(data{i}))= data{i};
    end
    
    
    [~,saveName] = fileparts(obj.opt.filepath);
    
    % Split the data into series by recording name, etc. and assign into
    % the final data structure
    
    % TODO: DOUBLE CHECK FOR SAVE OPTIONS
    ephysData = obj.HI_SplitSeries(tree, dCollapse, ephysData, saveName,stimTree);
    
    
    obj.HI_extractHEKADataTree(tree);
    obj.HI_extractHEKAStimTree(stimTree);
    obj.HI_extractHEKASolutionTree(solTree);


    f = fields(ephysData);

    dataRaw = cell(size(f));
    SR = cell(size(f));
for iExp = 1:numel(f)
    dataRaw{iExp,:} = reshape(ephysData.(f{iExp}).data(1,:),numel(ephysData.(f{iExp}).data(1,:)),1);
    SR{iExp,:} =  reshape([ephysData.(f{iExp}).samplingFreq{:}], numel([ephysData.(f{iExp}).samplingFreq{:}]),1); 
end

    obj.RecTable.dataRaw = vertcat(dataRaw{:});
    obj.RecTable.SR = vertcat(SR{:});
    
    %% ADD MINIMUM RANDOM NUMBER TO AVOID DISCRETIZATION
    for i=1:length(t.dataRaw)
        t.dataRaw{i} = t.dataRaw{i}+randn(size(t.dataRaw{i}))*eps;
       
    end
    
    
    % bundle data in container
    %         keyset = {'data','tree','stimTree','images','recID','fileID','notebook','solTree','solutions'};
    %         valueset = {t,tree,stimTree,[],obj.recID,obj.MatFileID,{tree{2,2}.GrText;tree{3,3}.SeComment},solTree,solutions};
    %
    
%     solFields = fieldnames(solutions);
%     solNB = cell(size(solFields));
%     offset = 30;
%     for iS = 1:numel(solNB)
%         solNB{iS}{1,:} = solFields{iS};
%         solNB{iS}{2,:} = char(32);
%         for iC = 3:size(solutions.(solFields{iS}),1)
%            chemNameL = strlength(solutions.(solFields{iS}){iC-2,'Chemical'}); 
%            solNB{iS}{iC,:} =  solutions.(solFields{iS}){iC-2,'Chemical'}+repmat(char(32),1,offset-chemNameL)+solutions.(solFields{iS}){iC-2,'Concentration'};
%         end
%       solNB{iS}{end+1,:} = char(32);
%         
%     end
%     notebook = {tree{2,2}.GrText;tree{3,3}.SeComment;vertcat(solNB{:})};
%     
    notebook = {tree{2,2}.GrText;tree{3,3}.SeComment};
    trees = struct('dataTree',{tree},'stimTree',{stimTree},'solutionTree',{solTree});
    keyset = {'data','trees','images','recID','fileID','notebook','solutions','fileVersion'};
    valueset = {t,trees,[],obj.recID,obj.MatFileID,notebook,solutions,1.1};
    obj.R = containers.Map(keyset,valueset);
    
% else % LOAD ONLY SOLUTION FILE
    
%     switch opt.fromVersion
%         case 0
%             [~, ~,~, solTree] = obj.PA_ImportHEKAtoMat;
%             solutions = obj.PA_extractHEKASolutionTree(solTree);
%             trees = struct('dataTree',{obj.R('tree')},'stimTree',{obj.R('stimTree')},'solutionTree',{solTree});
%             
%             keyset = {'fileVersion','solutions','trees'};
%             valueset = {1.1,solutions,trees};
%             
%             for iKey = 1:numel(keyset)
%                 obj.R(keyset{iKey}) = valueset{iKey};
%             end
%             
%             remove(obj.R,{'tree','stimTree'})
%             
%             disp(['>> File updated to version ',n2s(obj.R('fileVersion'))])
%         otherwise
%             warning('Source file version not specified.')
%     end
    
end
