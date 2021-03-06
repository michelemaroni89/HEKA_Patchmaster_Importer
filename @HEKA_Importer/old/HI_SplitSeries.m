function obj = HI_SplitSeries(obj,data,varargin)

% HI_SplitSeries.m
% This function takes the collapsed data set (dCollapse) and splits it by
% group and series, assigning these as fields into the struct.
%
% EXAMPLE:
%   [structA] = SplitSeries(tree, data, saveName, structA)
%   [structA] = SplitSeries(tree, data, saveName, structA, stimTree)
%
% INPUTS:
%   tree        struct          The metadata tree, from importing a HEKA
%                               Patchmaster .dat file.
%
%   data        cell            A 1xm cell containing all series and traces
%                               from all channels, as output by
%                               ImportHEKAtoMat() and collapsed by
%                               ImportPatchData().
%
%   saveName    char            The name of the file from which the data
%                               was imported, the date by default.
%
%   structA     struct          The output data structure to which new
%                               fields will be appended. May be empty.
%
% OPTIONAL INPUTS:
%   stimTree    cell            The stimulus metadata tree, from importing
%                               a .dat file.
%
% OUTPUTS:
%   structA     struct          Output data structure in same format, with
%                               newly appended fields representing groups.
%                               Each group is a struct, containing the
%                               original filename, the list of pgfs, and
%                               the data in a cell of dimensions (series,
%                               channel) for that group.
%
% Created by Sammy Katta on 27 May 2014.
% Modified by Christian Keine 01/2019.

P = inputParser;
P.addRequired('data');

P.parse(data,varargin{:});

stimTree = obj.trees.stimTree;
dataTree = obj.trees.dataTree;

% Find which rows in tree contain group, series, and sweep metadata
grLoc = find(~cellfun('isempty',dataTree(:,2)));
seLoc = find(~cellfun('isempty',dataTree(:,3)));

if ~isempty(stimTree)
	stLoc = find(~cellfun('isempty',stimTree(:,2)));
	
	% The number of entries with stimulus parameters should match the total
	% number of series.
	if length(seLoc) ~= length(stLoc)
		fprintf('%s stimulus data does not match total number of series\n', saveName)
		return
	end
end

% Figure out how many series are in each group/biological cell by pulling
% the SeSeriesCount field for the last series in the group, and initialize
% a cell array of that length to hold data from that group
serTot = 1;
% traceTot = 1;
dataRaw = cell(size(grLoc));
SR = cell(size(grLoc));
chNames = cell(size(grLoc));

for iGr = 1:length(grLoc)
	% Strip hyphens/other characters that are invalid in field names
	currGr = matlab.lang.makeValidName(dataTree{grLoc(iGr),2}.GrLabel);
	
	% Find number of series in each group but don't get tripped up by the
	% last group.
	if iGr<length(grLoc)
		nSer = length([dataTree{grLoc(iGr):grLoc(iGr+1),3}]);
		%         nSer = tree{seLoc(find(seLoc<grLoc(iGr+1),1,'last')),3}.SeSeriesCount;
	else
		nSer = length([dataTree{grLoc(iGr):end,3}]);
		%         nSer = tree{seLoc(end),3}.SeSeriesCount;
	end
	
	% Initialize cell array with space for 6 channels worth of data from a
	% given series. For series where fewer than 6 channels are recorded,
	% the cells in the last few rows will remain empty.
% 	grpData = cell(nSer,1);
	grpProt = cell(1,nSer);
	grpType = cell(nSer,1);
	grpUnit = cell(nSer,1);
	grpFs = cell(1,nSer);
	grpTimes = cell(1,nSer);
	grpHolds = cell(1,nSer);
	grpStim = cell(1,nSer);
	
	% Now let's figure out how many channels each series has and move the
	% corresponding data into our cell array.
	for iSer = 1:nSer
		
		% Name of pgf stim file used in each series
		grpProt{iSer} = dataTree{seLoc(serTot),3}.SeLabel;
		grpTimes{1,iSer} = dataTree{seLoc(serTot),3}.SeTime;
		grpFs{iSer} = 1/dataTree{seLoc(serTot)+2,5}.TrXInterval;
		grpHolds{iSer} = dataTree{seLoc(serTot),3}.SeAmplifierState.E9CCIHold;
		
		% Start at first trace in a series and move down until you hit a
		% blank to count number of channels/traces (this is not recorded in
		% either sweep or trace metadata, and is necessary for prying apart
		% multiple channels in one series)
		isTrace = 1;
		nChan = 0;
		chanType = cell(6,1);
		chanUnit = cell(6,1);
		
		while isTrace == 1
			if seLoc(serTot)+2+nChan > size(dataTree,1) ||...
					isempty(dataTree{seLoc(serTot)+2+nChan,5})
				isTrace = 0;
			else
				nChan = nChan + 1;
				chanType{nChan} = matlab.lang.makeValidName(dataTree{seLoc(serTot)+1+nChan,5}.TrLabel);
				chanUnit{nChan} = dataTree{seLoc(serTot)+1+nChan,5}.TrYUnit;
			end
		end
		
		% Assign data to proper location in cell array for that group.
		% If there are multiple channels/traces per sweep for a given
		% series, Patchmaster stores them as separate series, one after
		% another, i.e., if the real series 5 recorded both current and
		% voltage, data(5) will contain the current and data(6) will
		% contain the voltage.
		
		% STRIP DOWN TO ACTUAL NUMBER OF CHANNELS AND REMOVE EMPTY CELLS
		% FOR RESHAPING LATER
		
		chanType = chanType(1:nChan,:);
		chanUnit = chanUnit(1:nChan,:);
		

		% GET CHANNEL TYPE/NAME AND UNITS
		grpType{iSer} = reshape(chanType,1,nChan);
		grpUnit{iSer} = reshape(chanUnit,1,nChan);
		
		if ~isempty(stimTree)
			% Pull out the relevant section of the stimTree for the series at
			% hand. nChan may not be the same for stimTree if you have channels
			% with DA output but no *stored* AD input (i.e., more channels in
			% stimTree than in dataTree).
			try
				stLocEnd = stLoc(serTot+1)-1;
			catch
				stLocEnd = size(stimTree,1);
			end
			
			grpStim{iSer} = stimTree(stLoc(serTot):stLocEnd,2:4);
			
		end
		
		% Move on to the next round
		serTot = serTot+1;
	end
	
	% Save data to the appropriate group in the nested output struct.
	ephysData.(currGr).data = data{iGr};
	ephysData.(currGr).protocols = grpProt;
	ephysData.(currGr).channel = grpType;
	ephysData.(currGr).dataunit = grpUnit;
	ephysData.(currGr).samplingFreq = grpFs;
	ephysData.(currGr).startTimes = grpTimes;
	ephysData.(currGr).ccHold = grpHolds;
	
	if ~isempty(stimTree)
		ephysData.(currGr).stimTree = grpStim;
	end
	
	%% ADD MINIMUM RANDOM NUMBER TO AVOID DISCRETIZATION; ADD TO ALL CHANNELS
	addEPS = @(x) x+randn(size(x))*eps;
	
	
	for iSer=1:nSer
		ephysData.(currGr).data{iSer} = cellfun(addEPS,ephysData.(currGr).data{iSer},'UniformOutput',false);
	end
	
	dataRaw{iGr,:} = ephysData.(currGr).data;
	SR{iGr,:} =  reshape([ephysData.(currGr).samplingFreq{:}], numel([ephysData.(currGr).samplingFreq{:}]),1);
	chNames{iGr,:} = grpType;
	
end

obj.RecTable.dataRaw = vertcat(dataRaw{:});
obj.RecTable.SR = vertcat(SR{:});
obj.RecTable.chNames = vertcat(chNames{:});
obj.RecTable = struct2table(obj.RecTable);

end
