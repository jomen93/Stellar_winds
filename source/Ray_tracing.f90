program Ray_traicing 
  use constants 

  implicit none

    
  ! ============================================================================
  ! PROGRAM CONFIGURATION
  ! ============================================================================

  
  ! Limits in the outputs files
  integer, parameter :: outmin = 000
  integer, parameter :: outmax = 010

  ! mode operation 
  integer, parameter :: ACCEL_ISO = 0
  integer, parameter :: ACCEL_PAR = 1
  integer, parameter :: ACCEL_PER = 2
  integer, parameter :: accel = ACCEL_PAR


  ! Rotation parameteres
  ! The following parameteres allow the user yo pre-aplly up to four 
  ! 3D rotations to the scene before doing the integration along the
  ! line of sight.
  ! the "rot_center" parameters specify the center of rotation, given in 
  ! cell integer coordinates (same for all rotations)
  ! 
  ! the "rot_axis" parameters must be one of the constants 
  ! AXIS_X, AXIS_Y, AXIS_Z or AXIS_NONE (if no rotation is wanted)
  ! Positive rotation angles around a given axis are "counter-clockwise". When 
  ! arrow end of that axis points at the observer.

  ! The scene is always projectec along the AXIS_Z, with the tip of that axis
  ! pointed towars the observer, the positive AXIS_X pointing to right and the 
  ! positive AXIS_Y pointing up. All rotations are performed around these 
  ! original axes. Below a sketch of reference system 

  !        y
  !        ^
  !        |   Plane of the sky
  !        |                                
  !        |
  !        # -------- > x
  !       /
  !      /
  !     v
  !    z = line of sight

  ! Rotations around AXIS_Z are rotations around the "line_of_sight"
  ! Rotations around AXIS_X are rotations around a horizontal axis
  ! Rotations around AXIs_Y are rotations around vertical axis ponting up

  
  ! variable definitions to performance the rotations 
  real,    parameter :: rot_center_x = 0
  real,    parameter :: rot_center_y = 0
  real,    parameter :: rot_center_z = 0
  integer, parameter :: rot1_axis    = AXIS_NONE
  real,    parameter :: rot1_angle   = 0.0
  integer, parameter :: rot2_axis    = AXIS_NONE
  real,    parameter :: rot2_angle   = 0.0
  integer, parameter :: rot3_axis    = AXIS_NONE
  real,    parameter :: rot3_angle   = 0.0
  integer, parameter :: rot4_axis    = AXIS_NONE
  real,    parameter :: rot4_angle   = 0.0

  
  ! Output map size (vision plane resolution)
  integer, parameter :: mapcells_x = 1024
  integer, parameter :: mapcells_y = 1024
  integer, parameter :: mapcells_z = 256

  
  ! Path definitions to files
  character(*), parameter :: datadir   = "/storage2/jsmendezh/theta1_Orionis_C/data_cooling"
  ! Datafile template
  character(*), parameter :: blockstpl = "BlocksXXX.YYYY"
  ! Grid file template
  character(*), parameter :: gridtpl   = "Grid.YYYY"
  ! State file template
  character(*), parameter :: statetpl  = "State.YYYY"
  ! Output file template
  character(*), parameter :: outtpl   = "XrayX_raytracing.YYYY"


  ! Physical box sizes (cgs units)
  real, parameter :: xphystot = 60 * AU
  real, parameter :: yphystot = 60 * AU
  real, parameter :: zphystot = 15 * AU

  
  ! Mesh parameters (from file "parameteres.f90", depends of particular simulation)
  integer, parameter :: p_nbrootx = 4
  integer, parameter :: p_nbrooty = 4
  integer, parameter :: p_nbrootz = 1
  integer, parameter :: p_maxlev = 5
  integer, parameter :: ncells_x = 16
  integer, parameter :: ncells_y = 16
  integer, parameter :: ncells_z = 16


  ! Simulation running parameters
  ! processors to use 
  integer, parameter :: nprocs = 32
  ! Number of hidrodynamical equations 
  integer, parameter :: neqtot = 5


  ! Unit scaling 
  real, parameter :: mu0 = 1.3
  real, parameter :: ism_dens = 1.0 * mu0 * AMU
  ! length scale (cm)
  real, parameter :: l_sc = 1.0*AU          
  ! density scale (g cm^-3)
  real, parameter :: d_sc = ism_dens        
  ! velocity scale (cm s^-1)
  real, parameter :: v_sc = 1.0e5           
  real, parameter :: p_sc = d_sc*v_sc**2
  real, parameter :: e_sc = p_sc
  real, parameter :: t_sc = l_sc/v_sc


  ! definitions of orbital dynamics variables 

  ! variables to make mask in the simulation 
  real :: r1, r2, d, dist1, dist2, nx, ny, nz
  !  variables to orbital trajectories
  real :: x, y, z, x1, x2, y1, y2, vx1, vy1, vx2, vy2, phase
  ! location in the z-axis for each star 
  real :: z1 = zphystot/2.0
  real :: z2 = zphystot/2.0

  ! ====================================================
  ! Xray calculation parameters
  ! ====================================================

  ! Xray emissivity coefficients load from tables
  character(*), parameter :: xray_coefs = "/home/claudio/coefs/coef0.1_10kev.dat"
  ! Gas parameters (ideal gas):
  real, parameter :: mui = 1.3/2.1
  ! Ionization threshold
  real, parameter :: ion_thres = 5000
  ! Adiabatic expansion coefficient
  real, parameter :: gamma = 5.0/3.0
  ! heat capacity
  real, parameter :: cv = 1.0/(gamma-1.0)

  ! ============================================================================
  !                    NO NEED TO MODIFY BELOW THIS POINT
  ! ============================================================================


  integer :: nout, p, unitin, istat
  integer :: bID, blocksread, nb, nblocks
  integer :: bx, by, bz, i, j, k, i1, j1, k1, ip, jp, kp, ilev, io, jo, ko
  integer :: i2, j2, k2, i_off, j_off, k_off
  integer :: totcells_x, totcells_y, totcells_z
  integer :: mesh(7), numcoefs, counter
  real :: a, b, c, sigma, Kfact, prog, sumvalue
  real :: dx(p_maxlev), dy(p_maxlev), dz(p_maxlev), pvars(neqtot), uvars(neqtot)
  real :: line_of_sight(3), r(3), ro(3)
  real :: ds, N, at, rox, roy, roz, rx, ry, rz, xo, yo, zo
  integer :: ii, threshold_lev, ig, jg, kg, i_dif, j_dif, k_dif
  character(256) :: filename

  real, allocatable :: block(:,:,:,:)
  real, allocatable :: xraytable(:,:)
  real, allocatable :: out_density(:, :, :) 
  real, allocatable :: out_pressure(:, :, :) 


  write(*,*) "Allocating data arrays ..."


  ! Allocate data array for whole simulationat max resolution 
  totcells_x = p_nbrootx*ncells_x*2**(p_maxlev-1)
  totcells_y = p_nbrooty*ncells_y*2**(p_maxlev-1)
  totcells_z = p_nbrootz*ncells_z*2**(p_maxlev-1)

  ! Allocate data array for just one block 
  allocate( block(neqtot, ncells_x, ncells_y, ncells_z) )
  block(:, :, :, :) = 0.0
  write(*,'(1x,a,f6.1,a)') "block: ", sizeof(block)/1024./1024., " MB"

  ! Allocate output density array to map value on unstructured grid  in regular mesh
  allocate( out_density(mapcells_x, mapcells_y, mapcells_z) )
  out_density(:, :, :) = 0.0
  write(*,'(1x,a,f6.1,a)') "out density size: ", sizeof(out_density) ,1024./1024./1024., " GB"
 
 ! Allocate output density array to map value on unstructured grid  in regular mesh
  allocate( out_pressure(mapcells_x, mapcells_y, mapcells_z) )
  out_pressure(:, :, :) = 0.0
  write(*,'(1x,a,f6.1,a)') "out density size: ", sizeof(out_pressure) ,1024./1024./1024., " GB"
 
  ! Load the xray emission coefficients from file 
  write(*,'(2x,a,a,a)') "Loading xray coefficients from file ", trim(xray_coefs), " ..."
  open(unit=99, file=xray_coefs, status="old", iostat=istat)
  if (istat.ne.0) then
      write(*,'(a,a,a)') "Could not open the file ", trim(xray_coefs), " !"
      write(*,*) "***ABORTING***"
      close(99)
      stop
  end if

  read(99, *) numcoefs
  allocate( xraytable(2, numcoefs) )

  ! values assignement 
  do i=1,numcoefs
    read(99,*) a, b, c
    xraytable(1,i) = b
    xraytable(2,i) = c
  end do
  close (unit=99)

  ! Grid spacings - assumed EQUAL for all dimensions
  do ilev=1,p_maxlev
    dx(ilev) = xphystot/(ncells_x*p_nbrootx*2**(ilev-1))
    dy(ilev) = yphystot/(ncells_y*p_nbrooty*2**(ilev-1))
    dz(ilev) = zphystot/(ncells_z*p_nbrootz*2**(ilev-1))
  end do

  ! Pack Mesh parameters
  mesh(1) = p_nbrootx
  mesh(2) = p_nbrooty
  mesh(3) = p_nbrootz
  mesh(4) = p_maxlev
  mesh(5) = ncells_x
  mesh(6) = ncells_y
  mesh(7) = ncells_z

  ! Begins cycle over all outputs of the simulation
  do nout=outmin,outmax
    
    write(*,*) "=============================="
    write(*,'(1x,a,i0,a)') "Processing output ", nout, " ..."
    write(*,*) "=============================="
    write(*,*)
    write(*,'(1x,a,1x)') "Calculating x-ray emission ..."

    ! Map density in max resolution
    call Mapping()
    ! ray tracing 
    ! call trace(pvars, sumvalue)

    ! Write output map to disk
    call genfname(0, nout, datadir, outtpl, ".bin", filename)
    call writebin(filename, mapcells_x, mapcells_y, mapcells_z/2, out_density)

    write(*,*) "=============================="

  enddo 

contains 

! Project cell after raytracing

! xray calculations
subroutine trace(pvars, xray)
  implicit none

  real, intent(in) :: pvars(neqtot)
  real, intent(out) :: xray

  integer :: i, j, k, ix, ii, jj, zz
  real :: mintemp, maxtemp, temp, T1, T2, C1, C2, CX
  real :: x, y, z, at, N, los(3)

  at = 1

  do i=1, mapcells_x - 1
    do j=1, mapcells_y - 1
      do k=1, mapcells_z - 1

      ! Call function
      call computeLOS(los)
      
      ! Unit vector to image plane
      nx = los(1)
      ny = los(2)
      nz = los(3)

      ! calculate temperature in cgs units 
        temp = pvars(5)*(mu0*AMU/KB)/pvars(1)
        if (temp.gt.ion_thres) then
          temp = pvars(5)*(mui*AMU/KB)/pvars(1)
        end if

        ! interpolate emission coeficcient 
        mintemp = xraytable(1,1)
        maxtemp = xraytable(1, numcoefs)

        ! verify the limit of temperature to assing values
        if (temp.lt.mintemp) then
          CX = 0.0
        else if (temp.gt.maxtemp) then
          CX = xraytable(2, numcoefs)*(temp/maxtemp)**0.5
        else
          do ix=2, numcoefs
            if (xraytable(1,ix).gt.temp) then
              T1 = xraytable(1, ix-1)
              T2 = xraytable(1, ix)
              C1 = xraytable(2, ix-1)
              C2 = xraytable(2, ix)
              CX = C1 + (C2-C1)/(T2-T1) * (temp-T1)
              exit
            end if
          end do
        end if

        x = (i/mapcells_x)*xphystot
        y = (j/mapcells_y)*yphystot
        z = (k/mapcells_z)*zphystot

        ! increment over the line vision direction
        do ii=1, mapcells_x - i
          do jj=1, mapcells_y - j
            do zz=1, mapcells_z - k
              x = x + ii*dx(5)*nx
              y = y + jj*dy(5)*ny
              z = z + zz*dz(5)*nz

              N = out_density((x/xphystot), int(y/yphystot), int(z/zphystot))

              if (temp < ion_thres) then
                xray = (CX*(pvars(1)/mu0/AMU)**2)*exp(at*N)
              else
                xray = (CX*(pvars(1)/mui/AMU)**2)*exp(at*N)
              end if
  
            end do
          end do
        end do
      end do
    end do
  end do
  return  
end subroutine

! Map density in unstructured grid to a max resolution array grid
subroutine Mapping()
    implicit none
    
    ! Read one data file at a time
    do p=0, nprocs-1
      ! Generate filename based on templates
      call genfname(p, nout, datadir, blockstpl, ".bin", filename)

      ! Open data file
      ! write(*,'(1x,a,a,a)') "Opening data file '", trim(filename), "' ..." 
      unitin = 10 + p
      open( unit=unitin, file=filename, status="old", access="stream", iostat=istat )
      if ( istat.ne.0 ) then 
        write(*,"(a,a,a)") "Could not open the file ", trim(filename), " '! "
        write(*,"(a,a,a)") "Does the datadir ", trim(datadir), " 'exist? "
        close(unitin)
        stop
      end if

      ! Read file header
      blocksread = 0
      read(unitin) nblocks
      ! write(*,'(1x,a,i0,a)') "File contains ", nblocks, " blocks."

      ! Loop over all blocks, process one block at a time 
      do nb=1, nblocks

        ! process this block's data
        read(unitin) bID
        read(unitin) block(:, :, :, :)
        blocksread = blocksread + 1

        ! Identify level resolution of the grid 
        call meshlevel(bID, mesh, ilev)
        ! Get the reference corner position in physical units
        call getRefCorner(bID, xo, yo, zo)

        ! index transformation of physical corner reference for a given block 
        io =  int((xo/xphystot) * mapcells_x)
        jo =  int((yo/yphystot) * mapcells_y)
        ko =  int((zo/zphystot) * mapcells_z)

        ! variable to save level of refinement, util to iterate over map at max resolution
        threshold_lev = 2**(p_maxlev - ilev)
        ! For every cell , maintains the block reference
        do i = 1, ncells_x
          do j = 1, ncells_y
            do k = 1, ncells_z

              ! Index to map globals variables
              ig = io + (i-1) * threshold_lev 
              jg = jo + (j-1) * threshold_lev 
              kg = ko + (k-1) * threshold_lev 
              
              uvars = block(:, i, j, k)
              call flow2prim (uvars, pvars)
              pvars(1) = pvars(1)*d_sc
              pvars(2) = pvars(2)*v_sc
              pvars(3) = pvars(3)*v_sc
              pvars(4) = pvars(4)*v_sc
              pvars(5) = pvars(5)*p_sc

              do i_dif = 1, threshold_lev 
              	do j_dif = 1, threshold_lev 
              		do k_dif = 1, threshold_lev 
                      out_density(i_dif + ig, j_dif + jg , k_dif + kg ) = pvars(1)
                      out_pressure(i_dif + ig, j_dif + jg , k_dif + kg ) = pvars(5)
          	  		end do
          	  	end do
          	  end do

            end do
          end do
        end do

      end do
    end do    
end subroutine Mapping

! Generate filename based on templates
subroutine genfname (rank, nout, dir, template, ext, filename)

  implicit none
  integer, intent(in) :: rank
  integer, intent(in) :: nout
  character(*), intent(in) :: dir
  character(*), intent(in) :: template
  character(*), intent(in) :: ext
  character(256), intent(out) :: filename

  character(1) :: slash
  character(4) :: noutstr
  character(3) :: rankstr
  character(2) :: rotstr
  integer :: l

  l = len_trim(dir)
  if (datadir(l:l).ne.'/') then
    slash = '/'
  else
    slash = ''
  end if
  write(rankstr,'(I3.3)') rank
  write(noutstr,'(I4.4)') nout
  filename = template
  call replace (filename, 'XXX', rankstr)
  call replace (filename, 'YYYY', noutstr)

  if (accel.eq.ACCEL_ISO) call replace(filename, 'ZZZ', 'ISO')
  if (accel.eq.ACCEL_PAR) call replace(filename, 'ZZZ', 'PAR')
  if (accel.eq.ACCEL_PER) call replace(filename, 'ZZZ', 'PER')

  write(rotstr,'(I2.2)') int(rot2_angle)
  call replace(filename, 'AA', rotstr)

  write(filename,'(a)') trim(dir) // trim(slash) // trim(filename) // trim(ext)
end subroutine genfname

! Returns the refinemet level of a block 
subroutine meshlevel(bID, mesh, level)

  implicit none

  integer, intent(in) :: bID
  integer, intent(in) :: mesh(7)
  integer, intent(out) :: level

  integer :: minID, maxID

  if (bID.eq.-1) then
    level = -1
    return
  end if

  maxID = 0
  do level=1,mesh(4)
    minID = maxID + 1
    maxID = maxID + mesh(1)*mesh(2)*mesh(3)*8**(level-1)
    if ((bID.ge.minID).and.(bID.le.maxID)) then
      return
    end if
  end do
end subroutine meshlevel

! Returns the number of blocks in all previous levels
subroutine levelOffset(level, mesh, boffset)

  implicit none

  integer, intent(in) :: level
  integer, intent(in) :: mesh(7)
  integer, intent(out) :: boffset

  integer :: ilev

  boffset = 0
  do ilev=1,level-1
    boffset = boffset + mesh(1)*mesh(2)*mesh(3)*8**(ilev-1)
  end do
end subroutine levelOffset

! Returns the (x,y,z) local integer of a block at the block mesh level
subroutine bcoords(bID, mesh, ix, iy, iz)

  implicit none

  integer, intent(in) :: bID
  integer, intent(in) :: mesh(7)
  integer, intent(out) :: ix, iy, iz

  integer :: ilev, nx, ny, nz, localID, boffset

  call meshlevel (bID, mesh, ilev)
  call levelOffset (ilev, mesh, boffset)

  nx = mesh(1)*2**(ilev-1)
  ny = mesh(2)*2**(ilev-1)
  nz = mesh(3)*2**(ilev-1)

  localID = bID - boffset
  ix = mod(localID,nx)
  if (ix.eq.0) ix=nx
  iy = mod(ceiling(localID*1.0/(nx)),ny)
  if (iy.eq.0) iy=ny
  iz = mod(ceiling(localID*1.0/(nx*ny)),nz)
  if (iz.eq.0) iz=nz
end subroutine bcoords

! Returns the physical coordinates (in code units) of a block's
! reference corner
subroutine getRefCorner(bID, xx, yy, zz)
  implicit none
  
  integer, intent(in) :: bID
  real, intent(out) :: xx, yy, zz

  integer :: x, y, z, ilev
  ! identify level of refinement given a bID an ilev
  call meshlevel(bID, mesh, ilev)
  ! Ontaining physical coordinates from a particular corner 
  call bcoords(bID, mesh, x, y, z)

  xx = (x-1)*ncells_x*dx(ilev)
  yy = (y-1)*ncells_y*dy(ilev)
  zz = (z-1)*ncells_z*dz(ilev)
end subroutine getRefCorner

! Get the primitive variables form fluid variables
subroutine flow2prim (uvars, pvars)

  implicit none

  real, intent(in) :: uvars(neqtot)
  real, intent(out) :: pvars(neqtot)

  real :: rhov2

  pvars(1) = uvars(1)
  pvars(2) = uvars(2)/uvars(1)
  pvars(3) = uvars(3)/uvars(1)
  pvars(4) = uvars(4)/uvars(1)

  rhov2 = (uvars(2)**2 + uvars(3)**2 + uvars(4)**2)/uvars(1)
  pvars(5) = (uvars(5)-0.5*rhov2)/CV
  ! Floor on pressure
  if (pvars(5).lt.1.0e-30) then
    ! write(*,*) "PRESSURE FLOOR APPLIED!"
    pvars(5) = 1.0e-30
  end if

  ! Floor on density
  if (pvars(1).lt.1.0e-40) then
    pvars(1) = 1.0e-40
  end if

  if (neqtot.gt.5) then
    pvars(6:neqtot) = uvars(6:neqtot)
  end if

  return
end subroutine flow2prim

! Write output in .bin format
subroutine writebin(fname, nx, ny, zcut, outmap)
    implicit none
    
    character(*), intent(in) :: fname
    integer, intent(in) :: nx, ny, zcut
    real, intent(in) :: outmap(nx, ny, zcut)

    write(*,*) ""
    write(*,'(1x,a,a)') "Writing output file ", trim(fname)
    write(*,'(1x,a,i4,i4)') "Map dimensions:", nx, ny
    write(*,'(1x,a,i0)') "Map size: ", sizeof(outmap)
    write(*,'(1x,a,es10.3,es10.3)') "Range of values:", minval(outmap), maxval(outmap)
    write(*,*) ""
    open (unit=100, file=fname, status='replace', action="write", form='unformatted', access = "stream")
    write(100) outmap(:, :, zcut)
    close(100)
end subroutine writebin

subroutine computeLOS (los)

  implicit none

  real, intent(out) :: los(3)

  real :: x1, y1, z1, x2, y2, z2, x3, y3, z3, x4, y4, z4 

  ! Rotate z unit vector
  call rotatePoint (0.0, 0.0, 1.0, rot1_axis, rot1_angle, x1, y1, z1)
  call rotatePoint (x1, y1, z1, rot2_axis, rot2_angle, x2, y2, z2)
  call rotatePoint (x2, y2, z2, rot3_axis, rot3_angle, x3, y3, z3)
  call rotatePoint (x3, y3, z3, rot4_axis, rot4_angle, x4, y4, z4)

  los(1) = x4
  los(2) = y4
  los(3) = z4
end subroutine computeLOS

subroutine rotatePoint (x, y, z, axis, theta, xp, yp, zp)

  implicit none
  real, intent(in) :: x, y, z
  integer, intent(in) :: axis
  real, intent(in) :: theta
  real, intent(out) :: xp, yp, zp

  real :: theta_rad

  ! Don't do anything for null rotations
  if ((axis.eq.AXIS_NONE).or.(theta.eq.0.0)) then
    xp = x
    yp = y
    zp = z
    return
  end if

  ! Apply rotation matrix
  theta_rad = theta*PI/180.0
  if (axis.eq.AXIS_X) then
    xp = x
    yp = cos(theta_rad)*y - sin(theta_rad)*z
    zp = sin(theta_rad)*y + cos(theta_rad)*z
    return
  else if (axis.eq.AXIS_Y) then
    xp = cos(theta_rad)*x + sin(theta_rad)*z
    yp = y
    zp = -sin(theta_rad)*x + cos(theta_rad)*z
    return
  else if (axis.eq.AXIS_Z) then
    xp = cos(theta_rad)*x - sin(theta_rad)*y
    yp = sin(theta_rad)*x + cos(theta_rad)*y
    zp = z
    return
  else
    write(*,*) "Invalid rotation axis!"
    write(*,*) "axis=", axis
    write(*,*) "***ABORTING***"
    stop
  end if
end subroutine rotatePoint

end program Ray_traicing