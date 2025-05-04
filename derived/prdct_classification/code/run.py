import time
import pandas as pd
from model_builder import (
    merge_utd_data,
    load_utd_data,
    aggregate_utd_data,
    build_tfidf_model,
    build_sku_map_agg,
    classify_new_items_tfidf_sku,
    spacy_clean_product_description
)

def process_university_data(univ_file, supplier_col, prod_desc_col,
                            vectorizer, X_agg, agg_categories, sku_map_agg, utd_df):
    """
    Loads, cleans, and classifies a university's data using the same pipeline as UT Dallas.
    Creates new columns 'cleaned_desc' and 'cleaned_supplier' for the cleaned product description
    and supplier name, while preserving the original columns.
    """
    df = pd.read_excel(univ_file)
    print(f"Loaded {len(df)} rows from {univ_file}")
    # Remove duplicate rows based on supplier and product description.
    df_unique = df[[supplier_col, prod_desc_col]].drop_duplicates()
    print(f"Unique rows: {len(df_unique)}")

    # Create new cleaned columns for product description and supplier.
    df_unique["cleaned_desc"] = df_unique[prod_desc_col].apply(lambda x: spacy_clean_product_description(str(x)))
    df_unique["cleaned_supplier"] = df_unique[supplier_col].apply(lambda x: str(x).strip().lower())

    # For classification, use the cleaned_desc column.
    # (The classification function expects a column name for product description; here we pass 'cleaned_desc'.)
    tfidf_threshold = 0.25
    token_overlap_threshold = 0.6
    supplier_fuzzy_threshold = 95
    final_fuzzy_threshold = 95
    sku_fuzzy_threshold = 90
    classified_df, _ = classify_new_items_tfidf_sku(
        df_new = df_unique,
        product_col = "cleaned_desc",
        supplier_col = "cleaned_supplier",
        vectorizer = vectorizer,
        X_agg = X_agg,
        categories = agg_categories,
        sku_map_agg = sku_map_agg,
        utd_transactions_df = utd_df,
        tfidf_threshold = tfidf_threshold,
        token_overlap_threshold = token_overlap_threshold,
        supplier_fuzzy_threshold = supplier_fuzzy_threshold,
        final_fuzzy_threshold = final_fuzzy_threshold,
        sku_fuzzy_threshold = sku_fuzzy_threshold
    )
    return classified_df

if __name__ == "__main__":
    start_time = time.time()

    # -------------------------------------------------------------------------
    # A. MERGE UT DALLAS DATA
    # -------------------------------------------------------------------------
    combined_path = "/Users/conniexu/Dropbox (Harvard University)/RubiCon Dissertation/derived_output_sci_eq/ut_dallas_products/combined.xlsx"
    raw_utd_path = "/Users/conniexu/Dropbox (Harvard University)/RubiCon Dissertation/raw/FOIA/utdallas_2011_2024.xlsx"
    sku_var = "sku"
    supplier_id_var = "supplier_id"
    merged_utd_df = merge_utd_data(combined_path, raw_utd_path, sku_var, supplier_id_var)
    print("Merged UT Dallas data shape:", merged_utd_df.shape)
    merged_out = "../output/utdallas_merged.xlsx"
    merged_utd_df.to_excel(merged_out, index=False)
    print("Saved merged UT Dallas data to", merged_out)

    # -------------------------------------------------------------------------
    # B. LOAD & CLEAN UT DALLAS DATA (from combined.xlsx)
    # -------------------------------------------------------------------------
    product_col_utd = "product_desc"
    category_col_utd = "prdct_ctgry"
    utd_df = load_utd_data(combined_path, product_col_utd, sku_var, category_col_utd)
    print("UT Dallas cleaned data rows:", len(utd_df))
    if "supplier_id" not in utd_df.columns:
        full_utd = pd.read_excel(combined_path)
        if "supplier_id" in full_utd.columns:
            utd_df["supplier_id"] = full_utd["supplier_id"]
        else:
            raise KeyError("Combined UT Dallas file missing 'supplier_id'")
    utd_cleaned_out = "../output/ut_dallas_cleaned.xlsx"
    utd_df.to_excel(utd_cleaned_out, index=False)
    print("Saved UT Dallas cleaned data to", utd_cleaned_out)

    # -------------------------------------------------------------------------
    # C. AGGREGATE UT DALLAS DATA
    # -------------------------------------------------------------------------
    group_col = category_col_utd
    supplier_col = "supplier_id"
    agg_df = aggregate_utd_data(utd_df, group_col, sku_var, supplier_col)
    print("Aggregated UT Dallas data. Number of categories:", agg_df[group_col].nunique())
    agg_out = "../output/ut_dallas_aggregated.xlsx"
    agg_df.to_excel(agg_out, index=False)
    print("Saved aggregated UT Dallas data to", agg_out)

    # -------------------------------------------------------------------------
    # D. BUILD TF-IDF MODEL ON AGGREGATED DATA (ngram_range=(1,3))
    # -------------------------------------------------------------------------
    vectorizer, X_agg, agg_categories = build_tfidf_model(agg_df, text_col="agg_text", group_col=group_col, ngram_range=(1,3))
    print("Built TF-IDF model on aggregated UT Dallas data.")
    agg_df["tfidf_embedding"] = [str(list(x)) for x in X_agg.toarray()]
    emb_out = "../output/utdallas_aggregated_embeddings.xlsx"
    agg_df[[group_col, "tfidf_embedding"]].to_excel(emb_out, index=False)
    print("Saved aggregated embeddings to", emb_out)
    sku_map_agg = build_sku_map_agg(agg_df, sku_var, group_col)

    # -------------------------------------------------------------------------
    # E. PROCESS MULTIPLE UNIVERSITIES
    # -------------------------------------------------------------------------
    univ_configs = [
        {
            "file": "/Users/conniexu/Dropbox (Harvard University)/RubiCon Dissertation/raw/FOIA/utaustin_2012_2019.xlsx",
            "supplier_col": "Vendor Name",
            "prod_desc_col": "Item Description 1",
            "name": "UT Austin"
        },
        {
            "file": "/Users/conniexu/Dropbox (Harvard University)/RubiCon Dissertation/raw/FOIA/oregonstate_2010_2019.xlsx",
            "supplier_col": "Vendor Last Name",
            "prod_desc_col": "Purchase Line Description",
            "name": "Oregon State University"
        }
        # Add more configurations as needed.
    ]

    results = {}
    for config in univ_configs:
        print(f"\nProcessing {config['name']}...")
        classified_df = process_university_data(
            univ_file = config["file"],
            supplier_col = config["supplier_col"],
            prod_desc_col = config["prod_desc_col"],
            vectorizer = vectorizer,
            X_agg = X_agg,
            agg_categories = agg_categories,
            sku_map_agg = sku_map_agg,
            utd_df = utd_df
        )
        out_file = f"../output/{config['name'].replace(' ', '_').lower()}_classified.xlsx"
        classified_df.to_excel(out_file, index=False)
        results[config["name"]] = classified_df
        print(f"Saved classified data for {config['name']} to {out_file}")

        # Create a unique file based on the original supplier name, original product description,
        # and the predicted category. The original columns are preserved.
        unique_df = classified_df.drop_duplicates(subset=[config["supplier_col"], config["prod_desc_col"], "predicted_category"])
        unique_out_file = f"../output/{config['name'].replace(' ', '_').lower()}_classified_unique.xlsx"
        unique_df.to_excel(unique_out_file, index=False)
        print(f"Saved unique classified data for {config['name']} to {unique_out_file}")

    # -------------------------------------------------------------------------
    # F. REPORT TRANSACTION & CLASSIFICATION STAGE SHARES
    # -------------------------------------------------------------------------
    dallas_shares = (utd_df[category_col_utd].value_counts(normalize=True) * 100).round(2)
    print("UT Dallas Category Shares (%):")
    print(dallas_shares)
    for name, df_class in results.items():
        print(f"\n{name} Classified Category Shares (%):")
        print((df_class["predicted_category"].value_counts(normalize=True) * 100).round(2))
        print(f"{name} Classification Stage Shares (%):")
        print((df_class["classification_stage"].value_counts(normalize=True) * 100).round(2))

    # -------------------------------------------------------------------------
    # G. REPORT RUNTIME
    # -------------------------------------------------------------------------
    elapsed_time = time.time() - start_time
    print("Total runtime (minutes):", elapsed_time / 60)
