#!/usr/bin/env python3
"""Restrict the existing cleaned US-FBS price sample to explicit 500 mL."""
from pathlib import Path
from analysis import ROOT, pd, np, volume, MULTIPACK, MEDIA


def main():
    out = Path(__file__).resolve().parents[1] / "output/fbs_500ml_did"
    out.mkdir(parents=True, exist_ok=True)
    inputs = ROOT / "derived/first_stage/make_mkt_panel/output"
    panel_path = ROOT / "derived/first_stage/matched_panel/output/matched_uni_category_panel.dta"
    panel = pd.read_stata(panel_path, convert_categoricals=False)
    pairs = pd.read_stata(ROOT / "derived/first_stage/matched_panel/output/matched_pairs.dta")
    controls = pairs.loc[pairs.category.eq("us fbs"), "control_market"].unique().tolist()
    categories = ["us fbs"] + controls
    baseline = panel[panel.category.isin(categories)].copy()
    eligibility = pd.read_stata(inputs / "category_hhi_tfidf.dta")
    assert eligibility.loc[eligibility.category.isin(categories), "first_stage_sample"].eq(1).all()
    for col in ["avg_log_price", "raw_spend", "raw_qty", "obs_cnt"]:
        baseline[col] = baseline[col].astype("float64")
    assert baseline.groupby("category").mkt.nunique().eq(1).all()
    columns = ["product_desc", "clean_desc", "category", "year", "uni_id", "agencyname", "purchase_id", "price", "raw_price", "raw_qty", "raw_spend", "suppliername"]
    subsets = []
    with pd.read_stata(inputs / "item_level_tfidf.dta", chunksize=50000, columns=columns, convert_categoricals=False) as reader:
        for number, chunk in enumerate(reader, 1):
            if number == 1:
                reader.value_labels()
            subsets.append(chunk.loc[chunk.category.eq("us fbs")].copy())
    fbs = pd.concat(subsets, ignore_index=True)
    assert np.allclose(fbs.price, np.log(fbs.raw_price), atol=1e-6)
    # Rebuilding the unrestricted outcome must reproduce the existing panel.
    unrestricted = fbs.groupby(["uni_id", "year"], as_index=False).price.mean().rename(columns={"price": "rebuilt_price"})
    check = baseline[baseline.category.eq("us fbs")].merge(unrestricted, on=["uni_id", "year"], how="outer", validate="one_to_one", indicator=True)
    assert check._merge.eq("both").all(), "Item-level and existing-panel university-years differ"
    assert np.allclose(check.avg_log_price, check.rebuilt_price, atol=2e-6), "Unrestricted aggregation does not reproduce the existing price outcome"
    fbs["package_ml"] = fbs.product_desc.fillna("").map(volume)
    fbs["multipack"] = fbs.product_desc.fillna("").map(lambda s: bool(MULTIPACK.search(s)))
    fbs["media_or_buffer"] = fbs.product_desc.fillna("").map(lambda s: bool(MEDIA.search(s)))
    fbs["fbs_500ml"] = fbs.package_ml.eq(500) & ~fbs.multipack & ~fbs.media_or_buffer
    fbs.to_csv(out / "fbs_package_audit.csv", index=False)
    selected = fbs[fbs.fbs_500ml].copy()
    selected[["raw_price", "raw_qty", "raw_spend", "price"]] = selected[["raw_price", "raw_qty", "raw_spend", "price"]].astype("float64")
    collapsed = selected.groupby(["uni_id", "year"], as_index=False).agg(
        price_500ml=("price", "mean"), purchases_500ml=("price", "size"),
        spend_500ml=("raw_spend", "sum"), qty_500ml=("raw_qty", "sum"))
    # Carry over original market IDs, university IDs, and spending weights.
    restricted = baseline.merge(collapsed, on=["uni_id", "year"], how="left", validate="many_to_one")
    target = restricted.category.eq("us fbs")
    restricted = restricted[~target | restricted.price_500ml.notna()].copy()
    target = restricted.category.eq("us fbs")
    restricted.loc[target, "avg_log_price"] = restricted.loc[target, "price_500ml"]
    restricted.loc[target, "obs_cnt"] = restricted.loc[target, "purchases_500ml"]
    restricted.loc[target, "raw_spend"] = restricted.loc[target, "spend_500ml"]
    restricted.loc[target, "raw_qty"] = restricted.loc[target, "qty_500ml"]
    for name, d in [("baseline", baseline), ("fbs500", restricted)]:
        cols = ["category", "year", "uni_id", "mkt", "treated", "avg_log_price", "spend_2013", "obs_cnt", "raw_spend", "agencyname"]
        d[cols].to_stata(out / f"{name}_panel.dta", write_index=False, version=118)
    old_controls = baseline[baseline.category.isin(controls)].sort_values(["category", "uni_id", "year"])
    new_controls = restricted[restricted.category.isin(controls)].sort_values(["category", "uni_id", "year"])
    pd.testing.assert_frame_equal(old_controls[["category", "uni_id", "year", "avg_log_price", "spend_2013"]].reset_index(drop=True), new_controls[["category", "uni_id", "year", "avg_log_price", "spend_2013"]].reset_index(drop=True))
    selected.to_csv(out / "selected_fbs500_purchases.csv", index=False)
    (out / "sample_definition.txt").write_text("\n".join([
        "Input: " + str(inputs / "item_level_tfidf.dta"),
        "Existing cleaning, trimming, category assignment and supplier selection are retained.",
        "Treated market: classified us fbs only; countries of origin are not pooled.",
        "Require unambiguous 500 mL in the original product description; exclude recognized multipacks, media and buffers.",
        "No repeated-description or SKU requirement. No new matching.",
        "University-year outcome: unweighted mean of existing transaction log unit prices, as in the original pipeline.",
        "Controls, market IDs, university IDs, and original 2013 spending weights are unchanged.",
        "Controls: " + ", ".join(controls),
        "Existing DiD support rule is reapplied after restriction: first purchase year <2014 and last purchase year >2014 within university-market.",
        "Regress log price on treated x post(2014+); absorb year, university and market; cluster by market.",
        f"Original treated purchase lines: {len(fbs)}; explicit-500 mL purchase lines before support rule: {len(selected)}.",
        "Validated unrestricted item aggregation against existing panel and unchanged control outcomes/weights."
    ]) + "\n")
    print(f"Original FBS: {len(fbs)} purchases; 500 mL: {len(selected)} purchases; controls: {controls}", flush=True)


if __name__ == "__main__":
    main()
