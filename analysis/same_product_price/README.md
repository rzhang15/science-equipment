# Bounded same-product price check

## Actual 500 mL price DiD

The requested fixed-package-size first-stage regression is now separate from the descriptive same-product checks below. It uses the original cleaned item-level sample and existing US-FBS comparison markets, with no new matching and no repeated-SKU requirement.

Run from the repository root:

```bash
python analysis/same_product_price/code/prepare_fbs_did.py
stata-mp -b do analysis/same_product_price/code/fbs_500ml_did.do /n/holylabs/pakes_lab/Lab/sci_eq
python analysis/same_product_price/code/report_fbs_did.py
```

The preparation script restricts **classified US-FBS** purchases to descriptions with an unambiguous 500 mL volume and excludes recognized multipacks, media, and buffers. It uses the existing item-level cleaning and trimming. It rebuilds each university–market–year's mean transaction log price, leaves bioluminescence assay kit and dewar-flask control prices unchanged, and carries over original market/university IDs and 2013 spending weights. The original support rule (first year before 2014 and last year after 2014) is reapplied. It does not pool other FBS country categories or require SKU matching.

The Stata regression is:

```stata
reghdfe avg_log_price posttreat [aw=spend_2013], ///
    absorb(year uni_id mkt) vce(cluster mkt)
```

`posttreat` is treated × year≥2014. An otherwise identical unrestricted regression reproduces the saved original FBS coefficient and standard error. Event-study regressions replace the post interaction with treated × year indicators, omitting 2013. Missing treated years are exported as missing, not zero effects.

Outputs are under `output/fbs_500ml_did/`: the actual Stata `regression.log`, coefficient and event-study CSV/DTA files, PDF/PNG event-study comparison, annual coverage, restricted purchase audit, estimation panels, and `results.txt`. The reporting script verifies the original coefficient/SE, unchanged controls, package eligibility, and purchase counts.

There are only three market clusters. Reported 95% intervals use Stata's t critical value with two residual inference degrees of freedom. The original saved figures used 1.96 × SE; those normal-approximation bounds are also supplied in `estimate_summary.csv`. This check fixes recorded bottle volume, while product composition within the US-FBS category can still change.

## Descriptive same-product checks

Run from the repository root:

```bash
python analysis/same_product_price/code/analysis.py
```

This standalone first-stage robustness searches **original item descriptions across every source in the merged first-stage input**: GovSpend, Michigan, UT Dallas, and Oregon State. It does not change the main first-stage analysis. Other FOIA files not included in that input are outside this exercise.

The main sample requires an FBS description, an explicitly recorded 500 mL volume, positive price and spending, quantity at least one, and a recorded supplier. Recognizable multipacks, media containing FBS, and bundles are excluded. Repeated products are identified by buyer, literal supplier, and exact original description, normalizing case and whitespace only. No fuzzy description matching or supplier consolidation is used. This conservative identity avoids combining products across buyers or vendors, but can lose matches when descriptions or supplier names change. Identical descriptions may still conceal distinctions omitted from the records.

Separate catalog specifications recover UT Dallas's observed SKU field from the standardized records, matching on buyer, supplier, original description, purchase order, and date. Catalog punctuation and whitespace are normalized. One specification requires 500 mL in each transaction description; another also accepts an explicit 500 mL suffix in that transaction's SKU. The latter is also run through 2018 to expose dependence on late price spikes. Sizes are never inferred from a different purchase or an external catalog. Conflicting SKU assignments or sizes are withheld. The package audit also reports 50 and 100 mL records, without treating different sizes as the same product.

For all sources, an additional specification matches catalog-shaped codes at the **start** of original descriptions, requiring buyer, supplier, extracted code, and an explicit 500 mL size to agree. Text after the code may change. A separate conservative specification retains only exact-description matches containing such prefixes. The transaction audit records extracted codes for review. These matches are stronger than generic repeated descriptions, but are not equivalent to a validated manufacturer catalog crosswalk.

Products must appear in both 2010–2013 and 2014–2019. For each product, the code averages transaction log prices within year and averages observed years within each period. It reports the mean product log change using equal product weights and fixed pre-period spending weights. Quantity-weighted within-year log prices are a separate sensitivity. Missing years are not filled, and prices are not trimmed in the primary sample. Additional checks require line totals to agree with price × quantity within 1% (plus two cents), end the window in 2018, compare 2013 with 2014, hold order quantity fixed as part of product identity, and omit each product in turn. A secondary classified-US-FBS subset focuses on the treated market; the primary description-based selection does not require that classification.

A diagnostic also excludes **whole products** whose maximum/minimum observed price exceeds five, both for the full window and 2013–2014. This arbitrary diagnostic threshold is not a cleaning rule: large changes could be genuine, and the primary sample retains those purchases. Review `audit/large_price_range_transactions.csv` before interpreting those sensitivities.

These are **descriptive same-product before/after changes**, without a counterfactual or causal confidence intervals. They assess whether prices change when recorded product identity and size are fixed; they do not identify the merger's effect. They also do not hold serum lot, unrecorded package count, order quantity, or negotiated contract terms fixed. Comparison with the category-level results must account for this difference in estimand and sample.

Outputs are in `output/`:

- `results.txt` and `tables/summary.csv`: specification results and interpretation limits.
- `tables/*_pairs.csv` and `tables/*_annual.csv`: individual product changes and observed annual prices.
- `tables/coverage_by_buyer.csv`: retained rows/spending, explicit-500 mL coverage, and classified US-FBS spending for each buyer. The FBS denominator includes original-text candidates or classified FBS purchases with valid prices; it is not the full trimmed main regression sample.
- `tables/package_size_audit.csv` and `tables/input_sources.csv`: recorded sizes and input-source coverage.
- `audit/fbs_candidates.csv`: all original-text or category FBS candidates, including flags for eligibility, arithmetic consistency, and SKU recovery.
- `audit/*_retained_transactions.csv`: every transaction used by each specification.
- `tables/leave_one_product_out.csv` and `figures/product_price_paths.pdf`: product influence and price trajectories.

Use `--input`, `--utd`, `--output`, `--start`, and `--end` to change paths or the observation window. The treatment boundary remains 2014. To rerun estimates from the same audited input without rescanning the large Stata file:

```bash
python analysis/same_product_price/code/analysis.py \
  --candidates analysis/same_product_price/output/audit/fbs_candidates.csv
```

Requirements: pandas 2+, NumPy, Matplotlib. Outputs contain purchase-level data and should follow the repository's existing data-access practices.

Focused package-parsing and repeated-product weighting checks:

```bash
python -m unittest discover -s analysis/same_product_price/code -p 'test_analysis.py'
```

To produce the fixed-code definition audit, annual coverage, and comparison with the saved original US-FBS matched-control price series:

```bash
python analysis/same_product_price/code/compare_skus.py
```

Run the main analysis first after changing the extraction rules. The catalog extractor preserves alphabetic suffixes such as `FB5001-H`; it must not pool that code with `FB5001`. The corrected results supersede the initial 18-group/118-line embedded-code result, which incorrectly pooled that suffix.

The new `output/sku_findings.txt` and `tables/sku_magnitude_comparison.csv` distinguish unique catalog codes from buyer–supplier–code groups and purchase lines from distinct purchase orders. `audit/sku_definitions.csv` lists every group's code, supplier, buyer, original descriptions, package size, and observed years. `tables/sku_coverage_by_year.csv` shows annual support. `figures/sku_vs_matched_controls.pdf` (also PNG) overlays the original category and control paths with code cohorts purchased in both 2013 and 2014. It uses the saved **undetrended** regression series (`trt_coef_raw` and `year_fes_raw`), indexed to 2013. The count panel reports changing availability of cohort members in other years; those earlier/later annual averages are not a fully balanced SKU index. `figures/sku_dollar_price_paths.pdf` shows every full-window group's actual annual prices separately.

The comparison plot uses fixed 2013 SKU spending weights. Earlier/later averages include only observed cohort members, with annual counts shown below; the 2013–2014 comparison holds cohort membership fixed.

An existing-control benchmark also subtracts the saved matched-control change over each group's own observed years. That comparison is descriptive: the original controls are not newly matched to the SKU buyers, and the raw same-code estimates do not share the original DiD's weights and fixed effects. It should not be reported as a new causal same-SKU merger coefficient. The separate classified-US-FBS code subset is the closest market comparison with the original US-FBS estimate.
