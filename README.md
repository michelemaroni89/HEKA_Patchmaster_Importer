# HEKA Patchmaster Importer

Class to import HEKA Patchmaster files into Matlab.
The core functionality is based on the HEKA importer from sigTool (https://doi.org/10.1016/j.neuron.2015.10.042 and https://github.com/irondukepublishing/sigTOOL) with modifications from Sammy Katta (https://github.com/sammykatta/Matlab-PatchMaster).

This stand-alone importer works independent of sigTool and will additionally extract the stimulus (reconstructed from the pgf) and solutions (when solution base was active during recording). 

The recordings will be sorted into a table together with various parameters e.g series resistance (Rs), cell membrane capacitance (Cm), holding potential (Vhold), stimulus and solutions. 

 ## How to use:
**Input:**
- full file path and name of HEKA Patchmaster file that is to be loaded, e.g.
to load example HEKA Patchmaster file "MyData.dat" located in "C:\PatchClamp\" run HEKA_Importer('C:\PatchClamp\MyData.dat').

*Alternative:* run HEKA_Importer.GUI which will open the file dialog box from which the Patchmaster file can be selected.

**Output:**

Heka_Importer creates object containing the following properties:

- trees: structure containing the dataTree (from the .pul file), the stimTree (from the .pgf file) and solTree (from the .sol file). These tree structures are how HEKA saves the metadata for different recordings. For details on the HEKA file format check ftp://server.hekahome.de/pub/FileFormat/Patchmasterv9/.

- opt: structure containing different options when loading the file, currently it only contains the filepath of the HEKA Patchmaster file which was loaded

- RecTable: Matlab table containing the recordings and several parameters associated with them. Each row represents a different recording. The recorded data are stored in RecTable.dataRaw. 

- solutions: Matlab table containing the solutions and composition (chemicals & concentration) used during the experiments. This table is read-out from the solTree of the HEKA Patchmaster file. The names of solutions correspond to the columns "ExternalSolution" and "InternalSolution" of the RecTable. 