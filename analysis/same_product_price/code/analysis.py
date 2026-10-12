#!/usr/bin/env python3
"""Bounded, descriptive same-product check using all first-stage sources."""
from pathlib import Path
import argparse
import hashlib
import os
import re
import tempfile

import numpy as np
import pandas as pd
os.environ.setdefault("MPLCONFIGDIR", tempfile.mkdtemp(prefix="same-product-mpl-"))
os.environ.setdefault("XDG_CACHE_HOME", os.environ["MPLCONFIGDIR"])
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parents[3]
FBS = re.compile(r"f(?:o|oe|e)tal.*?(?:bovine|calf).*?serum|\bfbs(?=\b|\d)", re.I)
VOLUME = re.compile(r"(?<![\d.])(\d+(?:\.\d+)?)\s*m\s*l\b", re.I)
MULTIPACK = re.compile(r"\b([2-9]|[1-9]\d+)\s*[x×]\s*500\s*ml|\b(?:case|pack|pk)\s*(?:of\s*)?(?:[2-9]|[1-9]\d+)\b|\b(?:[2-9]|[1-9]\d+)\s*/\s*(?:pk|cs|pack|case)|\b500\s*ml\s*[x×]\s*([2-9]|[1-9]\d+)\b|\b(?:[2-9]|[1-9]\d+)\s*bottles\b|\btwo\s+for\s+one\b", re.I)
MEDIA = re.compile(r"\b(?:dmem|rpmi|medium|media|bundle|kit|buffer|buf)\b|\d+\s*%\s*(?:fbs|fetal)", re.I)
# Preserve single-letter catalog suffixes and HI, but do not absorb a
# following '-US certified...' description into a numeric catalog code.
CATALOG_PREFIX = re.compile(r"^\s*((?:[A-Z]{1,5}\d[A-Z0-9]*|\d{2,}(?:[-.]\d+)+|\d{7,})(?:[-.]\d+[A-Z0-9]*)*(?:[-.](?:HI|[A-Z])(?=[\s,;:]|$))?)(?=[\s,:;-]|$)", re.I)
KEY = ["agencyname", "supplier_key", "description_key", "purchase_id", "date_key"]


def normalize(s):
    return s.fillna("").astype(str).str.upper().str.replace(r"\s+", " ", regex=True).str.strip()


def volume(text):
    sizes = {float(v) for v in VOLUME.findall(text)}
    return next(iter(sizes)) if len(sizes) == 1 else np.nan


def keys(d):
    d["supplier_key"] = normalize(d.suppliername)
    d["description_key"] = normalize(d.product_desc)
    d["date_key"] = pd.to_datetime(d.date, errors="coerce", format="mixed").dt.strftime("%Y-%m-%d")
    d["year"] = pd.to_datetime(d.date_key).dt.year
    d["purchase_id"] = normalize(d.purchase_id)
    return d


def load(args):
    selected, counts = [], []
    cols = ["agencyname", "suppliername", "product_desc", "purchase_id", "price", "qty", "spend", "date", "category"]
    with pd.read_stata(args.input, chunksize=50000, columns=cols, convert_categoricals=False) as reader:
        for number, chunk in enumerate(reader, 1):
            # With categorical conversion disabled, pandas otherwise reloads
            # the entire Stata strL table on every chunk. Cache labels after
            # the first read so subsequent chunks reuse the decoded strings.
            if number == 1:
                reader.value_labels()
            text_fbs = chunk.product_desc.fillna("").map(lambda s: bool(FBS.search(s)))
            category_fbs = chunk.category.fillna("").str.lower().str.contains("fbs", regex=False)
            # Classification supplies coverage denominators only; entry to the check
            # requires FBS in the original description and a recorded volume.
            selected.append(chunk.loc[text_fbs | category_fbs].copy())
            counts.append(chunk.groupby("agencyname").size())
            if number % 10 == 0:
                print(f"Scanned {number * 50000:,} input rows", flush=True)
    d = keys(pd.concat(selected, ignore_index=True))
    d["text_fbs"] = d.product_desc.fillna("").map(lambda s: bool(FBS.search(s)))
    d["package_ml"] = d.product_desc.fillna("").map(volume)
    d["multipack"] = d.product_desc.fillna("").map(lambda s: bool(MULTIPACK.search(s)))
    d["media_or_bundle"] = d.product_desc.fillna("").map(lambda s: bool(MEDIA.search(s)))
    d["sku"] = ""
    # Recover observed catalog fields without joining on purchase ID alone.
    utd = pd.read_csv(args.utd, dtype=str, keep_default_na=False)
    utd = utd.rename(columns={"supplier": "suppliername"})
    utd["agencyname"] = "university of texas at dallas"
    utd = keys(utd)
    utd["sku_package_ml"] = utd.sku.map(volume)
    utd["sku"] = normalize(utd.sku).str.replace(r"[\s.-]", "", regex=True)
    utd.loc[utd.sku.isin(["", "NAN", "NONE", "<NA>"]), "sku"] = ""
    # Conflicting SKU assignments are withheld, never resolved arbitrarily.
    lookup = utd.groupby(KEY, dropna=False).sku.agg(lambda s: s.iloc[0] if s.nunique() == 1 else "").reset_index()
    sizes = utd.groupby(KEY, dropna=False).sku_package_ml.agg(lambda s: s.dropna().iloc[0] if s.nunique() == 1 else np.nan).reset_index()
    lookup = lookup.merge(sizes, on=KEY, validate="one_to_one")
    d = d.drop(columns="sku").merge(lookup, on=KEY, how="left", validate="many_to_one")
    d["sku"] = d.sku.fillna("")
    d["sku_match"] = d.sku.ne("")
    d["supplier_recorded"] = ~d.supplier_key.isin(["", "NA", "NAN", "NONE"])
    d["valid_price"] = (d.price > 0) & (d.qty >= 1) & (d.spend > 0) & d.supplier_recorded
    d["arithmetic_ok"] = np.isclose(d.price * d.qty, d.spend, rtol=.01, atol=.02)
    d["window"] = d.year.between(args.start, args.end)
    d["explicit_500"] = d.text_fbs & d.package_ml.eq(500) & ~d.multipack & ~d.media_or_bundle
    pd.concat(counts).groupby(level=0).sum().rename("all_input_rows").to_csv(args.output / "tables/input_sources.csv")
    return d


def product_id(d, method):
    identity = {"catalog": "sku", "embedded_catalog": "embedded_sku"}.get(method, "description_key")
    fields = ["agencyname", "supplier_key", identity]
    if method == "description_quantity":
        fields.append("qty")
    return d[fields].astype(str).agg(" | ".join, axis=1).map(lambda s: hashlib.sha256(s.encode()).hexdigest()[:16])


def analyze(d, name, method, out):
    d = d.copy()
    d["product_id"] = product_id(d, method)
    d["post"] = d.year.ge(2014)
    support = d.groupby("product_id").post.nunique()
    d = d[d.product_id.isin(support[support == 2].index)].copy()
    if d.empty:
        d.to_csv(out / f"audit/{name}_retained_transactions.csv", index=False)
        pd.DataFrame(columns=["product_id", "year", "log_price"]).to_csv(out / f"tables/{name}_annual.csv", index=False)
        pd.DataFrame(columns=["product_id", "log_change", "percent_change"]).to_csv(out / f"tables/{name}_pairs.csv", index=False)
        return d, pd.DataFrame(), pd.DataFrame()
    d["log_price"] = np.log(d.price)
    d["quantity_log_price"] = d.qty * d.log_price
    d["implied_spend"] = d.price * d.qty
    annual = d.groupby(["product_id", "year"], as_index=False).agg(
        log_price=("log_price", "mean"), quantity_log_price=("quantity_log_price", "sum"),
        qty=("qty", "sum"), rows=("price", "size"), spend=("spend", "sum"),
        implied_spend=("implied_spend", "sum"), agencyname=("agencyname", "first"),
        supplier=("supplier_key", "first"), description=("product_desc", "first"), sku=("sku", "first"),
        embedded_sku=("embedded_sku", "first"))
    annual["qty_weighted_log_price"] = annual.quantity_log_price / annual.qty
    annual["unit_value"] = annual.implied_spend / annual.qty
    annual["post"] = annual.year.ge(2014)
    periods = annual.groupby(["product_id", "post"]).agg(
        log_price=("log_price", "mean"), qty_log_price=("qty_weighted_log_price", "mean"),
        spend=("spend", "sum"), rows=("rows", "sum"), years=("year", "size"))
    pairs = periods.unstack("post")
    pairs.columns = [f"{v}_{'post' if p else 'pre'}" for v, p in pairs.columns]
    pairs["log_change"] = pairs.log_price_post - pairs.log_price_pre
    pairs["qty_log_change"] = pairs.qty_log_price_post - pairs.qty_log_price_pre
    pairs["percent_change"] = 100 * np.expm1(pairs.log_change)
    pairs["pre_price_geomean"] = np.exp(pairs.log_price_pre)
    pairs["post_price_geomean"] = np.exp(pairs.log_price_post)
    pairs = pairs.reset_index().merge(annual.drop_duplicates("product_id")[["product_id", "agencyname", "supplier", "description", "sku", "embedded_sku"]], validate="one_to_one")
    annual.to_csv(out / f"tables/{name}_annual.csv", index=False)
    pairs.to_csv(out / f"tables/{name}_pairs.csv", index=False)
    d.to_csv(out / f"audit/{name}_retained_transactions.csv", index=False)
    return d, annual, pairs


def summarize(name, d, pairs):
    result = dict(specification=name, products=len(pairs), rows=len(d), spending=d.spend.sum())
    for field in ["log_change", "qty_log_change"]:
        result[f"equal_product_{field}"] = pairs[field].mean() if len(pairs) else np.nan
        result[f"pre_spend_weighted_{field}"] = np.average(pairs[field], weights=pairs.spend_pre) if len(pairs) else np.nan
    result["equal_product_percent_change"] = 100 * np.expm1(result["equal_product_log_change"])
    result["pre_spend_weighted_percent_change"] = 100 * np.expm1(result["pre_spend_weighted_log_change"])
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, default=ROOT / "derived/first_stage/merge_price_data/output/first_stage_data_tfidf.dta")
    parser.add_argument("--utd", type=Path, default=ROOT / "derived/process_foias/standardize_foia/output/standardized/utdallas_2011_2024_standardized.csv")
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1] / "output")
    parser.add_argument("--start", type=int, default=2010)
    parser.add_argument("--end", type=int, default=2019)
    parser.add_argument("--candidates", type=Path, help="Reuse a previously generated fbs_candidates.csv instead of rescanning the input")
    args = parser.parse_args()
    for folder in ["tables", "audit", "figures"]:
        (args.output / folder).mkdir(parents=True, exist_ok=True)
    d = pd.read_csv(args.candidates, keep_default_na=False, dtype={"sku": str, "purchase_id": str}) if args.candidates else load(args)
    if args.candidates:
        for field in ["package_ml", "sku_package_ml"]:
            d[field] = pd.to_numeric(d[field], errors="coerce")
        d["window"] = d.year.between(args.start, args.end)
    d[["price", "qty", "spend"]] = d[["price", "qty", "spend"]].astype("float64")
    # Recompute text flags on cached candidates too, so tightening exclusions
    # does not require rescanning all 2.9 million original transactions.
    d["multipack"] = d.product_desc.fillna("").map(lambda s: bool(MULTIPACK.search(s)))
    d["media_or_bundle"] = d.product_desc.fillna("").map(lambda s: bool(MEDIA.search(s)))
    d["explicit_500"] = d.text_fbs & d.package_ml.eq(500) & ~d.multipack & ~d.media_or_bundle
    d["embedded_sku"] = normalize(d.product_desc.str.extract(CATALOG_PREFIX, expand=False)).str.replace(r"[\s.-]", "", regex=True)
    d.loc[d.embedded_sku.str.fullmatch(r"(?:FBS)?\d+(?:ML|L)", case=False), "embedded_sku"] = ""
    d.to_csv(args.output / "audit/fbs_candidates.csv", index=False)
    base = d[d.window & d.valid_price & d.explicit_500].copy()
    base["description_product_id"] = product_id(base, "description")
    ranges = base.groupby("description_product_id").price.agg(["min", "max"])
    suspicious = ranges.index[(ranges["max"] / ranges["min"]) > 5]
    base["price_range_over5"] = base.description_product_id.isin(suspicious)
    base[base.price_range_over5].to_csv(args.output / "audit/large_price_range_transactions.csv", index=False)
    specs = {
        "description_500ml": (base, "description"),
        "description_500ml_us_fbs": (base[base.category.str.lower().eq("us fbs")], "description"),
        "description_500ml_arithmetic_ok": (base[base.arithmetic_ok], "description"),
        "description_500ml_through2018": (base[base.year <= 2018], "description"),
        "description_500ml_2013_2014": (base[base.year.isin([2013, 2014])], "description"),
        "description_500ml_same_order_quantity": (base, "description_quantity"),
        "description_500ml_price_range_le5": (base[~base.price_range_over5], "description"),
        "description_500ml_2013_2014_range_le5": (base[base.year.isin([2013, 2014]) & ~base.price_range_over5], "description"),
        "description_500ml_catalog_prefix": (base[base.embedded_sku.ne("")], "description"),
        "embedded_catalog_500ml": (base[base.embedded_sku.ne("")], "embedded_catalog"),
        "embedded_catalog_500ml_us_fbs": (base[base.embedded_sku.ne("") & base.category.str.lower().eq("us fbs")], "embedded_catalog"),
        "embedded_catalog_500ml_2013_2014": (base[base.embedded_sku.ne("") & base.year.isin([2013, 2014])], "embedded_catalog"),
        "catalog_500ml": (base[base.sku_match], "catalog"),
    }
    # This secondary check uses sizes recorded on either description or SKU,
    # requiring each transaction to have the same explicit size (no propagation).
    sku_size = d.sku_package_ml
    size = d.package_ml.fillna(sku_size)
    conflict = d.package_ml.notna() & sku_size.notna() & d.package_ml.ne(sku_size)
    specs["catalog_500ml_sku_size"] = (d[d.window & d.valid_price & d.text_fbs & d.sku_match & size.eq(500) & ~conflict & ~d.multipack & ~d.media_or_bundle], "catalog")
    specs["catalog_500ml_sku_size_through2018"] = (specs["catalog_500ml_sku_size"][0].loc[lambda x: x.year <= 2018], "catalog")
    summaries, coverage = [], []
    for name, (sample, method) in specs.items():
        retained, annual, pairs = analyze(sample, name, method, args.output)
        summaries.append(summarize(name, retained, pairs))
        print(f"{name}: {len(pairs)} products; {len(retained)} transactions", flush=True)
        for agency, group in d[d.window & d.valid_price].groupby("agencyname"):
            explicit = group[group.explicit_500]
            kept = retained[retained.agencyname.eq(agency)]
            us = group[group.category.str.lower().eq("us fbs")]
            coverage.append(dict(specification=name, agencyname=agency,
                fbs_candidate_rows=len(group), fbs_candidate_spend=group.spend.sum(),
                explicit500_rows=len(explicit), explicit500_spend=explicit.spend.sum(),
                retained_rows=len(kept), retained_spend=kept.spend.sum(),
                retained_share_explicit500_spend=kept.spend.sum()/explicit.spend.sum() if len(explicit) else np.nan,
                us_fbs_spend=us.spend.sum(), retained_us_fbs_spend=kept.loc[kept.category.str.lower().eq("us fbs"), "spend"].sum()))
        if name == "description_500ml" and len(pairs):
            loo = [dict(omitted_product=p.product_id, **summarize(name, retained[retained.product_id.ne(p.product_id)], pairs[pairs.product_id.ne(p.product_id)])) for p in pairs.itertuples()]
            pd.DataFrame(loo).to_csv(args.output / "tables/leave_one_product_out.csv", index=False)
            fig, ax = plt.subplots(figsize=(9, 5))
            for _, g in annual.groupby("product_id"):
                ax.plot(g.year, 100 * np.expm1(g.log_price - g.log_price.iloc[0]), alpha=.55, marker=".")
            ax.axvline(2013.5, color="black", linestyle="--", linewidth=1)
            ax.axhline(0, color="gray", linewidth=.6)
            ax.set(xlabel="Year", ylabel="Price change from product's first observed year (%)",
                   title=f"Repeated descriptions: explicit 500 mL FBS ({len(pairs)} products)")
            fig.tight_layout()
            fig.savefig(args.output / "figures/product_price_paths.pdf")
            fig.savefig(args.output / "figures/product_price_paths.png", dpi=160)
            plt.close(fig)
    summary = pd.DataFrame(summaries)
    summary.to_csv(args.output / "tables/summary.csv", index=False)
    coverage = pd.DataFrame(coverage)
    coverage.to_csv(args.output / "tables/coverage_by_buyer.csv", index=False)
    d[d.window & d.text_fbs].assign(observed_ml=size).groupby(["agencyname", "observed_ml"], dropna=False).agg(rows=("price", "size"), spend=("spend", "sum")).to_csv(args.output / "tables/package_size_audit.csv")
    totals = coverage[coverage.specification.eq("description_500ml")].sum(numeric_only=True)
    share500 = totals.retained_spend / totals.explicit500_spend if totals.explicit500_spend else np.nan
    shareus = totals.retained_us_fbs_spend / totals.us_fbs_spend if totals.us_fbs_spend else np.nan
    report = [f"Bounded same-product price check; {args.start}-2013 vs 2014-{args.end}.",
        "All sources in the merged first-stage input are searched using original descriptions.",
        "Identity: buyer + literal supplier + exact description after case/whitespace normalization.",
        "Catalog checks: buyer + literal supplier + recorded UT Dallas SKU; punctuation normalized.",
        "Only products purchased in both periods enter. No missing-year prices are imputed.",
        "Average transaction log prices within product-year, then average observed years within period.",
        "Equal-product and fixed pre-period spending weights prevent changing product composition.",
        "These are descriptive before/after changes, without a control group or causal standard errors.",
        "Description matches can conceal grade, origin, heat treatment or lot changes omitted from text.",
        "Embedded-catalog matches use only an explicit catalog-shaped prefix in the original description.",
        "500 mL multipacks identified in text are excluded; unrecorded pack counts remain a limitation.",
        "No category-based entry rule or price trimming. Arithmetic and end-year sensitivities are separate.",
        "Coverage denominator includes positive-price/quantity/spend FBS text or classified FBS purchases.",
        "This is a bounded subset, not a replacement for the category-level matched-control estimates.",
        f"Main retained spending: ${totals.retained_spend:,.2f}; {share500:.2%} of explicit-500 mL FBS spending.",
        f"Retained classified US-FBS spending covers {shareus:.2%} of positive-price/quantity/spend US-FBS input spending.",
        "Price-range sensitivities exclude whole products with max/min observed price > 5; baseline retains them.",
        "The 2013-2014 and same-order-quantity checks should be considered alongside the full-window result.",
        "", summary.to_string(index=False)]
    (args.output / "results.txt").write_text("\n".join(report) + "\n")
    print(summary.to_string(index=False))


if __name__ == "__main__":
    main()
