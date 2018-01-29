PROGRAM INTERP_TO_GROUND_TRACK

   USE io_ezcdf
   USE mod_conf
   USE mod_bilin_2d
   USE mod_manip

   !!========================================================================
   !! Purpose :
   !!
   !! ---------
   !!
   !! Author :   Laurent Brodeau
   !! --------
   !!
   !!========================================================================

   IMPLICIT NONE

   !! ************************ Configurable part ****************************
   !!
   LOGICAL, PARAMETER :: &
      &   l_debug = .TRUE., &
      &   l_debug_mapping = .false., &
      &   l_akima = .true., &
      &   l_bilin = .false.
   !!
   LOGICAL :: &
      &      l_orbit_file_is_nc    = .FALSE.
   !!
   REAL(8), PARAMETER :: res = 0.1  ! resolution in degree
   !!
   INTEGER :: Nte, Nten, io, idx, iP, jP, iquadran
   !!
   REAL(8), DIMENSION(:,:), ALLOCATABLE :: Xgt, Ygt, Fgt, xlon_gt, xlat_gt, xdum
   !!
   !! Coupe stuff:
   REAL(8), DIMENSION(:), ALLOCATABLE :: Ftrack, Fmask, Ftrack_np, Ftrack_ephem

   REAL(8), DIMENSION(:,:),   ALLOCATABLE :: vdepth
   REAL(8), DIMENSION(:),     ALLOCATABLE :: vte, vt_model, vt_ephem   ! in seconds

   REAL(8),    DIMENSION(:,:,:), ALLOCATABLE :: RAB       !: alpha, beta
   INTEGER(4), DIMENSION(:,:,:), ALLOCATABLE :: IMETRICS  !: iP, jP, iquadran at each point
   INTEGER,    DIMENSION(:,:),   ALLOCATABLE :: IPB       !: ID of problem

   !! Grid, default name :
   CHARACTER(len=80) :: &
      &    cv_model, &
      &    cv_ephem, &
      &    cv_t   = 'time_counter',  &
      &    cv_mt  = 'tmask',         &
      &    cv_z   = 'deptht',        &
      &    cv_lon = 'glamt',         & ! input grid longitude name, T-points
      &    cv_lat = 'gphit'            ! input grid latitude name,  T-points

   CHARACTER(len=256)  :: cr, cunit
   CHARACTER(len=512)  :: cdum, cconf
   !!
   !!
   !!******************** End of conf for user ********************************
   !!
   !!               ** don't change anything below **
   !!
   LOGICAL ::  &
      &     l_exist   = .FALSE.
   !!
   !!
   CHARACTER(len=400)  :: &
      &    cf_track   = 'track.dat', &
      &    cf_model, &
      &    cf_mm='mesh_mask.nc', &
      &    cf_mapping, &
      &    cs_force_tv_m='', &
      &    cs_force_tv_e=''
   !!
   INTEGER      :: &
      &    jarg,   &
      &    idot,   &
      &    i0, j0,  &
      &    ni, nj, nk=0, Ntm=0, &
      &    ni1, nj1, ni2, nj2, &
      &    iargc, id_f1, id_v1
   !!
   !!
   INTEGER :: ji_min, ji_max, jj_min, jj_max, nib, njb

   REAL(4), DIMENSION(:,:), ALLOCATABLE :: xvar, xvar1, xvar2, xslp

   REAL(4), DIMENSION(:,:), ALLOCATABLE :: xdum2d, show_track
   REAL(8), DIMENSION(:,:), ALLOCATABLE ::    &
      &    xlont, xlatt
   !!
   INTEGER, DIMENSION(:,:), ALLOCATABLE :: JJidx, JIidx    ! debug
   !!
   INTEGER(2), DIMENSION(:,:), ALLOCATABLE :: mask
   !!
   INTEGER :: jt, jte, jt_s, jtm_1, jtm_2, jtm_1_o, jtm_2_o
   !!
   REAL(8) :: rt, rt0, rdt, &
      &       t_min_e, t_max_e, t_min_m, t_max_m, &
      &       alpha, beta, t_min, t_max
   !!
   CHARACTER(LEN=2), DIMENSION(12), PARAMETER :: &
      &            clist_opt = (/ '-h','-v','-x','-y','-z','-t','-i','-p','-n','-m','-f','-g' /)

   REAL(8) :: lon_min_2, lon_max_2, lat_min, lat_max
   
   TYPE(t_unit_t0) :: tut_epoch, tut_ephem, tut_model

   INTEGER :: it1, it2

   CHARACTER(80), PARAMETER :: cunit_time_out = 'seconds since 1970-01-01 00:00:00'

   !! Epoch is our reference time unit, it is "seconds since 1970-01-01 00:00:00" which translates into:
   tut_epoch%unit   = 's'
   tut_epoch%year   = 1970
   tut_epoch%month  = 1
   tut_epoch%day    = 1
   tut_epoch%hour   = 0
   tut_epoch%minute = 0
   tut_epoch%second = 0

   PRINT *, ''

   
   !! Getting string arguments :
   !! --------------------------

   jarg = 0

   DO WHILE ( jarg < iargc() )

      jarg = jarg + 1
      CALL getarg(jarg,cr)

      SELECT CASE (trim(cr))

      CASE('-h')
         call usage()

      CASE('-i')
         CALL GET_MY_ARG('input file', cf_model)

      CASE('-v')
         CALL GET_MY_ARG('model input variable', cv_model)

      CASE('-x')
         CALL GET_MY_ARG('longitude', cv_lon)

      CASE('-y')
         CALL GET_MY_ARG('latitude', cv_lat)

      CASE('-z')
         CALL GET_MY_ARG('depth', cv_z)

      CASE('-t')
         CALL GET_MY_ARG('time', cv_t)

      CASE('-p')
         CALL GET_MY_ARG('orbit ephem track file', cf_track)

      CASE('-m')
         CALL GET_MY_ARG('mesh_mask file', cf_mm)

      CASE('-f')
         CALL GET_MY_ARG('forced time vector construction for model', cs_force_tv_m)

      CASE('-g')
         CALL GET_MY_ARG('forced time vector construction for ephem', cs_force_tv_e)

      CASE('-n')
         l_orbit_file_is_nc = .TRUE.
         CALL GET_MY_ARG('ground track input variable', cv_ephem)

      CASE DEFAULT
         PRINT *, 'Unknown option: ', trim(cr) ; PRINT *, ''
         CALL usage()

      END SELECT

   END DO

   IF ( (trim(cv_model) == '').OR.(trim(cf_model) == '') ) THEN
      PRINT *, ''
      PRINT *, 'You must at least specify input file (-i) and input variable (-v)!!!'
      CALL usage()
   END IF

   PRINT *, ''
   PRINT *, ''; PRINT *, 'Use "-h" for help'; PRINT *, ''
   PRINT *, ''

   PRINT *, ' * Input file = ', trim(cf_model)
   PRINT *, '   => associated variable names = ', trim(cv_model)
   PRINT *, '   => associated longitude/latitude/time = ', trim(cv_lon), ', ', trim(cv_lat), ', ', trim(cv_t)
   PRINT *, '   => mesh_mask file = ', trim(cf_mm)


   PRINT *, ''

   !! Name of config: lulu
   idot = SCAN(cf_model, '/', back=.TRUE.)
   cdum = cf_model(idot+1:)
   idot = SCAN(cdum, '.', back=.TRUE.)
   cconf = cdum(:idot-1)

   idot = SCAN(cf_track, '/', back=.TRUE.)
   cdum = cf_track(idot+1:)
   idot = SCAN(cdum, '.', back=.TRUE.)
   cconf = TRIM(cconf)//'__to__'//cdum(:idot-1)


   PRINT *, ' *** CONFIG: cconf ='//TRIM(cconf)


   !! testing longitude and latitude
   !! ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   CALL DIMS(cf_mm, cv_lon, ni1, nj1, nk, Ntm)
   CALL DIMS(cf_mm, cv_lat, ni2, nj2, nk, Ntm)

   IF ( (nj1==-1).AND.(nj2==-1) ) THEN
      ni = ni1 ; nj = ni2
      PRINT *, 'Grid is 1D: ni, nj =', ni, nj
      lregin = .TRUE.
   ELSE
      IF ( (ni1==ni2).AND.(nj1==nj2) ) THEN
         ni = ni1 ; nj = nj1
         PRINT *, 'Grid is 2D: ni, nj =', ni, nj
         lregin = .FALSE.
      ELSE
         PRINT *, 'ERROR: problem with grid!' ; STOP
      END IF
   END IF

   ALLOCATE ( xlont(ni,nj), xlatt(ni,nj), xdum2d(ni,nj) )
   PRINT *, ''



   !! testing variable dimensions
   !! ~~~~~~~~~~~~~~~~~~~~~~~~~~~
   CALL DIMS(cf_model, cv_model, ni1, nj1, nk, Ntm)

   IF ( (ni1/=ni).AND.(nj1/=nj) ) THEN
      PRINT *, 'ERROR: dimension of ',trim(cv_model), 'does not agree with lon/lat' ; STOP
   END IF

   IF ( nk < 1 ) nk = 1

   IF ( Ntm < 1 ) THEN
      PRINT *, 'ERROR: ',trim(cv_model),' must have at least a time record!' ; STOP
   END IF


   PRINT *, 'Dimension for ',trim(cv_model),':'
   PRINT *, '   => ni =', ni ;   PRINT *, '   => nj =', nj
   PRINT *, '   => nk =', nk ;   PRINT *, '   => Ntm =', Ntm
   PRINT *, ''

   ALLOCATE ( xvar(ni,nj), xvar1(ni,nj), xvar2(ni,nj), xslp(ni,nj), mask(ni,nj), vdepth(nk,1), vt_model(Ntm) )

   IF ( lregin ) THEN
      PRINT *, 'Regular case not supported yet! Priority to ORCA grids...'
      STOP
   END IF




   !! The first important stage is to compare time slices in the OGCM 2D input field
   !! w.r.t the one in the ephem orbit file!
   !! Since we are dealing with satellite data, useing the UNIX "epoch" time seems
   !! appropriate:
   !!
   !! The Unix epoch (or Unix time or POSIX time or Unix timestamp) is the
   !! number of seconds that have elapsed since January 1, 1970 (midnight
   !! UTC/GMT), not counting leap seconds (in ISO 8601: 1970-01-01T00:00:00Z).
   !!
   !! As such, step #1 is to convert the time vector in both files to epoch time
   !! If there is no overlapping period of time between the two file, then no
   !! need to go further...
   !!
   CALL GET_VAR_INFO(cf_model, cv_t, cunit, cdum)
   tut_model  = GET_TIME_UNIT_T0(TRIM(cunit))
   PRINT *, ' *** Unit and reference time in model file:'
   PRINT *, tut_model

   IF ( l_orbit_file_is_nc ) THEN
      CALL GET_VAR_INFO(cf_track, 'time', cunit, cdum)
      tut_ephem  = GET_TIME_UNIT_T0(TRIM(cunit))
      PRINT *, ' *** Unit and reference time in ephem file:'
      PRINT *, tut_ephem
   END IF
   PRINT *, ''





   !! Getting coordinates
   !! ~~~~~~~~~~~~~~~~~~~

   IF ( nk > 1 ) CALL GETVAR_1D(cf_model, cv_z, vdepth(:,1))


   IF ( TRIM(cs_force_tv_m) /= '' ) THEN
      !! Building new time vector!
      idx = SCAN(TRIM(cs_force_tv_m),',')
      cdum = cs_force_tv_m(1:idx-1)
      READ(cdum,'(f)') rt0
      cdum = cs_force_tv_m(idx+1:)
      READ(cdum,'(f)') rdt
      PRINT *, ' *** MODEL: OVERIDING time vector with t0 and dt =', REAL(rt0,4), REAL(rdt,4)
      DO jt=1, Ntm
         vt_model(jt) = rt0 + REAL(jt-1)*rdt
      END DO
   ELSE
      !! Reading it in input file:
      CALL GETVAR_1D(cf_model, cv_t, vt_model)
   END IF

   IF ( l_debug ) THEN
      PRINT *, ''
      PRINT *, 'Time vector in NEMO input file is (s), (h), (d):'
      DO jt=1, Ntm
         PRINT *, vt_model(jt), vt_model(jt)/3600., vt_model(jt)/(3600.*24.)
      END DO
      PRINT *, ''
      PRINT *, ''
   END IF



   !! Getting longitude, latitude and mask in mesh_mask file:
   ! Longitude array:
   CALL GETVAR_2D   (i0, j0, cf_mm, cv_lon, 0, 0, 0, xdum2d)
   xlont(:,:) = xdum2d(:,:) ; i0=0 ; j0=0
   !!
   

   !! Min an max lon:
   lon_min_1 = MINVAL(xlont)
   lon_max_1 = MAXVAL(xlont)
   PRINT *, ' *** Minimum longitude on source domain before : ', lon_min_1
   PRINT *, ' *** Maximum longitude on source domain before : ', lon_max_1
   !!
   WHERE ( xdum2d < 0. ) xlont = xlont + 360.0_8
   !!
   lon_min_2 = MINVAL(xlont)
   lon_max_2 = MAXVAL(xlont)
   PRINT *, ' *** Minimum longitude on source domain: ', lon_min_2
   PRINT *, ' *** Maximum longitude on source domain: ', lon_max_2

   IF ( (lon_min_2 >= 0.).AND.(lon_min_2<2.5).AND.(lon_max_2>357.5).AND.(lon_max_2<=360.) ) THEN
      l_glob_lon_wize = .TRUE.
      PRINT *, 'Looks like global setup (longitude-wise at least...)'
   ELSE
      PRINT *, 'Looks like regional setup (longitude-wise at least...)'
      l_glob_lon_wize = .FALSE.
      !!
      WRITE(*,'("  => going to disregard points of target domain with lon < ",f7.2," and lon > ",f7.2)'), lon_min_1,lon_max_1
   END IF
   PRINT *, ''
   
   ! Latitude array:
   CALL GETVAR_2D   (i0, j0, cf_mm, cv_lat, 0, 0, 0, xdum2d)
   xlatt(:,:) = xdum2d(:,:) ; i0=0 ; j0=0

   !! Min an max lat:
   lat_min = MINVAL(xlatt)
   lat_max = MAXVAL(xlatt)
   PRINT *, ' *** Minimum latitude on source domain : ', lat_min
   PRINT *, ' *** Maximum latitude on source domain : ', lat_max
         WRITE(*,'("  => going to disregard points of target domain with lat < ",f7.2," and lat > ",f7.2)'), lat_min,lat_max
   PRINT *, ''



   !! 3D LSM
   CALL GETMASK_2D(cf_mm, cv_mt, mask, jlev=1)



   !! Reading along-track from file:

   INQUIRE(FILE=TRIM(cf_track), EXIST=l_exist )
   IF ( .NOT. l_exist ) THEN
      PRINT *, 'ERROR: please provide the file containing definition of orbit ephem track'; STOP
   END IF

   IF ( .NOT. l_orbit_file_is_nc ) THEN
      !! Getting number of lines:
      Nte = -1 ; io = 0
      OPEN (UNIT=13, FILE=TRIM(cf_track))
      DO WHILE (io==0)
         READ(13,*,iostat=io)
         Nte = Nte + 1
      END DO
      PRINT*, Nte, ' points in '//TRIM(cf_track)//'...'
      ALLOCATE ( Xgt(1,Nte), Ygt(1,Nte), vt_ephem(Nte), Fgt(1,Nte) )
      !!
      REWIND(13)
      DO jte = 1, Nte
         READ(13,*) vt_ephem(jte), Xgt(1,jte), Ygt(1,jte)
      END DO
      CLOSE(13)

   ELSE
      PRINT *, ''
      PRINT *, 'NetCDF orbit ephem!'
      CALL DIMS(cf_track, 'time', Nte, nj1, nk, ni1)
      PRINT *, ' *** Nb. time records in NetCDF ephem file:', Nte
      ALLOCATE ( Xgt(1,Nte), Ygt(1,Nte), vt_ephem(Nte), Fgt(1,Nte))
      CALL GETVAR_1D(cf_track, 'time', vt_ephem)
      CALL GETVAR_1D(cf_track, 'longitude', Xgt(1,:))
      CALL GETVAR_1D(cf_track, 'latitude',  Ygt(1,:))
      CALL GETVAR_1D(cf_track, cv_ephem,  Fgt(1,:))
      PRINT *, 'Done!'; PRINT *, ''
   END IF


   IF ( TRIM(cs_force_tv_e) /= '' ) THEN
      !! Building new time vector!
      idx = SCAN(TRIM(cs_force_tv_e),',')
      cdum = cs_force_tv_e(1:idx-1)
      READ(cdum,'(f)') rt0
      cdum = cs_force_tv_e(idx+1:)
      READ(cdum,'(f)') rdt
      PRINT *, ' *** EPHEM: OVERIDING time vector with t0 and dt =', REAL(rt0,4), REAL(rdt,4)
      DO jt=1, Nte
         vt_ephem(jt) = rt0 + REAL(jt-1)*rdt
         !PRINT *, ' vt_ephem(jt)= ', vt_ephem(jt)
      END DO
   END IF




   nib = ni ; njb = nj ; ji_min=1 ; ji_max=ni ; jj_min=1 ; jj_max=nj






   !PRINT *, ''
   !PRINT *, 'First time record for model:', vt_model(1)
   !itime = to_epoch_time_scalar( tut_model, vt_model(1) )
   !PRINT *, '     ==> in epoch time =>',  itime
   !PRINT *, ''
   !PRINT *, 'Last time record for model:', vt_model(Ntm)
   !itime = to_epoch_time_scalar( tut_model, vt_model(Ntm) )
   !PRINT *, '     ==> in epoch time =>',  itime

   !PRINT *, '' ; PRINT *, ''

   !PRINT *, 'First time record for ephem:', vt_ephem(1)
   !itime = to_epoch_time_scalar( tut_ephem, vt_ephem(1), dt=0.1_8 )
   !PRINT *, '     ==> in epoch time =>',  itime
   !PRINT *, ''
   !PRINT *, 'Last time record for ephem:', vt_ephem(Nte)
   !itime = to_epoch_time_scalar( tut_ephem, vt_ephem(Nte), dt=0.1_8 )
   !PRINT *, '     ==> in epoch time =>',  itime

   !PRINT *, ''

   !!
   !! Converting time vectors to epoch:
   !CALL time_vector_to_epoch_time( tut_ephem, vt_ephem )
   !CALL time_vector_to_epoch_time( tut_model, vt_model )


   !CALL to_epoch_time_vect( tut_model, vt_model )
   !PRINT *, vt_model(:)
   !PRINT *, ''


   PRINT *, ''
   PRINT *, ' Time vector in ephem file:'
   CALL to_epoch_time_vect( tut_ephem, vt_ephem, l_dt_below_sec=.true. )
   !PRINT *, vt_ephem(:)
   PRINT *, ''
   PRINT *, ''

   !! Defaults:
   Nten = Nte
   it1  = 1
   it2  = Nte

   IF ( .NOT. l_debug_mapping ) THEN
      PRINT *, ' Time vector in model file:'
      CALL to_epoch_time_vect( tut_model, vt_model, l_dt_below_sec=.FALSE. )
      !PRINT *, vt_model(:)
      PRINT *, ''




      t_min_e = MINVAL(vt_ephem)
      t_max_e = MAXVAL(vt_ephem)
      t_min_m = MINVAL(vt_model)
      t_max_m = MAXVAL(vt_model)

      PRINT *, ''
      PRINT *, ' *** Max min time for ephem:', t_min_e, t_max_e
      PRINT *, ' *** Max min time for model:', t_min_m, t_max_m
      PRINT *, ''

      IF ( (t_min_m >= t_max_e).OR.(t_min_e >= t_max_m).OR.(t_max_m <= t_min_e).OR.(t_max_e <= t_min_m) ) THEN
         PRINT *, ' No time overlap for Model and Ephem file! '
         STOP
      END IF

      t_min = MAX(t_min_e, t_min_m)
      t_max = MIN(t_max_e, t_max_m)
      PRINT *, ' *** Time overlap for Model and Ephem file:', t_min, t_max


      !! Findin when we can start and stop when scanning the ephem file:
      !! it1, it2
      DO it1 = 1, Nte-1
         IF ( (vt_ephem(it1) <= t_min).AND.(vt_ephem(it1+1) > t_min) ) EXIT
      END DO
      DO it2 = it1, Nte-1
         IF ( (vt_ephem(it2) <= t_max).AND.(vt_ephem(it2+1) > t_max) ) EXIT
      END DO

      Nten = it2 - it1 + 1

      PRINT *, ' it1, it2 =',it1, it2
      PRINT *, Nten, '  out of ', Nte
      PRINT *, ' => ', vt_ephem(it1), vt_ephem(it2)
      PRINT *, ''
   END IF ! IF ( .NOT. l_debug_mapping )

   ALLOCATE ( IMETRICS(1,Nten,3), RAB(1,Nten,2), IPB(1,Nten), IGNORE(1,Nten), xlon_gt(1,Nten), xlat_gt(1,Nten) )

   IGNORE(:,:) = 1 !lolo

   !! Main time loop is on time vector in ephem file!


   cf_mapping = 'MAPPING__'//TRIM(cconf)//'.nc'


   !! 
   xlon_gt(:,:) = Xgt(:,it1:it2)
   xlat_gt(:,:) = Ygt(:,it1:it2)

   DEALLOCATE ( Xgt, Ygt )
   
   IF ( .NOT. l_glob_lon_wize ) THEN
      ALLOCATE ( xdum(1,Nten) )
      xdum = SIGN(1.,180.-xlon_gt)*MIN(xlon_gt,ABS(xlon_gt-360.)) ! like xlon_gt but between -180 and +180 !
      WHERE ( xdum < lon_min_1 ) IGNORE=0
      WHERE ( xdum > lon_max_1 ) IGNORE=0
      DEALLOCATE ( xdum )
   END IF

   WHERE ( xlat_gt < lat_min ) IGNORE=0
   WHERE ( xlat_gt > lat_max ) IGNORE=0


   
   INQUIRE(FILE=trim(cf_mapping), EXIST=l_exist )
   IF ( .NOT. l_exist ) THEN
      PRINT *, ' *** Creating mapping file...'
      CALL MAPPING_BL(-1, xlont, xlatt, xlon_gt, xlat_gt, cf_mapping,  mask_out=IGNORE)
      PRINT *, ' *** Done!'; PRINT *, ''
   ELSE
      PRINT *, ' *** File "',trim(cf_mapping),'" found in current directory, using it!'
      PRINT *, ''
   END IF

   CALL RD_MAPPING_AB(cf_mapping, IMETRICS, RAB, IPB)
   PRINT *, ''; PRINT *, ' *** Mapping and weights read into "',trim(cf_mapping),'"'; PRINT *, ''



   !PRINT *, 'LOLO IMETRICS(1,:,1) =>', IMETRICS(1,:,1)

   !! Showing iy in file mask_+_nearest_points.nc:
   IF ( l_debug ) THEN
      ALLOCATE (JIidx(1,Nten) , JJidx(1,Nten) )
      !! Finding and storing the nearest points of NEMO grid to ephem points:
      !CALL FIND_NEAREST_POINT(Xgt, Ygt, xlont, xlatt,  JIidx, JJidx)
      JIidx(1,:) = IMETRICS(1,:,1)
      JJidx(1,:) = IMETRICS(1,:,2)
      ALLOCATE ( show_track(nib,njb) )
      show_track(:,:) = 0.
      DO jte = 1, Nten
         IF ( (JIidx(1,jte)>0).AND.(JJidx(1,jte)>0) )  show_track(JIidx(1,jte), JJidx(1,jte)) = REAL(jte,4)
      END DO
      WHERE (mask == 0) show_track = -9999.
      CALL PRTMASK(REAL(show_track(:,:),4), 'mask_+_nearest_points__'//TRIM(cconf)//'.nc', 'mask', xlont, xlatt, 'lon0', 'lat0', rfill=-9999.)
      !lolo:
      !CALL PRTMASK(REAL(xlont(:,:),4), 'lon_360.nc', 'lon')
      !show_track = SIGN(1.,180.-xlont)*MIN(xlont,ABS(xlont-360.))
      !CALL PRTMASK(REAL(show_track(:,:),4), 'lon_-180-180.nc', 'lon')
      !WHERE ( (show_track > 10.).OR.(show_track < -90.) ) show_track = -800.
      !CALL PRTMASK(REAL(show_track(:,:),4), 'lon_masked.nc', 'lon')
      !STOP 'interp_to_ground_track.f90'
      !lolo.
      
      DEALLOCATE ( show_track )
   END IF

   IF ( l_debug_mapping ) STOP'l_debug_mapping'



   !STOP 'mapping done!'

   ALLOCATE ( vte(Nten), Ftrack(Nten), Ftrack_ephem(Nten), Fmask(Nten), Ftrack_np(Nten) )


   vte(:) = vt_ephem(it1:it2)

   Ftrack_np(:) = -9999.
   Ftrack_ephem(:) = -9999.
   Ftrack(:) = -9999.
   Fmask(:) = 0.

   jt_s = 1 ; ! time step model!

   jtm_1_o = -100
   jtm_2_o = -100

   DO jte = 1, Nten
      !!
      rt = vte(jte)
      PRINT *, 'Treating ephem time =>', rt
      !!
      IF ( (rt >= t_min_m).AND.(rt < t_max_m) ) THEN
         !!
         !! Two surrounding time records in model file => jtm_1 & jtm_2
         DO jt=jt_s, Ntm-1
            IF ( (rt >= vt_model(jt)).AND.(rt < vt_model(jt+1)) ) EXIT
         END DO
         !!
         jtm_1 = jt
         jtm_2 = jt+1
         IF (jte==1) jt_s = jtm_1 ! Saving the actual first useful time step of the model!

         !PRINT *, ' rt, vt_model(jtm_1), vt_model(jtm_2) =>', rt, vt_model(jtm_1), vt_model(jtm_2)
         !!
         !! If first time we have these jtm_1 & jtm_2, getting the two surrounding fields:
         IF ( (jtm_1>jtm_1_o).AND.(jtm_2>jtm_2_o) ) THEN
            IF ( jtm_1_o == -100 ) THEN
               !PRINT *, 'Reading field '//TRIM(cv_model)//' in '//TRIM(cf_model)//' at jtm_1=', jtm_1
               !PRINT *, 'LOLO: id_f1, id_v1, jtm_1 =>', id_f1, id_v1, jtm_1
               CALL GETVAR_2D(id_f1, id_v1, cf_model, cv_model, Ntm, 0, jtm_1, xvar1, jt1=jt_s)
            ELSE
               !PRINT *, 'Getting field '//TRIM(cv_model)//' at jtm_1=', jtm_1,' from previous jtm_2 !'
               xvar1(:,:) = xvar2(:,:)
            END IF
            !PRINT *, 'Reading field '//TRIM(cv_model)//' in '//TRIM(cf_model)//' at jtm_2=', jtm_2
            CALL GETVAR_2D(id_f1, id_v1, cf_model, cv_model, Ntm, 0, jtm_2, xvar2, jt1=jt_s)
            xslp = (xvar2 - xvar1) / (vt_model(jtm_2) - vt_model(jtm_1)) ! slope...

         END IF

         !! Linear interpolation of field at time rt:
         xvar(:,:) = xvar1(:,:) + xslp(:,:)*(rt - vt_model(jtm_1))

         !! Performing bilinear interpolation:
         iP       = IMETRICS(1,jte,1)
         jP       = IMETRICS(1,jte,2)
         iquadran = IMETRICS(1,jte,3)

         alpha    = RAB(1,jte,1)
         beta     = RAB(1,jte,2)

         IF ( (iP == INT(rflg)).OR.(jP == INT(rflg)) ) THEN
            Ftrack(jte) = -9999. ; ! masking
            Ftrack_ephem(jte) = -9999. ; ! masking
            Fmask(jte) = -9999. ; ! masking
         ELSE
            !! INTERPOLATION !
            Ftrack(jte) = INTERP_BL(-1, iP, jP, iquadran, alpha, beta, REAL(xvar,8))
            !!
            Ftrack_ephem(jte) = Fgt(1,it1+jte-1) ! Input ephem data
            !!
         END IF

         Ftrack_np(jte) =  xvar(JIidx(1,jte),JJidx(1,jte)) ! NEAREST POINT interpolation

         jtm_1_o = jtm_1
         jtm_2_o = jtm_2
         jt_s    = jtm_1 ! so we do not rescan from begining...

      END IF

   END DO


   !! Masking
   WHERE ( Ftrack > 1.E9 ) Ftrack = -9999.
   !WHERE ( Fmask < 1.    ) Ftrack = -9999.
   WHERE ( IGNORE(1,:)==0    ) Ftrack = -9999.

   WHERE ( Ftrack_np > 1.E9 ) Ftrack_np = -9999.
   !WHERE ( Fmask < 1.    )    Ftrack_np = -9999.
   WHERE ( IGNORE(1,:)==0    )    Ftrack_np = -9999.

   WHERE ( Ftrack_ephem > 1.E9 )  Ftrack_ephem = -9999.
   WHERE ( IGNORE(1,:)==0    )    Ftrack_ephem = -9999.

   PRINT *, ''
   !WRITE(cf_out, '("track_",a,"_",a,".nc")') TRIM(cv_model), TRIM(cf_track)
   cf_out = 'result__'//TRIM(cconf)//'.nc4'
   PRINT *, ' * Output file = ', trim(cf_out)
   PRINT *, ''





   CALL PT_SERIES(vte(:), REAL(Ftrack,4), cf_out, 'time', cv_model, 'm', 'Model data, bi-linear interpolation', -9999., &
      &           ct_unit=TRIM(cunit_time_out), lpack=.TRUE., &
      &           vdt2=REAL(Ftrack_np,4),    cv_dt2=TRIM(cv_model)//'_np', cln2='Model data, nearest-point interpolation', &
      &           vdt3=REAL(Ftrack_ephem,4), cv_dt3=cv_ephem,              cln3='Original data as in ephem file...',   &
      &           vdt4=REAL(xlon_gt(1,:),4), cv_dt4='longitude',           cln4='Longitude (as in ephem file)',  &
      &           vdt5=REAL(xlat_gt(1,:),4), cv_dt5='latitude',            cln5='Latitude (as in ephem file)' ,  &
      &           vdt6=REAL(Fmask,4),        cv_dt6='mask',                cln6='Mask', &
      &           vdt7=REAL(IGNORE(1,:),4),  cv_dt7='ignore_out',          cln7='Ignore mask on target track (ignored where ignore_out==0)')

   IF ( l_debug ) DEALLOCATE ( JIidx, JJidx )
   DEALLOCATE ( Fgt )
   DEALLOCATE ( Ftrack, Ftrack_ephem )
   DEALLOCATE ( xlont, xlatt, xvar, xvar1, xvar2, xslp, mask )


   PRINT *, ''
   PRINT *, 'Written!'
   PRINT *, ' => check:'
   PRINT *, TRIM(cf_out)
   PRINT *, ''


CONTAINS






   SUBROUTINE GET_MY_ARG(cname, cvalue)
      CHARACTER(len=*), INTENT(in)    :: cname
      CHARACTER(len=*), INTENT(inout) :: cvalue
      !!
      IF ( jarg + 1 > iargc() ) THEN
         PRINT *, 'ERROR: Missing ',trim(cname),' name!' ; call usage()
      ELSE
         jarg = jarg + 1 ;  CALL getarg(jarg,cr)
         IF ( ANY(clist_opt == trim(cr)) ) THEN
            PRINT *, 'ERROR: Missing',trim(cname),' name!'; call usage()
         ELSE
            cvalue = trim(cr)
         END IF
      END IF
   END SUBROUTINE GET_MY_ARG


END PROGRAM INTERP_TO_GROUND_TRACK




SUBROUTINE usage()
   !!
   !OPEN(UNIT=6, FORM='FORMATTED', RECL=512)
   !!
   WRITE(6,*) ''
   WRITE(6,*) '   List of command line options:'
   WRITE(6,*) '   ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~'
   WRITE(6,*) ''
   WRITE(6,*) ' -i <input_file.nc>   => INPUTE FILE'
   WRITE(6,*) ''
   WRITE(6,*) ' -v  <name>           => Specify variable name in input file'
   WRITE(6,*) ''
   WRITE(6,*) ' -p  <track_file>     => Specify name of file containing orbit tack (columns: time, lon, lat)'
   WRITE(6,*) ''
   WRITE(6,*) ' -n  <name>           => file containing orbit ephem is in NetCDF, and this is the name of var'
   WRITE(6,*) '                         (default is columns in ASCII file <time> <lon> <lat>'
   WRITE(6,*) ''
   !!
   WRITE(6,*) ''
   WRITE(6,*) '    Optional:'
   WRITE(6,*)  ''
   WRITE(6,*) ' -x  <name>           => Specify longitude name in input file (default: lon)'
   WRITE(6,*) ''
   WRITE(6,*) ' -y  <name>           => Specify latitude  name in input file  (default: lat)'
   WRITE(6,*) ''
   WRITE(6,*) ' -z  <name>           => Specify depth name in input file (default: depth)'
   WRITE(6,*) ''
   WRITE(6,*) ' -t  <name>           => Specify time name in input file (default: time)'
   WRITE(6,*) ''
   WRITE(6,*) ' -m  <mesh_mask_file> => Specify mesh_mask file to be used (default: mesh_mask.nc)'
   WRITE(6,*) ''
   WRITE(6,*) ' -f  <t0,dt>          => overide time vector in input NEMO file with one of same length'
   WRITE(6,*) '                         based on t0 and dt (in seconds!) (ex: " ... -f 0.,3600.")'
   WRITE(6,*) ''
   WRITE(6,*) ' -g  <t0,dt>          => overide time vector in ephem file with one of same length'
   WRITE(6,*) '                         based on t0 and dt (in seconds!) (ex: " ... -f 0.,3600.")'
   WRITE(6,*) ''
   WRITE(6,*) ' -h                   => Show this message'
   WRITE(6,*) ''
   !!
   !CLOSE(6)
   STOP
   !!
END SUBROUTINE usage
!!