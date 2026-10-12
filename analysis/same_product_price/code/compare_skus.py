#!/usr/bin/env python3
"""Compare audited fixed-code FBS prices with saved first-stage controls."""
from pathlib import Path
import argparse

from analysis import ROOT, np, pd, plt


def read_csv(path):
    return pd.read_csv(path, dtype={"embedded_sku": str, "sku": str, "product_id": str})


def cohort_series(annual):
    # A fixed cohort observed on both sides of the 2014 boundary. Later-year
    # averages use the available members, with that limitation shown in the plot.
    supported = annual.groupby("product_id").year.agg(set)
    cohort = supported[supported.map(lambda years: {2013, 2014}.issubset(years))].index
    a = annual[annual.product_id.isin(cohort)].copy()
    baseline = a[a.year.eq(2013)].set_index("product_id").log_price
    a["log_change_from2013"] = a.log_price - a.product_id.map(baseline)
    weights = a[a.year.eq(2013)].set_index("product_id").spend
    a["fixed_pre_spend"] = a.product_id.map(weights)
    series = []
    for year, group in a.groupby("year"):
        series.append(dict(year=year, groups=len(group), codes=group.embedded_sku.nunique(),
            equal_log_change=group.log_change_from2013.mean(),
            weighted_log_change=np.average(group.log_change_from2013, weights=group.fixed_pre_spend)))
    return a, pd.DataFrame(series)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1] / "output")
    parser.add_argument("--first-stage", type=Path, default=ROOT / "analysis/first_stage")
    args = parser.parse_args()
    out, fs = args.output, args.first_stage
    es_path = fs / "output/estimates/es_avg_log_price_estimatesus fbs.csv"
    did_path = fs / "output/did_coefs_price.dta"
    es = pd.read_csv(es_path).sort_values("year")
    assert es.year.is_unique
    assert np.isclose(es.loc[es.year.eq(2013), "year_fes_raw"].iloc[0], 0)
    assert np.allclose(es.trt_coef_raw - es.year_fes_raw, es.b)
    did = pd.read_stata(did_path)
    original = did[did.category.eq("us fbs")].iloc[0]
    control = es.set_index("year").year_fes_raw
    definitions, coverage, magnitudes, cohorts, series_all = [], [], [], {}, []
    specifications = ["embedded_catalog_500ml", "embedded_catalog_500ml_us_fbs", "embedded_catalog_500ml_2013_2014", "catalog_500ml_sku_size", "catalog_500ml_sku_size_through2018"]
    for spec in specifications:
        d = read_csv(out / f"audit/{spec}_retained_transactions.csv")
        a = read_csv(out / f"tables/{spec}_annual.csv")
        pairs = read_csv(out / f"tables/{spec}_pairs.csv")
        code = "embedded_sku" if spec.startswith("embedded") else "sku"
        for product, group in d.groupby("product_id"):
            years = sorted(group.year.unique())
            definitions.append(dict(specification=spec, product_id=product,
                catalog_code=group[code].iloc[0], code_source="description prefix" if code == "embedded_sku" else "UT Dallas catalog field",
                buyer=group.agencyname.iloc[0], supplier=group.supplier_key.iloc[0],
                package_ml=500, rows=len(group), purchase_orders=group.purchase_id.nunique(),
                first_year=min(years), last_year=max(years), observed_years=",".join(map(str, years)),
                descriptions=" || ".join(sorted(group.product_desc.unique()))))
        for year, group in d.groupby("year"):
            coverage.append(dict(specification=spec, year=year, codes=group[code].nunique(),
                buyer_supplier_code_groups=group.product_id.nunique(), buyers=group.agencyname.nunique(),
                purchase_lines=len(group), purchase_orders=group.groupby("agencyname").purchase_id.nunique().sum(), spend=group.spend.sum()))
        # Use controls from the same observed years as each product, rather
        # than subtracting a control mean from a different calendar window.
        control_changes = {}
        for product, group in a.groupby("product_id"):
            pre = group.loc[group.year.lt(2014), "year"]
            post = group.loc[group.year.ge(2014), "year"]
            control_changes[product] = control.reindex(post).mean() - control.reindex(pre).mean()
        pairs["existing_control_log_change"] = pairs.product_id.map(control_changes)
        pairs["benchmark_adjusted_log_change"] = pairs.log_change - pairs.existing_control_log_change
        pairs.to_csv(out / f"tables/{spec}_control_benchmark_pairs.csv", index=False)
        raw_equal = pairs.log_change.mean()
        raw_weighted = np.average(pairs.log_change, weights=pairs.spend_pre)
        adj_equal = pairs.benchmark_adjusted_log_change.mean()
        adj_weighted = np.average(pairs.benchmark_adjusted_log_change, weights=pairs.spend_pre)
        magnitudes.append(dict(specification=spec, distinct_catalog_codes=d[code].nunique(),
            buyer_supplier_code_groups=d.product_id.nunique(), purchase_lines=len(d),
            purchase_orders=d.groupby("agencyname").purchase_id.nunique().sum(), buyers=d.agencyname.nunique(),
            first_year=d.year.min(), last_year=d.year.max(), spend=d.spend.sum(),
            equal_product_percent_change=100*np.expm1(raw_equal), fixed_pre_spend_percent_change=100*np.expm1(raw_weighted),
            existing_control_benchmark_equal_percent=100*np.expm1(adj_equal),
            existing_control_benchmark_weighted_percent=100*np.expm1(adj_weighted)))
        if spec in specifications[:2]:
            cohort, series = cohort_series(a)
            cohorts[spec] = (cohort, series)
            series_all.append(series.assign(specification=spec))
    pd.DataFrame(definitions).to_csv(out / "audit/sku_definitions.csv", index=False)
    pd.DataFrame(coverage).to_csv(out / "tables/sku_coverage_by_year.csv", index=False)
    magnitude = pd.DataFrame(magnitudes)
    magnitude.to_csv(out / "tables/sku_magnitude_comparison.csv", index=False)
    pd.concat(series_all, ignore_index=True).to_csv(out / "tables/sku_2013_2014_cohort_series.csv", index=False)
    es.to_csv(out / "tables/original_fbs_matched_control_series.csv", index=False)
    fig, axes = plt.subplots(3, 1, figsize=(10, 10), sharex=True, gridspec_kw={"height_ratios": [2, 2, 1]})
    cohort, broad = cohorts["embedded_catalog_500ml"]
    for _, group in cohort.groupby("product_id"):
        y = group.set_index("year").log_change_from2013.reindex(range(2010, 2020))
        axes[0].plot(y.index, 100*np.expm1(y), color="gray", alpha=.6, marker=".", linewidth=1)
    axes[0].set_title(f"Same catalog codes, same buyer/supplier, 500 mL: {cohort.product_id.nunique()} groups observed in 2013 and 2014")
    axes[0].set_ylabel("Price change from 2013 (%)")
    axes[1].plot(es.year, 100*np.expm1(es.trt_coef_raw), "o-", label="Original US-FBS category series", color="tab:blue")
    axes[1].plot(es.year, 100*np.expm1(es.year_fes_raw), "s--", label="Original matched-control series", color="tab:orange")
    for spec, color, label in [(specifications[0], "tab:green", "Same-code FBS cohort"), (specifications[1], "tab:purple", "Same-code classified US-FBS cohort")]:
        _, s = cohorts[spec]
        y = s.set_index("year").weighted_log_change.reindex(range(2010, 2020))
        axes[1].plot(y.index, 100*np.expm1(y), "o-", color=color, label=label)
        axes[2].plot(s.year, s.groups, "o-", color=color, label=label)
    axes[1].set_ylabel("Price change from 2013 (%)")
    axes[1].legend(fontsize=8, loc="upper left")
    axes[2].set(ylabel="SKU groups observed", xlabel="Year", xticks=range(2010, 2020))
    axes[2].set_ylim(bottom=0)
    for ax in axes:
        ax.axvline(2013.5, color="black", linestyle="--", linewidth=1)
        ax.axhline(0, color="gray", linewidth=.5)
        ax.grid(alpha=.12)
    fig.text(.04, .012, "SKU means use fixed 2013 spending weights among observed cohort members; membership available in each year varies.\nCategory/control series are saved regression paths before detrending, indexed to 2013; no causal SKU estimate is implied.", fontsize=8)
    fig.tight_layout(rect=[0, .055, 1, 1])
    fig.savefig(out / "figures/sku_vs_matched_controls.pdf")
    fig.savefig(out / "figures/sku_vs_matched_controls.png", dpi=160)
    plt.close(fig)
    # Dollar-price small multiples retain every full-window matched code group,
    # including groups without a purchase in 2013.
    a = read_csv(out / "tables/embedded_catalog_500ml_annual.csv")
    n = a.product_id.nunique()
    fig, axes = plt.subplots(int(np.ceil(n/3)), 3, figsize=(13, 3*np.ceil(n/3)), squeeze=False)
    for ax, (_, group) in zip(axes.flat, a.groupby("product_id")):
        ax.plot(group.year, np.exp(group.log_price), "o-", linewidth=1)
        ax.axvline(2013.5, color="black", linestyle="--", linewidth=.8)
        ax.set_title(group.embedded_sku.iloc[0]+"\n"+group.agencyname.iloc[0], fontsize=8)
        ax.set_yscale("log")
        ax.set_xlabel("Year", fontsize=8)
        ax.set_ylabel("Price per recorded unit ($, log scale)", fontsize=7)
        ax.tick_params(labelsize=7)
    for ax in list(axes.flat)[n:]:
        ax.set_visible(False)
    fig.tight_layout()
    fig.savefig(out / "figures/sku_dollar_price_paths.pdf")
    plt.close(fig)
    denom = pd.read_csv(out / "tables/coverage_by_buyer.csv")
    rows = denom[denom.specification.eq("embedded_catalog_500ml")]
    share500 = rows.retained_spend.sum()/rows.explicit500_spend.sum()
    usrows = denom[denom.specification.eq("embedded_catalog_500ml_us_fbs")]
    shareus = usrows.retained_us_fbs_spend.sum()/usrows.us_fbs_spend.sum()
    original_pct = 100*np.expm1(original.b)
    text = ["SKU definition and comparison with saved first-stage FBS estimates",
        "Original headline description result did NOT require a SKU.",
        "Corrected embedded-code identity: buyer + literal supplier + full extracted prefix + explicit 500 mL in each description.",
        "Preserve alphabetic catalog suffixes: FB5001-H is distinct from FB5001. These are recorded-code matches, not an external catalog validation.",
        "UT Dallas catalog-field identity: buyer + literal supplier + observed SKU + 500 mL recorded in description or SKU suffix.",
        "Line counts are purchase lines, not necessarily distinct purchase orders; both counts are exported.",
        f"Embedded-code retained spending covers {share500:.2%} of explicit-500 mL FBS input spending.",
        f"Classified US-FBS embedded-code subset covers {shareus:.2%} of valid-price/quantity/spend classified US-FBS input spending.",
        "Coverage denominators use the untrimmed merged input, not the main regression's trimmed estimation sample.",
        f"Saved original US-FBS DiD: {original.b:.6f} log points (SE {original.se:.6f}); {original_pct:.2f}% increase relative to controls.",
        f"Original coefficient source: {did_path}", f"Original annual series source: {es_path}",
        "Use year_fes_raw and trt_coef_raw for the overlay; the main plotted versions remove a fitted control trend.",
        "SKU estimates average observed product-years within pre/post periods. The original DiD uses different weights, units, and fixed effects.",
        "Existing-control benchmark subtracts the saved control change over each SKU's observed years; it is not a new causal SKU DiD or a matched-buyer estimate.",
        "Overlay cohort must be observed in both 2013 and 2014 and uses fixed 2013 SKU spending weights. Earlier/later availability varies; the count panel makes this visible.",
        "Catalog numbers and bottle volume alone do not resolve unrecorded case counts, line-unit errors, discounts, lots, or treatment suffixes omitted from the source.",
        "", magnitude.to_string(index=False), "", "Annual purchase-line and SKU-group support:", pd.DataFrame(coverage).to_string(index=False)]
    (out / "sku_findings.txt").write_text("\n".join(text)+"\n")
    print(magnitude.to_string(index=False))
    print(f"Original FBS DiD: {original.b:.6f} log points = {original_pct:.2f}%; coverage {share500:.2%} / classified-US {shareus:.2%}")


if __name__ == "__main__":
    main()
