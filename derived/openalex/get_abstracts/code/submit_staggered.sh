#!/bin/bash

START_INDEX=3120
END_INDEX=3122
BATCH_SIZE=200
DELAY_MINUTES=0

for (( i=$START_INDEX; i<$END_INDEX; i+=$BATCH_SIZE )); do

    ARRAY_RANGE="0-$((BATCH_SIZE - 1))"

    REAL_END=$((i + BATCH_SIZE - 1))

    echo "Submitting Batch for IDs $i to $REAL_END"
    echo " -> Starts in: $DELAY_MINUTES minutes"

    sbatch -p sapphire \
           -t 3-00:00:00 \
           --mem=50G \
           --array=$ARRAY_RANGE \
           --begin=now+${DELAY_MINUTES}minutes \
           --wrap="export SLURM_ARRAY_TASK_ID=\$((SLURM_ARRAY_TASK_ID + $i)); python pull_abstracts.py"

    ((DELAY_MINUTES+=15))
done
