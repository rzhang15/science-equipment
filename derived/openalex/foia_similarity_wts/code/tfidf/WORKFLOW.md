# TF-IDF Imputation Workflow (FOIA-Native Clustering)

This is the recommended pipeline: cluster FOIAs natively, validate them, then build imputation.

## Full Pipeline

### Phase 0: Extract & Validate FOIA Text

Extract FOIA text and cluster FOIAs to identify and drop non-life-science ones.

```bash
cd /n/home02/cxu75/sci_eq/derived/openalex/foia_similarity_wts/code/tfidf

# 0a. Get FOIA text (no pre-filtering, no cluster_fields dependency)
python 0_get_foia_text.py
# Output: foia_author_text_final.csv (~209-213 FOIAs)

# 0b. Vectorize (creates TF-IDF matrices needed for clustering)
python 1_vectorize.py --tag restricted
# Output: 
#   tfidf_foia_restricted.npz
#   tfidf_universe_restricted.npz
#   foia_ids_ordered_restricted.csv
#   universe_ids_restricted.parquet

# 0c. Cluster FOIAs into K=15 research subfields
python cluster_foias.py --tag restricted --n-clusters 15
# Output: foia_clusters_K15_restricted.csv

# 0d. INSPECT all clusters (no changes yet)
python 0b_validate_foia_clusters.py --tag restricted --inspect
# Review the output and decide which clusters are NOT life-science

# 0e. DROP non-life-science FOIA clusters
# Example: if clusters 50 (laser/optics) and 99 (psychology) are non-LS:
python 0b_validate_foia_clusters.py --tag restricted --drop-clusters "50,99"
# Output: 
#   foia_author_text_validated_restricted.csv (filtered FOIAs)
#   foia_validation_audit_restricted.csv (dropped FOIAs + reasons)
```

### Phase 1: Re-Vectorize with Validated FOIAs

Now vectorize using only the validated FOIAs.

```bash
# Copy validated text to standard location
cp ../../output/foia_author_text_validated_restricted.csv \
   ../../output/foia_author_text_final.csv

# Re-vectorize with validated FOIAs
python 1_vectorize.py --tag restricted
# This overwrites the previous vectors with the filtered FOIA set
```

### Phase 2: Build Within-Cluster Imputation

Use the FOIA-native clustering for within-cluster imputation.

```bash
# 2a. Filter universe to authors textually similar to FOIAs
python 0_filter_universe_by_foia_distance.py --tag restricted --keep-percentile 90
# Output: 
#   universe_ids_filtered_restricted.parquet
#   universe_filter_audit_restricted.csv (shows dropped universe authors)

# 2b. Assign filtered universe authors to FOIA clusters
python assign_universe_to_foia_clusters.py --tag restricted --n-clusters 15
# Output: universe_cluster_assignment_restricted.parquet

# 2c. Build within-cluster weight matrices
python 2_similarity_wts_within_cluster.py --tag restricted --k 5
# Output: 
#   weight_matrix_within_cluster_restricted.npz
#   match_diagnostics_within_cluster_restricted.parquet

# 2d. Impute exposure using within-cluster weights
python 3_impute_exposure_within_cluster.py --tag restricted
# Output: final_imputed_exposure_within_cluster_restricted.csv

# 2e. Validate with holdout test
python 5_holdout_stress_within_cluster.py --tag restricted
# Output: holdout_stress_*_within_cluster_restricted.csv
```

---

## Key Steps Explained

### 0a: Get FOIA Text
- Extracts text for all FOIAs
- Does NOT filter by cluster_fields (you'll validate manually instead)
- Output: `foia_author_text_final.csv`

### 0b: Vectorize
- Builds TF-IDF vectors for all FOIAs and universe authors
- Needed BEFORE clustering (clustering uses TF-IDF vectors)

### 0c: Cluster FOIAs
- Groups 207+ FOIAs into K=15 research subfields
- Each cluster has ~14 FOIAs with similar publications

### 0d: Inspect Clusters
- Prints all clusters with their FOIA IDs
- You manually review: "are these all life-science?"
- Example output:
  ```
  CLUSTER 0: 30 FOIAs
    A1234, A5678, ...
  CLUSTER 1: 17 FOIAs
    ...
  ```

### 0e: Validate & Drop
- Removes non-life-science clusters (e.g., optics, psychology, materials science)
- Creates filtered FOIA text file
- You specify which cluster IDs to drop via `--drop-clusters "50,99"`

### Phase 1: Re-Vectorize
- Takes the validated FOIAs and re-vectorizes
- Now your TF-IDF and imputation use only life-science FOIAs
- This ensures the entire pipeline downstream is built on validated data

### Phase 2: Within-Cluster Imputation
- Filters universe authors to those textually similar to FOIAs
- Assigns each universe author to a FOIA cluster
- Imputes exposure from FOIAs in the same cluster (reduces cross-field noise)

---

## Decision Points

**Step 0d — Inspecting clusters:**

Look at the printed clusters. Common non-life-science ones:
- Physics/optics: laser, photon, wavelength, optic
- Psychology/behavior: sexual, adolescent, social, psycholog
- Materials science: polymer, nanoparticle (maybe — depends on context)
- CS/algorithms: algorithm, network, neural, comput

**Life-science clusters** typically include:
- bacteria, virus, cell, protein, gene, mutation, disease
- antibody, antigen, immune, cytokin
- enzyme, kinase, phosphoryl
- development, embryo, differentiation

---

## Outputs Summary

| Stage | Output File | What It Is |
|---|---|---|
| **0a** | `foia_author_text_final.csv` | Raw FOIA text |
| **0b** | `tfidf_foia_restricted.npz` | TF-IDF vectors (all FOIAs) |
| **0c** | `foia_clusters_K15_restricted.csv` | FOIA cluster assignments |
| **0e** | `foia_author_text_validated_restricted.csv` | Filtered FOIA text (life-science only) |
| **Phase 1** | `tfidf_foia_restricted.npz` (overwritten) | TF-IDF vectors (validated FOIAs) |
| **2c** | `weight_matrix_within_cluster_restricted.npz` | Imputation weights (within-cluster) |
| **2d** | `final_imputed_exposure_within_cluster_restricted.csv` | Imputed exposure (main result) |

---

## Tuning Parameters

### Universe filtering (step 2a)
```bash
# Keep top 85% of universe (stricter)
python 0_filter_universe_by_foia_distance.py --tag restricted --keep-percentile 85

# Keep top 95% of universe (more lenient)
python 0_filter_universe_by_foia_distance.py --tag restricted --keep-percentile 95
```

### Within-cluster weighting (step 2c)
```bash
# Use K=3 neighbors (more smoothing)
python 2_similarity_wts_within_cluster.py --tag restricted --k 3

# Use K=10 neighbors (less smoothing)
python 2_similarity_wts_within_cluster.py --tag restricted --k 10

# Lower similarity floor (include weaker matches)
python 2_similarity_wts_within_cluster.py --tag restricted --floor 0.02
```

---

## Troubleshooting

**Q: I'm not sure if cluster X is life-science**
- Look at the top terms (printed in step 0c output)
- Google a few of the FOIAs in that cluster
- Err on the side of keeping it (you can always re-run)

**Q: Should I drop singleton clusters (only 1 FOIA)?**
- Probably yes — they're outliers
- Specify those cluster IDs in `--drop-clusters`

**Q: How many clusters should I expect to drop?**
- Typically 1-3 clusters out of 15
- If you're dropping >5, your FOIA list might have larger contamination issues

**Q: Can I re-run the pipeline after dropping different clusters?**
- Yes! Just run step 0e again with different cluster IDs
- It overwrites `foia_author_text_validated_restricted.csv`
- Then re-run phase 1 onwards
