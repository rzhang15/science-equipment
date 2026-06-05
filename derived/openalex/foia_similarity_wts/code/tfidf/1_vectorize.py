import argparse
import os
import math
import pickle
import numpy as np
import pandas as pd
import scipy.sparse
from joblib import Parallel, delayed
from sklearn.feature_extraction.text import TfidfVectorizer

# --- CONFIGURATION ---
UNIVERSE_PATH = "../../external/us_appended_text/cleaned_static_author_text_pre_us.parquet"
FOIA_PATH = "../../output/foia_author_text_final.csv"
OUTPUT_DIR = "../../output/"

# Default cluster-label source for --restrict-to-foia-clusters.
DEFAULT_CLUSTER_LABELS = (
    "../../../cluster_fields/output/author_static_clusters_100.csv"
)

# Vocab-shaping for universe→FOIA matching:
#   - Larger vocab + lower min_df lets long-tail PI-specific terms survive.
#   - max_df trims generic terms (boilerplate, super-common bio words).
#   - sublinear_tf is critical: per-author text is concatenated career output, so raw
#     token counts scale with productivity. log(1+tf) shifts the signal to topical mix,
#     i.e. "what fraction of an author's career is about X" — which is what we need
#     for the spending-share imputation assumption (same topics ⇒ same product mix).
MAX_FEATURES = 60_000
MIN_DF = 25
MAX_DF = 0.05
NGRAM_RANGE = (1, 2)

# Fit corpus cap. FOIA texts are always added to the fit sample so PI-specific
# vocabulary cannot be excluded by random universe sampling.
SAMPLE_SIZE = 500_000

# After fitting, prune vocab to features that appear in ≥ FOIA_MIN_DF FOIA PIs and
# ≤ FOIA_MAX_DF_FRAC fraction of FOIA PIs. Terms outside this band cannot help
# differentiate among the 200 FOIA PIs (the matching targets), so dropping them
# tightens the cosine geometry around the discriminative axes.
FOIA_MIN_DF = 2
FOIA_MAX_DF_FRAC = 0.95

# Parallelism for the universe transform (fit is single-threaded in sklearn).
N_JOBS = int(os.environ.get("SLURM_CPUS_PER_TASK", os.cpu_count() or 1))
TRANSFORM_CHUNK_SIZE = 20_000  # rows per worker task; smaller → better load balance


def _l2_normalize_rows(M):
    """Vectorized per-row L2 normalization for a sparse matrix."""
    norms = np.sqrt(np.asarray(M.multiply(M).sum(axis=1)).ravel())
    inv = 1.0 / np.maximum(norms, 1e-12)
    return (scipy.sparse.diags(inv) @ M).astype(np.float32)


def transform_chunk(vec, texts, keep_idx):
    """Worker: transform a slice of texts, prune to FOIA-relevant cols, L2-renormalize."""
    m = vec.transform(texts)[:, keep_idx]
    return _l2_normalize_rows(m).tocsr()


def restrict_to_foia_clusters(df_universe, df_foia, cluster_labels_path,
                              min_foia_pis):
    """Filter universe to authors in clusters occupied by ≥ min_foia_pis FOIA PIs.

    Returns (filtered_df_universe, audit_dict). Both df_universe and df_foia
    are matched on athr_id against cluster_labels_path's (athr_id, cluster_label)
    table. Authors with no cluster label are dropped.
    """
    if not os.path.exists(cluster_labels_path):
        raise SystemExit(f"cluster labels not found: {cluster_labels_path}")
    print(f"Loading cluster labels: {cluster_labels_path}")
    labels = pd.read_csv(cluster_labels_path,
                         dtype={"athr_id": str, "cluster_label": int})

    foia_labeled = df_foia[['athr_id']].merge(labels, on='athr_id', how='left')
    n_foia_with_cluster = foia_labeled['cluster_label'].notna().sum()
    foia_cluster_counts = (
        foia_labeled['cluster_label'].dropna().astype(int).value_counts()
    )
    keep_clusters = set(
        foia_cluster_counts[foia_cluster_counts >= min_foia_pis].index.astype(int)
    )

    univ_labeled = df_universe.merge(labels, on='athr_id', how='left')
    n_no_label = univ_labeled['cluster_label'].isna().sum()
    keep_mask = univ_labeled['cluster_label'].isin(keep_clusters)
    kept = univ_labeled.loc[keep_mask, ['athr_id', 'processed_text']].reset_index(drop=True)

    audit = {
        'cluster_labels_path': cluster_labels_path,
        'min_foia_pis_per_cluster': min_foia_pis,
        'n_foia_with_cluster': int(n_foia_with_cluster),
        'n_foia_total': len(df_foia),
        'n_keep_clusters': len(keep_clusters),
        'keep_clusters': sorted(keep_clusters),
        'n_universe_before': len(df_universe),
        'n_universe_unlabeled': int(n_no_label),
        'n_universe_after': len(kept),
        'drop_pct': 100.0 * (1 - len(kept) / max(len(df_universe), 1)),
    }
    print(f"  FOIA PIs with a cluster label: {audit['n_foia_with_cluster']}/{audit['n_foia_total']}")
    print(f"  Kept clusters (≥{min_foia_pis} FOIA PIs): {audit['n_keep_clusters']}")
    print(f"  Universe: {audit['n_universe_before']:,} -> {audit['n_universe_after']:,} "
          f"(dropped {audit['drop_pct']:.2f}%; {audit['n_universe_unlabeled']:,} unlabeled)")
    return kept, audit


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--restrict-to-foia-clusters", action="store_true",
                    help="Restrict universe to authors in cluster_fields clusters "
                         "occupied by ≥ --min-foia-pis FOIA PIs.")
    ap.add_argument("--cluster-labels-path", default=DEFAULT_CLUSTER_LABELS,
                    help="CSV with columns athr_id, cluster_label.")
    ap.add_argument("--min-foia-pis", type=int, default=1,
                    help="Only used with --restrict-to-foia-clusters. Drop clusters "
                         "with fewer than this many FOIA PIs.")
    ap.add_argument("--tag", default="",
                    help="Optional suffix appended to all output filenames, e.g. "
                         "'_restricted'. Lets restricted/baseline runs coexist.")
    ap.add_argument("--min-df",            type=int,   default=MIN_DF)
    ap.add_argument("--max-df",            type=float, default=MAX_DF)
    ap.add_argument("--max-features",      type=int,   default=MAX_FEATURES)
    ap.add_argument("--foia-min-df",       type=int,   default=FOIA_MIN_DF)
    ap.add_argument("--foia-max-df-frac",  type=float, default=FOIA_MAX_DF_FRAC)
    ap.add_argument("--min-foia-words",    type=int,   default=0,
                    help="Drop FOIA PIs whose processed_text has fewer than this "
                         "many whitespace-split tokens. Use ~50 to remove the "
                         "idx-64 case where a 16-word doc behaves as a generic-"
                         "term magnet after sublinear_tf + L2.")
    args = ap.parse_args()

    cfg_min_df            = args.min_df
    cfg_max_df            = args.max_df
    cfg_max_features      = args.max_features
    cfg_foia_min_df       = args.foia_min_df
    cfg_foia_max_df_frac  = args.foia_max_df_frac
    cfg_min_foia_words    = args.min_foia_words

    tag = args.tag
    if tag and not tag.startswith("_"):
        tag = "_" + tag

    print(f"Using N_JOBS={N_JOBS} for parallel transform")
    print(f"Output tag suffix: {tag!r}")

    # --- LOAD DATA ---
    print("Loading Universe Data...")
    df_universe = pd.read_parquet(UNIVERSE_PATH, columns=['athr_id', 'processed_text'])
    print(f"Total authors loaded: {df_universe['athr_id'].nunique()}")

    df_universe['processed_text'] = df_universe['processed_text'].fillna("").astype(str).str.strip()

    print("Filtering empty text...")
    initial_count = len(df_universe)
    df_universe = df_universe[df_universe['processed_text'].str.len() > 0].reset_index(drop=True)
    final_count = len(df_universe)
    print(f"Dropped {initial_count - final_count} authors with no text.")
    print(f"Final Universe Size: {final_count}")

    print("Loading FOIA Data...")
    df_foia = pd.read_csv(FOIA_PATH)
    df_foia['processed_text'] = df_foia['processed_text'].fillna("").astype(str)
    # Defensive: FOIA rows with no usable text embed as all-zero TF-IDF
    # vectors. They pollute LOOV and the FOIA-aware vocab pruning. Drop
    # them here too (0_get_foia_text.py also filters at the source).
    text_len = df_foia['processed_text'].str.len()
    if (text_len < 50).any():
        dropped = df_foia.loc[text_len < 50, 'athr_id'].tolist()
        print(f"  dropping {len(dropped)} FOIAs with empty/short text: {dropped}")
        df_foia = df_foia.loc[text_len >= 50].reset_index(drop=True)
    if cfg_min_foia_words > 0:
        word_counts = df_foia['processed_text'].str.split().str.len().fillna(0)
        short = word_counts < cfg_min_foia_words
        if short.any():
            dropped = df_foia.loc[short, 'athr_id'].tolist()
            print(f"  dropping {int(short.sum())} FOIAs with <{cfg_min_foia_words} words: {dropped}")
            df_foia = df_foia.loc[~short].reset_index(drop=True)
    n_foia = len(df_foia)
    print(f"FOIA PIs: {n_foia}")

    # --- OPTIONAL: RESTRICT UNIVERSE TO FOIA-OCCUPIED CLUSTERS ---
    audit = None
    if args.restrict_to_foia_clusters:
        df_universe, audit = restrict_to_foia_clusters(
            df_universe, df_foia, args.cluster_labels_path, args.min_foia_pis,
        )
        final_count = len(df_universe)

    # --- FIT VECTORIZER ---
    print(f"Fitting vectorizer (min_df={cfg_min_df}, max_df={cfg_max_df}, "
          f"max_features={cfg_max_features})...")
    tfidf = TfidfVectorizer(
        min_df=cfg_min_df,
        max_df=cfg_max_df,
        max_features=cfg_max_features,
        ngram_range=NGRAM_RANGE,
        dtype=np.float32,
        norm='l2',
        sublinear_tf=True,
        tokenizer=str.split,
        token_pattern=None,
    )

    if final_count > SAMPLE_SIZE:
        sample_min_df = max(1, int(round(cfg_min_df * SAMPLE_SIZE / final_count)))
        print(f"  fit on {SAMPLE_SIZE:,}-row universe sample + {n_foia} FOIA docs (min_df={sample_min_df})...")
        tfidf.set_params(min_df=sample_min_df)
        fit_texts = (
            df_universe['processed_text'].sample(n=SAMPLE_SIZE, random_state=42).tolist()
            + df_foia['processed_text'].tolist()
        )
        tfidf.fit(fit_texts)
        del fit_texts
    else:
        tfidf.fit(pd.concat([df_universe['processed_text'], df_foia['processed_text']]).tolist())

    print(f"Vocab size after fit: {len(tfidf.get_feature_names_out())}")

    # --- TRANSFORM FOIA (single-threaded, 200 docs) ---
    print("Transforming FOIA...")
    matrix_foia_full = tfidf.transform(df_foia['processed_text'].tolist())

    # --- FOIA-AWARE VOCAB PRUNING ---
    foia_binary = (matrix_foia_full > 0).astype(np.int32)
    foia_df_counts = np.asarray(foia_binary.sum(axis=0)).ravel()
    foia_max_count = int(np.floor(cfg_foia_max_df_frac * n_foia))
    keep_mask = (foia_df_counts >= cfg_foia_min_df) & (foia_df_counts <= foia_max_count)
    keep_idx = np.where(keep_mask)[0]
    print(f"FOIA-aware prune (min={cfg_foia_min_df}, max_frac={cfg_foia_max_df_frac}): "
          f"keeping {keep_mask.sum()} / {len(keep_mask)} features "
          f"(dropped {(~keep_mask).sum()})")

    matrix_foia = _l2_normalize_rows(matrix_foia_full[:, keep_idx]).tocsr()
    del matrix_foia_full

    # --- TRANSFORM UNIVERSE IN PARALLEL ---
    texts = df_universe['processed_text'].tolist()
    n = len(texts)
    n_chunks = math.ceil(n / TRANSFORM_CHUNK_SIZE)
    print(f"Transforming universe in {n_chunks} chunks of ≤{TRANSFORM_CHUNK_SIZE:,} rows "
          f"across {N_JOBS} workers...")

    chunks = [texts[i:i + TRANSFORM_CHUNK_SIZE] for i in range(0, n, TRANSFORM_CHUNK_SIZE)]
    del texts

    chunk_mats = Parallel(n_jobs=N_JOBS, backend="loky", verbose=5)(
        delayed(transform_chunk)(tfidf, c, keep_idx) for c in chunks
    )
    matrix_universe = scipy.sparse.vstack(chunk_mats, format='csr').astype(np.float32)
    del chunk_mats

    print(f"Universe Matrix Shape: {matrix_universe.shape}")
    print(f"FOIA Matrix Shape:     {matrix_foia.shape}")

    # --- SAVE ARTIFACTS ---
    print("Saving Sparse Matrices...")
    scipy.sparse.save_npz(f"{OUTPUT_DIR}tfidf_universe{tag}.npz", matrix_universe)
    scipy.sparse.save_npz(f"{OUTPUT_DIR}tfidf_foia{tag}.npz", matrix_foia)

    print("Saving ID Lists...")
    df_universe[['athr_id']].to_parquet(f"{OUTPUT_DIR}universe_ids{tag}.parquet", index=False)
    df_foia[['athr_id']].to_csv(f"{OUTPUT_DIR}foia_ids_ordered{tag}.csv", index=False)

    print("Saving Feature Names (Vocabulary)...")
    kept_features = tfidf.get_feature_names_out()[keep_idx]
    with open(f"{OUTPUT_DIR}feature_names{tag}.pkl", "wb") as f:
        pickle.dump(kept_features, f)

    pd.DataFrame({
        'feature': kept_features,
        'foia_df': foia_df_counts[keep_idx],
        'idf': tfidf.idf_[keep_idx],
    }).to_parquet(f"{OUTPUT_DIR}feature_diagnostics{tag}.parquet", index=False)

    if audit is not None:
        import json
        with open(f"{OUTPUT_DIR}restrict_audit{tag}.json", "w") as f:
            json.dump(audit, f, indent=2)
        print(f"Saved restrict audit: {OUTPUT_DIR}restrict_audit{tag}.json")

    print("Vectorization Complete.")


if __name__ == "__main__":
    main()
