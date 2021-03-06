function obj=HI_ImportHEKAtoMat(obj)
% ImportHEKA imports HEKA PatchMaster and ChartMaster .DAT files
% Filepath is taken from the input object.
%
% ImportHEKA has been tested with Windows generated .DAT files on Windows,
% Linux and Mac OS10.4.
%
% Both bundled and unbundled data files are supported. If your files are
% unbundled, they must all be in the same folder.
%
% Details of the HEKA file format are available from
%       ftp://server.hekahome.de/pub/FileFormat/Patchmasterv9/
%
%--------------------------------------------------------------------------
% Author: Malcolm Lidierth 12/09
% Copyright � The Author & King's College London 2009-
%--------------------------------------------------------------------------

% Revisions
% 17.04.10  TrXUnit: see within
% 28.11.11  TrXUnit: see within
% 15.08.12  Updated to support interleaved channels and PatchMaster 2.60
%               files dated 24-Jan-2011 onwards.
% 19.05.13 Modified by Samata Katta to output Matlab variable containing data
% 12.08.15 Don't save *.kcl file (line 793 commented out).
% 03.07.17 Modified by Samata Katta to read in stimulus parameters from
% .pgf section of .dat file.
% 01.01.2019 Modified by Christian Keine to read solution parameters from
% .sol section of .dat file.
% 04.02.2019: combine readout of dataTree, stimTree and solTree.
%
% See also	HEKA_Importer
% 			HEKA_Importer.HI_loadHEKAFile
% 			HEKA_Importer.HI_extractHEKASolutionTree
% 			HEKA_Importer.HI_extractHEKAStimTree
% 			HEKA_Importer.HI_extractHEKADataTree



[pathname, filename, ext]=fileparts(obj.opt.filepath);

% Open file and get bundle header. Assume little-endian to begin with
endian='ieee-le';
fh=fopen(obj.opt.filepath, 'r', endian);
[bundle, littleendianflag, isBundled]=getBundleHeader(fh);

% Big endian so repeat process
if ~isempty(littleendianflag) && littleendianflag==false
	fclose(fh);
	endian='ieee-be';
	fh=fopen(obj.opt.filepath, 'r', endian);
	bundle=getBundleHeader(fh);
end

%% GET DATA, STIM AND SOLUTION TREE

fileExt = {'.pul','.pgf','.sol'};
treeName = {'dataTree','stimTree','solTree'};

for iidx = fileExt
	fileExist = true;
	if isBundled
		%     ext = {'.dat','.pul','.pgf','.amp','.sol',[],[],'.mrk','.mth','.onl'};
		ext={bundle.oBundleItems.oExtension};
		% Find the section of the dat file
		idx=strcmp(iidx, ext);%15.08.2012 - change from strmatch
		if any(idx) % check if section exists, e.g. will be empty when solution base was not active during recordings
			start=bundle.oBundleItems(idx).oStart;
		else
			fileExist = false;
		end
	else
		% Or open pulse file if not bundled
		fclose(fh);
		start=0;
		fh=fopen(fullfile(pathname, [filename, iidx{1}]), 'r', endian);
		if fh<0
			fileExist = false;
		end
	end
	
	% READ OUT TREE
	if fileExist
		fseek(fh, start, 'bof');
		Magic = fread(fh, 4, 'uint8=>char');
		Levels=fread(fh, 1, 'int32=>int32');
		Sizes=fread(fh, double(Levels), 'int32=>int32');
		Position=ftell(fh);
		
		% Get the tree structures form the file sections
		obj.trees.(treeName{strcmp(iidx, fileExt)})=getTree(fh, Sizes, Position, iidx{1});
	else
		obj.trees.(treeName{strcmp(iidx, fileExt)}) = [];
	end
end

%% GET DATA
if isBundled
	% Set offset for data
	idx=strcmp('.dat', ext);%15.08.2012 - change from strmatch
	start=bundle.oBundleItems(idx).oStart;
else
	% Or open data file if not bundled
	fclose(fh);
	fh=fopen(obj.opt.filepath, 'r', endian);
	start=bundle.BundleHeaderSize;
end

% Now set pointer to the start of the data the data
fseek(fh, start, 'bof');

% Get the group headers into a structure array
ngroup=1;
for k=1:size(obj.trees.dataTree,1)
	if ~isempty(obj.trees.dataTree{k, 2})
		grp_row(ngroup)=k;  %#ok<AGROW>
		ngroup=ngroup+1;
	end
end

% ADD MINIMUM RANDOM NUMBER TO AVOID DISCRETIZATION; ADD TO ALL CHANNELS
addEPS = @(x) x+randn(size(x))*eps;

% For each group
matData2 = cell(numel(grp_row),1);
dataRaw = cell(numel(grp_row),1);

for iGr = 1:numel(grp_row)
	matData2{iGr}=LocalImportGroup(fh, obj.trees.dataTree, iGr, grp_row);
	
	for iSer = 1:numel(matData2{iGr})
		dataRaw{iGr,:}{iSer,:} = cellfun(addEPS,matData2{iGr}{iSer},'UniformOutput',false);
	end
	
end

obj.RecTable.dataRaw = vertcat(dataRaw{:});
obj.RecTable = struct2table(obj.RecTable);

end

%--------------------------------------------------------------------------
function [h, littleendianflag, isBundled]=getBundleHeader(fh)
%--------------------------------------------------------------------------
% Get the bundle header from a HEKA .dat file
fseek(fh, 0, 'bof');
h.oSignature=deblank(fread(fh, 8, 'uint8=>char')');
switch h.oSignature
	case 'DATA'
		% Old format: nothing to do
		h.oVersion=[];
		h.oTime=[];
		h.oItems=[];
		h.oIsLittleEndian=[];
		h.oBundleItems(1:12)=[];
		h.BundleHeaderSize=0;
		isBundled=false;
	case {'DAT1' 'DAT2'}
		% Newer format
		h.oVersion=fread(fh, 32, 'uint8=>char')';
		h.oTime=fread(fh, 1, 'double');
		h.oItems=fread(fh, 1, 'int32=>int32');
		h.oIsLittleEndian=fread(fh, 1, 'uint8=>logical');
		h.BundleHeaderSize=256;
		switch h.oSignature
			case 'DAT1'
				h.oBundleItems=[];
				isBundled=false;
			case {'DAT2'}
				fseek(fh, 64, 'bof');
				for k=1:12
					h.oBundleItems(k).oStart=fread(fh, 1, 'int32=>int32');
					h.oBundleItems(k).oLength=fread(fh, 1, 'int32=>int32');
					h.oBundleItems(k).oExtension=deblank(fread(fh, 8, 'uint8=>char')');
					h.oBundleItems(k).BundleItemSize=16;
				end
				isBundled=true;
		end
	otherwise
		error('This legacy file format is not supported');
end
littleendianflag=h.oIsLittleEndian;

end


%--------------------------------------------------------------------------
function [Tree, Counter]=getTree(fh, Sizes, Position, ext)
%--------------------------------------------------------------------------
% Main entry point for loading tree
[Tree, Counter]=getTreeReentrant(fh, {}, Sizes, 0, Position, 0, ext);
end


function [Tree, Position, Counter]=getTreeReentrant(fh, Tree, Sizes, Level, Position, Counter, ext)
%--------------------------------------------------------------------------
% Recursive routine called from LoadTree

switch ext
	case '.pul'
		[Tree, Position, Counter, nchild]=getOneDataLevel(fh, Tree, Sizes, Level, Position, Counter);
	case '.pgf'
		[Tree, Position, Counter, nchild]=getOneStimLevel(fh, Tree, Sizes, Level, Position, Counter);
	case '.sol'
		[Tree, Position, Counter, nchild]=getOneSolutionLevel(fh, Tree, Sizes, Level, Position, Counter);
end

for k=1:double(nchild)
	[Tree, Position, Counter]=getTreeReentrant(fh, Tree, Sizes, Level+1, Position, Counter, ext);
end

end


%--------------------------------------------------------------------------
function [Tree, Position, Counter, nchild]=getOneDataLevel(fh, Tree, Sizes, Level, Position, Counter)
%--------------------------------------------------------------------------
% Gets one record of the tree and the number of children
[s, Counter]=getOneRecord(fh, Level, Counter);
Tree{Counter, Level+1}=s;
Position=Position+Sizes(Level+1);
fseek(fh, Position, 'bof');
nchild=fread(fh, 1, 'int32=>int32');
Position=ftell(fh);
end

%--------------------------------------------------------------------------
function [rec, Counter]=getOneRecord(fh, Level, Counter)
%--------------------------------------------------------------------------
% Gets one record
Counter=Counter+1;
switch Level
	case 0
		rec=getRoot(fh);
	case 1
		rec=getGroup(fh);
	case 2
		rec=getSeries(fh);
	case 3
		rec=getSweep(fh);
	case 4
		rec=getTrace(fh);
	otherwise
		error('Unexpected Level');
end
end

% The functions below return data as defined by the HEKA PatchMaster
% specification

%--------------------------------------------------------------------------
function p=getRoot(fh)
%--------------------------------------------------------------------------
p.RoVersion=fread(fh, 1, 'int32=>int32');
p.RoMark=fread(fh, 1, 'int32=>int32');%               =   4; (* INT32 *)
p.RoVersionName=deblank(fread(fh, 32, 'uint8=>char')');%        =   8; (* String32Type *)
p.RoAuxFileName=deblank(fread(fh, 80, 'uint8=>char')');%        =  40; (* String80Type *)
p.RoRootText=deblank(fread(fh, 400, 'uint8=>char')');% (* String400Type *)
p.RoStartTime=fread(fh, 1, 'double=>double') ;%        = 520; (* LONGREAL *)
p.RoStartTimeMATLAB=time2date(p.RoStartTime);
p.RoMaxSamples=fread(fh, 1, 'int32=>int32'); %        = 528; (* INT32 *)
p.RoCRC=fread(fh, 1, 'int32=>int32'); %                = 532; (* CARD32 *)
p.RoFeatures=fread(fh, 1, 'int16=>int16'); %           = 536; (* SET16 *)
p.RoFiller1=fread(fh, 1, 'int16=>int16');%         = 538; (* INT16 *)
p.RoFiller2=fread(fh, 1, 'int32=>int32');%         = 540; (* INT32 *)
p.RootRecSize= 544;
p=orderfields(p);

end

%--------------------------------------------------------------------------
function g=getGroup(fh)
%--------------------------------------------------------------------------
% Group
g.GrMark=fread(fh, 1, 'int32=>int32');%               =   0; (* INT32 *)
g.GrLabel=deblank(fread(fh, 32, 'uint8=>char')');%               =   4; (* String32Size *)
g.GrText=deblank(fread(fh, 80, 'uint8=>char')');%                =  36; (* String80Size *)
g.GrExperimentNumber=fread(fh, 1, 'int32=>int32');%   = 116; (* INT32 *)
g.GrGroupCount=fread(fh, 1, 'int32=>int32');%         = 120; (* INT32 *)
g.GrCRC=fread(fh, 1, 'int32=>int32');%                = 124; (* CARD32 *)
g.GroupRecSize=128;%     (* = 16 * 8 *)
g=orderfields(g);

end

%--------------------------------------------------------------------------
function s=getSeries(fh)
%--------------------------------------------------------------------------
s.SeMark=fread(fh, 1, 'int32=>int32');%               =   0; (* INT32 *)
s.SeLabel=deblank(fread(fh, 32, 'uint8=>char')');%              =   4; (* String32Type *)
s.SeComment=deblank(fread(fh, 80, 'uint8=>char')');%            =  36; (* String80Type *)
s.SeSeriesCount=fread(fh, 1, 'int32=>int32');%        = 116; (* INT32 *)
s.SeNumbersw=fread(fh, 1, 'int32=>int32');%       = 120; (* INT32 *)
s.SeAmplStateOffset=fread(fh, 1, 'int32=>int32');%    = 124; (* INT32 *)
s.SeAmplStateSeries=fread(fh, 1, 'int32=>int32');%    = 128; (* INT32 *)
s.SeSeriesType=fread(fh, 1, 'uint8=>uint8');%         = 132; (* BYTE *)

% Added 15.08.2012
s.SeUseXStart=logical(fread(fh, 1, 'uint8=>uint8'));%         = 133; (* BYTE *)

s.SeFiller2=fread(fh, 1, 'uint8=>uint8');%         = 134; (* BYTE *)
s.SeFiller3=fread(fh, 1, 'uint8=>uint8');%         = 135; (* BYTE *)
s.SeTime=fread(fh, 1, 'double=>double') ;%               = 136; (* LONGREAL *)
s.SeTimeMATLAB=time2date(s.SeTime);
s.SePageWidth=fread(fh, 1, 'double=>double') ;%          = 144; (* LONGREAL *)
for k=1:4
	s.SeSwUserParamDescr(k).Name=deblank(fread(fh, 32, 'uint8=>char')');%
	s.SeSwUserParamDescr(k).Unit=deblank(fread(fh, 8, 'uint8=>char')');%
end
s.SeFiller4=fread(fh, 32, 'uint8=>uint8');%         = 312; (* 32 BYTE *)
s.SeSeUserParams=fread(fh, 4, 'double=>double');%       = 344; (* ARRAY[0..3] OF LONGREAL *)
s.SeLockInParams=getSeLockInParams(fh);%       = 376; (* SeLockInSize = 96, see "Pulsed.de" *)
s.SeAmplifierState=getAmplifierState(fh);%     = 472; (* AmplifierStateSize = 400 *)
s.SeUsername=deblank(fread(fh, 80, 'uint8=>char')');%           = 872; (* String80Type *)
for k=1:4
	s.SeSeUserParamDescr(k).Name=deblank(fread(fh, 32, 'uint8=>char')');% (* ARRAY[0..3] OF UserParamDescrType = 4*40 *)
	s.SeSeUserParamDescr(k).Unit=deblank(fread(fh, 8, 'uint8=>char')');%
end
s.SeFiller5=fread(fh, 1, 'int32=>int32');%         = 1112; (* INT32 *)
s.SeCRC=fread(fh, 1, 'int32=>int32');%                = 1116; (* CARD32 *)

% Added 15.08.2012
s.SeSeUserParams2=fread(fh, 4, 'double=>double');
for k=1:4
	s.SeSeUserParamDescr2(k).Name=deblank(fread(fh, 32, 'uint8=>char')');%
	s.SeSeUserParamDescr2(k).Unit=deblank(fread(fh, 8, 'uint8=>char')');%
end
s.SeScanParams=fread(fh, 96, 'uint8=>uint8');
s.SeriesRecSize=1408;%      (* = 176 * 8 *)
s=orderfields(s);
s.Sweeps = []; % used to store all the sweeps within the recording structure later on

end

%--------------------------------------------------------------------------
function sw=getSweep(fh)
%--------------------------------------------------------------------------
sw.SwMark=fread(fh, 1, 'int32=>int32');%               =   0; (* INT32 *)
sw.SwLabel=deblank(fread(fh, 32, 'uint8=>char')');%              =   4; (* String32Type *)
sw.SwAuxDataFileOffset=fread(fh, 1, 'int32=>int32');%  =  36; (* INT32 *)
sw.SwStimCount=fread(fh, 1, 'int32=>int32');%          =  40; (* INT32 *)
sw.SwSweepCount=fread(fh, 1, 'int32=>int32');%         =  44; (* INT32 *)
sw.SwTime=fread(fh, 1, 'double=>double');%               =  48; (* LONGREAL *)
sw.SwTimeMATLAB=time2date(sw.SwTime);% Also add in MATLAB datenum format
sw.SwTimer=fread(fh, 1, 'double=>double');%              =  56; (* LONGREAL *)
sw.SwSwUserParams=fread(fh, 4, 'double=>double');%       =  64; (* ARRAY[0..3] OF LONGREAL *)
sw.SwTemperature=fread(fh, 1, 'double=>double');%        =  96; (* LONGREAL *)
sw.SwOldIntSol=fread(fh, 1, 'int32=>int32');%          = 104; (* INT32 *)
sw.SwOldExtSol=fread(fh, 1, 'int32=>int32');%          = 108; (* INT32 *)
sw.SwDigitalIn=fread(fh, 1, 'int16=>int16');%          = 112; (* SET16 *)
sw.SwSweepKind=fread(fh, 1, 'int16=>int16');%          = 114; (* SET16 *)
sw.SwFiller1=fread(fh, 1, 'int32=>int32');%         = 116; (* INT32 *)
sw.SwMarkers=fread(fh, 4, 'double=>double');%            = 120; (* ARRAY[0..3] OF LONGREAL *)
sw.SwFiller2=fread(fh, 1, 'int32=>int32');%         = 152; (* INT32 *)
sw.SwCRC=fread(fh, 1, 'int32=>int32');%                = 156; (* CARD32 *)
sw.SweepRecSize         = 160;%      (* = 20 * 8 *)
sw=orderfields(sw);
sw.Traces = []; % used to store all the traces/channels within the sweep structure later on
end

%--------------------------------------------------------------------------
function tr=getTrace(fh)
%--------------------------------------------------------------------------
tr.TrMark=fread(fh, 1, 'int32=>int32');%               =   0; (* INT32 *)
tr.TrLabel=deblank(fread(fh, 32, 'uint8=>char')');%              =   4; (* String32Type *)
tr.TrTraceCount=fread(fh, 1, 'int32=>int32');%         =  36; (* INT32 *)
tr.TrData=fread(fh, 1, 'int32=>int32');%               =  40; (* INT32 *)
tr.TrDataPoints=fread(fh, 1, 'int32=>int32');%         =  44; (* INT32 *)
tr.TrInternalSolution=fread(fh, 1, 'int32=>int32');%   =  48; (* INT32 *)
tr.TrAverageCount=fread(fh, 1, 'int32=>int32');%       =  52; (* INT32 *)
tr.TrLeakCount=fread(fh, 1, 'int32=>int32');%          =  56; (* INT32 *)
tr.TrLeakTraces=fread(fh, 1, 'int32=>int32');%         =  60; (* INT32 *)
tr.TrDataKind=fread(fh, 1, 'uint16=>uint16');%           =  64; (* SET16 *) NB Stored unsigned
tr.TrFiller1=fread(fh, 1, 'int16=>int16');%         =  66; (* SET16 *)
tr.TrRecordingMode=fread(fh, 1, 'uint8=>uint8');%      =  68; (* BYTE *)
tr.TrAmplIndex=fread(fh, 1, 'uint8=>uint8');%          =  69; (* CHAR *)
tr.TrDataFormat=fread(fh, 1, 'uint8=>uint8');%         =  70; (* BYTE *)
tr.TrDataAbscissa=fread(fh, 1, 'uint8=>uint8');%       =  71; (* BYTE *)
tr.TrDataScaler=fread(fh, 1, 'double=>double');%         =  72; (* LONGREAL *)
tr.TrTimeOffset=fread(fh, 1, 'double=>double');%         =  80; (* LONGREAL *)
tr.TrZeroData=fread(fh, 1, 'double=>double');%           =  88; (* LONGREAL *)
tr.TrYUnit=deblank(fread(fh, 8, 'uint8=>char')');%              =  96; (* String8Type *)
tr.TrXInterval=fread(fh, 1, 'double=>double');%          = 104; (* LONGREAL *)
tr.TrXStart=fread(fh, 1, 'double=>double');%             = 112; (* LONGREAL *)
% 17.04.10 TrXUnit bytes may include some trailing characters after NULL
% byte
tr.TrXUnit=deblank(fread(fh, 8, 'uint8=>char')');%              = 120; (* String8Type *)
tr.TrYRange=fread(fh, 1, 'double=>double');%             = 128; (* LONGREAL *)
tr.TrYOffset=fread(fh, 1, 'double=>double');%            = 136; (* LONGREAL *)
tr.TrBandwidth=fread(fh, 1, 'double=>double');%          = 144; (* LONGREAL *)
tr.TrPipetteResistance=fread(fh, 1, 'double=>double');%  = 152; (* LONGREAL *)
tr.TrCellPotential=fread(fh, 1, 'double=>double');%      = 160; (* LONGREAL *)
tr.TrSealResistance=fread(fh, 1, 'double=>double');%     = 168; (* LONGREAL *)
tr.TrCSlow=fread(fh, 1, 'double=>double');%              = 176; (* LONGREAL *)
tr.TrGSeries=fread(fh, 1, 'double=>double');%            = 184; (* LONGREAL *)
tr.TrRsValue=fread(fh, 1, 'double=>double');%            = 192; (* LONGREAL *)
tr.TrGLeak=fread(fh, 1, 'double=>double');%              = 200; (* LONGREAL *)
tr.TrMConductance=fread(fh, 1, 'double=>double');%       = 208; (* LONGREAL *)
tr.TrLinkDAChannel=fread(fh, 1, 'int32=>int32');%      = 216; (* INT32 *)
tr.TrValidYrange=fread(fh, 1, 'uint8=>logical');%        = 220; (* BOOLEAN *)
tr.TrAdcMode=fread(fh, 1, 'uint8=>uint8');%            = 221; (* CHAR *)
tr.TrAdcChannel=fread(fh, 1, 'int16=>int16');%         = 222; (* INT16 *)
tr.TrYmin=fread(fh, 1, 'double=>double');%               = 224; (* LONGREAL *)
tr.TrYmax=fread(fh, 1, 'double=>double');%               = 232; (* LONGREAL *)
tr.TrSourceChannel=fread(fh, 1, 'int32=>int32');%      = 240; (* INT32 *)
tr.TrExternalSolution=fread(fh, 1, 'int32=>int32');%   = 244; (* INT32 *)
tr.TrCM=fread(fh, 1, 'double=>double');%                 = 248; (* LONGREAL *)
tr.TrGM=fread(fh, 1, 'double=>double');%                 = 256; (* LONGREAL *)
tr.TrPhase=fread(fh, 1, 'double=>double');%              = 264; (* LONGREAL *)
tr.TrDataCRC=fread(fh, 1, 'int32=>int32');%            = 272; (* CARD32 *)
tr.TrCRC=fread(fh, 1, 'int32=>int32');%                = 276; (* CARD32 *)
tr.TrGS=fread(fh, 1, 'double=>double');%                 = 280; (* LONGREAL *)
tr.TrSelfChannel=fread(fh, 1, 'int32=>int32');%        = 288; (* INT32 *)

% Added 15.08.2012
tr.TrInterleaveSize=fread(fh, 1, 'int32=>int32');%        = 292; (* INT32 *)
tr.TrInterleaveSkip=fread(fh, 1, 'int32=>int32');%        = 296; (* INT32 *)
tr.TrImageIndex=fread(fh, 1, 'int32=>int32');%        = 300; (* INT32 *)
tr.TrMarkers=fread(fh, 10, 'double=>double');%        = 304; (* ARRAY[0..9] OF LONGREAL *)
tr.TrSECM_X=fread(fh, 1, 'double=>double');%        = 384; (* LONGREAL *)
tr.TrSECM_Y=fread(fh, 1, 'double=>double');%        = 392; (* LONGREAL *)
tr.TrSECM_Z=fread(fh, 1, 'double=>double');%        = 400; (* LONGREAL *)
tr.TraceRecSize=408;

tr=orderfields(tr);

end

%% GET SOLUTION TREE
%--------------------------------------------------------------------------
function [Tree, Position, Counter, nchild]=getOneSolutionLevel(fh, Tree, Sizes, Level, Position, Counter)
%--------------------------------------------------------------------------
% Gets one record of the tree and the number of children
[s, Counter]=getOneSolutionRecord(fh, Level, Counter);
Tree{Counter, Level+1}=s;
Position=Position+Sizes(Level+1);
fseek(fh, Position, 'bof');
nchild=fread(fh, 1, 'int32=>int32');
Position=ftell(fh);

end

%--------------------------------------------------------------------------
function [rec, Counter]=getOneSolutionRecord(fh, Level, Counter)
%--------------------------------------------------------------------------
% Gets one record
Counter=Counter+1;
switch Level
	case 0
		rec=getSolutionRoot(fh);
	case 1
		rec=getSolution(fh);
	case 2
		rec=getChemical(fh);
		
	otherwise
		error('Unexpected Level');
end

end

%--------------------------------------------------------------------------
function p=getSolutionRoot(fh)
%--------------------------------------------------------------------------
p.RoVersion=fread(fh, 1, 'int16=>int16'); % = 0; (* INT16 *)
p.RoDataBaseName=deblank(fread(fh, 80, 'uint8=>char')');%               =   2; (* SolutionNameSize *)
p.RoSpare1=fread(fh, 1, 'int16=>int16');%        =   82; (* INT16 *)
p.RoCRC=fread(fh, 1, 'int32=>int32'); %        =  84; (* CARD32 *)
p.RootSize = 88;%          =  88

p=orderfields(p);

end


function s=getSolution(fh)
%--------------------------------------------------------------------------
% Stimulus level
s.SoNumber=fread(fh, 1, 'int32=>int32');%                =   0; (* INT32 *)
s.SoName=deblank(fread(fh, 80, 'uint8=>char')');%           =   4; (* SolutionNameSize  *)
s.SoNumeric=fread(fh, 1, 'real*4=>double');%             =  84; (* REAL *) *)
s.SoNumericName=deblank(fread(fh, 30, 'uint8=>char')');%             =  88; (* ChemicalNameSize *)
s.SoPH=fread(fh, 1, 'real*4=>double');%    = 118; (* REAL *)
s.SopHCompound=deblank(fread(fh, 30, 'uint8=>char')');%      = 122; (* ChemicalNameSize *)
s.soOsmol=fread(fh, 1, 'real*4=>double'); %152; (* REAL *)
s.SoCRC=fread(fh, 1, 'int32=>int32') ;%     = 156; (* CARD32 *)
s.SolutionSize=160;%      = 160

s=orderfields(s);

end

%--------------------------------------------------------------------------
function c=getChemical(fh)
%--------------------------------------------------------------------------
c.ChConcentration=fread(fh, 1, 'real*4=>double');%               =  0; (* REAL *)
c.ChName=deblank(fread(fh, 30, 'uint8=>char')');%      =   4; (* ChemicalNameSize *)
c.ChSpare1=fread(fh, 1, 'int16=>int16');%  =   34; (* INT16 *)
c.ChCRC=fread(fh, 1, 'int32=>int32')';%              36; (* CARD32 *)
c.ChemicalSize=40;%         =  40

c=orderfields(c);

end


%% GET STIMULUS TREE
%--------------------------------------------------------------------------
function [Tree, Position, Counter, nchild]=getOneStimLevel(fh, Tree, Sizes, Level, Position, Counter)
%--------------------------------------------------------------------------
% Gets one record of the tree and the number of children
[s, Counter]=getOneStimRecord(fh, Level, Counter);
Tree{Counter, Level+1}=s;
Position=Position+Sizes(Level+1);
fseek(fh, Position, 'bof');
nchild=fread(fh, 1, 'int32=>int32');
Position=ftell(fh);

end

%--------------------------------------------------------------------------
function [rec, Counter]=getOneStimRecord(fh, Level, Counter)
%--------------------------------------------------------------------------
% Gets one record
Counter=Counter+1;
switch Level
	case 0
		rec=getStimRoot(fh);
	case 1
		rec=getStimulation(fh);
	case 2
		rec=getChannel(fh);
	case 3
		rec=getStimSegment(fh);
	otherwise
		error('Unexpected Level');
end

end

% The functions below return data as defined by the HEKA PatchMaster
% specification

%--------------------------------------------------------------------------
function p=getStimRoot(fh)
%--------------------------------------------------------------------------
p.RoVersion=fread(fh, 1, 'int32=>int32');
p.RoMark=fread(fh, 1, 'int32=>int32');%               =   4; (* INT32 *)
p.RoVersionName=deblank(fread(fh, 32, 'uint8=>char')');%        =   8; (* String32Type *)
p.RoMaxSamples=fread(fh, 1, 'int32=>int32'); %        =  40; (* INT32 *)
p.RoFiller1 = fread(fh, 1, 'int32=>int32');%          =  44; (* INT32 *)
p.RoParams = fread(fh, 10, 'double=>double');%             =  48; (* ARRAY[0..9] OF LONGREAL *)
for k=1:10
	p.RoParamText{k}=deblank(fread(fh, 32, 'uint8=>char')');%        = 128; (* ARRAY[0..9],[0..31]OF CHAR *)
end
p.RoReserved =  fread(fh, 32, 'int32=>int32');%          = 448; (* INT32 *)
p.RoFiller2= fread(fh, 1, 'int32=>int32');%        = 576; (* INT32 *)
p.RoCRC= fread(fh, 1, 'int32=>int32');%                = 580; (* CARD32 *)
p.RootRecSize= 584; %      (* = 73 * 8 *)
p=orderfields(p);

end

%--------------------------------------------------------------------------
function s=getStimulation(fh)
%--------------------------------------------------------------------------
% Stimulus level
s.stMark=fread(fh, 1, 'int32=>int32');%                =   0; (* INT32 *)
s.stEntryName=deblank(fread(fh, 32, 'uint8=>char')');%           =   4; (* String32Type *)
s.stFileName=deblank(fread(fh, 32, 'uint8=>char')');%             =  36; (* String32Type *)
s.stAnalName=deblank(fread(fh, 32, 'uint8=>char')');%             =  68; (* String32Type *)
s.stDataStartSegment=fread(fh, 1, 'int32=>int32');%    = 100; (* INT32 *)
s.stDataStartTime=fread(fh, 1, 'double=>double') ;%      = 104; (* LONGREAL *)
s.stDataStartTimeMATLAB=time2date(s.stDataStartTime);
s.stSampleInterval=fread(fh, 1, 'double=>double') ;%     = 112; (* LONGREAL *)
s.stSweepInterval=fread(fh, 1, 'double=>double') ;%      = 120; (* LONGREAL *)
s.stLeakDelay=fread(fh, 1, 'double=>double') ;%          = 128; (* LONGREAL *)
s.stFilterFactor=fread(fh, 1, 'double=>double') ;%       = 136; (* LONGREAL *)
s.stNumberSweeps=fread(fh, 1, 'int32=>int32');%        = 144; (* INT32 *)
s.stNumberLeaks=fread(fh, 1, 'int32=>int32');%         = 148; (* INT32 *)
s.stNumberAverages=fread(fh, 1, 'int32=>int32');%      = 152; (* INT32 *)
s.stActualAdcChannels=fread(fh, 1, 'int32=>int32');%   = 156; (* INT32 *)
s.stActualDacChannels=fread(fh, 1, 'int32=>int32');%   = 160; (* INT32 *)
s.stExtTrigger=fread(fh, 1, 'uint8=>uint8');%          = 164; (* BYTE *)
s.stNoStartWait=fread(fh, 1, 'uint8=>logical');%        = 165; (* BOOLEAN *)
s.stUseScanRates=fread(fh, 1, 'uint8=>logical');%       = 166; (* BOOLEAN *)
s.stNoContAq=fread(fh, 1, 'uint8=>logical');%           = 167; (* BOOLEAN *)
s.stHasLockIn=fread(fh, 1, 'uint8=>logical');%          = 168; (* BOOLEAN *)
s.stOldStartMacKind=fread(fh, 1, 'uint8=>char');% = 169; (* CHAR *)
s.stOldEndMacKind=fread(fh, 1, 'uint8=>logical');%   = 170; (* BOOLEAN *)
s.stAutoRange=fread(fh, 1, 'uint8=>uint8');%          = 171; (* BYTE *)
s.stBreakNext=fread(fh, 1, 'uint8=>logical');%          = 172; (* BOOLEAN *)
s.stIsExpanded=fread(fh, 1, 'uint8=>logical');%         = 173; (* BOOLEAN *)
s.stLeakCompMode=fread(fh, 1, 'uint8=>logical');%       = 174; (* BOOLEAN *)
s.stHasChirp=fread(fh, 1, 'uint8=>logical');%           = 175; (* BOOLEAN *)
s.stOldStartMacro=deblank(fread(fh, 32, 'uint8=>char')');%   = 176; (* String32Type *)
s.stOldEndMacro=deblank(fread(fh, 32, 'uint8=>char')');%     = 208; (* String32Type *)
s.sIsGapFree=fread(fh, 1, 'uint8=>logical');%           = 240; (* BOOLEAN *)
s.sHandledExternally=fread(fh, 1, 'uint8=>logical');%   = 241; (* BOOLEAN *)
s.stFiller1=fread(fh, 1, 'uint8=>logical');%         = 242; (* BOOLEAN *)
s.stFiller2=fread(fh, 1, 'uint8=>logical');%         = 243; (* BOOLEAN *)
s.stCRC=fread(fh, 1, 'int32=>int32'); %                = 244; (* CARD32 *)
s.stTag=deblank(fread(fh, 32, 'uint8=>char')');%                = 248; (* String32Type *)
s.StimulationRecSize   = 280;%      (* = 35 * 8 *)

s=orderfields(s);

end

%--------------------------------------------------------------------------
function c=getChannel(fh)
%--------------------------------------------------------------------------
c.chMark=fread(fh, 1, 'int32=>int32');%               =   0; (* INT32 *)
c.chLinkedChannel=fread(fh, 1, 'int32=>int32');%      =   4; (* INT32 *)
c.chCompressionFactor=fread(fh, 1, 'int32=>int32');%  =   8; (* INT32 *)
c.chYUnit=deblank(fread(fh, 8, 'uint8=>char')');%              =  12; (* String8Type *)
c.chAdcChannel=fread(fh, 1, 'int16=>int16');%         =  20; (* INT16 *)
c.chAdcMode=fread(fh, 1, 'uint8=>uint8');%            =  22; (* BYTE *)
c.chDoWrite=fread(fh, 1, 'uint8=>logical');%            =  23; (* BOOLEAN *)
c.stLeakStore=fread(fh, 1, 'uint8=>uint8');%          =  24; (* BYTE *)
c.chAmplMode=fread(fh, 1, 'uint8=>uint8');%           =  25; (* BYTE *)
c.chOwnSegTime=fread(fh, 1, 'uint8=>logical');%         =  26; (* BOOLEAN *)
c.chSetLastSegVmemb=fread(fh, 1, 'uint8=>logical');%    =  27; (* BOOLEAN *)
c.chDacChannel=fread(fh, 1, 'int16=>int16');%         =  28; (* INT16 *)
c.chDacMode=fread(fh, 1, 'uint8=>uint8');%            =  30; (* BYTE *)
c.chHasLockInSquare=fread(fh, 1, 'uint8=>uint8');%    =  31; (* BYTE *)
c.chRelevantXSegment=fread(fh, 1, 'int32=>int32');%   =  32; (* INT32 *)
c.chRelevantYSegment=fread(fh, 1, 'int32=>int32');%   =  36; (* INT32 *)
c.chDacUnit=deblank(fread(fh, 8, 'uint8=>char')');%            =  40; (* String8Type *)
c.chHolding=fread(fh, 1, 'double=>double') ;%            =  48; (* LONGREAL *)
c.chLeakHolding=fread(fh, 1, 'double=>double') ;%        =  56; (* LONGREAL *)
c.chLeakSize=fread(fh, 1, 'double=>double') ;%           =  64; (* LONGREAL *)
c.chLeakHoldMode=fread(fh, 1, 'uint8=>uint8');%       =  72; (* BYTE *)
c.chLeakAlternate=fread(fh, 1, 'uint8=>logical');%      =  73; (* BOOLEAN *)
c.chAltLeakAveraging=fread(fh, 1, 'uint8=>logical');%   =  74; (* BOOLEAN *)
c.chLeakPulseOn=fread(fh, 1, 'uint8=>logical');%        =  75; (* BOOLEAN *)
c.chStimToDacID=fread(fh, 1, 'int16=>int16');%        =  76; (* SET16 *)
c.chCompressionMode=fread(fh, 1, 'int16=>int16');%    =  78; (* SET16 *)
c.chCompressionSkip=fread(fh, 1, 'int32=>int32');%    =  80; (* INT32 *)
c.chDacBit=fread(fh, 1, 'int16=>int16');%             =  84; (* INT16 *)
c.chHasLockInSine=fread(fh, 1, 'uint8=>logical');%      =  86; (* BOOLEAN *)
c.chBreakMode=fread(fh, 1, 'uint8=>uint8');%          =  87; (* BYTE *)
c.chZeroSeg=fread(fh, 1, 'int32=>int32');%            =  88; (* INT32 *)
c.chFiller1=fread(fh, 1, 'int32=>int32');%         =  92; (* INT32 *)
c.chSine_Cycle=fread(fh, 1, 'double=>double') ;%         =  96; (* LONGREAL *)
c.chSine_Amplitude=fread(fh, 1, 'double=>double') ;%     = 104; (* LONGREAL *)
c.chLockIn_VReversal=fread(fh, 1, 'double=>double') ;%   = 112; (* LONGREAL *)
c.chChirp_StartFreq=fread(fh, 1, 'double=>double') ;%    = 120; (* LONGREAL *)
c.chChirp_EndFreq=fread(fh, 1, 'double=>double') ;%      = 128; (* LONGREAL *)
c.chChirp_MinPoints=fread(fh, 1, 'double=>double') ;%    = 136; (* LONGREAL *)
c.chSquare_NegAmpl=fread(fh, 1, 'double=>double') ;%     = 144; (* LONGREAL *)
c.chSquare_DurFactor=fread(fh, 1, 'double=>double') ;%   = 152; (* LONGREAL *)
c.chLockIn_Skip=fread(fh, 1, 'int32=>int32');%        = 160; (* INT32 *)
c.chPhoto_MaxCycles=fread(fh, 1, 'int32=>int32');%    = 164; (* INT32 *)
c.chPhoto_SegmentNo=fread(fh, 1, 'int32=>int32');%    = 168; (* INT32 *)
c.chLockIn_AvgCycles=fread(fh, 1, 'int32=>int32');%   = 172; (* INT32 *)
c.chImaging_RoiNo=fread(fh, 1, 'int32=>int32');%      = 176; (* INT32 *)
c.chChirp_Skip=fread(fh, 1, 'int32=>int32');%         = 180; (* INT32 *)
c.chChirp_Amplitude=fread(fh, 1, 'double=>double') ;%    = 184; (* LONGREAL *)
c.chPhoto_Adapt=fread(fh, 1, 'uint8=>uint8');%        = 192; (* BYTE *)
c.chSine_Kind=fread(fh, 1, 'uint8=>uint8');%          = 193; (* BYTE *)
c.chChirp_PreChirp=fread(fh, 1, 'uint8=>uint8');%     = 194; (* BYTE *)
c.chSine_Source=fread(fh, 1, 'uint8=>uint8');%        = 195; (* BYTE *)
c.chSquare_NegSource=fread(fh, 1, 'uint8=>uint8');%   = 196; (* BYTE *)
c.chSquare_PosSource=fread(fh, 1, 'uint8=>uint8');%   = 197; (* BYTE *)
c.chChirp_Kind=fread(fh, 1, 'uint8=>uint8');%         = 198; (* BYTE *)
c.chChirp_Source=fread(fh, 1, 'uint8=>uint8');%       = 199; (* BYTE *)
c.chDacOffset=fread(fh, 1, 'double=>double') ;%          = 200; (* LONGREAL *)
c.chAdcOffset=fread(fh, 1, 'double=>double') ;%          = 208; (* LONGREAL *)
c.chTraceMathFormat=fread(fh, 1, 'uint8=>uint8');%    = 216; (* BYTE *)
c.chHasChirp=fread(fh, 1, 'uint8=>logical');%           = 217; (* BOOLEAN *)
c.chSquare_Kind=fread(fh, 1, 'uint8=>uint8');%        = 218; (* BYTE *)
c.chFiller2=fread(fh,13,'uint8=>char');%         = 219; (* ARRAY[0..13] OF CHAR *)
c.chSquare_Cycle=fread(fh, 1, 'double=>double') ;%       = 232; (* LONGREAL *)
c.chSquare_PosAmpl=fread(fh, 1, 'double=>double') ;%     = 240; (* LONGREAL *)
c.chCompressionOffset=fread(fh, 1, 'int32=>int32');%  = 248; (* INT32 *)
c.chPhotoMode=fread(fh, 1, 'int32=>int32');%          = 252; (* INT32 *)
c.chBreakLevel=fread(fh, 1, 'double=>double') ;%         = 256; (* LONGREAL *)
c.chTraceMath=deblank(fread(fh,128,'uint8=>char')');%          = 264; (* String128Type *)
c.chOldCRC=fread(fh, 1, 'int32=>int32');%             = 268; (* CARD32 *)
c.chFiller3=fread(fh, 1, 'int32=>int32');%         = 392; (* INT32 *)
c.chCRC=fread(fh, 1, 'int32=>int32');%                = 396; (* CARD32 *)
c.ChannelRecSize       = 400;%     (* = 50 * 8 *)
c=orderfields(c);

end

%--------------------------------------------------------------------------
function ss=getStimSegment(fh)
%--------------------------------------------------------------------------
ss.seMark=fread(fh, 1, 'int32=>int32');%               =   0; (* INT32 *)
ss.seClass=fread(fh, 1, 'uint8=>uint8');%              =   4; (* BYTE *)
ss.seDoStore=fread(fh, 1, 'uint8=>logical');%            =   5; (* BOOLEAN *)
ss.seVoltageIncMode=fread(fh, 1, 'uint8=>uint8');%     =   6; (* BYTE *)
ss.seDurationIncMode=fread(fh, 1, 'uint8=>uint8');%    =   7; (* BYTE *)
ss.seVoltage=fread(fh, 1, 'double=>double');%            =   8; (* LONGREAL *)
ss.seVoltageSource=fread(fh, 1, 'int32=>int32');%      =  16; (* INT32 *)
ss.seDeltaVFactor=fread(fh, 1, 'double=>double');%       =  20; (* LONGREAL *)
ss.seDeltaVIncrement=fread(fh, 1, 'double=>double');%    =  28; (* LONGREAL *)
ss.seDuration=fread(fh, 1, 'double=>double');%           =  36; (* LONGREAL *)
ss.seDurationSource=fread(fh, 1, 'int32=>int32');%     =  44; (* INT32 *)
ss.seDeltaTFactor=fread(fh, 1, 'double=>double');%       =  48; (* LONGREAL *)
ss.seDeltaTIncrement=fread(fh, 1, 'double=>double');%    =  56; (* LONGREAL *)
ss.seFiller1=fread(fh, 1, 'int32=>int32');%         =  64; (* INT32 *)
ss.seCRC=fread(fh, 1, 'int32=>int32');%                =  68; (* CARD32 *)
ss.seScanRate=fread(fh, 1, 'double=>double');%           =  72; (* LONGREAL *)
ss.StimSegmentRecSize   =  80;%      (* = 10 * 8 *)
ss=orderfields(ss);

end



%% GET AMPLIFIER DATA
%--------------------------------------------------------------------------
function L=getSeLockInParams(fh)
%--------------------------------------------------------------------------
offset=ftell(fh);
L.loExtCalPhase=fread(fh, 1, 'double=>double') ;%        =   0; (* LONGREAL *)
L.loExtCalAtten=fread(fh, 1, 'double=>double') ;%        =   8; (* LONGREAL *)
L.loPLPhase=fread(fh, 1, 'double=>double') ;%            =  16; (* LONGREAL *)
L.loPLPhaseY1=fread(fh, 1, 'double=>double') ;%          =  24; (* LONGREAL *)
L.loPLPhaseY2=fread(fh, 1, 'double=>double') ;%          =  32; (* LONGREAL *)
L.loUsedPhaseShift=fread(fh, 1, 'double=>double') ;%     =  40; (* LONGREAL *)
L.loUsedAttenuation=fread(fh, 1, 'double=>double');%    =  48; (* LONGREAL *)
L.loFiller1=fread(fh, 1, 'double=>double');
L.loExtCalValid=fread(fh, 1, 'uint8=>logical') ;%        =  64; (* BOOLEAN *)
L.loPLPhaseValid=fread(fh, 1, 'uint8=>logical') ;%       =  65; (* BOOLEAN *)
L.loLockInMode=fread(fh, 1, 'uint8=>uint8') ;%         =  66; (* BYTE *)
L.loCalMode=fread(fh, 1, 'uint8=>uint8') ;%            =  67; (* BYTE *)
L.LockInParamsSize=96;
fseek(fh, offset+L.LockInParamsSize, 'bof');

end

%--------------------------------------------------------------------------
function A=getAmplifierState(fh)
%--------------------------------------------------------------------------
offset=ftell(fh);
A.E9StateVersion=fread(fh, 1, 'double=>double');%       =   0; (* 8 = SizeStateVersion *)
A.E9RealCurrentGain=fread(fh, 1, 'double=>double');%    =   8; (* LONGREAL *)
A.E9RealF2Bandwidth=fread(fh, 1, 'double=>double');%    =  16; (* LONGREAL *)
A.E9F2Frequency=fread(fh, 1, 'double=>double');%        =  24; (* LONGREAL *)
A.E9RsValue=fread(fh, 1, 'double=>double');%            =  32; (* LONGREAL *)
A.E9RsFraction=fread(fh, 1, 'double=>double');%         =  40; (* LONGREAL *)
A.E9GLeak=fread(fh, 1, 'double=>double');%              =  48; (* LONGREAL *)
A.E9CFastAmp1=fread(fh, 1, 'double=>double');%          =  56; (* LONGREAL *)
A.E9CFastAmp2=fread(fh, 1, 'double=>double');%          =  64; (* LONGREAL *)
A.E9CFastTau=fread(fh, 1, 'double=>double');%           =  72; (* LONGREAL *)
A.E9CSlow=fread(fh, 1, 'double=>double');%              =  80; (* LONGREAL *)
A.E9GSeries=fread(fh, 1, 'double=>double');%            =  88; (* LONGREAL *)
A.E9StimDacScale=fread(fh, 1, 'double=>double');%       =  96; (* LONGREAL *)
A.E9CCStimScale=fread(fh, 1, 'double=>double');%        = 104; (* LONGREAL *)
A.E9VHold=fread(fh, 1, 'double=>double');%              = 112; (* LONGREAL *)
A.E9LastVHold=fread(fh, 1, 'double=>double');%          = 120; (* LONGREAL *)
A.E9VpOffset=fread(fh, 1, 'double=>double');%           = 128; (* LONGREAL *)
A.E9VLiquidJunction=fread(fh, 1, 'double=>double');%    = 136; (* LONGREAL *)
A.E9CCIHold=fread(fh, 1, 'double=>double');%            = 144; (* LONGREAL *)
A.E9CSlowStimVolts=fread(fh, 1, 'double=>double');%     = 152; (* LONGREAL *)
A.E9CCtr.TrackVHold=fread(fh, 1, 'double=>double');%       = 160; (* LONGREAL *)
A.E9TimeoutLength=fread(fh, 1, 'double=>double');%      = 168; (* LONGREAL *)
A.E9SearchDelay=fread(fh, 1, 'double=>double');%        = 176; (* LONGREAL *)
A.E9MConductance=fread(fh, 1, 'double=>double');%       = 184; (* LONGREAL *)
A.E9MCapacitance=fread(fh, 1, 'double=>double');%       = 192; (* LONGREAL *)
A.E9SerialNumber=fread(fh, 1, 'double=>double');%       = 200; (* 8 = SizeSerialNumber *)
A.E9E9Boards=fread(fh, 1, 'int16=>int16');%           = 208; (* INT16 *)
A.E9CSlowCycles=fread(fh, 1, 'int16=>int16');%        = 210; (* INT16 *)
A.E9IMonAdc=fread(fh, 1, 'int16=>int16');%            = 212; (* INT16 *)
A.E9VMonAdc=fread(fh, 1, 'int16=>int16');%            = 214; (* INT16 *)
A.E9MuxAdc=fread(fh, 1, 'int16=>int16');%             = 216; (* INT16 *)
A.E9TstDac=fread(fh, 1, 'int16=>int16');%             = 218; (* INT16 *)
A.E9StimDac=fread(fh, 1, 'int16=>int16');%            = 220; (* INT16 *)
A.E9StimDacOffset=fread(fh, 1, 'int16=>int16');%      = 222; (* INT16 *)
A.E9MaxDigitalBit=fread(fh, 1, 'int16=>int16');%      = 224; (* INT16 *)
A.E9SpareInt1=fread(fh, 1, 'int16=>int16');%       = 226; (* INT16 *)
A.E9SpareInt2=fread(fh, 1, 'int16=>int16');%       = 228; (* INT16 *)
A.E9SpareInt3=fread(fh, 1, 'int16=>int16');%       = 230; (* INT16 *)

A.E9AmplKind=fread(fh, 1, 'uint8=>uint8');%           = 232; (* BYTE *)
A.E9IsEpc9N=fread(fh, 1, 'uint8=>uint8');%            = 233; (* BYTE *)
A.E9ADBoard=fread(fh, 1, 'uint8=>uint8');%            = 234; (* BYTE *)
A.E9BoardVersion=fread(fh, 1, 'uint8=>uint8');%       = 235; (* BYTE *)
A.E9ActiveE9Board=fread(fh, 1, 'uint8=>uint8');%      = 236; (* BYTE *)
A.E9Mode=fread(fh, 1, 'uint8=>uint8');%               = 237; (* BYTE *)
A.E9Range=fread(fh, 1, 'uint8=>uint8');%              = 238; (* BYTE *)
A.E9F2Response=fread(fh, 1, 'uint8=>uint8');%         = 239; (* BYTE *)

A.E9RsOn=fread(fh, 1, 'uint8=>uint8');%               = 240; (* BYTE *)
A.E9CSlowRange=fread(fh, 1, 'uint8=>uint8');%         = 241; (* BYTE *)
A.E9CCRange=fread(fh, 1, 'uint8=>uint8');%            = 242; (* BYTE *)
A.E9CCGain=fread(fh, 1, 'uint8=>uint8');%             = 243; (* BYTE *)
A.E9CSlowToTstDac=fread(fh, 1, 'uint8=>uint8');%      = 244; (* BYTE *)
A.E9StimPath=fread(fh, 1, 'uint8=>uint8');%           = 245; (* BYTE *)
A.E9CCtr.TrackTau=fread(fh, 1, 'uint8=>uint8');%         = 246; (* BYTE *)
A.E9WasClipping=fread(fh, 1, 'uint8=>uint8');%        = 247; (* BYTE *)

A.E9RepetitiveCSlow=fread(fh, 1, 'uint8=>uint8');%    = 248; (* BYTE *)
A.E9LastCSlowRange=fread(fh, 1, 'uint8=>uint8');%     = 249; (* BYTE *)
A.E9Locked=fread(fh, 1, 'uint8=>uint8');%             = 250; (* BYTE *)
A.E9CanCCFast=fread(fh, 1, 'uint8=>uint8');%          = 251; (* BYTE *)
A.E9CanLowCCRange=fread(fh, 1, 'uint8=>uint8');%      = 252; (* BYTE *)
A.E9CanHighCCRange=fread(fh, 1, 'uint8=>uint8');%     = 253; (* BYTE *)
A.E9CanCCtr.Tracking=fread(fh, 1, 'uint8=>uint8');%      = 254; (* BYTE *)
A.E9HasVmonPath=fread(fh, 1, 'uint8=>uint8');%        = 255; (* BYTE *)

A.E9HasNewCCMode=fread(fh, 1, 'uint8=>uint8');%       = 256; (* BYTE *)
A.E9Selector=fread(fh, 1, 'uint8=>char');%           = 257; (* CHAR *)
A.E9HoldInverted=fread(fh, 1, 'uint8=>uint8');%       = 258; (* BYTE *)
A.E9AutoCFast=fread(fh, 1, 'uint8=>uint8');%          = 259; (* BYTE *)
A.E9AutoCSlow=fread(fh, 1, 'uint8=>uint8');%          = 260; (* BYTE *)
A.E9HasVmonX100=fread(fh, 1, 'uint8=>uint8');%        = 261; (* BYTE *)
A.E9TestDacOn=fread(fh, 1, 'uint8=>uint8');%          = 262; (* BYTE *)
A.E9QMuxAdcOn=fread(fh, 1, 'uint8=>uint8');%          = 263; (* BYTE *)

A.E9RealImon1Bandwidth=fread(fh, 1, 'double=>double');% = 264; (* LONGREAL *)
A.E9StimScale=fread(fh, 1, 'double=>double');%          = 272; (* LONGREAL *)

A.E9Gain=fread(fh, 1, 'uint8=>uint8');%               = 280; (* BYTE *)
A.E9Filter1=fread(fh, 1, 'uint8=>uint8');%            = 281; (* BYTE *)
A.E9StimFilterOn=fread(fh, 1, 'uint8=>uint8');%       = 282; (* BYTE *)
A.E9RsSlow=fread(fh, 1, 'uint8=>uint8');%             = 283; (* BYTE *)
A.E9Old1=fread(fh, 1, 'uint8=>uint8');%            = 284; (* BYTE *)
A.E9CCCFastOn=fread(fh, 1, 'uint8=>uint8');%          = 285; (* BYTE *)
A.E9CCFastSpeed=fread(fh, 1, 'uint8=>uint8');%        = 286; (* BYTE *)
A.E9F2Source=fread(fh, 1, 'uint8=>uint8');%           = 287; (* BYTE *)

A.E9TestRange=fread(fh, 1, 'uint8=>uint8');%          = 288; (* BYTE *)
A.E9TestDacPath=fread(fh, 1, 'uint8=>uint8');%        = 289; (* BYTE *)
A.E9MuxChannel=fread(fh, 1, 'uint8=>uint8');%         = 290; (* BYTE *)
A.E9MuxGain64=fread(fh, 1, 'uint8=>uint8');%          = 291; (* BYTE *)
A.E9VmonX100=fread(fh, 1, 'uint8=>uint8');%           = 292; (* BYTE *)
A.E9IsQuadro=fread(fh, 1, 'uint8=>uint8');%           = 293; (* BYTE *)
A.E9SpareBool4=fread(fh, 1, 'uint8=>uint8');%      = 294; (* BYTE *)
A.E9SpareBool5=fread(fh, 1, 'uint8=>uint8');%      = 295; (* BYTE *)

A.E9StimFilterHz=fread(fh, 1, 'double=>double');%       = 296; (* LONGREAL *)
A.E9RsTau=fread(fh, 1, 'double=>double');%              = 304; (* LONGREAL *)
A.E9FilterOffsetDac=fread(fh, 1, 'int16=>int16');%    = 312; (* INT16 *)
A.E9ReferenceDac=fread(fh, 1, 'int16=>int16');%       = 314; (* INT16 *)
A.E9SpareInt6=fread(fh, 1, 'int16=>int16');%       = 316; (* INT16 *)
A.E9SpareInt7=fread(fh, 1, 'int16=>int16');%       = 318; (* INT16 *)
A.E9Spares1=320;

A.E9CalibDate=fread(fh, 2, 'double=>double');%          = 344; (* 16 = SizeCalibDate *)
A.E9SelHold=fread(fh, 1, 'double=>double');%            = 360; (* LONGREAL *)
A.AmplifierStateSize   = 400;
fseek(fh, offset+A.AmplifierStateSize, 'bof');

end

%--------------------------------------------------------------------------
function matData2=LocalImportGroup(fh, dataTree, grp, grp_row)
%--------------------------------------------------------------------------
% Create a structure for the series headers


% Pad the indices for last series of last group
grp_row(end+1)=size(dataTree,1);

% Collect the series headers and row numbers for this group into a
% structure array
[ser_s, ser_row, nseries]=getSeriesHeaders(dataTree, grp_row, grp);

% Pad for last series
ser_row(nseries+1)=grp_row(grp+1);

dataoffsets=[];
% Create the channels

matData2 = cell(nseries,1);
for ser=1:nseries
	
	[sw_s, sw_row, nsweeps]=getSweepHeaders(dataTree, ser_row, ser);
	
	% Make sure the sweeps are in temporal sequence
	if any(diff(cell2mat({sw_s.SwTime}))<=0)
		% TODO: sort them if this can ever happen.
		% For the moment just throw an error
		error('Sweeps not in temporal sequence');
	end
	
	
	sw_row(nsweeps+1)=ser_row(ser+1);
	% Get the trace headers for this sweep
	[tr_row]=getTraceHeaders(dataTree, sw_row);
	
	
	for k=1:size(tr_row, 1)
		
		[tr_s, isConstantScaling, isConstantFormat, isFramed]=LocalCheckEntries(dataTree, tr_row, k);
		
		% TODO: Need a better way to do this
		% Check whether interleaving is supported with this file version
		% Note: HEKA added interleaving Jan 2011.
		% TrInterleaveSkip was previously in a filler block, so should always
		% be zero with older files.
		if tr_s(1).TrInterleaveSize>0 && tr_s(1).TrInterleaveSkip>0
			INTERLEAVE_SUPPORTED=true;
		else
			INTERLEAVE_SUPPORTED=false;
		end
		
		data=zeros(max(cell2mat({tr_s.TrDataPoints})), size(tr_row,2));
		
		for tr=1:size(tr_row,2)
			% Disc format
			[fmt, nbytes]=LocalFormatToString(tr_s(tr).TrDataFormat);
			% Always read into double
			readfmt=[fmt '=>double'];
			% Skip to start of the data
			fseek(fh, dataTree{tr_row(k,tr),5}.TrData, 'bof');
			% Store data offset for later error checks
			dataoffsets(end+1)=dataTree{tr_row(k,tr),5}.TrData; %#ok<AGROW>
			% Read the data
			if ~INTERLEAVE_SUPPORTED || dataTree{tr_row(k,tr),5}.TrInterleaveSize==0
				[data(1:dataTree{tr_row(k,tr),5}.TrDataPoints, tr)]=...
					fread(fh, double(dataTree{tr_row(k,tr),5}.TrDataPoints), readfmt);
			else
				offset=1;
				nelements= double(dataTree{tr_row(k,tr),5}.TrInterleaveSize/nbytes);
				for nread=1:floor(numel(data)/double(dataTree{tr_row(k,tr),5}.TrInterleaveSize/nbytes))
					[data(offset:offset+nelements-1), N]=fread(fh, nelements, readfmt);
					if (N<nelements)
						disp('End of file reached unexpectedly');
					end
					offset=offset+nelements;
					fseek(fh, double(dataTree{tr_row(k,tr),5}.TrInterleaveSkip-dataTree{tr_row(k,tr),5}.TrInterleaveSize), 'cof');
				end
			end
		end
		
		
		% Now scale the data to real world units
		% Note we also apply zero adjustment
		for col=1:size(data,2)
			data(:,col)=data(:,col)*tr_s(col).TrDataScaler+tr_s(col).TrZeroData;
		end
		
		matData2{ser,:}{k} = data;
		
	end
	
	
end


if numel(unique(dataoffsets))<numel(dataoffsets)
	warning('ImportHEKA:warning', 'This should never happen - please report to sigtool@kcl.ac.uk if you see this warning.');
	warning('ImportHEKA:multipleBlockRead', 'sigTOOL: Unexpected result: Some data blocks appear to have been read more then once');
end


end

%--------------------------------------------------------------------------
function [fmt, nbytes]=LocalFormatToString(n)
%--------------------------------------------------------------------------
switch n
	case 0
		fmt='int16';
		nbytes=2;
	case 1
		fmt='int32';
		nbytes=4;
	case 2
		fmt='single';
		nbytes=4;
	case 3
		fmt='double';
		nbytes=8;
end
return
end

%--------------------------------------------------------------------------
function [res, intflag]=LocalGetRes(fmt)
%--------------------------------------------------------------------------
switch fmt
	case {'int16' 'int32'}
		res=double(intmax(fmt))+double(abs(intmin(fmt)))+1;
		intflag=true;
	case {'single' 'double'}
		res=1;
		intflag=false;
end
return
end

%--------------------------------------------------------------------------
function [ser_s, ser_row, nseries]=getSeriesHeaders(tree, grp_row, grp)
%--------------------------------------------------------------------------
nseries=0;
for k=grp_row(grp)+1:grp_row(grp+1)-1
	if ~isempty(tree{k, 3})
		ser_s(nseries+1)=tree{k, 3}; %#ok<AGROW>
		ser_row(nseries+1)=k; %#ok<AGROW>
		nseries=nseries+1;
	end
end
return
end

%--------------------------------------------------------------------------
function [sw_s, sw_row, nsweeps]=getSweepHeaders(tree, ser_row, ser)
%--------------------------------------------------------------------------
nsweeps=0;
for k=ser_row(ser)+1:ser_row(ser+1)
	if ~isempty(tree{k, 4})
		sw_s(nsweeps+1)=tree{k, 4}; %#ok<AGROW>
		sw_row(nsweeps+1)=k; %#ok<AGROW>
		nsweeps=nsweeps+1;
	end
end
return
end

%--------------------------------------------------------------------------
function [tr_row, ntrace]=getTraceHeaders(tree, sw_row)
%--------------------------------------------------------------------------
ntrace=0;
m=1;
n=1;
for k=sw_row(1)+1:sw_row(end)
	if ~isempty(tree{k, 5})
		%tr_s(m,n)=tree{k, 5}; %#ok<NASGU>
		tr_row(m,n)=k;  %#ok<AGROW>
		ntrace=ntrace+1;
		m=m+1;
	else
		m=1;
		n=n+1;
	end
end
return
end


%--------------------------------------------------------------------------
function [tr_s, isConstantScaling, isConstantFormat, isFramed]=LocalCheckEntries(tree, tr_row, k)
%--------------------------------------------------------------------------
% Check units are the same for all traces
tr_s=[tree{tr_row(k, :),5}];


if numel(unique({tr_s.TrYUnit}))>1
	error('1002: Waveform units are not constant');
end

if numel(unique({tr_s.TrXUnit}))>1
	error('1003: Time units are not constant');
end

if numel(unique(cell2mat({tr_s.TrXInterval})))~=1
	error('1004: Unequal sample intervals');
end

% Other unexpected conditions - give user freedom to create these but warn
% about them
if numel(unique({tr_s.TrLabel}))>1
	warning('LocalCheckEntries:w2001', 'Different trace labels');
end

if numel(unique(cell2mat({tr_s.TrAdcChannel})))>1
	warning('LocalCheckEntries:w2002', 'Data collected from different ADC channels');
end

if numel(unique(cell2mat({tr_s.TrRecordingMode})))>1
	warning('LocalCheckEntries:w2003', 'Traces collected using different recording modes');
end

if numel(unique(cell2mat({tr_s.TrCellPotential})))>1
	warning('LocalCheckEntries:w2004', 'Traces collected using different Em');
end

% Check scaling factor is constant
ScaleFactor=unique(cell2mat({tr_s.TrDataScaler}));
if numel(ScaleFactor)==1
	isConstantScaling=true;
else
	isConstantScaling=false;
end


%... and data format
if numel(unique(cell2mat({tr_s.TrDataFormat})))==1
	isConstantFormat=true;
else
	isConstantFormat=false;
end

% Do we have constant epoch lengths and offsets?
if numel(unique(cell2mat({tr_s.TrDataPoints})))==1 &&...
		numel(unique(cell2mat({tr_s.TrTimeOffset })))==1
	isFramed=true;
else
	isFramed=false;
end
return
end

%--------------------------------------------------------------------------
function str=time2date(t)
%--------------------------------------------------------------------------
t=t-1580970496;
if t<0
	t=t+4294967296;
end
t=t+9561652096;
str=datestr(t/(24*60*60)+datenum(1601,1,1));
return
end
%--------------------------------------------------------------------------