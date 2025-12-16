#!/bin/bash
# run_edirect.sh

# --- CONFIGURATION ---
# Exit immediately if a pipe fails (Critical for catching esearch errors)
set -o pipefail 

# EDirect will automatically find this variable. Do not pass it as a flag.
export NCBI_API_KEY="2b1c3a5df0660f2619650b433dab47735808"
export PATH=${PATH}:${HOME}/edirect
# ---------------------

input_path="$1"

if [ -z "$input_path" ]; then
  echo "Error: No input file provided."
  exit 1
fi

echo "Processing: $input_path"

# Process file: skip header, remove carriage returns
tail -n +2 "$input_path" | tr -d '\r' | while IFS=$'\t' read -r query_name query_text || [ -n "$query_name" ]; do

    # Skip empty lines
    if [ -z "$query_text" ] || [ -z "$query_name" ]; then continue; fi

    output_filename="${query_name}_results.txt"
    
    echo "  Querying: $query_name"
    
    # Sanitize: Remove double quotes to prevent HTTP 400 Bad Request errors
    clean_query=$(echo "$query_text" | tr -d '"')

    # Run the search
    # REMOVED: -api_key flag (it caused the error)
    # The tool will use the exported variable automatically.
    if esearch -db pubmed -query "$clean_query" | efetch -format uid > "$output_filename"; then
        
        # Check if we actually got results (file not empty)
        if [ -s "$output_filename" ]; then
            count=$(wc -l < "$output_filename")
            echo "  Success. Saved $count PMIDs to $output_filename"
        else
            echo "  Warning: Query '$query_name' ran but returned 0 results."
            rm -f "$output_filename"
        fi
        
    else
        echo "  ERROR: Query '$query_name' failed (API or Syntax Error)."
        # Clean up empty file if it exists
        [ -f "$output_filename" ] && rm -f "$output_filename"
    fi

    sleep 0.5

done