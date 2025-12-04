# 6_examine_utdallas_counts.py
"""
This script loads the manually categorized UT Dallas data, calculates the
number of observations for each category, and saves the results to a CSV
file for easy analysis.
"""
import pandas as pd
import os
import config

def main():
    print("--- Starting UT Dallas Category Count Analysis ---")

    # 1. Load ONLY the required column from the categorized data file for efficiency
    print(f"ℹ️ Loading category data from: {os.path.basename(config.UT_DALLAS_CATEGORIES_XLSX)}...")
    try:
        # By specifying usecols, pandas only reads this one column, which is much faster.
        df_cat = pd.read_excel(config.UT_DALLAS_CATEGORIES_XLSX, usecols=[config.UT_CAT_COL])
    except FileNotFoundError:
        print(f"❌ Error: Could not find the category file at {config.UT_DALLAS_CATEGORIES_XLSX}")
        print("   Please ensure the path in config.py is correct.")
        return
    except ValueError as e:
        # This error occurs if the specified column isn't in the Excel file
        print(f"❌ Error: A column named '{config.UT_CAT_COL}' was not found in the Excel file.")
        print(f"   Pandas error: {e}")
        return
    except Exception as e:
        print(f"❌ An error occurred while loading the Excel file: {e}")
        return

    # 2. Check if the required category column exists (this is now redundant but safe)
    if config.UT_CAT_COL not in df_cat.columns:
        print(f"❌ Error: The category column '{config.UT_CAT_COL}' was not found in the file.")
        return

    # 3. Calculate the value counts for the category column
    print("ℹ️ Calculating observation counts for each category...")
    category_counts = df_cat[config.UT_CAT_COL].value_counts().reset_index()
    
    # 4. Rename columns for clarity
    category_counts.columns = ['category', 'observation_count']

    # 5. Save the results to a new CSV file in the output directory
    output_path = os.path.join(config.OUTPUT_DIR, "utdallas_category_counts.csv")
    try:
        category_counts.to_csv(output_path, index=False)
        print(f"\n✅ Success! Category counts saved to: {output_path}")
        print("\nYou can now open this CSV file in Excel or any spreadsheet program to examine the distribution.")
    except Exception as e:
        print(f"❌ An error occurred while saving the CSV file: {e}")

if __name__ == "__main__":
    main()

