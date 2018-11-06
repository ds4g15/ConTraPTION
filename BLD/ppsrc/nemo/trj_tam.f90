MODULE trj_tam
   !!======================================================================
   !!                       ***  MODULE trj_tam ***
   !! NEMOVAR trajectory: Allocate and read the trajectory for linearzation
   !!======================================================================

   !!----------------------------------------------------------------------
   !!----------------------------------------------------------------------
   !!   bkg_init : Initialize the background fields from disk
   !!----------------------------------------------------------------------
   !! * Modules used
   USE par_oce
   USE tamtrj             ! Parameters for the assmilation interface
   USE in_out_manager
   USE oce                ! Model variables
   USE zdf_oce            ! Vertical mixing variables
   USE zdfddm             ! Double diffusion mixing parameterization
   USE zdfbfr
   USE trc_oce
   USE ldftra_oce         ! Lateral tracer mixing coefficient defined in memory
   USE ldfslp             ! Slopes of neutral surfaces
   USE tradmp             ! Tracer damping
   USE sbc_oce            ! Ocean surface boundary conditions
   USE iom                ! Library to read input files
   USE zdfmxl
   USE divcur             ! horizontal divergence and relative vorticity
   USE sshwzv
   USE oce_tam

   IMPLICIT NONE

   !! * Routine accessibility
   PRIVATE
   PUBLIC &
      & trj_rea,     &   !: Read trajectory at time step kstep into now fields
      & trj_rd_spl,  &   !: Read simple data (without interpolation)
      & trj_wri_spl, &   !: Write simple data (without interpolation)
      & tl_trj_wri,  &   !: Write simple linear-tangent data
      & tl_trj_ini,  &   !: initialize the model-tangent state trajectory
      & trj_deallocate   !: Deallocate all the saved variable

! 2014-01-13 - SAM
   PUBLIC ad_trj_ini, ad_trj_wri

   LOGICAL, PUBLIC :: &
      & ln_trjwri_tan = .FALSE.   !: No output of the state trajectory fields

! 2014-01-13 - SAM 
   LOGICAL, PUBLIC :: ln_trjwri_adj = .FALSE.

   CHARACTER (LEN=40), PUBLIC :: &
      & cn_tantrj                                  !: Filename for storing the
                                                   !: linear-tangent trajectory
! 2014-01-13 - SAM
   CHARACTER (LEN=40), PUBLIC :: cn_adjtrj

   INTEGER, PUBLIC :: &
      & nn_ittrjfrq_tan         !: Frequency of trajectory output for linear-tangent

! 2014-01-13 - SAM
! 2015-02-14 - SAM (re-added nn_ittrj0_adj on 2015-03-03 as inadvertantly deleted previous version)
   INTEGER, PUBLIC :: nn_ittrjfrq_adj, nn_ittrj0_adj

   !! * Module variables
   LOGICAL, SAVE :: &
      & ln_mem = .FALSE.      !: Flag for allocation
   INTEGER, SAVE :: inumtrj1 = -1, inumtrj2 = -1
   REAL(wp), SAVE :: &
      & stpr1, &
      & stpr2
   REAL(wp), ALLOCATABLE, DIMENSION(:,:), SAVE :: &
      & empr1,    &
      & empsr1,   &
      & empr2,    &
      & empsr2,   &
      & bfruar1,  &
      & bfrvar1,  &
      & bfruar2,  &
      & bfrvar2
   REAL(wp), ALLOCATABLE, DIMENSION(:,:), SAVE :: &
      & aeiur1,   &
      & aeivr1,   &
      & aeiwr1,   &
      & aeiur2,   &
      & aeivr2,   &
      & aeiwr2
  REAL(wp), ALLOCATABLE, DIMENSION(:,:,:), SAVE :: &
      & unr1,     &
      & vnr1,     &
      & tnr1,     &
      & snr1,     &
      & avmur1,   &
      & avmvr1,   &
      & avtr1,    &
      & uslpr1,   &
      & vslpr1,   &
      & wslpir1,  &
      & wslpjr1,  &
      & avsr1,    &
      & etot3r1,  &
      & unr2,     &
      & vnr2,     &
      & tnr2,     &
      & snr2,     &
      & avmur2,   &
      & avmvr2,   &
      & avtr2,    &
      & uslpr2,   &
      & vslpr2,   &
      & wslpir2,  &
      & wslpjr2,  &
      & avsr2,    &
      & etot3r2
  REAL(wp), ALLOCATABLE, DIMENSION(:,:), SAVE :: &
      & hmlp1,    &
      & hmlp2,    &
      & sshnr1,   & !
      & sshnr2      ! 
!!!2017-05-04 Added 'sshn' to trajectory

CONTAINS

   SUBROUTINE tl_trj_ini
      !!-----------------------------------------------------------------------
      !!
      !!                  ***  ROUTINE tl_trj_ini ***
      !!
      !! ** Purpose : initialize the model-tangent state trajectory
      !!
      !! ** Method  :
      !!
      !! ** Action  :
      !!
      !! References :
      !!
      !! History :
      !!        ! 10-07 (F. Vigilant)
      !!-----------------------------------------------------------------------

      IMPLICIT NONE

      !! * Modules used
      NAMELIST/namtl_trj/ nn_ittrjfrq_tan, ln_trjwri_tan, cn_tantrj

      ln_trjwri_tan = .FALSE.
      nn_ittrjfrq_tan = 1
      cn_tantrj = 'tl_trajectory'
      REWIND ( numnam )
      READ   ( numnam, namtl_trj )

      ! Control print
      IF(lwp) THEN
         WRITE(numout,*)
         WRITE(numout,*) 'tl_trj_ini : Linear-Tagent Trajectory handling:'
         WRITE(numout,*) '~~~~~~~~~~~~'
         WRITE(numout,*) '          Namelist namtl_trj : set trajectory parameters'
         WRITE(numout,*) '             Logical switch for writing out state trajectory         ', &
            &            ' ln_trjwri_tan = ', ln_trjwri_tan
         WRITE(numout,*) '             Frequency of trajectory output                          ', &
            &            ' nn_ittrjfrq_tan = ', nn_ittrjfrq_tan
      END IF
   END SUBROUTINE tl_trj_ini

   SUBROUTINE ad_trj_ini
      !!-----------------------------------------------------------------------
      !!
      !!                  ***  ROUTINE ad_trj_ini ***
      !!
      !! ** Purpose : initialize the adjoint trajectory
      !!
      !! ** Method  :
      !!
      !! ** Action  :
      !!
      !! References :
      !!
      !! History :
      !!        ! 2014-01-13 adapted copy of tl_trj_ini, 10-07 (F. Vigilant)
      !!        ! 2014-01-13 - SAM 
      !!-----------------------------------------------------------------------

      IMPLICIT NONE

      NAMELIST/namad_trj/ nn_ittrjfrq_adj, nn_ittrj0_adj, ln_trjwri_adj, cn_adjtrj

      ln_trjwri_adj = .FALSE.
      nn_ittrjfrq_adj = 1
      nn_ittrj0_adj = nit000-1
      cn_adjtrj = 'ad_trajectory'
      REWIND ( numnam )
      READ   ( numnam, namad_trj )

      ! Control print
      IF(lwp) THEN
         WRITE(numout,*)
         WRITE(numout,*) 'ad_trj_ini : Adjoint trajectory handling:'
         WRITE(numout,*) '~~~~~~~~~~~~'
         WRITE(numout,*) '          Namelist namad_trj : set trajectory parameters'
         WRITE(numout,*) '             Logical switch for writing out adjoint trajectory       ', &
            &            ' ln_trjwri_adj = ', ln_trjwri_adj
         WRITE(numout,*) '             Frequency of adjoint trajectory output                  ', &
            &            ' nn_ittrjfrq_adj = ', nn_ittrjfrq_adj
         WRITE(numout,*) '             Offset of adjoint trajectory output                     ', &
            &            ' nn_ittrj0_adj = ', nn_ittrj0_adj
      END IF
    END SUBROUTINE ad_trj_ini

   SUBROUTINE trj_rea( kstp, kdir, lreset )
      !!-----------------------------------------------------------------------
      !!
      !!                  ***  ROUTINE trj_reat  ***
      !!
      !! ** Purpose : Read from file the trjectory from the outer loop
      !!
      !! ** Method  : IOM
      !!
      !! ** Action  :
      !!
      !! References :
      !!
      !! History :
      !!        ! 08-05 (K. Mogensen) Initial version
      !!        ! 09-03 (F.Vigilant) Add reading of hmlp and calls (divcur, wzvmod)
      !!        ! 2010-04 (F. Vigilant) converison to 3.2
      !!        ! 2012-07 (P.-A. Bouttier) converison to 3.4
      !!-----------------------------------------------------------------------
      !! * Modules used
      !! * Arguments
      INTEGER, INTENT(in) :: &
         & kstp, &           ! Step for requested trajectory
         & kdir              ! Direction for stepping (1 forward, -1 backward
! 2014-06-16 - SAM: added lreset option
      LOGICAL, INTENT(in), OPTIONAL :: lreset ! Reset interpolation at given time step (Note, sensitive to value of kdir)
      !! * Local declarations
      CHARACTER (LEN=100) :: &
         & cl_dirtrj
      INTEGER :: &
         & inrcm,  &
         & inrcp,  &
         & inrc,   &
         & istpr1, &
         & istpr2, &
	 & it
      REAL(KIND=wp) :: &
         & zwtr1, &
         & zwtr2, &
         & zden,  &
         & zstp
      ! Initialize data and open file
      !! if step time is corresponding to a saved state
! 2014-06-16 - SAM: added lreset option
      IF ( ( MOD( kstp - nit000 + 1, nn_ittrjfrq ) == 0 ) .OR. PRESENT(lreset) ) THEN

! 2014-06-16 - SAM: added lreset option
!         it = kstp - nit000 + 1
         it = ((kstp - nit000 + 1 + nn_ittrjoffset) - MOD(kstp - nit000 + 1, nn_ittrjfrq))

         IF ( inumtrj1 == -1 ) THEN

            ! Define the input file
! 2014-03-25 - SAM: allow time step number in input/output filenames to be >5
!            WRITE(cl_dirtrj, FMT='(A,A,I6.6,".nc")' ) TRIM( cn_dirtrj ), '_', it
            WRITE(cl_dirtrj, FMT='(A,A,I0.8,".nc")' ) TRIM( cn_dirtrj ), '_', it
!!!2017-09-20 changing filenames to min 8 digits, no max

            !         WRITE(cl_dirtrj, FMT='(A,".nc")' ) TRIM( c_dirtrj )
            cl_dirtrj = TRIM( cl_dirtrj )

            IF(lwp) THEN

               WRITE(numout,*)
               WRITE(numout,*)'Reading non-linear fields from : ',TRIM(cl_dirtrj)
               WRITE(numout,*)

            ENDIF
            CALL iom_open( cl_dirtrj, inumtrj1 )
            if ( inumtrj1 == -1) CALL ctl_stop( 'No tam_trajectory cl_amstrj found' )
            IF ( .NOT. ln_mem ) THEN
               ALLOCATE( &
                  & empr1(jpi,jpj),  &
                  & empsr1(jpi,jpj), &
                  & empr2(jpi,jpj),  &
                  & empsr2(jpi,jpj), &
                  & bfruar1(jpi,jpj),&
                  & bfrvar1(jpi,jpj),&
                  & bfruar2(jpi,jpj),&
                  & bfrvar2(jpi,jpj) &
                  & )

               ALLOCATE( &
                  & unr1(jpi,jpj,jpk),     &
                  & vnr1(jpi,jpj,jpk),     &
                  & tnr1(jpi,jpj,jpk),     &
                  & snr1(jpi,jpj,jpk),     &
		  & sshnr1(jpi,jpj),       & !!!2017-05-04
                  & avmur1(jpi,jpj,jpk),   &
                  & avmvr1(jpi,jpj,jpk),   &
                  & avtr1(jpi,jpj,jpk),    &
                  & etot3r1(jpi,jpj,jpk),  &
                  & unr2(jpi,jpj,jpk),     &
                  & vnr2(jpi,jpj,jpk),     &
                  & tnr2(jpi,jpj,jpk),     &
                  & snr2(jpi,jpj,jpk),     & 
                  & sshnr2(jpi,jpj),       & !!!2017-05-04 added sshn to trajectory              
                  & avmur2(jpi,jpj,jpk),   &
                  & avmvr2(jpi,jpj,jpk),   &
                  & avtr2(jpi,jpj,jpk),    &
                  & etot3r2(jpi,jpj,jpk)   &
                  & )
               ALLOCATE( &
                  & aeiur1(jpi,jpj), &
                  & aeivr1(jpi,jpj), &
                  & aeiwr1(jpi,jpj), &
                  & aeiur2(jpi,jpj), &
                  & aeivr2(jpi,jpj), &
                  & aeiwr2(jpi,jpj)  &
                  & )

               ALLOCATE( &
                  & uslpr1(jpi,jpj,jpk),   &
                  & vslpr1(jpi,jpj,jpk),   &
                  & wslpir1(jpi,jpj,jpk),  &
                  & wslpjr1(jpi,jpj,jpk),  &
                  & uslpr2(jpi,jpj,jpk),   &
                  & vslpr2(jpi,jpj,jpk),   &
                  & wslpir2(jpi,jpj,jpk),  &
                  & wslpjr2(jpi,jpj,jpk)   &
                  & )


               ln_mem = .TRUE.
            ENDIF
         ENDIF


      ! Read records

         inrcm = INT( ( kstp - nit000 + 1 ) / nn_ittrjfrq ) + 1

         ! Copy record 1 into record 2
! 2014-06-16 - SAM: added lreset option
         IF ( ( kstp /= nitend )         .AND. &
            & ( kstp - nit000 + 1 /= 0 ) .AND. &
            & ( kdir == -1 ) .AND. &
            & .NOT.PRESENT(lreset) ) THEN

            stpr2           = stpr1

            empr2   (:,:)   = empr1   (:,:)
            empsr2  (:,:)   = empsr1  (:,:)
            bfruar2  (:,:)  = bfruar1 (:,:)
            bfrvar2  (:,:)  = bfrvar1 (:,:)

            unr2    (:,:,:) = unr1    (:,:,:)
            vnr2    (:,:,:) = vnr1    (:,:,:)
            tnr2    (:,:,:) = tnr1    (:,:,:)
            snr2    (:,:,:) = snr1    (:,:,:)
! 2017-05-04 Added 'sshn' to trajectory
            sshnr2   (:,:)   = sshnr1   (:,:)!
            avmur2  (:,:,:) = avmur1  (:,:,:)
            avmvr2  (:,:,:) = avmvr1  (:,:,:)
            avtr2   (:,:,:) = avtr1   (:,:,:)
            uslpr2  (:,:,:) = uslpr1  (:,:,:)
            vslpr2  (:,:,:) = vslpr1  (:,:,:)
            wslpir2 (:,:,:) = wslpir1 (:,:,:)
            wslpjr2 (:,:,:) = wslpjr1 (:,:,:)
            etot3r2 (:,:,:) = etot3r1 (:,:,:)
            aeiur2  (:,:)   = aeiur1  (:,:)
            aeivr2  (:,:)   = aeivr1  (:,:)
            aeiwr2  (:,:)   = aeiwr1  (:,:)

            istpr1 = INT( stpr1 )

            IF(lwp) WRITE(numout,*) &
               &                 '    Trajectory record copy time step = ', istpr1

         ENDIF

         IF ( ( kstp - nit000 + 1 /= 0 ) .AND. ( kdir == -1 ) ) THEN
            ! We update the input filename
! 2014-03-25 - SAM: allow time step number in input/output filenames to be >5
!            WRITE(cl_dirtrj, FMT='(A,A,I0.5,".nc")' ) TRIM(cn_dirtrj ), '_', (it-nn_ittrjfrq)
!            WRITE(cl_dirtrj, FMT='(A,A,I6.6,".nc")' ) TRIM(cn_dirtrj ), '_', (it-nn_ittrjfrq)
!!!2017-05-01 copied filename format from previous configuration

            WRITE(cl_dirtrj, FMT='(A,A,I0.8,".nc")' ) TRIM(cn_dirtrj ), '_', (it-nn_ittrjfrq)
            !!!2017-09-20 changing filnemaes to min 8 digits, no max

            cl_dirtrj = TRIM( cl_dirtrj )
            IF(lwp) THEN
               WRITE(numout,*)
               WRITE(numout,*)'Reading non-linear fields from : ',TRIM(cl_dirtrj)
               WRITE(numout,*)
            ENDIF
         ENDIF

         ! Read record 1

! 2014-06-16 - SAM: added lreset option
         IF ( ( kstp - nit000 + 1 == 0 ) .AND.( kdir == 1           ) .OR. &
            & ( kstp - nit000 + 1 /= 0 ) .AND.( kdir == -1          ) .OR. &
            & PRESENT(lreset) ) THEN

            IF ( kdir == -1 ) inrcm = inrcm - 1
!            inrc = inrcm
            ! temporary fix: currently, only one field by step time
            inrc = 1
            stpr1 = (inrcm - 1) * nn_ittrjfrq

            ! bug fixed to read several time the initial data
! 2014-06-29
!            IF ( ( kstp - nit000 + 1 == 0 ) .AND. ( kdir == 1 ) .OR. &
!                 & PRESENT(lreset) ) THEN
            IF ( ( kstp - nit000 + 1 == 0 ) .AND. ( kdir == 1 ) ) THEN
! 2014-06-29 .OR. &
! 2014-06-29                & PRESENT(lreset) ) THEN
               ! Define the input file
! 2014-03-25 - SAM: allow time step number in input/output filenames to be >5
!               WRITE(cl_dirtrj, FMT='(A,A,I6.6,".nc")' ) TRIM( cn_dirtrj ), '_', it
               WRITE(cl_dirtrj, FMT='(A,A,I0.8,".nc")' ) TRIM( cn_dirtrj ), '_', it
               !!!2017-09-20 changed filename structure - min 8 digits, no max

               cl_dirtrj = TRIM( cl_dirtrj )

               IF(lwp) THEN
                  WRITE(numout,*)
                  WRITE(numout,*)'Reading non-linear fields from : ',TRIM(cl_dirtrj)
                  WRITE(numout,*)
               ENDIF
            END IF
            IF ( inumtrj1 /= -1 )   CALL iom_open( cl_dirtrj, inumtrj1 )

            CALL iom_get( inumtrj1, jpdom_autoglo, 'emp'   , empr1   , inrc )
            CALL iom_get( inumtrj1, jpdom_autoglo, 'emps'  , empsr1  , inrc )
            CALL iom_get( inumtrj1, jpdom_autoglo, 'un'    , unr1    , inrc )
            CALL iom_get( inumtrj1, jpdom_autoglo, 'vn'    , vnr1    , inrc )
            CALL iom_get( inumtrj1, jpdom_autoglo, 'tn'    , tnr1    , inrc )
            CALL iom_get( inumtrj1, jpdom_autoglo, 'sn'    , snr1    , inrc )
! 2017-05-04 Added 'sshn' to trajectory
            CALL iom_get( inumtrj1, jpdom_autoglo, 'sshn'  , sshnr1  , inrc )!
            CALL iom_get( inumtrj1, jpdom_autoglo, 'avmu'  , avmur1  , inrc )
            CALL iom_get( inumtrj1, jpdom_autoglo, 'avmv'  , avmvr1  , inrc )
            CALL iom_get( inumtrj1, jpdom_autoglo, 'avt'   , avtr1   , inrc )
            CALL iom_get( inumtrj1, jpdom_autoglo, 'bfrua' , bfruar1 , inrc )
            CALL iom_get( inumtrj1, jpdom_autoglo, 'bfrva' , bfrvar1 , inrc )
            CALL iom_get( inumtrj1, jpdom_autoglo, 'uslp'  , uslpr1  , inrc )
            CALL iom_get( inumtrj1, jpdom_autoglo, 'vslp'  , vslpr1  , inrc )
            CALL iom_get( inumtrj1, jpdom_autoglo, 'wslpi' , wslpir1 , inrc )
            CALL iom_get( inumtrj1, jpdom_autoglo, 'wslpj' , wslpjr1 , inrc )
            CALL iom_get( inumtrj1, jpdom_autoglo, 'etot3' , etot3r1 , inrc )
            CALL iom_get( inumtrj1, jpdom_autoglo, 'aeiu'  , aeiur1  , inrc )
            CALL iom_get( inumtrj1, jpdom_autoglo, 'aeiv'  , aeivr1  , inrc )
            CALL iom_get( inumtrj1, jpdom_autoglo, 'aeiw'  , aeiwr1  , inrc )
            CALL iom_close( inumtrj1 )

            istpr1 = INT( stpr1 )
            IF(lwp)WRITE(numout,*) '   trajectory read time step = ', istpr1,&
               &                   '  record = ', inrc

         ENDIF


         ! Copy record 2 into record 1
! 2014-06-16 - SAM: added lreset option
         IF ( ( kstp - nit000 + 1 /= 0 ) .AND. &
            & ( kstp /= nitend         ) .AND. &
            & ( kdir == 1              ) .AND. &
            & .NOT.PRESENT(lreset) ) THEN

            stpr1           = stpr2
            empr1   (:,:)   = empr2   (:,:)
            empsr1  (:,:)   = empsr2  (:,:)
            bfruar1 (:,:)   = bfruar2 (:,:)
            bfrvar1 (:,:)   = bfrvar2 (:,:)
            unr1    (:,:,:) = unr2    (:,:,:)
            vnr1    (:,:,:) = vnr2    (:,:,:)
            tnr1    (:,:,:) = tnr2    (:,:,:)
            snr1    (:,:,:) = snr2    (:,:,:)
! 2017-05-04 Added 'sshn' to trajectory
            sshnr1  (:,:)   = sshnr2  (:,:)!
            avmur1  (:,:,:) = avmur2  (:,:,:)
            avmvr1  (:,:,:) = avmvr2  (:,:,:)
            avtr1   (:,:,:) = avtr2   (:,:,:)
            uslpr1  (:,:,:) = uslpr2  (:,:,:)
            vslpr1  (:,:,:) = vslpr2  (:,:,:)
            wslpir1 (:,:,:) = wslpir2 (:,:,:)
            wslpjr1 (:,:,:) = wslpjr2 (:,:,:)
            etot3r1 (:,:,:) = etot3r2 (:,:,:)
            aeiur1  (:,:)   = aeiur2  (:,:)
            aeivr1  (:,:)   = aeivr2  (:,:)
            aeiwr1  (:,:)   = aeiwr2  (:,:)

            istpr1 = INT( stpr1 )
            IF(lwp) WRITE(numout,*) &
               &                 '   Trajectory record copy time step = ', istpr1

         ENDIF

         ! Read record 2
! 2014-06-16 - SAM: added lreset option
         IF ( ( ( kstp /= nitend ) .AND. ( kdir == 1  )) .OR. &
            &   ( kstp == nitend ) .AND.(  kdir == -1   ) .OR. &
            & PRESENT(lreset) ) THEN

               ! Define the input file
               IF  (  kdir == -1   ) THEN
! 2014-03-25 - SAM: allow time step number in input/output filenames to be >5
!                   WRITE(cl_dirtrj, FMT='(A,A,I6.6,".nc")' ) TRIM( cn_dirtrj ), '_', it
                   WRITE(cl_dirtrj, FMT='(A,A,I0.8,".nc")' ) TRIM( cn_dirtrj ), '_', it
                   !!!2017-09-20 changed filename structure, min 8 digits, no max
               ELSE
! 2014-03-25 - SAM: allow time step number in input/output filenames to be >5
!                  WRITE(cl_dirtrj, FMT='(A,A,I6.6,".nc")' ) TRIM( cn_dirtrj ), '_', (it+nn_ittrjfrq)
                  WRITE(cl_dirtrj, FMT='(A,A,I0.8,".nc")' ) TRIM( cn_dirtrj ), '_', (it+nn_ittrjfrq)
                  !!!2017-09-20 changed filename structure, min 8 digits, no max

               ENDIF
               cl_dirtrj = TRIM( cl_dirtrj )

               IF(lwp) THEN
                  WRITE(numout,*)
                  WRITE(numout,*)'Reading non-linear fields from : ',TRIM(cl_dirtrj)
                  WRITE(numout,*)
               ENDIF

               CALL iom_open( cl_dirtrj, inumtrj2 )


            inrcp = inrcm + 1
            !            inrc  = inrcp
            inrc = 1  ! temporary  fix

            stpr2 = (inrcp - 1) * nn_ittrjfrq

            CALL iom_get( inumtrj2, jpdom_autoglo, 'emp'   , empr2   , inrc )
            CALL iom_get( inumtrj2, jpdom_autoglo, 'emps'  , empsr2  , inrc )
            CALL iom_get( inumtrj2, jpdom_autoglo, 'un'    , unr2    , inrc )
            CALL iom_get( inumtrj2, jpdom_autoglo, 'vn'    , vnr2    , inrc )
            CALL iom_get( inumtrj2, jpdom_autoglo, 'tn'    , tnr2    , inrc )
            CALL iom_get( inumtrj2, jpdom_autoglo, 'sn'    , snr2    , inrc )
! 2017-05-04 Added 'sshn' to trajectory
            CALL iom_get( inumtrj2, jpdom_autoglo, 'sshn'  , sshnr2  , inrc )!
            CALL iom_get( inumtrj2, jpdom_autoglo, 'avmu'  , avmur2  , inrc )
            CALL iom_get( inumtrj2, jpdom_autoglo, 'avmv'  , avmvr2  , inrc )
            CALL iom_get( inumtrj2, jpdom_autoglo, 'avt'   , avtr2   , inrc )
            CALL iom_get( inumtrj2, jpdom_autoglo, 'bfrua' , bfruar2 , inrc )
            CALL iom_get( inumtrj2, jpdom_autoglo, 'bfrva' , bfrvar2 , inrc )
            CALL iom_get( inumtrj2, jpdom_autoglo, 'uslp'  , uslpr2  , inrc )
            CALL iom_get( inumtrj2, jpdom_autoglo, 'vslp'  , vslpr2  , inrc )
            CALL iom_get( inumtrj2, jpdom_autoglo, 'wslpi' , wslpir2 , inrc )
            CALL iom_get( inumtrj2, jpdom_autoglo, 'wslpj' , wslpjr2 , inrc )
            CALL iom_get( inumtrj2, jpdom_autoglo, 'etot3' , etot3r2 , inrc )
            CALL iom_get( inumtrj2, jpdom_autoglo, 'aeiu'  , aeiur2  , inrc )
            CALL iom_get( inumtrj2, jpdom_autoglo, 'aeiv'  , aeivr2  , inrc )
            CALL iom_get( inumtrj2, jpdom_autoglo, 'aeiw'  , aeiwr2  , inrc )
            CALL iom_close( inumtrj2 )

            istpr2 = INT( stpr2 )
            IF(lwp)WRITE(numout,*) '   trajectory read2 time step = ', istpr2,&
               &                   '  record = ', inrc
         ENDIF

      ENDIF

!2014-06-16 - SAM: Warning if interpolation is attempted without having read in trajectory data
      IF ((inumtrj1==-1).OR.(inumtrj2==-1)) THEN
         IF(lwp) WRITE(numout,*) '   Warning! Interpolation of trajectory is attempted without', &
              & ' having trajectory data available'
      ENDIF

      ! Add warning for user
      IF ( (kstp == nitend) .AND. ( MOD( kstp - nit000 + 1, nn_ittrjfrq ) /= 0 )  ) THEN
          IF(lwp) WRITE(numout,*) '   Warning ! nitend (=',nitend, ')', &
               &                  ' and saving frequency (=',nn_ittrjfrq,') not compatible.'
      ENDIF

      ! Linear interpolate to the current step

      IF(lwp)WRITE(numout,*) '   linear interpolate to current', &
         &                   ' time step = ', kstp

      ! Interpolation coefficients

      zstp = kstp - nit000 + 1

      zden   = 1.0 / ( stpr2 - stpr1 )

      zwtr1  = ( stpr2 - zstp      ) * zden
      zwtr2  = ( zstp  - stpr1     ) * zden

      IF(lwp)WRITE(numout,*) '   linear interpolate coeff.', &
         &                   '  = ', zwtr1, zwtr2

! 2014-06-16 - SAM: correct transition of b->n for 'kdir==-1'
      IF ( ( kstp /= nit000-1 ).AND.( kdir == 1 ) ) THEN
         tsb(:,:,:,:) = tsn(:,:,:,:)
         ub(:,:,:) = un(:,:,:)
         vb(:,:,:) = vn(:,:,:)
      END IF
      emp(:,:)      = zwtr1 * empr1   (:,:)   + zwtr2 * empr2   (:,:)
      emps(:,:)     = zwtr1 * empsr1  (:,:)   + zwtr2 * empsr2  (:,:)
      bfrua(:,:)    = zwtr1 * bfruar1 (:,:)   + zwtr2 * bfruar2 (:,:)
      bfrva(:,:)    = zwtr1 * bfrvar1 (:,:)   + zwtr2 * bfrvar2 (:,:)
      un(:,:,:)     = zwtr1 * unr1    (:,:,:) + zwtr2 * unr2    (:,:,:)
      vn(:,:,:)     = zwtr1 * vnr1    (:,:,:) + zwtr2 * vnr2    (:,:,:)
      tsn(:,:,:,jp_tem)     = zwtr1 * tnr1    (:,:,:) + zwtr2 * tnr2    (:,:,:)
      tsn(:,:,:,jp_sal)     = zwtr1 * snr1    (:,:,:) + zwtr2 * snr2    (:,:,:)
! 2017-05-04 Added 'sshn' to trajectory
      sshn(:,:)     = zwtr1 * sshnr1    (:,:) + zwtr2 * sshnr2    (:,:)!
! 2014-06-16 - SAM: correct transition of b->n for 'kdir==-1'; Note, zstp should always be at leas stpr1+1
      IF ( kdir == -1 ) THEN
! 2015-03-09 - SAM: corrected 'stpr2 - zstp -1 ' to 'stpr2 - zstp + 1'
         zwtr1  = ( stpr2 - zstp + 1  ) * zden
         zwtr2  = ( zstp - 1 - stpr1 ) * zden
         ub(:,:,:)     = zwtr1 * unr1    (:,:,:) + zwtr2 * unr2    (:,:,:)
         vb(:,:,:)     = zwtr1 * vnr1    (:,:,:) + zwtr2 * vnr2    (:,:,:)
         tsb(:,:,:,jp_tem)     = zwtr1 * tnr1    (:,:,:) + zwtr2 * tnr2    (:,:,:)
         tsb(:,:,:,jp_sal)     = zwtr1 * snr1    (:,:,:) + zwtr2 * snr2    (:,:,:)

         IF(lwp)WRITE(numout,*) ' b linear interpolate coeff.', &
           &                   '  = ', zwtr1, zwtr2

         zwtr1  = ( stpr2 - zstp      ) * zden
         zwtr2  = ( zstp  - stpr1     ) * zden      
      END IF
! 2014-06-16 - SAM: added lreset option; Note, tsb, ub, vb are not
! set to values from the preceding time step, hence call to
! 'trj_rea(kstp,0)' should be followed by call to 'trj_rea' with
! 'kdir==1' or 'kdir==-1' (as it usually is when the common time step
! subroutines are called ('stp_tan' and 'stp_adj')
      IF ( ( kstp == nit000-1 ).OR.PRESENT(lreset) ) THEN
         tsb(:,:,:,:) = tsn(:,:,:,:)
         ub(:,:,:) = un(:,:,:)
         vb(:,:,:) = vn(:,:,:)
      END IF
      avmu(:,:,:)   = zwtr1 * avmur1  (:,:,:) + zwtr2 * avmur2  (:,:,:)
      avmv(:,:,:)   = zwtr1 * avmvr1  (:,:,:) + zwtr2 * avmvr2  (:,:,:)
      avt(:,:,:)    = zwtr1 * avtr1   (:,:,:) + zwtr2 * avtr2   (:,:,:)
      uslp(:,:,:)   = zwtr1 * uslpr1  (:,:,:) + zwtr2 * uslpr2  (:,:,:)
      vslp(:,:,:)   = zwtr1 * vslpr1  (:,:,:) + zwtr2 * vslpr2  (:,:,:)
      wslpi(:,:,:)  = zwtr1 * wslpir1 (:,:,:) + zwtr2 * wslpir2 (:,:,:)
      wslpj(:,:,:)  = zwtr1 * wslpjr1 (:,:,:) + zwtr2 * wslpjr2 (:,:,:)
      etot3(:,:,:)  = zwtr1 * etot3r1 (:,:,:) + zwtr2 * etot3r2 (:,:,:)
      aeiu(:,:)     = zwtr1 * aeiur1  (:,:)   + zwtr2 * aeiur2  (:,:)
      aeiv(:,:)     = zwtr1 * aeivr1  (:,:)   + zwtr2 * aeivr2  (:,:)
      aeiw(:,:)     = zwtr1 * aeiwr1  (:,:)   + zwtr2 * aeiwr2  (:,:)

      CALL ssh_wzv( kstp )

   END SUBROUTINE trj_rea


   SUBROUTINE trj_wri_spl(filename)
      !!-----------------------------------------------------------------------
      !!
      !!                  ***  ROUTINE trj_wri_spl ***
      !!
      !! ** Purpose : Write SimPLe data to file the model state trajectory
      !!
      !! ** Method  :
      !!
      !! ** Action  :
      !!
      !! History :
      !!        ! 09-07 (F. Vigilant)
      !!-----------------------------------------------------------------------
      !! *Module udes
      USE iom
      USE sol_oce, ONLY : & ! solver variables
      & gcb, gcx
      !! * Arguments
      !! * Local declarations
      INTEGER :: &
         & inum, &                  ! File unit number
         & fd                       ! field number
      CHARACTER (LEN=50) :: &
         & filename

      fd=1
      WRITE(filename, FMT='(A,A)' ) TRIM( filename ), '.nc'
      filename = TRIM( filename )
      CALL iom_open( filename, inum, ldwrt = .TRUE., kiolib = jprstlib)

      ! Output trajectory fields
      CALL iom_rstput( fd, fd, inum, 'un'   , un   )
      CALL iom_rstput( fd, fd, inum, 'vn'   , vn   )
      CALL iom_rstput( fd, fd, inum, 'tn'   , tsn(:,:,:,jp_tem)   )
      CALL iom_rstput( fd, fd, inum, 'sn'   , tsn(:,:,:,jp_sal)   )
      CALL iom_rstput( fd, fd, inum, 'sshn' , sshn )
      CALL iom_rstput( fd, fd, inum, 'wn'   , wn   )
      CALL iom_rstput( fd, fd, inum, 'tb'   , tsb(:,:,:,jp_tem)   )
      CALL iom_rstput( fd, fd, inum, 'sb'   , tsb(:,:,:,jp_sal)   )
      CALL iom_rstput( fd, fd, inum, 'ua'   , ua   )
      CALL iom_rstput( fd, fd, inum, 'va'   , va   )
      CALL iom_rstput( fd, fd, inum, 'ta'   , tsa(:,:,:,jp_tem)   )
      CALL iom_rstput( fd, fd, inum, 'sa'   , tsa(:,:,:,jp_sal)   )
      CALL iom_rstput( fd, fd, inum, 'sshb' , sshb )
      CALL iom_rstput( fd, fd, inum, 'rhd'  , rhd  )
      CALL iom_rstput( fd, fd, inum, 'rhop' , rhop )
      CALL iom_rstput( fd, fd, inum, 'gtu'  , gtsu(:,:,jp_tem)  )
      CALL iom_rstput( fd, fd, inum, 'gsu'  , gtsu(:,:,jp_sal)  )
      CALL iom_rstput( fd, fd, inum, 'gru'  , gru  )
      CALL iom_rstput( fd, fd, inum, 'gtv'  , gtsv(:,:,jp_tem)  )
      CALL iom_rstput( fd, fd, inum, 'gsv'  , gtsv(:,:,jp_sal)  )
      CALL iom_rstput( fd, fd, inum, 'grv'  , grv  )
      CALL iom_rstput( fd, fd, inum, 'rn2'  , rn2  )
      CALL iom_rstput( fd, fd, inum, 'gcb'  , gcb  )
      CALL iom_rstput( fd, fd, inum, 'gcx'  , gcx  )

      CALL iom_close( inum )

   END SUBROUTINE trj_wri_spl

   SUBROUTINE trj_rd_spl(filename)
      !!-----------------------------------------------------------------------
      !!
      !!                  ***  ROUTINE asm_trj__wop_rd ***
      !!
      !! ** Purpose : Read SimPLe data from file the model state trajectory
      !!
      !! ** Method  :
      !!
      !! ** Action  :
      !!
      !! History :
      !!        ! 09-07 (F. Vigilant)
      !!-----------------------------------------------------------------------
      !! *Module udes
      USE iom                 ! I/O module
      USE sol_oce, ONLY : & ! solver variables
      & gcb, gcx
      !! * Arguments
      !! * Local declarations
      INTEGER :: &
         & inum, &                  ! File unit number
         & fd                       ! field number
      CHARACTER (LEN=50) :: &
         & filename

      fd=1
      WRITE(filename, FMT='(A,A)' ) TRIM( filename ), '.nc'
      filename = TRIM( filename )
      CALL iom_open( filename, inum)

      ! Output trajectory fields
      CALL iom_get( inum, jpdom_autoglo, 'un'   , un,   fd )
      CALL iom_get( inum, jpdom_autoglo, 'vn'   , vn,   fd )
      CALL iom_get( inum, jpdom_autoglo, 'tn'   , tsn(:,:,:,jp_tem),   fd )
      CALL iom_get( inum, jpdom_autoglo, 'sn'   , tsn(:,:,:,jp_sal),   fd )
      CALL iom_get( inum, jpdom_autoglo, 'sshn' , sshn, fd )
      CALL iom_get( inum, jpdom_autoglo, 'wn'   , wn,   fd )
      CALL iom_get( inum, jpdom_autoglo, 'tb'   , tsb(:,:,:,jp_tem),   fd )
      CALL iom_get( inum, jpdom_autoglo, 'sb'   , tsb(:,:,:,jp_sal),   fd )
      CALL iom_get( inum, jpdom_autoglo, 'ua'   , ua,   fd )
      CALL iom_get( inum, jpdom_autoglo, 'va'   , va,   fd )
      CALL iom_get( inum, jpdom_autoglo, 'ta'   , tsa(:,:,:,jp_tem),   fd )
      CALL iom_get( inum, jpdom_autoglo, 'sa'   , tsa(:,:,:,jp_sal),   fd )
      CALL iom_get( inum, jpdom_autoglo, 'sshb' , sshb, fd )
      CALL iom_get( inum, jpdom_autoglo, 'rhd'  , rhd,  fd )
      CALL iom_get( inum, jpdom_autoglo, 'rhop' , rhop, fd )
      CALL iom_get( inum, jpdom_autoglo, 'gtu'  , gtsu(:,:,jp_tem),  fd )
      CALL iom_get( inum, jpdom_autoglo, 'gsu'  , gtsu(:,:,jp_sal),  fd )
      CALL iom_get( inum, jpdom_autoglo, 'gru'  , gru,  fd )
      CALL iom_get( inum, jpdom_autoglo, 'gtv'  , gtsv(:,:,jp_tem),  fd )
      CALL iom_get( inum, jpdom_autoglo, 'gsv'  , gtsv(:,:,jp_sal),  fd )
      CALL iom_get( inum, jpdom_autoglo, 'grv'  , grv,  fd )
      CALL iom_get( inum, jpdom_autoglo, 'rn2'  , rn2,  fd )
      CALL iom_get( inum, jpdom_autoglo, 'gcb'  , gcb,  fd )
      CALL iom_get( inum, jpdom_autoglo, 'gcx'  , gcx,  fd )

      CALL iom_close( inum )

   END SUBROUTINE trj_rd_spl

   SUBROUTINE tl_trj_wri(kstp)
      !!-----------------------------------------------------------------------
      !!
      !!                  ***  ROUTINE tl_trj_wri ***
      !!
      !! ** Purpose : Write SimPLe data to file the model state trajectory
      !!
      !! ** Method  :
      !!
      !! ** Action  :
      !!
      !! History :
      !!        ! 10-07 (F. Vigilant)
      !!-----------------------------------------------------------------------
      !! *Module udes
      USE iom
      !! * Arguments
      INTEGER, INTENT(in) :: &
         & kstp           ! Step for requested trajectory
      !! * Local declarations
      INTEGER :: &
         & inum           ! File unit number
      INTEGER :: &
         & it
      CHARACTER (LEN=50) :: &
         & filename
      CHARACTER (LEN=100) :: &
         & cl_tantrj

      ! Initialize data and open file
      !! if step time is corresponding to a saved state
      IF ( ( MOD( kstp - nit000 + 1, nn_ittrjfrq_tan ) == 0 )  ) THEN

         it = kstp - nit000 + 1

            ! Define the input file
! 2014-03-25 - SAM: allow time step number in input/output filenames to be >5
!            WRITE(cl_tantrj, FMT='(I6.6, A,A,".nc")' ) it, '_', TRIM( cn_tantrj )
            WRITE(cl_tantrj, FMT='(I0.8, A,A,".nc")' ) it, '_', TRIM( cn_tantrj )
            !!!2017-09-20 changed filename structure - min 8 digits, no max

            cl_tantrj = TRIM( cl_tantrj )

            IF(lwp) THEN
               WRITE(numout,*)
               WRITE(numout,*)'Writing linear-tangent fields from : ',TRIM(cl_tantrj)
               WRITE(numout,*)
            ENDIF

            CALL iom_open( cl_tantrj, inum, ldwrt = .TRUE., kiolib = jprstlib)

            ! Output trajectory fields
            CALL iom_rstput( it, it, inum, 'un_tl'   , un_tl   )
            CALL iom_rstput( it, it, inum, 'vn_tl'   , vn_tl   )
            CALL iom_rstput( it, it, inum, 'un'   , un   )
            CALL iom_rstput( it, it, inum, 'vn'   , vn   )
            CALL iom_rstput( it, it, inum, 'tn_tl'   , tsn_tl(:,:,:,jp_tem)   )
            CALL iom_rstput( it, it, inum, 'sn_tl'   , tsn_tl(:,:,:,jp_sal)   )
            CALL iom_rstput( it, it, inum, 'wn_tl'   , wn_tl   )
            CALL iom_rstput( it, it, inum, 'hdivn_tl', hdivn_tl)
            CALL iom_rstput( it, it, inum, 'rotn_tl' , rotn_tl )
            CALL iom_rstput( it, it, inum, 'rhd_tl' , rhd_tl )
            CALL iom_rstput( it, it, inum, 'rhop_tl' , rhop_tl )
            CALL iom_rstput( it, it, inum, 'sshn_tl' , sshn_tl )

            CALL iom_close( inum )

         ENDIF

   END SUBROUTINE tl_trj_wri

   SUBROUTINE ad_trj_wri(kstp, lforce)
      !!-----------------------------------------------------------------------
      !!
      !!                  ***  ROUTINE ad_trj_wri ***
      !!
      !! ** Purpose : Write out adjoint trajectory
      !!
      !! ** Method  :
      !!
      !! ** Action  :
      !!
      !! History :
      !!        ! 2014-01-13 adapted copy of tl_trj_wri, 10-07 (F. Vigilant)
      !!        ! 2014-01-13 SAM
      !!-----------------------------------------------------------------------
      !! *Module udes
      USE iom
      !! * Arguments
      INTEGER, INTENT(in) :: &
         & kstp           ! Step for requested trajectory
! 2015-02-15
      LOGICAL, INTENT(in), OPTIONAL :: lforce ! Force output
      !! * Local declarations
      INTEGER :: &
         & inum           ! File unit number
      INTEGER :: &
         & it
      CHARACTER (LEN=50) :: &
         & filename
      CHARACTER (LEN=100) :: &
         & cl_adjtrj

      ! Initialize data and open file
      !! if step time is corresponding to a saved state

      IF ( ( MOD( kstp - nit000 + 1 - nn_ittrj0_adj, nn_ittrjfrq_adj ) == 0 ) .OR. PRESENT(lforce) ) THEN

         it = kstp - nit000 + 1

            ! Define the input file
! 2014-03-25 - SAM: allow time step number in input/output filenames to be >5#

!            WRITE(cl_adjtrj, FMT='(I6.6, A,A,".nc")' ) it, '_', TRIM( cn_adjtrj )
            WRITE(cl_adjtrj, FMT='(I0.8, A,A,".nc")' ) it, '_', TRIM( cn_adjtrj )
            !!! 2017-09-20 changed filename structure - min 8 digits, max 8 digits 

            cl_adjtrj = TRIM( cl_adjtrj )

            IF(lwp) THEN
               WRITE(numout,*)
               WRITE(numout,*)'Writing adjoint fields from : ',TRIM(cl_adjtrj)
               WRITE(numout,*)
            ENDIF

            CALL iom_open( cl_adjtrj, inum, ldwrt = .TRUE., kiolib = jprstlib)

            ! Output trajectory fields
            CALL iom_rstput( it, it, inum, 'un_ad'   , un_ad   )
            CALL iom_rstput( it, it, inum, 'vn_ad'   , vn_ad   )
            CALL iom_rstput( it, it, inum, 'un'   , un   )
            CALL iom_rstput( it, it, inum, 'vn'   , vn   )
            CALL iom_rstput( it, it, inum, 'tn_ad'   , tsn_ad(:,:,:,jp_tem)   )
            CALL iom_rstput( it, it, inum, 'sn_ad'   , tsn_ad(:,:,:,jp_sal)   )
            CALL iom_rstput( it, it, inum, 'wn_ad'   , wn_ad   )
            CALL iom_rstput( it, it, inum, 'hdivn_ad', hdivn_ad)
            CALL iom_rstput( it, it, inum, 'rotn_ad' , rotn_ad )
            CALL iom_rstput( it, it, inum, 'rhd_ad' , rhd_ad )
            CALL iom_rstput( it, it, inum, 'rhop_ad' , rhop_ad )
            CALL iom_rstput( it, it, inum, 'sshn_ad' , sshn_ad )

            CALL iom_close( inum )

         ENDIF

   END SUBROUTINE ad_trj_wri


   SUBROUTINE trj_deallocate
      !!-----------------------------------------------------------------------
      !!
      !!                  ***  ROUTINE trj_deallocate ***
      !!
      !! ** Purpose : Deallocate saved trajectory arrays
      !!
      !! ** Method  :
      !!
      !! ** Action  :
      !!
      !! History :
      !!        ! 2010-06 (A. Vidard)
      !!-----------------------------------------------------------------------

         IF ( ln_mem ) THEN
            DEALLOCATE(  &
               & empr1,  &
               & empsr1, &
               & empr2,  &
               & empsr2, &
               & bfruar1,&
               & bfrvar1,&
               & bfruar2,&
               & bfrvar2 &
               & )
!!!2017-05-04 added 'sshn' to trajectory
            DEALLOCATE(    &
               & unr1,     &
               & vnr1,     &
               & tnr1,     &
               & snr1,     &
               & sshnr1,   &!
               & avmur1,   &
               & avmvr1,   &
               & avtr1,    &
               & etot3r1,  &
               & unr2,     &
               & vnr2,     &
               & tnr2,     &
               & snr2,     &
               & sshnr2,   &!
               & avmur2,   &
               & avmvr2,   &
               & avtr2,    &
               & etot3r2   &
               & )

            DEALLOCATE(  &
               & aeiur1, &
               & aeivr1, &
               & aeiwr1, &
               & aeiur2, &
               & aeivr2, &
               & aeiwr2  &
               & )

            DEALLOCATE(    &
               & uslpr1,   &
               & vslpr1,   &
               & wslpir1,  &
               & wslpjr1,  &
               & uslpr2,   &
               & vslpr2,   &
               & wslpir2,  &
               & wslpjr2   &
               & )


            ln_mem = .FALSE.
	 ENDIF
         END SUBROUTINE trj_deallocate
END MODULE trj_tam