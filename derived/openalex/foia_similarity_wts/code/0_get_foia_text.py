import pandas as pd
import os

# --- PATHS ---
foia_path = '../external/foia/foia_athrs.dta'
ls_samp_path = '../external/ls_samp/list_of_athrs.dta'
text_data_path = '../external/appended_text/cleaned_static_author_text_pre.parquet' # The big file from Script 2
output_path = '../output/foia_author_text_final.csv'

print("Loading FOIA and Sample lists...")
df_foia = pd.read_stata(foia_path)
df_ls = pd.read_stata(ls_samp_path)

df_foia_valid = pd.merge(
    df_foia, 
    df_ls, 
    on='athr_id', 
    how='inner', 
    validate='one_to_one'
)

print(f"FOIA Authors identified: {len(df_foia_valid)}")

if os.path.exists(text_data_path):
    print("Loading pre-processed text data...")
    df_text = pd.read_parquet(text_data_path, columns=['athr_id', 'processed_text'])
    df_final = pd.merge(
        df_foia_valid,
        df_text,
        on='athr_id',
        how='left',
        validate='one_to_one'
    )
    
    missing_count = df_final['processed_text'].isna().sum()
    if missing_count > 0:
        print(f"WARNING: {missing_count} FOIA authors are missing text data.")
    
    print(f"Successfully matched text for {len(df_final) - missing_count} authors.")

else:
    print(f"CRITICAL ERROR: Text file not found at {text_data_path}")
    print("Please run the text processing script first.")
    df_final = df_foia_valid # Fallback to just the list

df_final.to_csv(output_path, index=False)
print(f"Saved final FOIA dataset to: {output_path}")