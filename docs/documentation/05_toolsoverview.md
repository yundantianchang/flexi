(ToolsOverview)=
# Tools Overview

This section gives an overview over the additional tools contained in the **FLEXI** repository. It also provides references to the tutorials where they are used as reference.
<!--There are two different kinds of tools:-->

<!--* **POSTI**-tools can be compiled together with **FLEXI** given the according `cmake` options.-->
<!--* In the `tools` folder, a collection of shell and python scripts can be found, which are mainly used to manage **FLEXI** runs and **FLEXI** output files.-->

## POSTI Tools

<!--The **POSTI** tools are mostly documented in and in the tutorials [NACA0012](#NACA0012). Here, an overview is given together with references to the respective tutorials. -->
The different **POSTI** tools are used to further post-process the simulation results obtained with **FLEXI**. They can be compiled together with **FLEXI** given the according `cmake` option. A list and description for the input parameters of the associated **POSTI** tools can be displayed with the command
```bash
[posti_toolname] --help
```

(tools-visualization)=
### POSTI_VISU

`POSTI_VISU` converts **FLEXI** StateFiles, TimeAverage and BaseFlow files from the HDF5 format to the ParaView readable `.vtu` (single) or `.pvtu` (parallel) format. 

The `POSTI_VISU` tool reads a separate parameter file as optional first argument, while the files to be visualized are passed as the last argument. Without specifying a separate parameter file, the parameters stored in the userblock of the files are used and only the conservative variables are visualized.
The latter can be a single file or several files, specified either as simple space-separated list like `Testcase_State_0.h5 Testcase_State_1.h5` or via standard wildcarding like `Testcase_State_*.h5`. The file must contain the entire volume solution, i.e. can be a StateFile or a TimeAverage file, for example.  

For serial execution, the `POSTI_VISU` tool is invoked by entering
```bash
posti_visu [parameter_postiVisu.ini [parameter_flexi.ini]] <statefiles>
```
The tool also runs in parallel by prepending `mpirun -np <no. processors>` to the above command, as usual, provided the compiler option `LIBS_USE_MPI` is enabled.
```bash
mpirun -np <no. processors> posti_visu [parameter_postiVisu.ini [parameter_flexi.ini]] <statefiles>
```

```{important}
When post-processing with activated `LIBS_USE_MPI` flag, especially with large cases and large files as is often the case with TimeAverage files, the file size of approximately $2\, GB$ per core must not be exceeded. In this case, the number of cores used must be increased for MPI-parallel executable **POSTI** tools, or **POSTI** must be compiled with `LIBS_USE_MPI=OFF`.
ParaView can only read state files up to $2\, GB$ in single mode (`.vtu`).
```



The  **POSTI_VISU** tool has a help function that describes the available parameters. This help can be invoked by running the tool with the flag `--help`
```bash
posti_visu --help
```

The most important runtime parameters to be set in `parameter_postiVisu.ini` are listed in the table below.

```{list-table} POSTI_VISU parameters.
:header-rows: 1
:name: tab:postivisu_parameters
:align: center
:width: 100%
:widths: 20 30 50
* - Parameter
  - Possible Values
  - Description
* - NodeTypeVisu
  - VISU / GAUSS / GAUSS-LOBATTO / VISU-INNER
  - Node type of visualization basis; the default *VISU* uses equidistant nodes which include the boundary points of the elements.
* - NVisu
  - 1 / 2 / 3 / ...
  - Polynomial degree used to sample the solution for visualization; if left unspecified, it defaults to using the number of collocation points per elements, i.e. $N+1$ per dimension.<br/>
    For high-quality visualization, it is usually advisable to choose a value higher than $N$ in order to keep interpolation errors small.
* - VarName
  - Density / VelocityX / ...
  - Names of the variables to be visualized, parameter can be specified multiple times to visualize more than one variable and set to both conservatives (e.g. *Density*) and primitives (e.g. *VelocityX*).<br/>
    If left unspecified, it defaults to visualizing the five conservative variables.
* - BoundaryName
  - Density / WallFriction / y+ / ...
  - Name of the boundary to visualize. Some variables can only be visualized on the boundary like WallFriction / y+.
```

In the following all available variables that can be used for visualization are listed. 
```bash
Density, MomentumX, MomentumY, MomentumZ, EnergyStagnationDensity, VelocityX, VelocityY, VelocityZ, Pressure, Temperature, VelocityMagnitude, VelocitySound, Mach, EnergyStagnation  ,EnthalpyStagnation  ,Entropy  ,TotalTemperature  ,TotalPressure  ,PressureTimeDeriv  ,VorticityX  ,VorticityY  ,VorticityZ  ,VorticityMagnitude  ,NormalizedHelicity  ,Lambda2  ,Dilatation  ,QCriterion  ,Schlieren  ,WallFrictionX  ,WallFrictionY  ,WallFrictionZ  ,WallFrictionMagnitude  ,WallHeatTransfer  ,x+  ,y+  z+  
``` 

The practical application of `POSTI_VISU` can be practiced in the following tutorials. [](sec:tut_linadv), [](sec:tut_freestream), [](sec:tut_cavity), [](sec:tut_sod), [](sec:tut_dmr), [](Cylinder), [](NACA0012)



<!------------------------------------------------------------------------------------------------->
<!--**Paraview plugin**-->
<!----------------------------------- -------------------------------------------------------------->
<!--A ParaView reader based on `posti_visu` to load **FLEXI** state files in ParaView. Provides the interface to adjust `posti_visu` parameters in the ParaView GUI. Requires to build ParaView from source.-->

<!--Basic usage: `libVisuReader.so` is loaded as a Plugin in ParaView-->



(sec:swap_mesh)=
### POSTI_SWAPMESH

The `POSTI_SWAPMESH` tool interpolates the solution of a StateFile or a TimeAverage file from one mesh to another, or from one polynomial degree to another. To do so, the parametric coordinates of the interpolation points of the new state are searched in the old mesh. For non-equal elements a Newton algorithm is used to find the parametric coordinates of the interpolation points. Based on the found parametric coordinates high-order interpolation to the interpolation points in the new mesh is performed. Non-conforming meshes are allowed. A reference state can be given for areas in the target mesh which are not covered by the original mesh. The project name and therefore the file name is based on the original project name with '_newMesh' appended, the original file is therefore not overwritten. 

For serial execution, the `POSTI_SWAPMESH` tool is invoked by entering
```bash
posti_swapmesh parameter_postiSwapmesh.ini <statefiles>
```
The tool also runs in parallel using OpenMP. To run in parallel the environment Variable `OMP_NUM_THREADS=XXX` need to be set with the number of threads to be used, provided the compiler option `LIBS_USE_OPENMP` is enabled. In this case the parallel execution is the same as the single execution. 

A list of parameters used by the `POSTI_SWAPMESH` tool is listed in the table below.
An example of the `POSTI_SWAPMESH` tool can be found in 
```bash
./flexi/ini/swapmesh
```

  


```{list-table} POSTI_SWAPMESH parameters.
:header-rows: 1
:name: tab:postiswapmesh_parameters
:align: center
:width: 100%
:widths: 25 25 50
* - Parameter
  - Possible Values
  - Description
* - MeshFileOld
  - none / MeshFileName.h5
  - Old mesh file (if different than the one found in the state file)
* - MeshFileNew
  - MeshFileName.h5
  - New mesh file
* - useCurvedsOld
  - T/F
  - Controls usage of high-order information in old mesh. Turn off to discard
* - useCurvedsNew
  - T/F
  - Controls usage of high-order information in new mesh. Turn off to discard
* - NInter
  - 1 / 2 / 3 / ...
  - Polynomial degree used for interpolation on new mesh (should be equal or  higher than NNew) - the state will be interpolated to this degree and then projected down to NNew
* - NNew
  - 1 / 2 / 3 / ...
  - Polynomial degree used in new state files
* - NSuper
  - 1 / 2 / 3 / ...
  - Polynomial degree used for supersampling on the old mesh, used to get an initial guess for Newton's method - should be higher than NGeo of old mesh
* - maxTolerance
  - value $\ge 0$
  - Tolerance used to mark points as invalid if outside of reference element more than maxTolerance
* - printTroublemakers
  - T/F
  - Turn output of not-found points on or off
* - RefState
  - complete conservative state vector
  - If a RefState is defined, this state will be used at points that are marked as invalid - without a RefState, the program will abort in this case
* - abortTolerance
  - value $\ge 0$
  - Tolerance used to decide if the program should abort if no RefState is given
* - ExtrudeTo3D
  - T/F
  - Perform an extrusion of a one-layer mesh to the 3D version Layer which is used in extrusion
* - ExtrudePeriodic
  - T/F
  - Perform a periodic extrusion of a 3D mesh to a mesh with extended z length
```



<!--TODO:-->
<!------------------------------------------------------------------------------------------------->
<!--**posti_swapmesh**-->
<!----------------------------------- -------------------------------------------------------------->
<!--This tool interpolates the solution in a state file from one mesh to another or from one polynomial degree to another. It is based on high-order interpolation and a Newton coordinate search algorithm. Non-conforming meshes are allowed. A reference state can be given for areas in the target mesh which are not covered by the original mesh.-->

<!--Basic usage: `posti_swapmesh [parameter.ini] [statefile.h5]`-->

<!--Further info / usage examples: `ini/swapmesh` folder-->

<!--(tools-recordpoints)=-->
<!--### Record points-->

<!--The following tools allow to sample high-frequency data in **FLEXI** at certain points, lines or areas in the computational domain, from defining the location of the recordpoints to visualization.-->

<!-------------------------------------------------------------------------------------------------->
<!--**posti_preparerecordpoints**-->
<!----------------------------------- -------------------------------------------------------------->
<!--It record values at a set of physical points over time with a higher temporal sampling rate than the state file output interval given in the parameter file of **FLEXI**. It has an own parmeter file where the record point coordinates and the **FLEXI** mesh file are defined. Finally, an additional `.h5` file is created, whose path is passed to **FLEXI** as an additional parameter.-->

<!--Basic usage: `posti_preparerecordpoints [parameter_prepareRP.ini]`-->

<!--Further info / usage examples: \ref{sec:postiRecordpoints}-->

<!-------------------------------------------------------------------------------------------------->
<!--**posti_visualizerecordpoints**-->
<!----------------------------------- -------------------------------------------------------------->
<!--This tool performs the post-processing of the `*_RP_*` files written by **FLEXI**. It merges several time steps and allows to output values over time or spectra.-->

<!--Basic usage: `posti_visualizerecordpoints [parameter_visuRP.ini] [projectname_RP_*.h5]`-->

<!--Further info / usage examples: \ref{sec:postiRecordpoints}-->

<!-------------------------------------------------------------------------------------------------->
<!--**posti_evaluaterecordpoints**-->
<!----------------------------------- -------------------------------------------------------------->
<!--This tool can evaluate the values at recorpoints a posteriori from existing statefiles. Can be used if the recordpoints have not been set during the simulation, but will only give coarse temporal resolution.-->

<!--Basic usage: `posti_evaluaterecordpoints [parameter.ini] [statefile.h5]`-->

<!--Further info / usage examples: No tutorials so far-->

<!--(sec:time_averaging)=-->
<!--### Time averaging-->

<!--The following tools allow to handle either time-averaged high-frequency data averaged during the simulation or averages the states files written by **FLEXI** over time.-->

<!------------------------------------------------------------------------------------------------->
<!--**posti_mergetimeaverages**-->
<!----------------------------------- -------------------------------------------------------------->
<!--This tool averages several **FLEXI** `State` or `TimeAverage` files. If `TimeAverage` files are the input, each files is weighted with its time averaging period. `State` files are all weighted equally. All HDF5 data sets are averaged and no additional parameter file is required.-->

<!--Basic usage: `posti_mergetimeaverages [statefile1.h5 statefile2.h5 ...]`-->

<!--Further info / usage examples: No tutorials so far-->

<!------------------------------------------------------------------------------------------------->
<!--**posti_calcfluctuations**-->
<!----------------------------------- -------------------------------------------------------------->
<!--This tool calculates fluctuations from the `Mean` and `MeanSquare` given in the (merged) `TimeAverage` files. Fluctuations are then written into an additional data set in the same HDF5 file. All applicable fluctuations are calculated and no additional parameter file is required.-->
<!--During the simulation, **FLEXI** will write two data sets: The mean value of a variable and the mean of the square of the variable. We can then use the following equality to calculate fluctuations (=mean of the square of the fluctuations):-->

<!--$\overline{(UU)} = \overline{(u+u')(u+u')} = \overline{(uu)} + \overline{2uu'} + \overline{u'u'} = uu + \overline{u'u'}$-->

<!--where we split the total value of a variable U in the mean u and the fluctuating part u'.-->
<!--Thus, with the stored $UU$ and $u=U$ we then calculate the fluctuations in here as:-->

<!--$\overline{u'u'} = \overline{UU} - uu$-->

<!--Basic usage: `posti_calcfluctuations [statefile1.h5 statefile2.h5 ...]`-->

<!--Further info / usage examples: No tutorials so far-->

<!--### Fast Fourier Transform-->
<!--TODO:-->
<!------------------------------------------------------------------------------------------------->
<!--**posti_channel_fft**-->
<!----------------------------------- -------------------------------------------------------------->
<!--This tool calculates the mean velocity and Reynolds stress profiles of the turbulent channel flow test case by averaging both in the direction parallel to the wall and by averaging the upper and lower half of the channel. Furthermore, kinetic energy spectra dependent on the distance to the wall are computed.-->

<!--Basic usage: `posti_channel_fft [parameter_channelfft.ini] [statefile1.h5 statefile2.h5 ...]`-->

<!--Further info / usage examples: TODO-->

<!----->
<!------------------------------------------------------------------------------------------------->
<!--**posti_init_hit**-->
<!----------------------------------- -------------------------------------------------------------->
<!--Brief description                  No description so far-->

<!--Basic usage                        `posti_visu [parameter.ini] [statefile.h5]`-->

<!--Further info / usage example       No tutorials so far-->
<!------------------------------------------------------------------------------------------------->
<!---->


<!--[>===========================================================================================================================<]-->


<!--## Tools folder-->

<!--The scripts provided in the `tools` folder are generally not part of the tutorials.-->
<!--They are briefly described below. The path to the python files (of the form `$FLEXIROOT/tools/SUBDIR/`) is omitted in the following.-->
<!--For most python tools, possible arguments and syntax can be shown with the `-h` argument:-->
<!--```bash-->
<!--python3 [toolname.py] -h-->
<!--```-->
<!--(sec:animate_tool)=-->
<!--### Animate tool-->

<!--The python script **animate_paraview.py** creates movies from a series of state files using `PvBatch`, a GUI-less interface to ParaView.-->
<!--You need ParaView installed on your system (details can be found in the ParaView [>- TODO <] section) and the directory containing the `PvBatch` executable needs to be a part of your `$PATH`. Before running this script, you have to visualize your **FLEXI** state file with ParaView and save the current view via `Save State...`, e.g. under the name `pvstate.pvsm`. You also need the `MEncoder` tool installed. The basic command to run the script is-->
<!--```bash-->
<!--python3 animate_paraview.py -l [pvstate.pvsm] -r [path_to_posti_paraview_plugin] [statefile1.h5 statefile2.h5 ...]-->
<!--```-->
<!--Apart from the movie file, the script also outputs a `.png`-file for each HDF5 file given as input.-->
<!--In order to visualize a set of `.vtu`-files, e.g., from the `posti_visu` output, omit the `-r` argument and pass `.vtu`-files instead of `.h5`-files. Further options can be shown with the `-h` argument.-->

<!--There are further tools for image handling in this folder:-->

<!--The tool **concatenatepics.py** stitches several pairs of images (e.g. creates a time series of stitched images from two time series of images). A possible command could look like this (*Further options can be shown with the `-h` argument*):-->
<!--```bash-->
<!--python3 concatenatepics.py -d e -p left*.png  -a right*.png-->
<!--```-->
<!--The tool **crop.py** crops several images to the same size. Simply pass all images as arguments:-->
<!--```bash-->
<!--python3 crop.py [image*.png]-->
<!--```-->
<!--The script **pics2movie.py** creates a movie from several images using the `mencoder` tool (which is also done as part of the `animate_paraview.py` script. Basic usage is again-->
<!--```bash-->
<!--python3 pics2movie.py [image*.png]-->
<!--```-->
<!--and further options can again be shown with the `-h` argument.-->


<!--[>...........................................................................................................................<]-->

<!--### Convergence test tool-->

<!--The python scripts `convergence.py` and `convergence_grid.py` provide automated convergence tests for p- and h-convergence, respectively.-->
<!--The basic command is-->
<!--```bash-->
<!--python3 convergence.py flexi [parameter.ini]-->
<!--```-->
<!--where `convergence` can be replaced by `convergence_grid` for h-convergence. Further options can again be shown with the `-h` option.-->

<!--Note that for h-convergence, the mesh names are hard-coded to the form `CART_HEX_PERIODIC_MORTAR_XXX_2D_mesh.h5`, where `XXX` denotes the number of elements in each direction, and `MORTAR` and `2D` are optional. The polynomial degree in the parameter file is *always* overwritten by the one passed to the script as an optional argument, with a default value of 3, if no such argument is passed. [>-TODO: change this in the script<]-->


<!--[>...........................................................................................................................<]-->

<!--### Userblock tool-->

<!--The `userblock` contains complete information about a **FLEXI** run (git branch of the repository, differences to that branch, `cmake` configuration and parameter file) and is prepended to every `.h5` state file. The parameter file is prepended in ASCII format, the rest is binary and is generated automatically during the build process with the `generate_userblock.sh` script. It can be extracted and printed using the `extract_userblock.py` script. Its basic usage is-->
<!--```bash-->
<!--python3 extract_userblock.py -XXX [statefile.h5]-->
<!--```-->
<!--where `-XXX` can be replaced by-->

<!--* `-s` to show all available parts of the userblock (such as `CMAKE` or `GIT BRANCH`)-->
<!--* `-a` to print the complete userblock-->
<!--* `-p [part]` to print one of the parts listed with the `-s` command.-->

<!--The second python tool in this folder is `rebuild.py`. It extracts the userblock from a state file and builds a **FLEXI** repository and binary identical to the one that the state file was created with. In order to do so, it clones a **FLEXI** git repository, checks out the given branch, applies the stored changes to the git `HEAD` and builds **FLEXI** with the stored `cmake` options. If run with the parameter file given in the `INIFILE` part of the userblock, this binary should reproduce the same results/behavior (possible remaining sources of different output are for example differences in restart files, compilers, linked libraries or machines). The basic usage is-->
<!--```bash-->
<!--python3 rebuild.py [dir] [statefile.h5]-->
<!--```-->
<!--where `dir` is an empty directory that the repository is cloned into and where the `flexi` executable is built. `statefile.h5` is the state file whose userblock is used to rebuild the `flexi` executable. Help can be shown via `-h` for both userblock scripts.-->


<!--[>...........................................................................................................................<]-->

<!--### Other scripts-->

<!--#### Sort files scripts-->

<!--The `sortfiles.sh` script sorts all `.h5`-files in subfolders `State`, `BaseFlow`, `TimeAvg` and `RP`, while keeping the last time instance at the upper level. It also copies `Log.*.sdb`, `.log` and `.out` files into a `logs` subdirectory. The project name is hard-coded in the script and has to be adapted there, the directory that is to be sorted is passed as an argument.-->

<!--#### HPC tools-->

<!--The `getload.py` script is specific to runs on HPC systems. It calculates a suitable number of nodes and cores to achieve-->

<!--* a specific number of degrees of freedom per core which is close to a target-->
<!--* an average number of elements per core which is just below a close integer, such that parallel efficiency is not impaired by a few cores with higher load that the others have to wait for.-->

<!--No arguments are passed to this script, all input values are hard-coded and have to be adjusted in the script.-->


<!--[>...........................................................................................................................<]-->

<!--### Testcase scripts-->

<!--#### Fast Fourier Transform-->

<!--The python script **plotChannelFFT.py** creates plots of the mean velocity and the Reynolds stress profiles as well as the turbulent energy spectra based on the posti_channel_fft HDF5 output files. Basic usage is:-->
<!--```bash-->
<!--python3 plotChannelFFT.py -p projectname -t time-->
<!--```-->
<!--Further options can be shown with the `-h` argument.-->
