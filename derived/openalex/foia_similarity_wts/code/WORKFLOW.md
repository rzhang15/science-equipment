# foia_similarity_wts — run order

The pipeline builds TF-IDF nearest-neighbor imputation weights from FOIA authors
to the full universe of US life-science authors, then imputes exposure /
category spend / annual spend to every universe author.

The `--tag restricted` variant is the **main spec** — its outputs are what
`analysis/reduced_form/`, `analysis/predicted_impact/`, and
`process_foias/foia_expenditure/` consume.

Everything else here is either (a) validation of that main spec, (b) evidence
that SciBERT/BERT is NOT an improvement over TF-IDF, or (c) sanity checks.

---

## External inputs (must exist first)

Symlinked via `links.txt` under `../external/`:

- `us_appended_text/cleaned_static_author_text_pre_us_v2.parquet` — **cleaned** US life-science text (from `us_cluster_fields/0b_clean_us_corpus.py`; scraper-boilerplate + <200-char authors dropped). Same population that `us_cluster_fields/2_cluster.py` clusters, so cluster labels cover 100% of this pipeline's universe.
- `appended_text/author_static_clusters_100.csv`, `cluster_label_worksheet_100.csv` — K=100 life-science cluster labels (used for `--restrict-to-ls-clusters` in `tfidf/1_vectorize.py`)
- `exposure_wts/athr_exposure.dta` — per-FOIA scalar exposure
- `exposure_wts/athr_exposure_list.dta` — FOIA athr_id list
- `exposure_wts/athr_spend.dta` — per-FOIA annual spend (input to `4_impute_annual_spend.py`)
- `exposure_wts/athr_category_spend.dta` — per-FOIA×category×year spend (input to `4_impute_shift_share.py`)
- `coauthors/coauthors.dta` — (FOIA athr_id, coauthor_id) map
- `ls_athrs/cleaned_last20yrs_all_jrnls` — publication panel used by `foia_authors.do`
- `athr_panel/athr_panel_full_year_last_*.dta` — optional, for `--restrict-to-panel` in `0_get_foia_text.py`

Not symlinked but hard-coded:

- `../../us_cluster_fields/output/author_static_clusters_25.csv`, `static_cluster_descriptions_25.txt` — k=25 clustering **on the US-only corpus** (input to `cluster_sanity_check.py`). Produced by `us_cluster_fields/run_sweep.sbatch`. Uses the same universe as this pipeline, so unmapped-author rate is minimal.
- `../../cluster_fields/output/author_text_unstemmed.parquet` — pre-stem lifetime text (input to `bert/0b_build_foia_unstemmed.py`)
- `../../cluster_fields/output/bert/author_paper_edges.parquet`, `papers_text.parquet` — paper-level edges + text (input to `0c_get_coauthor_stemmed.py` and `bert/0c_build_coauthor_unstemmed.py`)
- `../../get_coauthors/temp/relevant_pprs.dta` — FOIA paper IDs, excluded from coauthor texts

---

## Phase 0 — Build corpora

Text once, used by both the TF-IDF and BERT tracks.

| Step | File | Produces |
|---|---|---|
| 0.1 | `0_get_foia_text.py` | `output/foia_author_text_final.csv`, `foia_author_text_final_dropped.csv` |
| 0.2 | `bert/0b_build_foia_unstemmed.py` | `output/foia_author_text_unstemmed.csv` |
| 0.3 | `0b_get_coauthor_text.py` | `output/coauthor_text_final.csv`, `foia_coauthor_map.csv` |
| 0.4 | `0c_get_coauthor_stemmed.py` | `output/coauthor_text_stemmed.csv` |
| 0.5 | `bert/0c_build_coauthor_unstemmed.py` | `output/coauthor_text_unstemmed.csv` |

Step 0.4 is the TF-IDF-vocab-aligned coauthor corpus (needed only for `tfidf/test_coauthor_similarity.py`). Step 0.5 is the unstemmed variant for BERT.

---

## Phase 1 — Main TF-IDF pipeline (produces the exposure files that reduced_form reads)

Run with `--tag restricted` throughout. All outputs land in `../output/` and carry the `_restricted` suffix.

| Step | File | Produces |
|---|---|---|
| 1.1 | `tfidf/1_vectorize.py --tag restricted` | `tfidf_foia_restricted.npz`, `tfidf_universe_restricted.npz`, `foia_ids_ordered_restricted.csv`, `universe_ids_restricted.parquet`, `feature_names_restricted.pkl`, `feature_diagnostics_restricted.parquet`, `restrict_audit_restricted.json` |
| 1.2 | `tfidf/2_similarity_wts.py --tag restricted` | `weight_matrix_restricted.npz`, `match_diagnostics_restricted.parquet` |
| 1.3 | `tfidf/3_impute_exposure.py --tag restricted` | **`final_imputed_exposure_restricted.csv`** ← the file `analysis/predicted_impact/` and `process_foias/foia_expenditure/` load |
| 1.4 | `tfidf/4_impute_annual_spend.py --tag restricted` | `imputed_annual_spend_restricted.csv` |
| 1.5 | `tfidf/4_impute_shift_share.py --tag restricted` | `final_imputed_shift_share_restricted.csv`, `imputed_shares_matrix_restricted.npz`, `imputed_shares_markets_restricted.csv`, `shock_balance_restricted.csv` |
| 1.6 | `tfidf/export_diag_to_dta.py --tag restricted` | `match_diagnostics_restricted.dta` — Stata copy used by `analysis/reduced_form/code/analysis.do` to build confidence quartiles |

`tfidf/config.py` is imported by `1_vectorize.py` for the shared stopword set — not run directly.

`tfidf/run_pipeline.sbatch` is the SLURM wrapper that chains steps 1.1–1.3 (edit before use if you want 1.4–1.5 as well).

---

## Phase 2 — Validation of the main spec

| Step | File | Produces |
|---|---|---|
| 2.1 | `tfidf/5_holdout_stress.py --tag restricted` | `holdout_stress_pairs_restricted.csv`, `holdout_stress_summary_restricted.csv`, `holdout_stress_overall_restricted.txt`, `holdout_scatter_restricted.png` |
| 2.2 | `tfidf/test_coauthor_similarity.py --tag restricted` | `coauthor_validation_pairs_tfidf.csv`, `coauthor_validation_summary_tfidf.txt` |
| 2.3 | `plot_coauthor_validation.py --method tfidf` | `output/figures/coauthor_validation_tfidf.png`, `coauthor_validation_by_copubs_tfidf.csv`, `coauthor_validation_trend_tfidf.csv` |
| 2.4 | `cluster_sanity_check.py --tag restricted --k 25` | `k25_cluster_sanity.csv`, `k25_cluster_sanity_overall.txt`, `output/figures/k25_cluster_sanity.png` |

**Step 2.1** — held-out-FOIA stress test (per-fold predictions of held-out FOIAs' exposure) — evidence that the imputation is well-calibrated when the anchor set is smaller.

**Steps 2.2–2.3** — coauthor validation: for each known (FOIA, coauthor) pair, imputed coauthor exposure should track FOIA true exposure. Produces the TF-IDF side of the coauthor comparison figure.

**Step 2.4** — new sanity check. For each k=25 cluster from `../us_cluster_fields` (US-only corpus, matches this pipeline's universe), reports (a) # FOIA authors, (b) # non-FOIA universe authors, (c) mean/median own-cluster W share (fraction of a universe author's imputation weight that lands on FOIAs in the same k=25 cluster). Own-cluster share ≫ 1/k means TF-IDF nearest-neighbors and the k=25 clustering see the same topical signal. Summary breaks out FOIA-rich (≥5 anchors) vs thin (1–4) vs empty (0) clusters so uneven FOIA coverage doesn't muddy the read.

**Prereq: run the US pipeline first.**

```bash
cd /n/home02/cxu75/sci_eq/derived/openalex/us_cluster_fields/code
python 0b_clean_us_corpus.py                 # drops boilerplate + <200-char authors
python 1_vectorize.py                        # US-only TF-IDF (reads the v2 parquet)
sbatch run_sweep.sbatch                      # K sweep {10,15,20,25,30}
```

`run_sweep.sbatch` auto-runs `0b_clean_us_corpus.py` and `1_vectorize.py` if their outputs are missing (or if `FORCE_CLEAN=1` / `FORCE_VECTORIZE=1`). Produces `us_cluster_fields/output/author_static_clusters_25.csv` and `static_cluster_descriptions_25.txt` for `cluster_sanity_check.py`.

**Important:** the tfidf pipeline (`tfidf/1_vectorize.py`) reads the same `cleaned_static_author_text_pre_us_v2.parquet`. If you rebuilt the v2 cleaning, re-run Phase 1 so the universe matches the clustering.

---

## Phase 3 — SciBERT / BERT evidence (that TF-IDF still wins)

BERT embedding + validation track. Run once per model tag (`allenai-specter`, `pritamdeka/S-Scibert-snli-multinli-stsb`, `pritamdeka/S-PubMedBert-MS-MARCO`).

| Step | File | Produces |
|---|---|---|
| 3.1 | `bert/1_vectorize.py --model <MODEL>` | `bert_foia_<tag>_unstemmed.npy`, `bert_foia_ids_<tag>_unstemmed.csv` |
| 3.2 | `bert/1_vectorize.py --model <MODEL> --coauthor-input coauthor_text_unstemmed.csv` (via `run_coauthor_embed.sbatch`) | `bert_foia_<tag>_coauthors_unstemmed.npy`, `bert_foia_ids_<tag>_coauthors_unstemmed.csv` |
| 3.3 | `bert/gen_validation_wts.py --model <MODEL> --k 50` | `validation_weights_bert_<tag>_k50.npz` |
| 3.4 | `bert/loov.py --model <MODEL> --source-k 50` | `validation_plot_bert_<tag>.png` (per-model) plus the K-sweep CSVs (`loov_k_sweep_bert.csv`, `loov_k_sweep_by_iso_bert.csv` — historical, produced by an older LOOV harness that was rolled into `bert/loov.py`) |
| 3.5 | `bert/2_similarity_wts.py --model <MODEL>` | dense universe×FOIA weights (not currently retained in `output/` — reproduce on demand) |
| 3.6 | `bert/3_impute_exposure.py --model <MODEL>` | BERT imputed exposure (not retained; reproduce on demand) |
| 3.7 | `bert/test_coauthor_similarity.py --model <MODEL>` | `coauthor_validation_pairs_bert_<tag>.csv`, `coauthor_validation_summary_bert_<tag>.txt` |
| 3.8 | `plot_coauthor_validation.py --method bert` | `output/figures/coauthor_validation_bert.png`, `coauthor_validation_by_copubs_bert.csv`, `coauthor_validation_trend_bert.csv` |

SBATCH wrappers:
- `bert/run_build_unstemmed.sbatch` — bundles the two `0b_*` / `0c_*` unstemmed corpus builds
- `bert/run_coauthor_embed.sbatch` — runs `1_vectorize.py` on the coauthor corpus
- `bert/run_pipeline.sbatch` — end-to-end BERT chain (1.1 → validation)

The comparison figures + `figures/k_sweep_validation.pdf` are the artefacts that document why TF-IDF wins on this task.

---

## Legacy / infra

- `foia_authors.do` — pulls `athr_exposure_list.dta` cross-joined against `ls_athrs`. Not called by any current pipeline; kept because it's the historical entry point for materializing the FOIA↔publication panel. Safe to run standalone if you need to rebuild that panel.
- `make.py` — gslab_make bootstrap (creates `../external/` symlinks from `links.txt`). Run once before anything else.
- `links.txt` — external symlink manifest consumed by `make.py`.
- `__pycache__/` — Python bytecode cache; auto-regenerated, safe to delete.

---

## Full run, cold start (main spec + all validation)

```bash
cd /n/home02/cxu75/sci_eq/derived/openalex/foia_similarity_wts/code

# 0. Externals
python make.py

# 1. Corpora
python 0_get_foia_text.py
python bert/0b_build_foia_unstemmed.py
python 0b_get_coauthor_text.py
python 0c_get_coauthor_stemmed.py
python bert/0c_build_coauthor_unstemmed.py

# 2. Main TF-IDF pipeline
cd tfidf
python 1_vectorize.py       --tag restricted
python 2_similarity_wts.py  --tag restricted
python 3_impute_exposure.py --tag restricted
python 4_impute_annual_spend.py --tag restricted
python 4_impute_shift_share.py  --tag restricted
python export_diag_to_dta.py    --tag restricted

# 3. Validation
python 5_holdout_stress.py       --tag restricted
python test_coauthor_similarity.py --tag restricted
cd ..
python plot_coauthor_validation.py --method tfidf
python cluster_sanity_check.py     --tag restricted --k 25

# 4. BERT comparison (per-model; PubMedBert shown, repeat for others)
cd bert
python 1_vectorize.py --model "pritamdeka/S-PubMedBert-MS-MARCO"
python 1_vectorize.py --model "pritamdeka/S-PubMedBert-MS-MARCO" \
    --coauthor-input ../../output/coauthor_text_unstemmed.csv
python gen_validation_wts.py --model "pritamdeka/S-PubMedBert-MS-MARCO" --k 50
python loov.py               --model "pritamdeka/S-PubMedBert-MS-MARCO" --source-k 50
python test_coauthor_similarity.py --model "pritamdeka/S-PubMedBert-MS-MARCO"
cd ..
python plot_coauthor_validation.py --method bert
```
