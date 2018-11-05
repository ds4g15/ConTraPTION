#! /bin/bash

# Note, options '--report-bindings -x MALLOC_MMAP_MAX_=-1 -x MALLOC_TRIM_THRESHOLD_=33554432 --mca mpi_paffinity_alone' used for 'mpirun' command obtained from A. Coward

#SBATCH -J SPINUP
#SBATCH -o SPINUP.out
#SBATCH -N 4
#SBATCH -n 64
#SBATCH -t 23:59:59
#SBATCH -p low

runname=SPINUP
spinnum=NUM
nyears=50

module purge
module load shared
module load gcc
module load intel/compiler/64/14.0/2013_sp1.2.144
module load openmpi/intel/64/1.6.5
module load netcdf/intel/64/4.3.0
module load slurm

ln -sf namelist.${runname}${spinnum} namelist
ln -sf namelist_ice.${runname}${spinnum} namelist_ice

time `which mpirun` --report-bindings -x MALLOC_MMAP_MAX_=-1 -x MALLOC_TRIM_THRESHOLD_=33554432 --mca mpi_paffinity_alone 1 -np 64 ./nemo.exe

mv ocean.output ocean.output_${runname}${spinnum}

for filename in `cat date.file | cut -d ' ' -f 2`grid_?_0000.nc `cat date.file | cut -d ' ' -f 2`icemod_0000.nc; do \
    rm ${filename/_0000.nc/}_????.nc
done
for filename in ${runname}_`printf '%08i' $((nyears*spinnum*5475))`_restart_0000.nc ${runname}_`printf '%08i' $((nyears*spinnum*5475))`_restart_ice_0000.nc; do \
    ../../../TOOLS/rebuild_nemo ${filename/_0000.nc} 64; \
    if [ -e ${filename/_0000.nc/}.nc ];
    then rm ${filename/_0000.nc/}_????.nc;
    fi
done

