import os
import pandas as pd

folder_path = "../external/abstracts"
all_dfs = []

def parse_messy_csv(filepath):
    parsed_rows = []
    
    with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
        # Read lines and strip whitespace immediately
        lines = f.readlines()
        
        for i, line in enumerate(lines):
            # 1. Skip Header
            if i == 0: continue
            
            line = line.strip()
            
            # 2. Skip empty lines or garbage lines (like the "@@@@@" rows)
            if not line or line.startswith('@'): 
                continue 
            
            # 3. Split ONLY on the first comma
            # This protects commas inside the abstract
            parts = line.split(',', 1)
            
            if len(parts) == 2:
                row_id = parts[0].strip()
                
                # 4. Clean the abstract
                # .strip() removes whitespace
                # .strip('"') removes the quotes wrapping the text
                abstract = parts[1].strip().strip('"')
                
                # 5. Filter: Ensure Abstract is real text
                if (abstract 
                    and abstract.lower() != 'nan' 
                    and abstract.lower() != 'none' 
                    and len(abstract) > 5): # sanity check: abstract must be > 5 chars
                    
                    parsed_rows.append([row_id, abstract])
                
    return pd.DataFrame(parsed_rows, columns=['id', 'abstract'])

# --- Main Execution ---
print("Starting processing...")

for filename in os.listdir(folder_path):
    if filename.endswith('.csv'):
        file_path = os.path.join(folder_path, filename)
        
        try:
            df = parse_messy_csv(file_path)
            if not df.empty:
                all_dfs.append(df)
        except Exception as e:
            print(f"Error parsing {filename}: {e}")

if all_dfs:
    combined_data = pd.concat(all_dfs, ignore_index=True)
    
    # Final cleanup: Remove duplicates if IDs overlap between files
    combined_data.drop_duplicates(subset=['id'], inplace=True)
    
    output_path = "../output/combined_abstracts.csv"
    combined_data.to_csv(output_path, index=False)
    print(f"Success! Saved {len(combined_data)} valid abstracts to {output_path}")
else:
    print("No valid data found.")