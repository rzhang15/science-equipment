#!/bin/bash

# --- CONFIGURATION ---
TOTAL_JOBS=12455       # From Job 0 to 12456
BATCH_SIZE=10000       # Step size (based on your filenames)
OUTPUT_DIR="../output"
MISSING_FILE="missing_jobs.txt"

# Clear previous run
> $MISSING_FILE

echo "Checking $TOTAL_JOBS jobs for missing or empty output..."

for (( i=0; i<=$TOTAL_JOBS; i++ )); do
    
    # Calculate the expected filename
    start=$((i * BATCH_SIZE))
    end=$((start + BATCH_SIZE))
    file="${OUTPUT_DIR}/abstracts_${start}_${end}.csv"

    # Check if file is missing
    if [[ ! -f "$file" ]]; then
        echo "$i" >> $MISSING_FILE
        # echo "Missing: Job $i (File: $file)"
        continue
    fi

    # Check if file is empty (less than 50 bytes = likely just header or empty)
    file_size=$(stat -c%s "$file")
    if [[ $file_size -lt 50 ]]; then
        echo "$i" >> $MISSING_FILE
        echo "Empty: Job $i (Size: $file_size bytes)"
    fi

done

count=$(wc -l < $MISSING_FILE)
echo "------------------------------------------------"
echo "Check complete."
echo "Found $count missing/failed jobs."
echo "IDs saved to: $MISSING_FILE"
