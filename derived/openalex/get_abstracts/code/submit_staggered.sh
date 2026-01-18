#!/bin/bash

# --- CONFIGURATION ---
START_INDEX=3120    # Where to start (e.g., 201)
END_INDEX=3122         # 12456 Where to stop (e.g., run up to 2200)
BATCH_SIZE=200         # How many jobs per array (201-400 = 200 jobs)
DELAY_MINUTES=0

# Loop through the range
for (( i=$START_INDEX; i<$END_INDEX; i+=$BATCH_SIZE )); do

    # Calculate the valid array range for Slurm (0 to 199)
    # We use this to stay under the MaxArraySize limit
    ARRAY_RANGE="0-$((BATCH_SIZE - 1))"

    # Calculate the "real" end index for this batch just for the echo message
    REAL_END=$((i + BATCH_SIZE - 1))

    echo "Submitting Batch for IDs $i to $REAL_END"
    echo " -> Starts in: $DELAY_MINUTES minutes"

    # Submit the job
    # The --wrap command adds the loop offset ($i) to the Slurm ID (0-199)
    # So Python sees the correct global ID (e.g., 1, 402...)
    sbatch -p sapphire \
           -t 3-00:00:00 \
           --mem=50G \
           --array=$ARRAY_RANGE \
           --begin=now+${DELAY_MINUTES}minutes \
           --wrap="export SLURM_ARRAY_TASK_ID=\$((SLURM_ARRAY_TASK_ID + $i)); python pull_abstracts.py"

    # Increment delay by 30 minutes for the next batch
    ((DELAY_MINUTES+=15))
done
