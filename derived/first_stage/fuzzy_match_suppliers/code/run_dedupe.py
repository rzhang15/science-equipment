import pandas as pd
import dedupe
import os
import re

# --- File Paths ---
csv_file_path = '../external/samp/govspend_panel.csv'
supplier_name_column = 'suppliername'
output_csv_path = '../output/supplier_mapping_dedupe.csv'
settings_file = 'supplier_dedupe_settings.json'
training_file = 'supplier_dedupe_training.json'


def pre_process(name):
    """
    A simpler pre-processing function for dedupe.
    Dedupe is smart enough to handle a lot of this, but
    cleaning common suffixes helps it focus on the important parts.
    """
    if not isinstance(name, str):
        return ''
    
    name = name.lower().strip()
    
    # Remove common business suffixes
    suffixes = r'\b(inc|incorporated|llc|ll|ltd|plc|ag|co|corp|corporation|company|international|gmbh|pllc)\b'
    name = re.sub(suffixes, '', name)
    
    # Remove all punctuation
    name = re.sub(r'[^a-z0-9\s]', '', name).strip()
    # Condense multiple spaces
    name = re.sub(r'\s+', ' ', name)
    
    return name

def read_data(csv_path, column_name):
    """Reads the CSV and prepares it for dedupe."""
    print(f"Reading '{csv_path}'...")
    df = pd.read_csv(csv_path, low_memory=False, dtype=str)
    
    # Clean column headers
    df.columns = [col.strip().lower() for col in df.columns]
    
    if column_name not in df.columns:
        raise KeyError(f"Column '{column_name}' not found. Please check your CSV.")
        
    print(f"Found {len(df)} total rows.")
    
    # Get unique, non-null names
    unique_names = df[column_name].dropna().unique()
    print(f"Found {len(unique_names)} unique supplier names.")
    
    # --- Prepare data for dedupe ---
    # Dedupe expects a dictionary of dictionaries, where the key
    # is a unique ID (we just use the name itself) and the value
    # is a dictionary of the fields to compare.
    data_dict = {}
    for name in unique_names:
        processed_name = pre_process(name)
        if processed_name:
            data_dict[name] = {'suppliername': processed_name}
            
    print(f"Prepared {len(data_dict)} names for deduplication.")
    return data_dict

def main():
    try:
        # --- 1. Read and Prepare Data ---
        data_d = read_data(csv_file_path, supplier_name_column)
        
        # --- 2. Define Fields for Dedupe ---
        # We tell dedupe what fields to compare and what type they are.
        # 'String' type is good for names.
        # Use 'Text' if you have longer descriptions (uses TF-IDF).
        fields = [
            {'field': 'suppliername', 'type': 'String'}
        ]
        
        # --- 3. Initialize Dedupe ---
        # We are doing 'Dedupe', which finds duplicates *within* one file.
        # (The other option is 'RecordLinkage' for two different files)
        deduper = dedupe.Dedupe(fields)
        
        # --- 4. Load Previous Training (if it exists) ---
        if os.path.exists(training_file):
            print(f"Found existing training file: '{training_file}'")
            with open(training_file, 'rb') as f:
                deduper.prepare_training(data_d, training_file=f)
        else:
            deduper.prepare_training(data_d)
            
        print("\n--- Starting Active Learning ---")
        print("Dedupe will ask you to label pairs. (y/n/u/f)")
        print(" (y)es = These are the same company")
        print(" (n)o  = These are different companies")
        print(" (u)nsure = Skip")
        print(" (f)inished = Stop labeling and start clustering")
        print("-" * 30)

        # --- 5. Start the Interactive Labeling Loop ---
        # This will run on your command line
        dedupe.console_label(deduper)
        
        print("\nTraining complete.")
        
        # --- 6. Save Your Training Data ---
        # This saves the (y/n/u) labels you just provided.
        with open(training_file, 'w') as tf:
            deduper.write_training(tf)
            
        # --- 7. Train the Model ---
        # This takes your labels and builds a machine learning model
        print("Training model...")
        deduper.train()

        # --- 8. Save the Learned Settings ---
        # This saves the *model* itself (the learned rules).
        with open(settings_file, 'wb') as sf:
            deduper.write_settings(sf)
        print(f"Model settings saved to: {settings_file}")

        # --- 9. Find the Clusters (Groups) ---
        print("\nFinding clusters... (this may take a few minutes)")
        # This is where it applies the model to all 33k+ names.
        # The threshold is the "confidence" score (0-1).
        # You can lower it to find more (but less certain) matches.
        clustered_dupes = deduper.partition(data_d, threshold=0.5)
        
        print(f"Found {len(clustered_dupes)} clusters (groups).")

        # --- 10. Create and Save the Final Mapping ---
        print("Creating final mapping file...")
        
        # We need to turn the cluster results into a simple
        # "original_name" -> "canonical_name" map
        cluster_mapping = {}
        for cluster_id, cluster in enumerate(clustered_dupes):
            # The first item in the cluster is the "canonical" name
            canonical_name = cluster[0]
            for original_name in cluster:
                cluster_mapping[original_name] = canonical_name
        
        # Convert to DataFrame
        final_df = pd.DataFrame(cluster_mapping.items(), 
                                columns=['original_suppliername', 'canonical_supplier'])

        # Save to CSV
        output_dir = os.path.dirname(output_csv_path)
        if output_dir and not os.path.exists(output_dir):
            os.makedirs(output_dir)
            
        final_df.to_csv(output_csv_path, index=False)
        
        print(f"\n✅ All done! The final file is saved at: {output_csv_path}")

    except FileNotFoundError:
        print(f"\n[ERROR] The file was not found at '{csv_file_path}'.")
    except KeyError as e:
        print(f"\n[ERROR] {e}")
    except Exception as e:
        print(f"\n[ERROR] An unexpected error occurred: {e}")

if __name__ == "__main__":
    main()