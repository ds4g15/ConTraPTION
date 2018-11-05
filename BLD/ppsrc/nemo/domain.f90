MODULE domain
   !!==============================================================================
   !!                       ***  MODULE domain   ***
   !! Ocean initialization : domain initialization
   !!==============================================================================
   !! History :  OPA  !  1990-10  (C. Levy - G. Madec)  Original code
   !!                 !  1992-01  (M. Imbard) insert time step initialization
   !!                 !  1996-06  (G. Madec) generalized vertical coordinate 
   !!                 !  1997-02  (G. Madec) creation of domwri.F
   !!                 !  2001-05  (E.Durand - G. Madec) insert closed sea
   !!   NEMO     1.0  !  2002-08  (G. Madec)  F90: Free form and module
   !!            2.0  !  2005-11  (V. Garnier) Surface pressure gradient organization
   !!            3.3  !  2010-11  (G. Madec)  initialisation in C1D configuration
   !!----------------------------------------------------------------------
   
   !!----------------------------------------------------------------------
   !!   dom_init       : initialize the space and time domain
   !!   dom_nam        : read and contral domain namelists
   !!   dom_ctl        : control print for the ocean domain
   !!----------------------------------------------------------------------
   USE oce             ! ocean variables
   USE dom_oce         ! domain: ocean
   USE sbc_oce         ! surface boundary condition: ocean
   USE phycst          ! physical constants
   USE closea          ! closed seas
   USE in_out_manager  ! I/O manager
   USE lib_mpp         ! distributed memory computing library

   USE domhgr          ! domain: set the horizontal mesh
   USE domzgr          ! domain: set the vertical mesh
   USE domstp          ! domain: set the time-step
   USE dommsk          ! domain: set the mask system
   USE domwri          ! domain: write the meshmask file
   USE domvvl          ! variable volume
   USE c1d             ! 1D vertical configuration
   USE dyncor_c1d      ! Coriolis term (c1d case)         (cor_c1d routine)
   USE timing          ! Timing

   IMPLICIT NONE
   PRIVATE

   PUBLIC   dom_init   ! called by opa.F90

   !! * Substitutions
   !!----------------------------------------------------------------------
   !!                    ***  domzgr_substitute.h90   ***
   !!----------------------------------------------------------------------
   !! ** purpose :   substitute fsdep. and fse.., the vert. depth and scale
   !!      factors depending on the vertical coord. used, using CPP macro.
   !!----------------------------------------------------------------------
   !! History :  1.0  !  2005-10  (A. Beckmann, G. Madec) generalisation to all coord.
   !!            3.1  !  2009-02  (G. Madec, M. Leclair)  pure z* coordinate
   !!----------------------------------------------------------------------
! reference for s- or zps-coordinate (3D no time dependency)
! z- or s-coordinate (1D or 3D + no time dependency) use reference in all cases




   !!----------------------------------------------------------------------
   !! NEMO/OPA 3.3 , NEMO Consortium (2010)
   !! $Id: domzgr_substitute.h90 2528 2010-12-27 17:33:53Z rblod $
   !! Software governed by the CeCILL licence (NEMOGCM/NEMO_CeCILL.txt)
   !!----------------------------------------------------------------------
   !!-------------------------------------------------------------------------
   !! NEMO/OPA 3.3 , NEMO Consortium (2010)
   !! $Id: domain.F90 3720 2012-12-04 10:10:08Z cbricaud $
   !! Software governed by the CeCILL licence        (NEMOGCM/NEMO_CeCILL.txt)
   !!-------------------------------------------------------------------------
CONTAINS

   SUBROUTINE dom_init
      !!----------------------------------------------------------------------
      !!                  ***  ROUTINE dom_init  ***
      !!                    
      !! ** Purpose :   Domain initialization. Call the routines that are 
      !!              required to create the arrays which define the space 
      !!              and time domain of the ocean model.
      !!
      !! ** Method  : - dom_msk: compute the masks from the bathymetry file
      !!              - dom_hgr: compute or read the horizontal grid-point position
      !!                         and scale factors, and the coriolis factor
      !!              - dom_zgr: define the vertical coordinate and the bathymetry
      !!              - dom_stp: defined the model time step
      !!              - dom_wri: create the meshmask file if nmsh=1
      !!              - 1D configuration, move Coriolis, u and v at T-point
      !!----------------------------------------------------------------------
      INTEGER ::   jk          ! dummy loop argument
      INTEGER ::   iconf = 0   ! local integers
      !!----------------------------------------------------------------------
      !
      IF( nn_timing == 1 )   CALL timing_start('dom_init')
      !
      IF(lwp) THEN
         WRITE(numout,*)
         WRITE(numout,*) 'dom_init : domain initialization'
         WRITE(numout,*) '~~~~~~~~'
      ENDIF
      !
                             CALL dom_nam      ! read namelist ( namrun, namdom, namcla )
                             CALL dom_clo      ! Closed seas and lake
                             CALL dom_hgr      ! Horizontal mesh
                             CALL dom_zgr      ! Vertical mesh and bathymetry
                             CALL dom_msk      ! Masks
      IF( lk_vvl         )   CALL dom_vvl      ! Vertical variable mesh
      !
      IF( lk_c1d         )   CALL cor_c1d      ! 1D configuration: Coriolis set at T-point
      !
      hu(:,:) = 0._wp                          ! Ocean depth at U- and V-points
      hv(:,:) = 0._wp
      DO jk = 1, jpk
         hu(:,:) = hu(:,:) + e3u(:,:,jk) * umask(:,:,jk)
         hv(:,:) = hv(:,:) + e3v(:,:,jk) * vmask(:,:,jk)
      END DO
      !                                        ! Inverse of the local depth
      hur(:,:) = 1._wp / ( hu(:,:) + 1._wp - umask(:,:,1) ) * umask(:,:,1)
      hvr(:,:) = 1._wp / ( hv(:,:) + 1._wp - vmask(:,:,1) ) * vmask(:,:,1)

                             CALL dom_stp      ! time step
      IF( nmsh /= 0      )   CALL dom_wri      ! Create a domain file
      IF( .NOT.ln_rstart )   CALL dom_ctl      ! Domain control
      !
      IF( nn_timing == 1 )   CALL timing_stop('dom_init')
      !
   END SUBROUTINE dom_init


   SUBROUTINE dom_nam
      !!----------------------------------------------------------------------
      !!                     ***  ROUTINE dom_nam  ***
      !!                    
      !! ** Purpose :   read domaine namelists and print the variables.
      !!
      !! ** input   : - namrun namelist
      !!              - namdom namelist
      !!              - namcla namelist
      !!              - namnc4 namelist   ! "key_netcdf4" only
      !!----------------------------------------------------------------------
      USE ioipsl
      NAMELIST/namrun/ nn_no   , cn_exp    , cn_ocerst_in, cn_ocerst_out, ln_rstart , nn_rstctl,   &
         &             nn_it000, nn_itend  , nn_date0    , nn_leapy     , nn_istate , nn_stock ,   &
         &             nn_write, ln_dimgnnn, ln_mskland  , ln_clobber   , nn_chunksz
      NAMELIST/namdom/ nn_bathy , rn_e3zps_min, rn_e3zps_rat, nn_msh    , rn_hmin,   &
         &             nn_acc   , rn_atfp     , rn_rdt      , rn_rdtmin ,            &
         &             rn_rdtmax, rn_rdth     , nn_baro     , nn_closea
      NAMELIST/namcla/ nn_cla
      !!----------------------------------------------------------------------

      REWIND( numnam )              ! Namelist namrun : parameters of the run
      READ  ( numnam, namrun )
      !
      IF(lwp) THEN                  ! control print
         WRITE(numout,*)
         WRITE(numout,*) 'dom_nam  : domain initialization through namelist read'
         WRITE(numout,*) '~~~~~~~ '
         WRITE(numout,*) '   Namelist namrun'
         WRITE(numout,*) '      job number                      nn_no      = ', nn_no
         WRITE(numout,*) '      experiment name for output      cn_exp     = ', cn_exp
         WRITE(numout,*) '      restart logical                 ln_rstart  = ', ln_rstart
         WRITE(numout,*) '      control of time step            nn_rstctl  = ', nn_rstctl
         WRITE(numout,*) '      number of the first time step   nn_it000   = ', nn_it000
         WRITE(numout,*) '      number of the last time step    nn_itend   = ', nn_itend
         WRITE(numout,*) '      initial calendar date aammjj    nn_date0   = ', nn_date0
         WRITE(numout,*) '      leap year calendar (0/1)        nn_leapy   = ', nn_leapy
         WRITE(numout,*) '      initial state output            nn_istate  = ', nn_istate
         WRITE(numout,*) '      frequency of restart file       nn_stock   = ', nn_stock
         WRITE(numout,*) '      frequency of output file        nn_write   = ', nn_write
         WRITE(numout,*) '      multi file dimgout              ln_dimgnnn = ', ln_dimgnnn
         WRITE(numout,*) '      mask land points                ln_mskland = ', ln_mskland
         WRITE(numout,*) '      overwrite an existing file      ln_clobber = ', ln_clobber
         WRITE(numout,*) '      NetCDF chunksize (bytes)        nn_chunksz = ', nn_chunksz
      ENDIF

      no = nn_no                    ! conversion DOCTOR names into model names (this should disappear soon)
      cexper = cn_exp
      nrstdt = nn_rstctl
      nit000 = nn_it000
      nitend = nn_itend
      ndate0 = nn_date0
      nleapy = nn_leapy
      ninist = nn_istate
      nstock = nn_stock
      nwrite = nn_write


      !                             ! control of output frequency
      IF ( nstock == 0 .OR. nstock > nitend ) THEN
         WRITE(ctmp1,*) 'nstock = ', nstock, ' it is forced to ', nitend
         CALL ctl_warn( ctmp1 )
         nstock = nitend
      ENDIF
      IF ( nwrite == 0 ) THEN
         WRITE(ctmp1,*) 'nwrite = ', nwrite, ' it is forced to ', nitend
         CALL ctl_warn( ctmp1 )
         nwrite = nitend
      ENDIF

      SELECT CASE ( nleapy )        ! Choose calendar for IOIPSL
      CASE (  1 ) 
         CALL ioconf_calendar('gregorian')
         IF(lwp) WRITE(numout,*) '   The IOIPSL calendar is "gregorian", i.e. leap year'
      CASE (  0 )
         CALL ioconf_calendar('noleap')
         IF(lwp) WRITE(numout,*) '   The IOIPSL calendar is "noleap", i.e. no leap year'
      CASE ( 30 )
         CALL ioconf_calendar('360d')
         IF(lwp) WRITE(numout,*) '   The IOIPSL calendar is "360d", i.e. 360 days in a year'
      END SELECT

      REWIND( numnam )              ! Namelist namdom : space & time domain (bathymetry, mesh, timestep)
      READ  ( numnam, namdom )

      IF(lwp) THEN
         WRITE(numout,*)
         WRITE(numout,*) '   Namelist namdom : space & time domain'
         WRITE(numout,*) '      flag read/compute bathymetry      nn_bathy     = ', nn_bathy
         WRITE(numout,*) '      min depth of the ocean    (>0) or    rn_hmin   = ', rn_hmin
         WRITE(numout,*) '      min number of ocean level (<0)       '
         WRITE(numout,*) '      minimum thickness of partial      rn_e3zps_min = ', rn_e3zps_min, ' (m)'
         WRITE(numout,*) '         step level                     rn_e3zps_rat = ', rn_e3zps_rat
         WRITE(numout,*) '      create mesh/mask file(s)          nn_msh       = ', nn_msh
         WRITE(numout,*) '           = 0   no file created           '
         WRITE(numout,*) '           = 1   mesh_mask                 '
         WRITE(numout,*) '           = 2   mesh and mask             '
         WRITE(numout,*) '           = 3   mesh_hgr, msh_zgr and mask'
         WRITE(numout,*) '      ocean time step                      rn_rdt    = ', rn_rdt
         WRITE(numout,*) '      asselin time filter parameter        rn_atfp   = ', rn_atfp
         WRITE(numout,*) '      time-splitting: nb of sub time-step  nn_baro   = ', nn_baro
         WRITE(numout,*) '      acceleration of converge             nn_acc    = ', nn_acc
         WRITE(numout,*) '        nn_acc=1: surface tracer rdt       rn_rdtmin = ', rn_rdtmin
         WRITE(numout,*) '                  bottom  tracer rdt       rdtmax    = ', rn_rdtmax
         WRITE(numout,*) '                  depth of transition      rn_rdth   = ', rn_rdth
         WRITE(numout,*) '      suppression of closed seas (=0)      nn_closea = ', nn_closea
      ENDIF

      ntopo     = nn_bathy          ! conversion DOCTOR names into model names (this should disappear soon)
      e3zps_min = rn_e3zps_min
      e3zps_rat = rn_e3zps_rat
      nmsh      = nn_msh
      nacc      = nn_acc
      atfp      = rn_atfp
      rdt       = rn_rdt
      rdtmin    = rn_rdtmin
      rdtmax    = rn_rdtmin
      rdth      = rn_rdth

      REWIND( numnam )              ! Namelist cross land advection
      READ  ( numnam, namcla )
      IF(lwp) THEN
         WRITE(numout,*)
         WRITE(numout,*) '   Namelist namcla'
         WRITE(numout,*) '      cross land advection                 nn_cla    = ', nn_cla
      ENDIF

      snc4set%luse = .FALSE.        ! No NetCDF 4 case
      !
   END SUBROUTINE dom_nam


   SUBROUTINE dom_ctl
      !!----------------------------------------------------------------------
      !!                     ***  ROUTINE dom_ctl  ***
      !!
      !! ** Purpose :   Domain control.
      !!
      !! ** Method  :   compute and print extrema of masked scale factors
      !!----------------------------------------------------------------------
      INTEGER ::   iimi1, ijmi1, iimi2, ijmi2, iima1, ijma1, iima2, ijma2
      INTEGER, DIMENSION(2) ::   iloc   ! 
      REAL(wp) ::   ze1min, ze1max, ze2min, ze2max
      !!----------------------------------------------------------------------
      !
      IF(lk_mpp) THEN
         CALL mpp_minloc( e1t(:,:), tmask(:,:,1), ze1min, iimi1,ijmi1 )
         CALL mpp_minloc( e2t(:,:), tmask(:,:,1), ze2min, iimi2,ijmi2 )
         CALL mpp_maxloc( e1t(:,:), tmask(:,:,1), ze1max, iima1,ijma1 )
         CALL mpp_maxloc( e2t(:,:), tmask(:,:,1), ze2max, iima2,ijma2 )
      ELSE
         ze1min = MINVAL( e1t(:,:), mask = tmask(:,:,1) == 1._wp )    
         ze2min = MINVAL( e2t(:,:), mask = tmask(:,:,1) == 1._wp )    
         ze1max = MAXVAL( e1t(:,:), mask = tmask(:,:,1) == 1._wp )    
         ze2max = MAXVAL( e2t(:,:), mask = tmask(:,:,1) == 1._wp )    

         iloc  = MINLOC( e1t(:,:), mask = tmask(:,:,1) == 1._wp )
         iimi1 = iloc(1) + nimpp - 1
         ijmi1 = iloc(2) + njmpp - 1
         iloc  = MINLOC( e2t(:,:), mask = tmask(:,:,1) == 1._wp )
         iimi2 = iloc(1) + nimpp - 1
         ijmi2 = iloc(2) + njmpp - 1
         iloc  = MAXLOC( e1t(:,:), mask = tmask(:,:,1) == 1._wp )
         iima1 = iloc(1) + nimpp - 1
         ijma1 = iloc(2) + njmpp - 1
         iloc  = MAXLOC( e2t(:,:), mask = tmask(:,:,1) == 1._wp )
         iima2 = iloc(1) + nimpp - 1
         ijma2 = iloc(2) + njmpp - 1
      ENDIF
      IF(lwp) THEN
         WRITE(numout,*)
         WRITE(numout,*) 'dom_ctl : extrema of the masked scale factors'
         WRITE(numout,*) '~~~~~~~'
         WRITE(numout,"(14x,'e1t maxi: ',1f10.2,' at i = ',i5,' j= ',i5)") ze1max, iima1, ijma1
         WRITE(numout,"(14x,'e1t mini: ',1f10.2,' at i = ',i5,' j= ',i5)") ze1min, iimi1, ijmi1
         WRITE(numout,"(14x,'e2t maxi: ',1f10.2,' at i = ',i5,' j= ',i5)") ze2max, iima2, ijma2
         WRITE(numout,"(14x,'e2t mini: ',1f10.2,' at i = ',i5,' j= ',i5)") ze2min, iimi2, ijmi2
      ENDIF
      !
   END SUBROUTINE dom_ctl

   !!======================================================================
END MODULE domain
