MODULE pttam
!2017-02-10/16 separated TAM  passive tracer time step loops from nemogcm_tam.F90

  USE par_oce
  USE domain
  USE oce
  USE oce_tam
  USE sbc_oce_tam
  USE sbc_oce, ONLY:rnf_b !!! 2017-03-24 temporary fix to avoid problems with uninitialised field rnf_b
  USE sol_oce_tam
  USE tamctl
  USE iom
  USE trj_tam
  USE wrk_nemo
  USE step_tam, ONLY: stp_tan, stp_adj
  USE step_oce_tam
  !!!! For initialisation as in test subroutine of OPATAM_SRC/step.F90
  !!!! 2016-07-21: added qrp_ad, erp_ad
  ! 2017-03-24: added nn_sstr
  USE sbcssr_tam, ONLY: qrp_tl, erp_tl, qrp_ad, erp_ad, nn_sstr
  !!!! 2016-06-20: added adjoint time stepping loop
  USE sbcfwb_tam, ONLY: a_fwb_tl, a_fwb_ad
  ! 2017-04-25 Temporary installation of sbc_tmp_rm, may be replaced in the future
  USE sbcmod_tam, ONLY: sbc_tmp_rm

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

  IMPLICIT NONE

  PRIVATE

  ! Namelisted variables
  CHARACTER(len=132),PUBLIC :: cn_pttam_init
  INTEGER                   :: nn_pttam_out_freq

  !!!! 2016-06-20: added adjoint time stepping loop
  INTEGER :: jk
  
  ! Variable declaration
  REAL(KIND=wp), POINTER, DIMENSION(:,:,:) :: ztn_tlin
  INTEGER:: ncid

  ! 2016-06-21 added global mask used to select region
  REAL(wp), PUBLIC, ALLOCATABLE, SAVE, DIMENSION(:,:,:) :: tmsk_region
  REAL(wp), PUBLIC, ALLOCATABLE, SAVE, DIMENSION(:,:,:) :: tmsk_nasmw !!! 2016-08-19 added new variable to create edw mask
  REAL(wp), PUBLIC, ALLOCATABLE, SAVE, DIMENSION(:,:):: tmp_rm,sal_rm !: 2017-03-24  mean tracer volume removed in top layer
  PUBLIC pt_init 
  PUBLIC pt_finalise
  PUBLIC pt_run
  PUBLIC pt_tam_wri !2017-03-03 added subroutine to write output variables to file 

CONTAINS 

  SUBROUTINE pt_init

    NAMELIST/nampttam/cn_pttam_init, nn_pttam_out_freq

    cn_pttam_init = 'PTTAM_init.nc'
    nn_pttam_out_freq = 15

    REWIND(numnam)
    READ(numnam, nampttam)
    IF (lwp) THEN
       WRITE(numout,*) "pttam - filename for initialisation field: ", TRIM(cn_pttam_init)
       WRITE(numout,*) "pttam - 1/(output frequency):              ", nn_pttam_out_freq
    END IF

    !!!! 2016-06-21 added global mask used to select region
    IF (.NOT.ALLOCATED(tmsk_region)) ALLOCATE(tmsk_region(jpi, jpj, jpk))
    !!!! 2016-08-23
    IF (.NOT.ALLOCATED(tmsk_nasmw)) ALLOCATE(tmsk_nasmw(jpi, jpj, jpk))

    IF (.NOT.ALLOCATED(tmp_rm))    ALLOCATE(tmp_rm(jpi,jpj), sal_rm(jpi,jpj))

    !!!! 2016-06-21 added global mask used to select region
    tmsk_region(:,:,:) = 0._wp
    !!!! 2016-08-23
    tmsk_nasmw(:,:,:) = 0._wp
    
    tmp_rm(:,:) = 0._wp
    sal_rm(:,:) = 0._wp !2017-03-24 storage surface removal of tracer by damping

    !!! 2017-03-24 temporary fix to avoid problems with uninitialised field rnf_b
                  !temporarily force flux boundary condition
    rnf_b(:,:) = 0.0_wp

  END SUBROUTINE pt_init

  SUBROUTINE pt_finalise

    !!!! 2016-06-21 added global mask used to select region
    DEALLOCATE(tmsk_region)
    !!!! 2016-08-23
    DEALLOCATE(tmsk_nasmw)
 
     IF(ALLOCATED(tmp_rm)) DEALLOCATE(tmp_rm,sal_rm)

  END SUBROUTINE pt_finalise

  SUBROUTINE pt_run(pn_swi)

    INTEGER::pn_swi

    IF (pn_swi == 200) THEN
       CALL pt_tan
    ELSEIF (pn_swi == 201) THEN
       CALL pt_adj
    END IF
    
  END SUBROUTINE pt_run

  SUBROUTINE pt_tan

    INTEGER::istep

!    CHARACTER(LEN=132)::zfname !moved to other subroutine 2017-03-03
    
    ! Initialisation as in test subroutine of OPATAM_SRC/step.F90
    CALL     oce_tam_init(1)
    CALL sbc_oce_tam_init(1)
    CALL sol_oce_tam_init(1)
    qrp_tl = 0.0_wp
    erp_tl = 0.0_wp   
    emp_tl(:,:) = 0.0_wp
    a_fwb_tl = 0.0_wp

    ! Variable allocation and initialisation
    CALL wrk_alloc(jpi,jpj,jpk,ztn_tlin)
    ztn_tlin(:,:,:) = 0.0_wp

    ! Reading in of initial perturbation
    !!!! 2016-05-16 added variable for name of initial tracer distribution
    CALL iom_open(cn_pttam_init,ncid,kiolib = jpnf90)
    CALL iom_get(ncid,jpdom_autoglo,"Tinit",ztn_tlin,0)

    ztn_tlin(:,:,:) = ztn_tlin(:,:,:)*tmask(:,:,:)

    CALL lbc_lnk(ztn_tlin(:,:,:), 'T', 1.0_wp)

    ! 2016-06-21 added global mask used to select region
    tmsk_region(:,:,:) = ztn_tlin(:,:,:)

    ! Initialisation of TL model
    istep = nit000 - 1
    CALL trj_rea( istep, 1)
    istep = nit000

    CALL day_tam(nit000, 0)
    un_tl(:,:,:) = 0.0_wp
    vn_tl(:,:,:) = 0.0_wp
    sshn_tl(:,:) = 0.0_wp
    ! 2016-06-09 added switch and frequency for on-line resetting of NASMW
!!!later IF (ln_tl_nasmw_auto) THEN
!!!later    WHERE ((tsn(:,:,:,jp_tem) >= 17.0_wp).AND.(tsn(:,:,:,jp_tem) <= 19.0_wp))
!!!later       tsn_tl(:,:,:,jp_tem) = ztn_tlin(:,:,:)
!!!later       tsn_tl(:,:,:,jp_sal) = ztn_tlin(:,:,:)
!!!later    END WHERE
!!!later ELSEIF (ln_edw_auto) THEN
!!!later    tsn_tl(:,:,:,jp_tem) = tmsk_region(:,:,:)*tmsk_nasmw(:,:,:)
!!!later    tsn_tl(:,:,:,jp_sal) = tmsk_region(:,:,:)*tmsk_nasmw(:,:,:)
!!!later ELSE
       tsn_tl(:,:,:,jp_tem) = ztn_tlin(:,:,:)
       tsn_tl(:,:,:,jp_sal) = ztn_tlin(:,:,:)
!!!later END IF
    CALL iom_close(ncid)

    ub_tl(:,:,:) = 0.0_wp
    vb_tl(:,:,:) = 0.0_wp
    sshb_tl(:,:) = 0.0_wp
    tsb_tl(:,:,:,jp_tem) = ztn_tlin(:,:,:)
    tsb_tl(:,:,:,jp_sal) = ztn_tlin(:,:,:)

    CALL pt_tam_wri(nit000 - 1,0) !write to output file for initial step
    CALL istate_init_tan
    ! Time step loop
    DO istep = nit000, nitend, 1
       CALL stp_tan( istep )
       IF (nn_sstr == 1) THEN
          tmp_rm(:,:) = tmp_rm(:,:) - qrp_tl(:,:)*rdttra(1)*ro0cpr*e1t(:,:)*e2t(:,:)
       END IF
       
       un_tl(:,:,:) = 0.0_wp
       vn_tl(:,:,:) = 0.0_wp
       sshn_tl(:,:) = 0.0_wp 
       ub_tl(:,:,:) = 0.0_wp
       vb_tl(:,:,:) = 0.0_wp
       sshb_tl(:,:) = 0.0_wp

       ! write output ocasionally...
!       IF (MOD(istep, 15) == 0) THEN !2017-03-02 edited to
       IF (MOD(istep - nit000 + 1, nn_pttam_out_freq) ==0) THEN
          CALL pt_tam_wri( istep,0 ) !2017-03-03 added output writing to separate subroutine
       END IF

    END DO
    ! Variable deallocation
    CALL wrk_dealloc(jpi, jpj, jpk, ztn_tlin)

    IF (lwp) THEN
       WRITE(numout,*)
       WRITE(numout,*) ' TL_PASSIVE: Finished!'
       WRITE(numout,*) ' ---------------------'
       WRITE(numout,*)
    ENDIF
    CALL flush(numout)

    ! 2016-06-20: added adjoint time stepping loop
  END SUBROUTINE pt_tan

SUBROUTINE pt_adj

  INTEGER::istep
  
  CALL trj_rea(nit000-1, 1)
  DO istep = nit000, nitend
     CALL day_tam(istep, 0)
  END DO
  CALL trj_rea(istep-1, -1)

  call oce_tam_init(2)
  call sbc_oce_tam_init(2)
  call sol_oce_tam_init(2)
  call trc_oce_tam_init(2)
  qrp_ad          = 0.0_wp
  erp_ad          = 0.0_wp
  emp_ad(:,:)     = 0.0_wp
  a_fwb_ad        = 0.0_wp
!!!!!!

  ! Variable allocation and initialisation
  CALL wrk_alloc(jpi,jpj,jpk,ztn_tlin)
  ztn_tlin(:,:,:) = 0.0_wp
  ! Reading in of initial perturbation
  ! 2016-07-12 ported masking of initialisation from TLM (Tinit is initial distribution at start of adjoint run, ztn_tlin is the mask specified by .nc in namelist)
  CALL iom_open(cn_pttam_init,ncid,kiolib = jpnf90)
  CALL iom_get(ncid,jpdom_autoglo,"Tinit",ztn_tlin,0)

  CALL lbc_lnk(ztn_tlin(:,:,:), 'T', 1.0_wp)

  tmsk_region(:,:,:) = ztn_tlin(:,:,:)

!!!!!!! next part should be in step_tam?!
  tsn_ad(:,:,:,:) = 0.0_wp
!!!later  IF (ln_tl_nasmw_auto) THEN             !!!2016-08-09 - added tmsk_i(:,:,_) to handling of initialisation
!!!later     DO jk = 1, jpk
!!!later        WHERE ((tsn(:,:,jk,jp_tem) >= 17.0_wp).AND.(tsn(:,:,jk,jp_tem) <= 19.0_wp))
!!!later           tsn_ad(:,:,jk,jp_tem) = 1.0_wp*tmsk_i(:,:,jk)*e1t(:,:)*e2t(:,:)*e3t(:,:,jk)
!!!later           tsn_ad(:,:,jk,jp_sal) = 1.0_wp*tmsk_i(:,:,jk)*e1t(:,:)*e2t(:,:)*e3t(:,:,jk)
!!!later        END WHERE
!!!later
!!!later     END DO
!!!later     WHERE ((tsn(:,:,1,jp_tem) >= 17.0_wp).AND.(tsn(:,:,1,jp_tem) <= 19.0_wp))
!!!later        tsn_ad(:,:,1,jp_tem) = tsn_ad(:,:,1,jp_tem) + 1.0_wp*tmsk_i(:,:,1)*e1t(:,:)*e2t(:,:)*sshn(:,:)
!!!later        tsn_ad(:,:,1,jp_sal) = tsn_ad(:,:,1,jp_sal) + 1.0_wp*tmsk_i(:,:,1)*e1t(:,:)*e2t(:,:)*sshn(:,:)
!!!later     END WHERE
!!!later  ELSE
     DO jk=1,jpk
        tsn_ad(:,:,jk,jp_tem) = 1.0_wp*tmsk_i(:,:,jk)*tmsk_region(:,:,jk)*e1t(:,:)*e2t(:,:)*e3t(:,:,jk)
        tsn_ad(:,:,jk,jp_sal) = 1.0_wp*tmsk_i(:,:,jk)*tmsk_region(:,:,jk)*e1t(:,:)*e2t(:,:)*e3t(:,:,jk)
     END DO
     tsn_ad(:,:,1,jp_tem) = tsn_ad(:,:,1,jp_tem)  +  1.0_wp*tmsk_i(:,:,1)*tmsk_region(:,:,1)*e1t(:,:)*e2t(:,:)*sshn(:,:)
     tsn_ad(:,:,1,jp_sal) = tsn_ad(:,:,1,jp_sal)  +  1.0_wp*tmsk_i(:,:,1)*tmsk_region(:,:,1)*e1t(:,:)*e2t(:,:)*sshn(:,:)
!!!later  ENDIF

!!! 2016-07-04 modified above code so IF was not nested inside WHERE

  un_ad(:,:,:)    = 0.0_wp
  vn_ad(:,:,:)    = 0.0_wp
  sshn_ad(:,:)    = 0.0_wp

  tsb_ad(:,:,:,:) = 0.0_wp
  ub_ad(:,:,:)    = 0.0_wp
  vb_ad(:,:,:)    = 0.0_wp
  sshb_ad(:,:)    = 0.0_wp

  DO istep = nitend, nit000, -1

     IF (MOD(istep - nit000 + 1, nn_pttam_out_freq) ==0) THEN
        CALL pt_tam_wri( istep,1) !2017-03-03 added output writing to separate subroutine
     END IF

     un_ad(:,:,:) = 0.0_wp
     vn_ad(:,:,:) = 0.0_wp
     sshn_ad(:,:) = 0.0_wp 
     ub_ad(:,:,:) = 0.0_wp
     vb_ad(:,:,:) = 0.0_wp
     sshb_ad(:,:) = 0.0_wp

     CALL stp_adj(istep)

     ! 2017-04-25 Temporary installation of sbc_tmp_rm, may be replaced in the future
     tmp_rm(:,:) = sbc_tmp_rm(:,:)

  END DO

  
  CALL istate_init_adj

 CALL pt_tam_wri(nit000 - 1,1) !write to output file for initial step

!!!later  CALL tl_trj_wri(nit000-1, 1)



END SUBROUTINE pt_adj

SUBROUTINE pt_tam_wri( kstp , wri_swi )


  INTEGER, INTENT( in ) :: wri_swi
  INTEGER, INTENT( in ) :: kstp
  CHARACTER(LEN=132)::zfname
IF (wri_swi==0) THEN

   WRITE(zfname, FMT='(A,I0.8,A)') 'PTTAM_output_', kstp, '.nc'

   CALL iom_open(zfname, ncid, ldwrt=.TRUE., kiolib = jprstlib)
   CALL iom_rstput(kstp, kstp, ncid, 'tn_tl', tsn_tl(:,:,:,jp_tem))
   CALL iom_rstput(kstp, kstp, ncid, 'tb_tl', tsb_tl(:,:,:,jp_tem))
   CALL iom_rstput(kstp, kstp, ncid, 'tmp_rm', tmp_rm(:,:))
!   CALL iom_close(ncid)
 ! need to add conditional to check tn v ad writing
ELSEIF (wri_swi==1) THEN
   WRITE(zfname, FMT='(A,I0.8,A)') 'PTTAM_output_', kstp, '.nc'

   CALL iom_open(zfname, ncid, ldwrt=.TRUE., kiolib = jprstlib)
   CALL iom_rstput(kstp, kstp, ncid, 'tn_ad', tsn_ad(:,:,:,jp_tem))
   CALL iom_rstput(kstp, kstp, ncid, 'tb_ad', tsb_ad(:,:,:,jp_tem))
   CALL iom_rstput(kstp, kstp, ncid, 'tmp_rm', tmp_rm(:,:))
!   CALL iom_close(ncid)
END IF
   CALL iom_rstput(kstp, kstp, ncid, 'tn'   , tsn(:,:,:,jp_tem)   )
   CALL iom_rstput(kstp, kstp, ncid, 'sn'   , tsn(:,:,:,jp_sal)   )
   CALL iom_close(ncid)
!!! 2017-08-14 added tn/sn outputs from background traj 
END SUBROUTINE pt_tam_wri

END MODULE pttam
