import pyalex
from pyalex import Works
import pandas as pd
from itertools import chain
import sys
import os

# --- CONFIGURATION ---
pyalex.config.api_key = "01bd3ab8d66ee5d53d209f63f2dea37d" 
BATCH_SIZE = 10000  

def main():
    try:
        task_id = int(os.environ['SLURM_ARRAY_TASK_ID'])
    except KeyError:
        print("Warning: SLURM_ARRAY_TASK_ID not found. Defaulting to Task 0.")
        task_id = 0

    print(f"--- Starting Task {task_id} (Batch Size: {BATCH_SIZE}) ---")
    start_index = task_id * BATCH_SIZE
    end_index = start_index + BATCH_SIZE
    print("Loading ID list...")
    pmid_file = pd.read_stata('../output/all_works.dta', columns=['id'])
    all_ids = pmid_file['id'].dropna().astype(str).str.strip().tolist()
    all_ids = [x for x in all_ids if x != ""]
    if start_index >= len(all_ids):
        print("Start index exceeds total IDs. Job finished (nothing to do).")
        sys.exit(0)
    my_ids = all_ids[start_index : end_index]
    print(f"Processing indices {start_index} to {end_index} (Count: {len(my_ids)})")
    results_ids = []
    results_abstracts = []
    api_chunk_size = 50 
    for i in range(0, len(my_ids), api_chunk_size):
        chunk = my_ids[i : i + api_chunk_size]
        formatted_chunk = []
        for x in chunk:
            if x.startswith("W") or x.startswith("http"):
                formatted_chunk.append(x)
            else:
                formatted_chunk.append(f"W{x}")
        query = "|".join(formatted_chunk)
        try:
            output = Works().filter(openalex_id=query)
            for item in chain(*output.paginate(per_page=50)):
                results_ids.append(item.get("id", "").replace("https://openalex.org/", ""))
                abstract_text = item["abstract"]
                results_abstracts.append(abstract_text)
        except Exception as e:
            print(f"Error on inner chunk {i}: {e}")
    df = pd.DataFrame({'id': results_ids, 'abstract': results_abstracts})
    file_path = f"../output/abstracts_{start_index}_{end_index}.csv"
    df.to_csv(file_path, index=False)
    print(f"Success! Saved {len(df)} abstracts to {file_path}")
if __name__ == "__main__":
    main()