# Bounded same-product price check

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
