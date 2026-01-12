import pyalex
from pyalex import Works
import pandas as pd
from itertools import chain

pyalex.config.api_key = "01bd3ab8d66ee5d53d209f63f2dea37d" 
chunk_size = 40 

pmid_file = pd.read_stata('../external/list_of_works.dta')

all_ids = pmid_file['id'].dropna().astype(str).str.strip().tolist()
all_ids = [x for x in all_ids if x != ""]
print(f"Total valid IDs to process: {len(all_ids)}")

# --- Main Loop ---
for i in range(0, len(all_ids), chunk_size):
    chunk = all_ids[i : i + chunk_size]
    query = "|".join(chunk)
    try:
        ids = []
        abstracts = []
        output = Works().filter(openalex_id=query)
        for item in chain(*output.paginate(per_page=50)):
            ids.append(item.get("id"))
            abstracts.append(item.get("abstract"))
        df = pd.DataFrame({'id': ids, 'abstract': abstracts})
        file_path = f"../output/abstract{i}_{i+chunk_size}.csv"
        df.to_csv(file_path, index=False)
        print(f"Completed batch {i} - Extracted {len(df)} records")

    except Exception as e:
        print(f"Error on batch starting at {i}: {e}")