"""
Build foia_author_text_final.csv and report each FOIA's cluster assignment
+ top terms for diagnostic purposes.

The script does four filtering passes, in order:

  1. (Optional) Restrict FOIA list to authors present as athr_id rows in
     the downstream analysis panel (default: all_jrnls_r1_r2_public).
     Aligns the imputation training pool with the eventual reduced-form
     sample so we don't fit similarity weights on FOIAs we can never
     analyze. Pass --restrict-to-panel "" to disable.
  2. Join with the cluster_fields K=100 assignment so we know which life-
     science subfield each FOIA lives in.
  3. Drop FOIA rows whose cluster was flagged non-life-science in the
     filter worksheet (off by default; pass --drop-non-ls to apply).
     FOIAs are by construction life-science PIs, so a FOIA landing in a
     non-LS cluster usually points at a disambiguation problem rather
     than a true social-scientist FOIA. Inspect before dropping.
  4. Drop FOIA rows whose lifetime text is too short to be meaningful
     (<50 chars). These can't be embedded; they pollute downstream LOOV.

Inputs:
  ../external/exposure_wts/athr_exposure_list.dta            (FOIA athr_ids)
  ../external/athr_panel/athr_panel_full_year_last_{panel}.dta (analysis panel)
  ../external/us_appended_text/cleaned_static_author_text_pre_us.parquet
  ../external/cluster_fields/author_static_clusters_{K}.csv
  ../external/cluster_fields/cluster_label_worksheet_{K}.csv  (keep + top_terms)

Outputs:
  ../output/foia_author_text_final.csv          (athr_id, processed_text,
                                                 cluster_label, cluster_keep,
                                                 cluster_top_terms)
  ../output/foia_author_text_final_dropped.csv  athr_ids dropped + reason
"""
import argparse
import os
import pandas as pd
import polars as pl

ap = argparse.ArgumentParser()
ap.add_argument("--cluster-k", type=int, default=100,
                help="Match author_static_clusters_{K}.csv from cluster_fields/output.")
ap.add_argument("--drop-non-ls", action="store_true",
                help="Drop FOIA authors whose cluster was flagged non-life-science. "
                     "Default: report only, do not drop.")
ap.add_argument("--restrict-to-panel", default="",
                help="Suffix of the analysis panel .dta in "
                     "../external/athr_panel/athr_panel_full_year_last_{suffix}.dta. "
                     "If set, drops FOIA athr_ids that have no row in that panel. "
                     "DEFAULT: empty (no filter) — the imputation pool benefits "
                     "from edge-of-distribution FOIA anchors even when those PIs "
                     "are ineligible for the analysis sample. Pass e.g. "
                     "'all_jrnls_r1_r2_public' to enforce panel membership.")
args = ap.parse_args()

# --- PATHS ---
foia_path      = "../external/exposure_wts/athr_exposure_list.dta"
text_data_path = "../external/us_appended_text/cleaned_static_author_text_pre_us.parquet"
clusters_path  = f"../external/cluster_fields/author_static_clusters_{args.cluster_k}.csv"
worksheet_path = f"../external/cluster_fields/cluster_label_worksheet_{args.cluster_k}.csv"
output_path    = "../output/foia_author_text_final.csv"
dropped_path   = output_path.replace(".csv", "_dropped.csv")

drop_records = []

print("Loading FOIA author list...")
df_foia = pd.read_stata(foia_path)
df_foia["athr_id"] = df_foia["athr_id"].astype(str)
print(f"  FOIA authors: {len(df_foia)}")

# ----------------------------------------------------------------------
# Filter pass 1 (optional): restrict to FOIAs present in the analysis panel
# ----------------------------------------------------------------------
if args.restrict_to_panel:
    panel_path = (f"../external/athr_panel/athr_panel_full_year_last_"
                  f"{args.restrict_to_panel}.dta")
    if not os.path.exists(panel_path):
        raise FileNotFoundError(
            f"Missing analysis panel for --restrict-to-panel="
            f"{args.restrict_to_panel!r}: {panel_path}"
        )
    print(f"Restricting FOIA list to athr_ids in {panel_path}...")
    # Stata .dta -> read only the athr_id column via pandas
    panel_set = set(
        pd.read_stata(panel_path, columns=["athr_id"])["athr_id"].astype(str).unique()
    )
    in_panel = df_foia["athr_id"].isin(panel_set)
    n_drop = int((~in_panel).sum())
    if n_drop:
        for aid in df_foia.loc[~in_panel, "athr_id"].tolist():
            drop_records.append({
                "athr_id": aid,
                "reason": f"not_in_panel_{args.restrict_to_panel}",
                "cluster_label": None,
                "cluster_top_terms": None,
            })
        print(f"  dropping {n_drop} FOIAs absent from panel "
              f"{args.restrict_to_panel}: "
              f"{df_foia.loc[~in_panel, 'athr_id'].tolist()}")
    df_foia = df_foia.loc[in_panel].reset_index(drop=True)
    print(f"  FOIA authors after panel filter: {len(df_foia)}")

foia_ids = df_foia["athr_id"].tolist()

# ----------------------------------------------------------------------
# Join cluster assignment + cluster metadata
# ----------------------------------------------------------------------
if not os.path.exists(clusters_path):
    raise FileNotFoundError(f"Missing cluster file: {clusters_path}. "
                            f"Run cluster_fields/code/2_cluster.py first.")
if not os.path.exists(worksheet_path):
    raise FileNotFoundError(f"Missing worksheet: {worksheet_path}. "
                            f"Run cluster_fields/code/3_filter_life_science.py first.")

print(f"Loading cluster assignments (K={args.cluster_k})...")
df_clusters = (
    pl.scan_csv(clusters_path, schema_overrides={"athr_id": pl.Utf8})
    .filter(pl.col("athr_id").is_in(foia_ids))
    .collect()
    .to_pandas()
)
print(f"  matched cluster rows: {len(df_clusters)} / {len(df_foia)} FOIAs")

print(f"Loading cluster worksheet...")
df_ws = pd.read_csv(worksheet_path)[
    ["cluster_label", "keep", "n_authors", "top_terms"]
].rename(columns={
    "n_authors": "cluster_size",
    "keep": "cluster_keep",
    "top_terms": "cluster_top_terms",
})

df_foia = df_foia.merge(df_clusters, on="athr_id", how="left")
df_foia = df_foia.merge(df_ws, on="cluster_label", how="left")

# ----------------------------------------------------------------------
# Per-cluster FOIA breakdown
# ----------------------------------------------------------------------
print("\n=== FOIA authors grouped by cluster ===")
breakdown = (
    df_foia
    .assign(_present=df_foia["cluster_label"].notna())
    .groupby("cluster_label", dropna=False)
    .agg(
        n_foia=("athr_id", "size"),
        cluster_size=("cluster_size", "first"),
        cluster_keep=("cluster_keep", "first"),
        cluster_top_terms=("cluster_top_terms", "first"),
    )
    .reset_index()
    .sort_values("n_foia", ascending=False)
)
for _, r in breakdown.iterrows():
    if pd.isna(r["cluster_label"]):
        print(f"  [NO CLUSTER]   n_foia={int(r['n_foia']):>3}   "
              f"FOIAs missing from cluster file (no text -> not embedded)")
        continue
    flag = "KEEP" if r["cluster_keep"] == 1 else "DROP"
    cid = int(r["cluster_label"])
    cs  = int(r["cluster_size"]) if pd.notna(r["cluster_size"]) else 0
    print(f"  C{cid:3d} [{flag}]  n_foia={int(r['n_foia']):>3}  "
          f"cluster_size={cs:>8,}   top: {r['cluster_top_terms']}")

n_in_drop = int((df_foia["cluster_keep"] == 0).sum())
n_no_cluster = int(df_foia["cluster_label"].isna().sum())
print(f"\nSummary:")
print(f"  FOIAs in life-science clusters (keep=1):    "
      f"{(df_foia['cluster_keep'] == 1).sum()}")
print(f"  FOIAs in non-life-science clusters (keep=0): {n_in_drop}")
print(f"  FOIAs missing from cluster file:             {n_no_cluster}")

# ----------------------------------------------------------------------
# Filter pass 3: optional cluster-based drop (non-life-science cluster)
# ----------------------------------------------------------------------
if args.drop_non_ls and n_in_drop > 0:
    drop_mask = df_foia["cluster_keep"] == 0
    for _, r in df_foia.loc[drop_mask].iterrows():
        drop_records.append({
            "athr_id": r["athr_id"],
            "reason": "non_life_science_cluster",
            "cluster_label": int(r["cluster_label"]) if pd.notna(r["cluster_label"]) else None,
            "cluster_top_terms": r["cluster_top_terms"],
        })
    print(f"\nDropping {n_in_drop} FOIAs in non-life-science clusters "
          f"(--drop-non-ls).")
    df_foia = df_foia.loc[~drop_mask].reset_index(drop=True)
elif n_in_drop > 0:
    print(f"\nNOTE: {n_in_drop} FOIAs are in non-life-science clusters but "
          f"not dropped. Pass --drop-non-ls to filter them out.")

# ----------------------------------------------------------------------
# Pull text
# ----------------------------------------------------------------------
if not os.path.exists(text_data_path):
    raise FileNotFoundError(f"Text parquet not found: {text_data_path}")

print("\nFiltering text parquet to FOIA authors (lazy scan)...")
remaining_ids = df_foia["athr_id"].tolist()
df_text = (
    pl.scan_parquet(text_data_path)
    .select(["athr_id", "processed_text"])
    .with_columns(pl.col("athr_id").cast(pl.Utf8))
    .filter(pl.col("athr_id").is_in(remaining_ids))
    .collect(streaming=True)
    .to_pandas()
)
print(f"  matched text rows: {len(df_text)} / {len(remaining_ids)}")

df_final = df_foia.merge(df_text, on="athr_id", how="left", validate="one_to_one")

# ----------------------------------------------------------------------
# Filter pass 4: drop empty/short text
# ----------------------------------------------------------------------
text_len = df_final["processed_text"].fillna("").str.len()
drop_mask = text_len < 50
if drop_mask.any():
    for _, r in df_final.loc[drop_mask].iterrows():
        drop_records.append({
            "athr_id": r["athr_id"],
            "reason": "empty_or_short_text",
            "cluster_label": int(r["cluster_label"]) if pd.notna(r["cluster_label"]) else None,
            "cluster_top_terms": r["cluster_top_terms"],
        })
    print(f"\nDROPPING {drop_mask.sum()} FOIAs with empty/short text (<50 chars):")
    for aid in df_final.loc[drop_mask, "athr_id"].tolist():
        chars = text_len.loc[df_final["athr_id"] == aid].iloc[0]
        print(f"  {aid}   text_chars={chars}")
    df_final = df_final.loc[~drop_mask].reset_index(drop=True)

# ----------------------------------------------------------------------
# Save outputs
# ----------------------------------------------------------------------
keep_cols = ["athr_id", "processed_text", "cluster_label",
             "cluster_keep", "cluster_top_terms"]
df_final = df_final[[c for c in keep_cols if c in df_final.columns]]

print(f"\nFinal FOIA pool size: {len(df_final)}")
df_final.to_csv(output_path, index=False)
print(f"Saved {output_path}")

if drop_records:
    pd.DataFrame(drop_records).to_csv(dropped_path, index=False)
    print(f"Saved drop audit: {dropped_path}  ({len(drop_records)} rows)")
