function HI_loadHEKAFile(obj)
% Function to load HEKA PATCHMASTER files.
% Takes HEKA_IMPORTER object as input, loads PATCHMASTER file and extract
% data create RecTable and tree structure. Check the functions listed below
% for more information.
% 
% See also	HEKA_Importer 
% 			HEKA_Importer.HI_SplitSeries
% 			HEKA_Importer.HI_ImportHEKAtoMat 			
% 			HEKA_Importer.HI_extractHEKASolutionTree
% 			HEKA_Importer.HI_extractHEKAStimTree
% 			HEKA_Importer.HI_extractHEKADataTree

% CHECK IF FILE EXISTS
if ~exist(obj.opt.filepath,'file')
    warning('File not found'); return
end
  
    %% CALL IMPORT FUNCTION
    data = obj.HI_ImportHEKAtoMat;

%     for i = length(data):-1:1
%         dCollapse(1:length(data{i}))= data{i};
%     end
    
    % EXTRACT DATA AND SORT INFORMATION FROM TREE STRUCTURES
    obj.HI_SplitSeries(data);
    obj.HI_extractHEKADataTree;
    obj.HI_extractHEKAStimTree;
    obj.HI_extractHEKASolutionTree;


    
end
