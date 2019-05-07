#!/bin/bash
#SBATCH -A p30553             ## account (unchanged)
#SBATCH -p "short"          ## "-p" instead of "-q"
#SBATCH -N 1                 ## number of nodes
#SBATCH -n 1                 ## number of cores
#SBATCH -t 00:10:00          ## walltime
#SBATCH	--job-name="fixed_dis"    ## name of job

module purge all	     ## purge environment modules
module load netlogo/6.0.1           ## Load modules (unchanged)

cd /software/netlogo/6.0.1

netlogo-headless.sh \
--model /projects/p30553/mmss-thesis/dynamic_model.nlogo \
--experiment fixed_dis \
-- table /projects/p30553/mmss-thesis/BehaviorSearch_output/fixed_dis.csv