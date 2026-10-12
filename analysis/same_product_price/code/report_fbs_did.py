#!/usr/bin/env python3
"""Validate and display the actual 500 mL first-stage price DiD."""
from pathlib import Path
import re
from analysis import ROOT, pd, np, plt


def main():
    out = Path(__file__).resolve().parents[1] / "output/fbs_500ml_did"
    results = pd.read_csv(out / "did_results.csv")
    original = pd.read_stata(ROOT / "analysis/first_stage/output/did_coefs_price.dta")
    original = original[original.category.eq("us fbs")].iloc[0]
    baseline = results[results.specification.eq("baseline")].iloc[0]
    restricted = results[results.specification.eq("fbs500")].iloc[0]
    assert np.isclose(baseline.b, original.b, atol=1e-6)
    assert np.isclose(baseline.se, original.se, atol=1e-6)
    panels = {s: pd.read_stata(out / f"{s}_estimation_panel.dta") for s in ["baseline", "fbs500"]}
    controls = []
    for sample, d in panels.items():
        d = d[d.did_sample.eq(1)]
        controls.append(d[d.treated.eq(0)][["category", "uni_id", "year", "avg_log_price", "spend_2013", "obs_cnt"]].sort_values(["category", "uni_id", "year"]).reset_index(drop=True))
    pd.testing.assert_frame_equal(controls[0], controls[1])
    target = panels["fbs500"]
    target = target[target.treated.eq(1) & target.did_sample.eq(1)]
    purchases = pd.read_csv(out / "selected_fbs500_purchases.csv", dtype={"purchase_id": str})
    purchases = purchases.merge(target[["uni_id", "year"]], on=["uni_id", "year"], validate="many_to_one")
    assert purchases.package_ml.eq(500).all()
    assert not purchases.multipack.any() and not purchases.media_or_buffer.any()
    assert len(purchases) == restricted.treated_purchases
    assert purchases.uni_id.nunique() == restricted.treated_unis
    purchases.to_csv(out / "estimation_fbs500_purchases.csv", index=False)
    results["percent_effect"] = 100*np.expm1(results.b)
    results["percent_ci_low"] = 100*np.expm1(results.ci_low)
    results["percent_ci_high"] = 100*np.expm1(results.ci_high)
    results["normal_ci_low"] = results.b - 1.96*results.se
    results["normal_ci_high"] = results.b + 1.96*results.se
    results.to_csv(out / "estimate_summary.csv", index=False)
    events = pd.read_csv(out / "event_study.csv")
    # Validate the exported estimates against Stata's displayed regression,
    # guarding against scalar/variable abbreviation collisions in exports.
    displayed = re.findall(r"^\s*event_(\d{4})\s*\|\s*([\d.\-]+)\s+([\d.\-]+)", (out / "regression.log").read_text(), re.M)
    assert len(displayed) == 18
    for number, (year, b, se) in enumerate(displayed):
        spec = "baseline" if number < 9 else "fbs500"
        row = events[events.specification.eq(spec) & events.year.eq(int(year))].iloc[0]
        assert np.isclose(row.b, float(b), atol=1e-6)
        assert np.isclose(row.se, float(se), atol=1e-6)
    fig, ax = plt.subplots(figsize=(10, 5.5))
    for name, color, offset, label in [("baseline", "tab:blue", -.07, "Original all-size US-FBS"), ("fbs500", "tab:orange", .07, "US-FBS: explicit 500 mL")]:
        e = events[events.specification.eq(name)].sort_values("year")
        x = e.year + offset
        ax.errorbar(x, e.b, yerr=np.vstack([e.b-e.ci_low, e.ci_high-e.b]), fmt="o", color=color, capsize=3, markersize=4, linewidth=1, label=label)
        ax.plot(x, e.b, color=color, linewidth=1)
    ax.axvline(2013.5, color="black", linestyle="--", linewidth=1)
    ax.axhline(0, color="gray", linewidth=.7)
    ax.set(xlabel="Year", ylabel="Log-price effect relative to matched controls (2013 = 0)",
           title="Fixed-package-size robustness: 500 mL FBS price DiD", xticks=range(2010, 2020))
    ax.legend(loc="upper left", fontsize=9)
    ax.grid(alpha=.12)
    fig.text(.035, .025, "Same comparison markets, year/university/market fixed effects, and original 2013 spending weights.\n95% intervals use market-clustered SEs and t critical values (3 markets, 2 residual inference degrees of freedom).", fontsize=8)
    fig.tight_layout(rect=[0, .09, 1, 1])
    fig.savefig(out / "event_study_500ml_vs_original.pdf")
    fig.savefig(out / "event_study_500ml_vs_original.png", dpi=160)
    plt.close(fig)
    coverage = pd.read_csv(out / "fbs500_coverage_by_year.csv")
    years = sorted(purchases.year.unique().astype(int))
    share = restricted.treated_purchases / baseline.treated_purchases
    report = ["500 mL US-FBS price difference-in-differences",
        "These are actual reghdfe regressions, not descriptive before/after averages.",
        "Baseline reproduces the saved original all-size FBS coefficient and SE within 1e-6.",
        "Treated sample: existing cleaned/classified US-FBS purchases with an explicit unambiguous 500 mL description.",
        "Recognizable multipacks, media and buffers are excluded. Countries are not pooled; no SKU repetition requirement.",
        "The outcome is the mean transaction log unit price within university-market-year, using the original cleaning/trimming.",
        "Controls: bioluminescence assay kit and dewar flasks; no package-volume restrictions on controls.",
        "Controls' estimation rows, prices, weights and purchase counts are exactly unchanged.",
        "Fixed effects: year, university, market. Weights: original category-level 2013 spending. Cluster: market.",
        "Post begins in 2014. Existing support rule: university-market first year <2014 and last year >2014.",
        f"Restricted estimation sample: {int(restricted.treated_purchases)} FBS purchase lines from {int(restricted.treated_unis)} universities; {int(restricted.control_purchases)} control purchase lines.",
        f"FBS purchase coverage: {share:.2%} of the original treated estimation purchases; observed years: {years}.",
        f"Estimate: {restricted.b:.6f} log points; SE {restricted.se:.6f}; 95% t CI [{restricted.ci_low:.6f}, {restricted.ci_high:.6f}]; p={restricted.p:.6f}.",
        f"Percentage effect: {100*np.expm1(restricted.b):.2f}%.",
        "With only three market clusters, uncertainty estimates should be interpreted cautiously; the overall event-study F statistic is unavailable.",
        "Original saved plots use 1.96*SE bounds. This plot uses t(2) bounds; normal-approximation bounds are also exported in estimate_summary.csv.",
        "The positive post-merger price estimate remains with bottle volume fixed. Product grade/origin/brand mix within the US-FBS category can still change.",
        "", results.to_string(index=False), "", "Restricted annual estimation coverage:", coverage.to_string(index=False)]
    (out / "results.txt").write_text("\n".join(report)+"\n")
    print(results.to_string(index=False))
    print(f"Validated actual 500 mL estimation purchases and unchanged controls; treated purchase coverage {share:.2%}; years {years}.")


if __name__ == "__main__":
    main()
