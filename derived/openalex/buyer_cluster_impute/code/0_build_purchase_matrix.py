"""
Build (author x category) purchase-share matrix from athr_category_spend.dta.

  - Filter to keep == 1 (project-defined relevant categories).
  - Sum spend across years 2010-2013 per (athr_id, category).
  - Drop categories that appear for fewer than MIN_AUTHORS_PER_CAT authors.
  - Row-normalize so each author's shares sum to 1.

Output: ../output/foia_purchase_matrix.parquet  (athr_id, cat_0..cat_C-1)
        ../output/category_names.txt            (column order)
"""
import numpy as np
import pandas as pd
import config as cfg


def main():
    cfg.OUT.mkdir(parents=True, exist_ok=True)

    raw = pd.read_stata(cfg.SPEND_DTA)
    print(f"raw spend rows: {len(raw):,}")

    kept = raw[raw["keep"] == 1].copy()
    kept["athr_id"] = kept["athr_id"].astype(str)
    print(f"kept (keep==1):  {len(kept):,}   authors={kept['athr_id'].nunique()}   "
          f"categories={kept['category'].nunique()}")

    # Sum spend across years
    spend = (
        kept.groupby(["athr_id", "category"], as_index=False)["spend"].sum()
    )
    print(f"author-cat pairs after year-sum: {len(spend):,}")

    # Drop ultra-rare categories
    n_authors_per_cat = spend.groupby("category")["athr_id"].nunique()
    keep_cats = n_authors_per_cat[n_authors_per_cat >= cfg.MIN_AUTHORS_PER_CAT].index
    spend = spend[spend["category"].isin(keep_cats)]
    print(f"after dropping cats w/ <{cfg.MIN_AUTHORS_PER_CAT} authors: {spend['category'].nunique()} cats")

    # Pivot to wide matrix (zeros where no purchase)
    wide = spend.pivot_table(index="athr_id", columns="category",
                             values="spend", fill_value=0.0)
    print(f"matrix shape (author x cat): {wide.shape}")

    # Row-normalize to shares (some authors may have 0 total if all categories dropped — drop them)
    row_sums = wide.sum(axis=1)
    nonzero = row_sums > 0
    if (~nonzero).any():
        print(f"dropping {(~nonzero).sum()} authors with zero spend across kept cats")
    wide = wide.loc[nonzero]
    wide = wide.div(wide.sum(axis=1), axis=0)
    print(f"final matrix: {wide.shape}")

    wide.reset_index().to_parquet(cfg.OUT / "foia_purchase_matrix.parquet", index=False)

    with open(cfg.OUT / "category_names.txt", "w") as f:
        for c in wide.columns:
            f.write(c + "\n")

    # Quick sanity prints
    print("\n--- top 10 categories by aggregate share ---")
    print(wide.sum(axis=0).sort_values(ascending=False).head(10).round(3).to_string())


if __name__ == "__main__":
    main()
