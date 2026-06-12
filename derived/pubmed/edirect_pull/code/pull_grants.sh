#!/bin/bash
# pull_grants.sh — pull PubMed GrantList for every PMID in temp/pmids.txt
# Uses direct HTTP to efetch.fcgi (much faster than EDirect's epost+efetch)
# Parallel + resumable + retry. Skips batches whose final .tsv already exists.

set -o pipefail
export NCBI_API_KEY="2b1c3a5df0660f2619650b433dab47735808"

PMIDS=../temp/pmids.txt
BATCH_DIR=../temp/grants_batches
SPLIT_DIR=../temp/grants_batches/_ids
BATCH_SIZE=200
N_PARALLEL=${N_PARALLEL:-10}
MAX_RETRIES=3

mkdir -p "$BATCH_DIR" "$SPLIT_DIR"

if [ ! -f "$PMIDS" ]; then
    echo "ERROR: $PMIDS not found. Run: python3 export_pmids.py"
    exit 1
fi

if [ -z "$(ls -A "$SPLIT_DIR" 2>/dev/null)" ]; then
    echo "Splitting PMIDs into batches of $BATCH_SIZE..."
    split -l "$BATCH_SIZE" -d -a 7 "$PMIDS" "$SPLIT_DIR/b_"
fi

total=$(ls "$SPLIT_DIR" | wc -l)
done_start=$(ls "$BATCH_DIR"/b_*.tsv 2>/dev/null | wc -l)
echo "Total batches: $total"
echo "Already done:  $done_start"
echo "Workers:       $N_PARALLEL"
echo "Started:       $(date)"

process_batch() {
    local ids_file=$1
    local name=$(basename "$ids_file")
    local out_file="$BATCH_DIR/${name}.tsv"
    local tmp_file="${out_file}.tmp"

    [ -f "$out_file" ] && return 0

    local ids
    ids=$(tr '\n' ',' < "$ids_file" | sed 's/,$//')

    local attempt
    for attempt in 1 2 3; do
        curl -sS --max-time 90 \
            --data-urlencode "db=pubmed" \
            --data-urlencode "id=${ids}" \
            --data-urlencode "retmode=xml" \
            --data-urlencode "api_key=${NCBI_API_KEY}" \
            "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi" 2>/dev/null \
            | python3 "$WORKER_PARSER" > "$tmp_file" 2>/dev/null
        if [ "${PIPESTATUS[1]}" = "0" ]; then
            mv "$tmp_file" "$out_file"
            return 0
        fi
        rm -f "$tmp_file"
        sleep $((attempt * 2))
    done
    return 1
}
export -f process_batch
export BATCH_DIR
export WORKER_PARSER="$PWD/parse_grants.py"

# Background progress reporter
(
    while true; do
        sleep 120
        done_now=$(ls "$BATCH_DIR"/b_*.tsv 2>/dev/null | wc -l)
        echo "  progress: $done_now / $total at $(date +%H:%M:%S)"
    done
) &
PROG_PID=$!
trap "kill $PROG_PID 2>/dev/null" EXIT

find "$SPLIT_DIR" -maxdepth 1 -type f -name 'b_*' -print0 \
    | xargs -0 -P "$N_PARALLEL" -n 1 bash -c 'process_batch "$1"' _

done_end=$(ls "$BATCH_DIR"/b_*.tsv 2>/dev/null | wc -l)
echo "Finished: $(date)"
echo "Total done: $done_end / $total"
