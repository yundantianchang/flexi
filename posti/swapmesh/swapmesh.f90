!=================================================================================================================================
! Copyright (c) 2010-2022 Prof. Claus-Dieter Munz
! Copyright (c) 2022-2024 Prof. Andrea Beck
! This file is part of FLEXI, a high-order accurate framework for numerically solving PDEs with discontinuous Galerkin methods.
! For more information see https://www.flexi-project.org and https://numericsresearchgroup.org
!
! FLEXI is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License
! as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
!
! FLEXI is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty
! of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License v3.0 for more details.
!
! You should have received a copy of the GNU General Public License along with FLEXI. If not, see <http://www.gnu.org/licenses/>.
!=================================================================================================================================
#include "flexi.h"

!===================================================================================================================================
!> Containes the routines that will initialize and finalize the swapmesh routine as well as the routines to read an old state file
!> and to write the newly interpolated state to a .h5 file.
!===================================================================================================================================
MODULE MOD_SwapMesh
! MODULES
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PRIVATE
!-----------------------------------------------------------------------------------------------------------------------------------

PUBLIC:: InitSwapmesh
PUBLIC:: ReadOldStateFile
PUBLIC:: WriteNewStateFile
PUBLIC:: FinalizeSwapmesh
!===================================================================================================================================

CONTAINS

!===================================================================================================================================
!> Read in user defined parameters and prepare data for swapmesh.
!> The old and new mesh will be read and stored, the necessary Vandermonde matrices are built and the parametric coordinates
!> of the new gauss points in the old mesh are found.
!===================================================================================================================================
SUBROUTINE InitSwapmesh()
! MODULES
!-----------------------------------------------------------------------------------------------------------------------------------
USE MOD_Globals
USE MOD_SwapMesh_Vars
USE MOD_ReadInTools
USE MOD_Commandline_Arguments
USE MOD_StringTools,             ONLY: STRICMP,GetFileExtension,INTTOSTR
USE MOD_DG_Vars,                 ONLY: U
USE MOD_Interpolation,           ONLY: GetVandermonde
USE MOD_Interpolation_Vars,      ONLY: NodeTypeVISU,NodeTypeCL
USE MOD_ChangeBasis,             ONLY: ChangeBasis3D
USE MOD_HDF5_Input,              ONLY: OpenDataFile,CloseDataFile,GetDataProps,ReadAttribute
USE MOD_IO_HDF5,                 ONLY: File_ID
USE MOD_SMParametricCoordinates, ONLY: GetParametricCoordinates
USE MOD_Interpolation,           ONLY: InitInterpolation
USE MOD_Output_Vars,             ONLY: NOut,ProjectName
USE MOD_Mesh_Vars,               ONLY: nElems,OffsetElem,nGlobalElems
#if USE_OPENMP
USE OMP_Lib,                     ONLY: OMP_GET_WTIME
#endif
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT / OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
CHARACTER(LEN=255)  :: MeshFile_state
INTEGER             :: nElems_State
REAL                :: Time
CHARACTER(LEN=255)  :: tmp
!===================================================================================================================================
! Open the first statefile to read necessary attributes
CALL OpenDataFile(Args(2),create=.FALSE.,single=.FALSE.,readOnly=.TRUE.)
CALL ReadAttribute(File_ID,'MeshFile',    1,StrScalar=MeshFile_state)
CALL ReadAttribute(File_ID,'Project_Name',1,StrScalar=ProjectName)
CALL GetDataProps(nVar_State,NState,nElems_State,NodeTypeState)
CALL CloseDataFile()

! change projectname to not re-write the same state
ProjectName = TRIM(ProjectName)//'_newMesh'

! The old mesh file can be overwritten by the user, if nothing is specified the mesh file read from the state is used
MeshFileOld = GETSTR('MeshFileOld',TRIM(MeshFile_state))

! New mesh file, the state will be interpolated to this one
MeshFileNew = GETSTR('MeshFileNew')

NodeTypeOut = GETSTR('NodeTypeNew',NodeTypeState)

! Curved meshes or not
useCurvedsOld = GETLOGICAL("useCurvedsOld")
useCurvedsNew = GETLOGICAL("useCurvedsNew")

! Read in polynomial degrees used for interpolation, supersampling and for the new state
! If they have not been specified, use the polynomial degree of the old state
NInter      = GETINT('NInter',INTTOSTR(NState))
NSuper      = GETINT('NSuper',INTTOSTR(NState))
NNew        = GETINT('NNew',  INTTOSTR(NState))
! Set NOut for output state routine to the polynomial degree of the new state (so no interpolation will be done)
NOut        = NNew

printTroublemakers = GETLOGICAL('printTroublemakers','.TRUE.')

! Tolerance used to mark the position of an interpolation point in the new mesh as invalid. Will be invalid if the reference
! coordinate is more than maxtol outside of [-1,1], e.g "overshoot tolerance"
maxTol = 1. + GETREAL('maxTolerance','5.e-2')

IF (CountOption('RefState').GE.1) THEN
  ! If a reference state is given in the parameter file, it will be used whenever a gauss point can not be found.
  ! This means the program will never abort, so the abort tolerance will be set to a huge number!
  RefState = GETREALARRAY('RefState',nVar_State)
  abortTol = HUGE(1.)
ELSE
  ! Set the abort tolerance, standard is the same as "overshoot tolerance"
  WRITE(tmp,*) maxTol
  abortTol     =GETREAL('abortTolerance',TRIM(tmp))
END IF

! Init interpolation on new polynomial degree, will set PP_N to NNew
CALL InitInterpolation(NNew)

! Extrusion of a one-layer mesh to the 3D version
ExtrudeTo3D = GETLOGICAL("ExtrudeTo3D",'.FALSE.')
IF (ExtrudeTo3D) ExtrudeK = GETINT("ExtrudeK")

! Extrusion of a one-layer mesh to the 3D version
ExtrudePeriodic = GETLOGICAL("ExtrudePeriodic",'.FALSE.')
IF (ExtrudePeriodic) abortTol = HUGE(1.)

! Initialize the old mesh, store the mesh coordinates (transformed to CL points) and the number of elements as well as the old NGeo
SWRITE(UNIT_stdOut,'(132("-"))')
SWRITE(UNIT_stdOut,'(A)', ADVANCE='NO') ' INIT OLD MESH...'
Time = OMP_FLEXITIME()
IF (ExtrudePeriodic) THEN
  CALL ReadMeshCoords(MeshFileOld,useCurvedsOld,NGeoOld,nElemsOld,xCLOld,nElems_IJK=nElemsOld_IJK)
ELSE
  CALL ReadMeshCoords(MeshFileOld,useCurvedsOld,NGeoOld,nElemsOld,xCLOld)
END IF
CALL DisplayMessageAndTime(OMP_FLEXITIME()-TIME,'DONE!',DisplayLine=.FALSE.)

! Initialize new mesh
SWRITE(UNIT_stdOut,'(A)', ADVANCE='NO') ' INIT NEW MESH...'
Time = OMP_FLEXITIME()
IF (ExtrudeTo3D.OR.ExtrudePeriodic) THEN
  CALL ReadMeshCoords(MeshFileNew,useCurvedsNew,NGeoNew,nElemsNew,xCLNew,Elem_IJK,nElems_IJK=nElemsNew_IJK)
ELSE
  CALL ReadMeshCoords(MeshFileNew,useCurvedsNew,NGeoNew,nElemsNew,xCLNew)
END IF
CALL DisplayMessageAndTime(OMP_FLEXITIME()-TIME,'DONE!',DisplayLine=.TRUE.)

! Transform mesh coordinates, i.e. reflect, rotate and translate the mesh and swapped state
SWRITE(UNIT_stdOut,'(A)') ' APPLY COORDINATE TRANSFORMATION...'
Time = OMP_FLEXITIME()
CALL TransformMeshCoords(xCLOld, (NGeoOld+1)**3*nElemsOld)
CALL DisplayMessageAndTime(OMP_FLEXITIME()-TIME,'DONE!',DisplayLine=.TRUE.)

! Set offset elem and local and global number of elements in mesh vars (later needed for output routine)
nGlobalElems = nElemsNew
nElems       = nElemsNew
OffsetElem   = 0 ! OffsetElem is 0 since the tool only works on singel

! Prepare the necessary Vandermonde matrizes, also interpolate the new mesh coordinates to xCLInter (on polynomial degree of NInter)
ALLOCATE(xCLInter(3,0:NInter,0:NInter,0:ZDIM(NInter),nElemsNew))
CALL prepareVandermonde()

! Evaluate parametric coordinates
ALLOCATE(xiInter(PP_dim,0:NInter,0:NInter,0:ZDIM(NInter),nElemsNew))
ALLOCATE(InterToElem(   0:NInter,0:NInter,0:ZDIM(NInter),nElemsNew))
ALLOCATE(IPDone(        0:NInter,0:NInter,0:ZDIM(NInter),nElemsNew))
ALLOCATE(equalElem(nElemsNew))

! Find the parametric coordinates of the interpolation points of the new state in the old mesh
CALL GetParametricCoordinates()

! Allocate aray for new and the old solution - for the new solution, we use the U array from DG vars
! to be able to later use the WriteState routine from FLEXI
ALLOCATE(UOld(nVar_State,0:NState,0:NState,0:ZDIM(NState),nElemsOld))
ALLOCATE(U   (nVar_State,0:NNew,  0:NNew,  0:ZDIM(NNew)  ,nElemsNew))
END SUBROUTINE InitSwapmesh


!===================================================================================================================================
!> This routine will read in the specified mesh file, convert the equidistant mesh coordinates to CL points and return them.
!> Additionally the number of elements in the mesh as well as NGeo will be returned.
!> The user can specify if curved meshes should be used or not.
!===================================================================================================================================
SUBROUTINE ReadMeshCoords(MeshFile,useCurveds,NGeo,nElems,XCL,Elem_IJK,nElems_IJK)
! MODULES
USE MOD_Globals
USE MOD_HDF5_Input
USE MOD_Interpolation,         ONLY: GetVandermonde
USE MOD_Interpolation_Vars,    ONLY: NodeTypeVISU,NodeTypeCL
USE MOD_IO_HDF5,               ONLY: File_ID
USE MOD_ChangeBasisByDim,      ONLY: ChangeBasisVolume
USE MOD_2D,                    ONLY: to2D_rank5
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT / OUTPUT VARIABLES
CHARACTER(LEN=255),INTENT(IN)  :: MeshFile       !< Mesh file to be read
LOGICAL,INTENT(IN)             :: useCurveds     !< Switch curved interpretation of mesh on or off
REAL,ALLOCATABLE,INTENT(OUT)   :: XCL(:,:,:,:,:) !< Mesh coordinates on CL points
INTEGER,INTENT(OUT)            :: NGeo           !< Polynomial degree of mesh representation
INTEGER,INTENT(OUT)            :: nElems         !< Number of elements in mesh
INTEGER,ALLOCATABLE,INTENT(OUT),OPTIONAL :: Elem_IJK(:,:) !< IJK sorting of mesh
INTEGER,INTENT(OUT),OPTIONAL   :: nElems_IJK(3)  !< IJK sorting of mesh
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL,ALLOCATABLE               :: NodeCoords(:,:,:,:,:)
REAL,ALLOCATABLE               :: NodeCoordsTmp(:,:,:,:,:)
REAL,ALLOCATABLE               :: Vdm_EQNgeo_CLNgeo(:,:)
INTEGER                        :: iElem
LOGICAL                        :: dsExists
!===================================================================================================================================
! Open the mesh file
CALL OpenDataFile(MeshFile,create=.FALSE.,single=.FALSE.,readOnly=.TRUE.)
! Read NGeo from mesh file
CALL ReadAttribute(File_ID,'Ngeo',1,IntScalar=NGeo)

! Get the number of elements in the mesh file by reading the size of the ElemInfo array
CALL GetDataSize(File_ID,'ElemInfo',nDims,HSize)
IF(HSize(1).NE.6) THEN
  CALL Abort(__STAMP__,&
    'ERROR: Wrong size of ElemInfo, should be 6')
END IF
CHECKSAFEINT(HSize(2),4)
nElems=INT(HSize(2),4)
DEALLOCATE(HSize)

! Now read in the equidistant coordinates of the mesh nodes
IF(useCurveds)THEN
  ALLOCATE(NodeCoords(3,0:NGeo,0:NGeo,0:NGeo,nElems))
  CALL ReadArray('NodeCoords',2,(/3,nElems*(NGeo+1)**3/),0,2,RealArray=NodeCoords)
ELSE
  ! If the mesh should be interpreted as not curved, store only the corner nodes
  ALLOCATE(NodeCoords(   3,0:1,   0:1,   0:1,   nElems))
  ALLOCATE(NodeCoordsTmp(3,0:NGeo,0:NGeo,0:NGeo,nElems))
  CALL ReadArray('NodeCoords',2,(/3,nElems*(NGeo+1)**3/),0,2,RealArray=NodeCoordsTmp)
  NodeCoords(:,0,0,0,:)=NodeCoordsTmp(:,0,   0,   0,   :)
  NodeCoords(:,1,0,0,:)=NodeCoordsTmp(:,NGeo,0,   0,   :)
  NodeCoords(:,0,1,0,:)=NodeCoordsTmp(:,0,   NGeo,0,   :)
  NodeCoords(:,1,1,0,:)=NodeCoordsTmp(:,NGeo,NGeo,0,   :)
  NodeCoords(:,0,0,1,:)=NodeCoordsTmp(:,0,   0,   NGeo,:)
  NodeCoords(:,1,0,1,:)=NodeCoordsTmp(:,NGeo,0,   NGeo,:)
  NodeCoords(:,0,1,1,:)=NodeCoordsTmp(:,0,   NGeo,NGeo,:)
  NodeCoords(:,1,1,1,:)=NodeCoordsTmp(:,NGeo,NGeo,NGeo,:)
  DEALLOCATE(NodeCoordsTmp)
  NGeo=1
END IF

#if (PP_dim == 2)
! If this is a two dimensional calculation, all subsequent operations are performed on the reduced mesh.
SWRITE(UNIT_stdOut,'(A)') " RUNNING A 2D SIMULATION! "
! The mesh coordinates read in by the readMesh routine are therefore reduced by one dimension.
CALL to2D_rank5((/1,0,0,0,1/),(/3,NGeo,NGeo,NGeo,nElems/),4,NodeCoords)
NodeCoords(3,:,:,:,:) = 0.
#endif

! Convert the equidistant mesh nodes to CL points
ALLOCATE(Vdm_EQNgeo_CLNgeo(0:Ngeo,0:Ngeo))
CALL GetVandermonde(Ngeo,NodeTypeVISU,Ngeo,NodeTypeCL,Vdm_EQNgeo_CLNgeo,modal=.FALSE.)
ALLOCATE(xCL(3,0:NGeo,0:NGeo,0:ZDIM(NGeo),nElems))
DO iElem=1,nElems
  CALL ChangeBasisVolume(3,NGeo,NGeo,Vdm_EQNGeo_CLNGeo,NodeCoords(:,:,:,:,iElem),xCL(:,:,:,:,iElem))
END DO ! iElem
DEALLOCATE(Vdm_EQNgeo_CLNgeo,NodeCoords)

IF (PRESENT(Elem_IJK).OR.PRESENT(nElems_IJK)) THEN
  CALL DatasetExists(File_ID,'nElems_IJK',dsExists)
  IF(dsExists)THEN
    CALL ReadArray('nElems_IJK',1,(/3/),0,1,IntArray=nElems_IJK)
    IF (PRESENT(Elem_IJK)) THEN
      ALLOCATE(Elem_IJK(3,nElems))
      CALL ReadArray('Elem_IJK',2,(/3,nElems/),0,2,IntArray=Elem_IJK)
    END IF
  ELSE
  CALL Abort(__STAMP__,&
    'ERROR: Not a IJK sorted mesh!')
  END IF
END IF
CALL CloseDataFile()
END SUBROUTINE ReadMeshCoords


!=================================================================================================================================
!> Performs transformation to the mesh coordinates, which eventually transform (reflect, rotate, translate) the state.
!> The transformations are computed in the following order:
!> 1. Reflection
!> 2. Rotation
!> 3. Translation
!=================================================================================================================================
SUBROUTINE TransformMeshCoords(x, n)
! MODULES
USE MOD_Globals
USE MOD_PreProc,     ONLY: PP_PI
USE MOD_ReadInTools, ONLY: CountOption,GETINT,GETREAL,GETREALARRAY
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!---------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
INTEGER,INTENT(IN) :: n        !> Number of points
!---------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
REAL,INTENT(INOUT) :: x(3,n)   !> Coordinates
!---------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER            :: i,j
REAL               :: mat(3,3)
REAL               :: dx(3),ang(3)
!=================================================================================================================================
! 1. Reflection
IF (CountOption('reflection').GE.1) THEN
  i = GETINT('reflection_dir')
  IF ( (i.GT.PP_dim) .OR. (i.LT.1)) CALL Abort(__STAMP__,'Reflection direction must be between 1 and 3!')
  DO j=1,n
    x(i,j) = -x(i,j)
  END DO
END IF
! 2. Rotation
IF (CountOption('rotation_angle').GE.1) THEN
  ang = GETREALARRAY('rotation_angle',3)
  IF ( (PP_dim.EQ.2) .AND. (ang(3).NE.0)) THEN
    SWRITE(UNIT_stdOut,'(A)') "WARNING: Rotation around z-axis in 2D is not possible, setting angle to 0."
    ang(3) = 0.
  END IF
  ang(1:PP_dim) = ang(1:PP_dim)/180.*PP_PI ! Convert from deg to rad
  ! 3x3 rotation matrix for intrinsic rotation with ang = (yaw, pitch, roll)
  mat(1,1) =  COS(ang(1))*COS(ang(2))
  mat(1,2) =  COS(ang(1))*SIN(ang(2))*SIN(ang(3))-SIN(ang(1))*COS(ang(3))
  mat(1,3) =  COS(ang(1))*SIN(ang(2))*COS(ang(3))+SIN(ang(1))*SIN(ang(3))
  mat(2,1) =  SIN(ang(1))*COS(ang(2))
  mat(2,2) =  SIN(ang(1))*SIN(ang(2))*SIN(ang(3))+COS(ang(1))*COS(ang(3))
  mat(2,3) =  SIN(ang(1))*SIN(ang(2))*COS(ang(3))-COS(ang(1))*SIN(ang(3))
  mat(3,1) = -SIN(ang(2))
  mat(3,2) =  COS(ang(2))*SIN(ang(3))
  mat(3,3) =  COS(ang(2))*COS(ang(3))
  ! Rotate
  DO j=1,n
    x(:,j) = MATMUL(mat,x(:,j))
  END DO
END IF
! 3. Translation
IF (CountOption('displacement').GE.1) THEN
  dx = GETREALARRAY('displacement',3)
  DO j=1,n
    DO i=1,PP_dim
      x(i,j) = x(i,j) + dx(i)
    END DO
  END DO
END IF
END SUBROUTINE TransformMeshCoords


!=================================================================================================================================
!> Prepare Vandemonde matrizes used in swapmesh. This includes:
!>   * Vandemonde CL    Ngeo   --> Equidistant NSuper
!>   * Vandemonde CL    NInter --> Gauss       NNew
!>   * Vandemonde Gauss NState --> Gauss       NNew
!>   * Vandemonde CL    Ngeo   --> CL          NInter
!=================================================================================================================================
SUBROUTINE prepareVandermonde()
! MODULES
USE MOD_Swapmesh_Vars,       ONLY: NInter,NNew,NState,NState,NGeoOld,NGeoNew,NSuper
USE MOD_Swapmesh_Vars,       ONLY: NodeTypeState,nElemsNew,xCLInter,NodeTypeOut
USE MOD_Swapmesh_Vars,       ONLY: Vdm_CLNGeo_EquiNSuper,Vdm_CLNInter_GPNNew,Vdm_GPNState_GPNNew
USE MOD_Swapmesh_Vars,       ONLY: xCLNew
USE MOD_Interpolation,       ONLY: GetVandermonde
USE MOD_Interpolation_Vars,  ONLY: NodeType,NodeTypeCL,NodeTypeVISU
USE MOD_ChangeBasisByDim,    ONLY: ChangeBasisVolume
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!---------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!---------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!---------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER            :: iElemNew
REAL               :: Vdm_CLNGeo_CLNInter(0:NInter,0:NGeoNew)
!=================================================================================================================================
! Build visu Vandermonde
ALLOCATE(Vdm_CLNGeo_EquiNSuper(0:NSuper,0:NGeoOld))
CALL GetVandermonde(NGeoOld,NodeTypeCL,NSuper,NodeTypeVISU,Vdm_CLNGeo_EquiNSuper)

! Vandermonde from interpolation CL to new solution G/GL
ALLOCATE(Vdm_CLNInter_GPNNew(0:NNew,0:NInter))
CALL GetVandermonde(NInter,NodeTypeCL,NNew,NodeTypeOut,Vdm_CLNInter_GPNNew)

! Vandermonde for direct interpolation in equal elements
IF((NNew.NE.NState).OR.(NodeTypeState.NE.NodeTypeOut))THEN
  ALLOCATE(Vdm_GPNState_GPNNew(0:NNew,0:NState))
  CALL GetVandermonde(NState,NodeTypeState,NNew,NodeTypeOut,Vdm_GPNState_GPNNew)
END IF

IF(NGeoNew.NE.NInter)THEN
  CALL GetVandermonde(NGeoNew,NodeTypeCL,NInter,NodeTypeCL,Vdm_CLNGeo_CLNInter)
  DO iElemNew=1,nElemsNew
    CALL ChangeBasisVolume(3,NGeoNew,NInter,Vdm_CLNGeo_CLNInter,xCLNew(:,:,:,:,iElemNew),xCLInter(:,:,:,:,iElemNew))
  END DO
ELSE
  xCLInter = xCLNew
END IF

END SUBROUTINE prepareVandermonde


!===================================================================================================================================
!> Open a state file, read the old state and store the information later needed to write a new state.
!===================================================================================================================================
SUBROUTINE ReadOldStateFile(StateFile)
! MODULES
USE MOD_Globals,       ONLY: Abort,PrintWarning
USE MOD_StringTools,   ONLY: STRICMP
USE MOD_HDF5_Input,    ONLY: OpenDataFile,CloseDataFile,ReadArray,ReadAttribute,GetDataSize,GetVarNames
USE MOD_IO_HDF5,       ONLY: File_ID,HSize
USE MOD_Swapmesh_Vars, ONLY: nVar_State,NState,nElemsOld,Time_State,UOld,NNew,nElemsNew
USE MOD_ReadInTools,   ONLY: ExtractParameterFile,ModifyParameterFile
USE MOD_Output_Vars,   ONLY: UserBlockTmpFile,userblock_total_len
USE MOD_Output,        ONLY: print_userblock
USE MOD_Equation_Vars, ONLY: StrVarNames
USE MOD_DG_Vars,       ONLY: U
USE ISO_C_BINDING,     ONLY: C_NULL_CHAR
USE MOD_2D
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT / OUTPUT VARIABLES
CHARACTER(LEN=255),INTENT(IN)      :: StateFile !< State file to be read
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
LOGICAL                          :: userblockFound,VarNamesExist
CHARACTER(LEN=255),PARAMETER     :: prmfile=".parameter.ini"
CHARACTER(LEN=255)               :: FileType
CHARACTER(LEN=255),ALLOCATABLE   :: VarNames_TimeAvg( :)     !< List of varnames in TimeAvg-File
CHARACTER(LEN=255),ALLOCATABLE   :: VarNames_ElemData(:)     !< List of varnames for element-wise data
REAL,ALLOCATABLE                 :: UMean(  :,:,:,:,:)      !< Mean solution from old TimeAvg state
REAL,ALLOCATABLE                 :: U_local(:,:,:,:,:)
INTEGER                          :: iVar,nVarsFound,nDims
!===================================================================================================================================
! Open the data file
CALL OpenDataFile(StateFile,create=.FALSE.,single=.FALSE.,readOnly=.TRUE.)

CALL ReadAttribute(File_ID,'File_Type',1,StrScalar=FileType)

SELECT CASE(TRIM(FileType))
CASE('State')
  ! Read the DG solution and store in U_local
  CALL GetDataSize(File_ID,'DG_Solution',nDims,HSize)
  ALLOCATE(U_local(nVar_State,0:HSize(2)-1,0:HSize(3)-1,0:HSize(4)-1,1:HSize(5)))
  CALL ReadArray('DG_Solution',5,INT(HSize),0,5,RealArray=U_local)

CASE('TimeAvg')
  CALL GetDataSize(File_ID,'Mean',nDims,HSize)
  nVar_State=SIZE(StrVarNames)
  ALLOCATE(VarNames_TimeAvg(INT(HSize(1))))
  CALL ReadAttribute(File_ID,'VarNames_Mean',INT(HSize(1)),StrArray=VarNames_TimeAvg)
  SDEALLOCATE(UOld)
  ALLOCATE(UOld(nVar_State,0:NState,0:NState,0:NState,nElemsOld))
  SDEALLOCATE(U)
  ALLOCATE(U   (nVar_State,0:NNew,  0:NNew,  0:NNew,  nElemsNew))
  ALLOCATE(U_local( nVar_State,0:HSize(2)-1,0:HSize(3)-1,0:HSize(4)-1,1:HSize(5)))
  ALLOCATE(UMean(INT(HSize(1)),0:HSize(2)-1,0:HSize(3)-1,0:HSize(4)-1,1:HSize(5)))
  CALL ReadArray('Mean',5,INT(HSize),0,5,RealArray=UMean)
  nVarsFound=0
  DO iVar=1,SIZE(StrVarNames)
    IF (TRIM(VarNames_TimeAvg(iVar)) .EQ. TRIM(StrVarNames(nVarsFound+1))) THEN
      nVarsFound = nVarsFound+1
      U_local(nVarsFound,:,:,:,:)=UMean(iVar,:,:,:,:)
    END IF
  END DO
  IF(nVarsFound .NE. SIZE(StrVarNames) ) CALL Abort(__STAMP__,&
    'TimeAvg file does not contain all necessary variables for converting to state')
END SELECT

#if PP_dim == 3
IF (HSize(4).EQ.1) THEN
  ! FLEXI compiled 3D, but data is 2D => expand third space dimension
  CALL ExpandArrayTo3D(5,(/nVar_State,NState+1,NState+1,1,nElemsOld/),4,NState+1,U_local,UOld)
ELSE
  ! FLEXI compiled 3D + data 3D
  UOld = U_local
END IF
#else
IF (HSize(4).EQ.1) THEN
  ! FLEXI compiled 2D + data 2D
  UOld = U_local
ELSE
  ! FLEXI compiled 2D, but data is 3D => reduce third space dimension
  CALL to2D_rank5((/1,0,0,0,1/),(/nVar_State,NState,NState,NState,nElemsOld/),4,U_local)
  UOld = U_local
END IF
#endif
DEALLOCATE(HSize)

! Read the current time
CALL ReadAttribute(File_ID,'Time',1,RealScalar=Time_State)

! Extract parameter file from userblock (if found)
CALL ExtractParameterFile(StateFile,TRIM(prmfile),userblockFound)
! Modify the polynomial degree in the parameterfile to NNew
CALL ModifyParameterFile(TRIM(prmfile),'N',NNew,userblockFound)
! prepare userblock file
CALL print_userblock(TRIM(UserBlockTmpFile)//C_NULL_CHAR,TRIM(prmfile)//C_NULL_CHAR)
INQUIRE(FILE=TRIM(UserBlockTmpFile),SIZE=userblock_total_len)

! Check for FV in solution
CALL GetVarNames('VarNamesAdd',VarNames_ElemData,VarNamesExist)
IF (VarNamesExist) THEN
  nVarsFound =  SIZE(VarNames_ElemData)
  DO iVar=1,nVarsFound
    IF (STRICMP(TRIM(VarNames_ElemData(iVar)),'FV_Elems')) &
      CALL PrintWarning('The Swapmesh tool does not support FV subcells at the moment!\n&
                        &FV cells are interpreted as DG cells, which might cause interpolation errors or even invalid solutions!')
  END DO
END IF

! Close the data file
CALL CloseDataFile()
SDEALLOCATE(VarNames_TimeAvg)
SDEALLOCATE(VarNames_ElemData)
SDEALLOCATE(UMean)
!SDEALLOCATE(UFluc)
DEALLOCATE(U_local)

END SUBROUTINE ReadOldStateFile


!===================================================================================================================================
!> Write the new state file by calling the WriteState routine from FLEXI. All necessary variables must have been set correctly!
!===================================================================================================================================
SUBROUTINE WriteNewStateFile()
! MODULES
USE MOD_PreProc
USE MOD_Globals
USE MOD_IO_HDF5
USE MOD_HDF5_Output,        ONLY: WriteState,WriteAttribute
USE MOD_Output_Vars,        ONLY: ProjectName
USE MOD_Swapmesh_Vars,      ONLY: Time_State,MeshFileNew,NodeTypeOut,NodeTypeState
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT / OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
CHARACTER(LEN=255)             :: FileName,FileType

!===================================================================================================================================
CALL WriteState(TRIM(MeshFileNew),Time_State,Time_State,isErrorFile=.FALSE.)

! Update the nodetype attribute in the State file, delete old attribute and rewrite
IF (NodeTypeOut.NE.NodeTypeState) THEN
  SWRITE(UNIT_stdOut,'(A)') "Updating NodeType in Statefile to new NodeType."
  FileType=MERGE('ERROR_State','State      ',.FALSE.)
  FileName=TRIM(TIMESTAMP(TRIM(ProjectName)//'_'//TRIM(FileType),Time_State))//'.h5'
  CALL OpenDataFile(FileName,create=.FALSE.,single=.TRUE.,readOnly=.FALSE.)
  CALL H5ADELETE_F(   File_ID,'NodeType',iError)
  CALL WriteAttribute(File_ID,'NodeType',1,StrScalar=(/NodeTypeOut/))
  CALL CloseDataFile()
END IF

END SUBROUTINE WriteNewStateFile


!===================================================================================================================================
!> Finalize swapmesh variables
!===================================================================================================================================
SUBROUTINE FinalizeSwapmesh()
! MODULES
USE MOD_Swapmesh_Vars
USE MOD_DG_Vars,         ONLY: U
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT / OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!===================================================================================================================================
SDEALLOCATE(Vdm_CLNGeo_EquiNSuper)
SDEALLOCATE(Vdm_CLNInter_GPNNew)
SDEALLOCATE(Vdm_GPNState_GPNNew)
SDEALLOCATE(xCLInter)
SDEALLOCATE(xCLOld)
SDEALLOCATE(xCLNew)
SDEALLOCATE(xiInter)
SDEALLOCATE(InterToElem)
SDEALLOCATE(equalElem)
SDEALLOCATE(IPDone)
SDEALLOCATE(UOld)
SDEALLOCATE(U)
SDEALLOCATE(Elem_IJK)

END SUBROUTINE FinalizeSwapmesh

END MODULE MOD_SwapMesh
