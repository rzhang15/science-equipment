import pandas as pd
import networkx as nx
from fuzzywuzzy import fuzz

# --- Step 1: Load the data ---
input_file = "../external/samp/merged_unis.dta"
df = pd.read_stata(input_file)

# --- Step 2: Extract unique supplier names ---
unique_suppliers = df['suppliername'].dropna().unique()

# --- Step 3: Build a similarity graph based on fuzzy matching ---
G = nx.Graph()
G.add_nodes_from(unique_suppliers)
similarity_threshold = 90  # Adjust threshold as needed

for i, name1 in enumerate(unique_suppliers):
    for name2 in unique_suppliers[i+1:]:
        similarity = fuzz.ratio(name1.lower(), name2.lower())
        if similarity >= similarity_threshold:
            G.add_edge(name1, name2)

# --- Step 4: Cluster similar supplier names ---
clusters = list(nx.connected_components(G))
name_mapping = {}
for cluster in clusters:
    # Choose the alphabetically first name as the canonical name
    canonical_name = sorted(cluster)[0]
    for name in cluster:
        name_mapping[name] = canonical_name

# --- Step 5: Map the canonical company names back to the dataframe ---
df['company_name'] = df['suppliername'].map(name_mapping)

# --- Step 6: Pre-process string columns to ensure Latin-1 compatibility ---
def to_latin1(x):
    if isinstance(x, str):
        # Replace characters that can't be encoded in Latin-1
        return x.encode('latin-1', errors='replace').decode('latin-1')
    return x

for col in df.select_dtypes(include=['object']).columns:
    df[col] = df[col].apply(to_latin1)

# --- Step 7: Export the final data using Stata format version 117 ---
output_file = "../output/merged_unis_final.dta"
df.to_stata(output_file, write_index=False, version=117)
print(f"Export complete: {output_file}")
