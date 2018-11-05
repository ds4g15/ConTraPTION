MODULE traadv_muscl2
   !!======================================================================
   !!                       ***  MODULE  traadv_muscl2  ***
   !! Ocean  tracers:  horizontal & vertical advective trend
   !!======================================================================
   !! History :  1.0  !  2002-06  (G. Madec) from traadv_muscl
   !!            3.2  !  2010-05  (C. Ethe, G. Madec)  merge TRC-TRA + switch from velocity to transport
   !!----------------------------------------------------------------------

   !!----------------------------------------------------------------------
   !!   tra_adv_muscl2 : update the tracer trend with the horizontal
   !!                    and vertical advection trends using MUSCL2 scheme
   !!----------------------------------------------------------------------
   USE oce             ! ocean dynamics and active tracers
   USE dom_oce         ! ocean space and time domain
   USE trdmod_oce      ! tracers trends 
   USE trdtra          ! tracers trends 
   USE in_out_manager  ! I/O manager
   USE dynspg_oce      ! choice/control of key cpp for surface pressure gradient
   USE trabbl          ! tracers: bottom boundary layer
   USE lib_mpp         ! distribued memory computing
   USE lbclnk          ! ocean lateral boundary condition (or mpp link) 
   USE diaptr          ! poleward transport diagnostics
   USE trc_oce         ! share passive tracers/Ocean variables
   USE wrk_nemo        ! Memory Allocation
   USE timing          ! Timing
   USE lib_fortran     ! Fortran utilities (allows no signed zero when 'key_nosignedzero' defined)


   IMPLICIT NONE
   PRIVATE

   PUBLIC   tra_adv_muscl2        ! routine called by step.F90

   LOGICAL  :: l_trd       ! flag to compute trends

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
   !!----------------------------------------------------------------------
   !!                   ***  vectopt_loop_substitute  ***
   !!----------------------------------------------------------------------
   !! ** purpose :   substitute the inner loop starting and inding indices 
   !!      to allow unrolling of do-loop using CPP macro.
   !!----------------------------------------------------------------------
   !!----------------------------------------------------------------------
   !! NEMO/OPA 3.3 , NEMO Consortium (2010)
   !! $Id: vectopt_loop_substitute.h90 2528 2010-12-27 17:33:53Z rblod $ 
   !! Software governed by the CeCILL licence (NEMOGCM/NEMO_CeCILL.txt)
   !!----------------------------------------------------------------------
   !!----------------------------------------------------------------------
   !! NEMO/OPA 3.3 , NEMO Consortium (2010)
   !! $Id: traadv_muscl2.F90 4500 2014-02-18 15:26:08Z timgraham $ 
   !! Software governed by the CeCILL licence     (NEMOGCM/NEMO_CeCILL.txt)
   !!----------------------------------------------------------------------
CONTAINS

   SUBROUTINE tra_adv_muscl2( kt, kit000, cdtype, p2dt, pun, pvn, pwn,      &
      &                                         ptb, ptn, pta, kjpt )
      !!----------------------------------------------------------------------
      !!                   ***  ROUTINE tra_adv_muscl2  ***
      !!
      !! ** Purpose :   Compute the now trend due to total advection of T and 
      !!      S using a MUSCL scheme (Monotone Upstream-centered Scheme for
      !!      Conservation Laws) and add it to the general tracer trend.
      !!
      !! ** Method  : MUSCL scheme plus centered scheme at ocean boundaries
      !!
      !! ** Action  : - update (pta) with the now advective tracer trends
      !!              - save trends 
      !!
      !! References : Estubier, A., and M. Levy, Notes Techn. Pole de Modelisation
      !!              IPSL, Sept. 2000 (http://www.lodyc.jussieu.fr/opa)
      !!----------------------------------------------------------------------
      USE oce     , ONLY:   zwx   => ua    , zwy   => va         ! (ua,va) used as 3D workspace
      !!
      INTEGER                              , INTENT(in   ) ::   kt              ! ocean time-step index
      INTEGER                              , INTENT(in   ) ::   kit000          ! first time step index
      CHARACTER(len=3)                     , INTENT(in   ) ::   cdtype          ! =TRA or TRC (tracer indicator)
      INTEGER                              , INTENT(in   ) ::   kjpt            ! number of tracers
      REAL(wp), DIMENSION(        jpk     ), INTENT(in   ) ::   p2dt            ! vertical profile of tracer time-step
      REAL(wp), DIMENSION(jpi,jpj,jpk     ), INTENT(in   ) ::   pun, pvn, pwn   ! 3 ocean velocity components
      REAL(wp), DIMENSION(jpi,jpj,jpk,kjpt), INTENT(in   ) ::   ptb, ptn        ! before & now tracer fields
      REAL(wp), DIMENSION(jpi,jpj,jpk,kjpt), INTENT(inout) ::   pta             ! tracer trend 
      !!
      INTEGER  ::   ji, jj, jk, jn   ! dummy loop indices
      REAL(wp) ::   zu, z0u, zzwx, zw         ! local scalars
      REAL(wp) ::   zv, z0v, zzwy, z0w        !   -      -
      REAL(wp) ::   ztra, zbtr, zdt, zalpha   !   -      -
      REAL(wp), POINTER, DIMENSION(:,:,:) :: zslpx, zslpy
      !!----------------------------------------------------------------------
      !
      IF( nn_timing == 1 )  CALL timing_start('tra_adv_muscl2')
      !
      CALL wrk_alloc( jpi, jpj, jpk, zslpx, zslpy )
      !

      IF( kt == kit000 )  THEN
         IF(lwp) WRITE(numout,*)
         IF(lwp) WRITE(numout,*) 'tra_adv_muscl2 : MUSCL2 advection scheme on ', cdtype
         IF(lwp) WRITE(numout,*) '~~~~~~~~~~~~~~~'
      ENDIF
      !
      l_trd = .FALSE.
      IF( ( cdtype == 'TRA' .AND. l_trdtra ) .OR. ( cdtype == 'TRC' .AND. l_trdtrc ) )   l_trd = .TRUE.
      !                                                          ! ===========
      DO jn = 1, kjpt                                            ! tracer loop
         !                                                       ! ===========
         ! I. Horizontal advective fluxes
         ! ------------------------------
         ! first guess of the slopes
         zwx(:,:,jpk) = 0.e0   ;   zwy(:,:,jpk) = 0.e0        ! bottom values
         ! interior values
         DO jk = 1, jpkm1
            DO jj = 1, jpjm1      
               DO ji = 1, jpim1   ! vector opt.
                  zwx(ji,jj,jk) = umask(ji,jj,jk) * ( ptb(ji+1,jj,jk,jn) - ptb(ji,jj,jk,jn) )
                  zwy(ji,jj,jk) = vmask(ji,jj,jk) * ( ptb(ji,jj+1,jk,jn) - ptb(ji,jj,jk,jn) )
               END DO
           END DO
         END DO
         !
         CALL lbc_lnk( zwx, 'U', -1. )                        ! lateral boundary conditions on zwx, zwy   (changed sign)
         CALL lbc_lnk( zwy, 'V', -1. )
         !                                             !-- Slopes of tracer
         zslpx(:,:,jpk) = 0.e0   ;   zslpy(:,:,jpk) = 0.e0    ! bottom values
         DO jk = 1, jpkm1                                     ! interior values
            DO jj = 2, jpj
               DO ji = 2, jpi   ! vector opt.
                  zslpx(ji,jj,jk) =                    ( zwx(ji,jj,jk) + zwx(ji-1,jj  ,jk) )   &
                     &            * ( 0.25 + SIGN( 0.25, zwx(ji,jj,jk) * zwx(ji-1,jj  ,jk) ) )
                  zslpy(ji,jj,jk) =                    ( zwy(ji,jj,jk) + zwy(ji  ,jj-1,jk) )   &
                     &            * ( 0.25 + SIGN( 0.25, zwy(ji,jj,jk) * zwy(ji  ,jj-1,jk) ) )
               END DO
            END DO
         END DO
         !
         DO jk = 1, jpkm1                                     ! Slopes limitation
            DO jj = 2, jpj
               DO ji = 2, jpi   ! vector opt.
                  zslpx(ji,jj,jk) = SIGN( 1., zslpx(ji,jj,jk) ) * MIN(    ABS( zslpx(ji  ,jj,jk) ),   &
                     &                                                 2.*ABS( zwx  (ji-1,jj,jk) ),   &
                     &                                                 2.*ABS( zwx  (ji  ,jj,jk) ) )
                  zslpy(ji,jj,jk) = SIGN( 1., zslpy(ji,jj,jk) ) * MIN(    ABS( zslpy(ji,jj  ,jk) ),   &
                     &                                                 2.*ABS( zwy  (ji,jj-1,jk) ),   &
                     &                                                 2.*ABS( zwy  (ji,jj  ,jk) ) )
               END DO
           END DO
         END DO             ! interior values

        !                                             !-- MUSCL horizontal advective fluxes
         DO jk = 1, jpkm1                                     ! interior values
            zdt  = p2dt(jk)
            DO jj = 2, jpjm1
               DO ji = 2, jpim1   ! vector opt.
                  ! MUSCL fluxes
                  z0u = SIGN( 0.5, pun(ji,jj,jk) )
                  zalpha = 0.5 - z0u
                  zu  = z0u - 0.5 * pun(ji,jj,jk) * zdt / ( e1u(ji,jj) * e2u(ji,jj) * e3u(ji,jj,jk) )
                  zzwx = ptb(ji+1,jj,jk,jn) + zu * zslpx(ji+1,jj,jk)
                  zzwy = ptb(ji  ,jj,jk,jn) + zu * zslpx(ji  ,jj,jk)
                  zwx(ji,jj,jk) = pun(ji,jj,jk) * ( zalpha * zzwx + (1.-zalpha) * zzwy )
                  !
                  z0v = SIGN( 0.5, pvn(ji,jj,jk) )
                  zalpha = 0.5 - z0v
                  zv  = z0v - 0.5 * pvn(ji,jj,jk) * zdt / ( e1v(ji,jj) * e2v(ji,jj) * e3v(ji,jj,jk) )
                  zzwx = ptb(ji,jj+1,jk,jn) + zv * zslpy(ji,jj+1,jk)
                  zzwy = ptb(ji,jj  ,jk,jn) + zv * zslpy(ji,jj  ,jk)
                  zwy(ji,jj,jk) = pvn(ji,jj,jk) * ( zalpha * zzwx + (1.-zalpha) * zzwy )
               END DO
            END DO
         END DO

         !!  centered scheme at lateral b.C. if off-shore velocity
         DO jk = 1, jpkm1
            DO jj = 2, jpjm1
               DO ji = 2, jpim1   ! vector opt.
                  IF( umask(ji,jj,jk) == 0. ) THEN
                     IF( pun(ji+1,jj,jk) > 0. .AND. ji /= jpi ) THEN
                        zwx(ji+1,jj,jk) = 0.5 * pun(ji+1,jj,jk) * ( ptn(ji+1,jj,jk,jn) + ptn(ji+2,jj,jk,jn) )
                     ENDIF
                     IF( pun(ji-1,jj,jk) < 0. ) THEN
                        zwx(ji-1,jj,jk) = 0.5 * pun(ji-1,jj,jk) * ( ptn(ji-1,jj,jk,jn) + ptn(ji,jj,jk,jn) ) 
                     ENDIF
                  ENDIF
                  IF( vmask(ji,jj,jk) == 0. ) THEN
                     IF( pvn(ji,jj+1,jk) > 0. .AND. jj /= jpj ) THEN
                        zwy(ji,jj+1,jk) = 0.5 * pvn(ji,jj+1,jk) * ( ptn(ji,jj+1,jk,jn) + ptn(ji,jj+2,jk,jn) )
                     ENDIF
                     IF( pvn(ji,jj-1,jk) < 0. ) THEN
                        zwy(ji,jj-1,jk) = 0.5 * pvn(ji,jj-1,jk) * ( ptn(ji,jj-1,jk,jn) + ptn(ji,jj,jk,jn) ) 
                     ENDIF
                  ENDIF
               END DO
            END DO
         END DO
         CALL lbc_lnk( zwx, 'U', -1. )   ;   CALL lbc_lnk( zwy, 'V', -1. )   ! lateral boundary condition (changed sign)

         ! Tracer flux divergence at t-point added to the general trend
         DO jk = 1, jpkm1
            DO jj = 2, jpjm1
               DO ji = 2, jpim1   ! vector opt.
                  zbtr = 1. / ( e1t(ji,jj) * e2t(ji,jj) * e3t(ji,jj,jk) )
                  ! horizontal advective trends 
                  ztra = - zbtr * ( zwx(ji,jj,jk) - zwx(ji-1,jj  ,jk  )   &
                  &               + zwy(ji,jj,jk) - zwy(ji  ,jj-1,jk  ) )
                  ! added to the general tracer trends
                  pta(ji,jj,jk,jn) = pta(ji,jj,jk,jn) + ztra
               END DO
           END DO
         END DO
         !                                 ! trend diagnostics (contribution of upstream fluxes)
         IF( l_trd ) THEN
            CALL trd_tra( kt, cdtype, jn, jptra_trd_xad, zwx, pun, ptb(:,:,:,jn) )
            CALL trd_tra( kt, cdtype, jn, jptra_trd_yad, zwy, pvn, ptb(:,:,:,jn) )
         END IF

         !                                 ! "Poleward" heat and salt transports (contribution of upstream fluxes)
         IF( cdtype == 'TRA' .AND. ln_diaptr .AND. ( MOD( kt, nn_fptr ) == 0 ) ) THEN
            IF( jn == jp_tem )  htr_adv(:) = ptr_vj( zwy(:,:,:) )
            IF( jn == jp_sal )  str_adv(:) = ptr_vj( zwy(:,:,:) )
         ENDIF

         ! II. Vertical advective fluxes
         ! -----------------------------
         !                                             !-- first guess of the slopes
         zwx (:,:, 1 ) = 0.e0    ;    zwx (:,:,jpk) = 0.e0    ! surface & bottom boundary conditions
         DO jk = 2, jpkm1                                     ! interior values
            zwx(:,:,jk) = tmask(:,:,jk) * ( ptb(:,:,jk-1,jn) - ptb(:,:,jk,jn) )
         END DO

         !                                             !-- Slopes of tracer
         zslpx(:,:,1) = 0.e0                                  ! surface values
         DO jk = 2, jpkm1                                     ! interior value
            DO jj = 1, jpj
               DO ji = 1, jpi
                  zslpx(ji,jj,jk) =                    ( zwx(ji,jj,jk) + zwx(ji,jj,jk+1) )   &
                     &            * ( 0.25 + SIGN( 0.25, zwx(ji,jj,jk) * zwx(ji,jj,jk+1) ) )
               END DO
            END DO
         END DO
         !                                             !-- Slopes limitation
         DO jk = 2, jpkm1                                     ! interior values
            DO jj = 1, jpj
               DO ji = 1, jpi
                  zslpx(ji,jj,jk) = SIGN( 1., zslpx(ji,jj,jk) ) * MIN(    ABS( zslpx(ji,jj,jk  ) ),   &
                     &                                                 2.*ABS( zwx  (ji,jj,jk+1) ),   &
                     &                                                 2.*ABS( zwx  (ji,jj,jk  ) )  )
               END DO
            END DO
         END DO
         !                                             !-- vertical advective flux
         !                                                    ! surface values  (bottom already set to zero)
         IF( lk_vvl ) THEN    ;   zwx(:,:, 1 ) = 0.e0                      !  variable volume
         ELSE                 ;   zwx(:,:, 1 ) = pwn(:,:,1) * ptb(:,:,1,jn)   ! linear free surface
         ENDIF
         !
         DO jk = 1, jpkm1                                     ! interior values
            zdt  = p2dt(jk)
            DO jj = 2, jpjm1
               DO ji = 2, jpim1   ! vector opt.
                  zbtr = 1. / ( e1t(ji,jj) * e2t(ji,jj) * e3w(ji,jj,jk+1) )
                  z0w = SIGN( 0.5, pwn(ji,jj,jk+1) )
                  zalpha = 0.5 + z0w
                  zw  = z0w - 0.5 * pwn(ji,jj,jk+1) * zdt * zbtr
                  zzwx = ptb(ji,jj,jk+1,jn) + zw * zslpx(ji,jj,jk+1)
                  zzwy = ptb(ji,jj,jk  ,jn) + zw * zslpx(ji,jj,jk  )
                  zwx(ji,jj,jk+1) = pwn(ji,jj,jk+1) * ( zalpha * zzwx + (1.-zalpha) * zzwy )
               END DO
            END DO
         END DO
         !
         DO jk = 2, jpkm1        ! centered near the bottom
            DO jj = 2, jpjm1
               DO ji = 2, jpim1   ! vector opt.
                  IF( tmask(ji,jj,jk+1) == 0. ) THEN
                     IF( pwn(ji,jj,jk) > 0. ) THEN
                        zwx(ji,jj,jk) = 0.5 * pwn(ji,jj,jk) * ( ptn(ji,jj,jk-1,jn) + ptn(ji,jj,jk,jn) ) 
                     ENDIF
                  ENDIF
               END DO
            END DO
         END DO
         !
         DO jk = 1, jpkm1        ! Compute & add the vertical advective trend
            DO jj = 2, jpjm1      
               DO ji = 2, jpim1   ! vector opt.
                  zbtr = 1. / ( e1t(ji,jj) * e2t(ji,jj) * e3t(ji,jj,jk) )
                  ! vertical advective trends 
                  ztra = - zbtr * ( zwx(ji,jj,jk) - zwx(ji,jj,jk+1) )
                  ! added to the general tracer trends
                  pta(ji,jj,jk,jn) =  pta(ji,jj,jk,jn) + ztra
               END DO
            END DO
         END DO
         !                       ! trend diagnostics (contribution of upstream fluxes)
         IF( l_trd )  CALL trd_tra( kt, cdtype, jn, jptra_trd_zad, zwx, pwn, ptb(:,:,:,jn) )
         !
      END DO
      !
      CALL wrk_dealloc( jpi, jpj, jpk, zslpx, zslpy )
      !
      IF( nn_timing == 1 )  CALL timing_stop('tra_adv_muscl2')
      !
   END SUBROUTINE tra_adv_muscl2

   !!======================================================================
END MODULE traadv_muscl2
