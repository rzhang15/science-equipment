"""
Validate FOIA clusters and filter out non-life-science clusters.

After clustering FOIAs with cluster_foias.py, use this script to:
1. Print all clusters with their FOIAs and top terms
2. Manually identify non-life-science clusters
3. Drop those clusters from the FOIA text file

Usage:
  # First, inspect all clusters (no filtering)
  python 0b_validate_foia_clusters.py --tag restricted --inspect

  # Then, after deciding which clusters to drop:
  python 0b_validate_foia_clusters.py --tag restricted --drop-clusters "50,99"

Output:
  output/foia_author_text_validated_{tag}.csv  (filtered FOIAs)
  output/foia_validation_audit_{tag}.csv       (dropped FOIAs + reasons)
"""
import argparse
import os
import pickle
import numpy as np
import pandas as pd
import scipy.sparse

OUT_DIR = "../output/"


def get_top_terms(cluster_indices, tfidf_foia, feature_names, n_terms=15):
    """Extract top terms from a cluster's TF-IDF centroid."""
    if len(cluster_indices) == 0:
        return []
    cluster_vectors = tfidf_foia[cluster_indices]
    centroid = np.asarray(cluster_vectors.mean(axis=0)).ravel()
    top_idx = np.argsort(-centroid)[:n_terms]
    return [(feature_names[i], centroid[i]) for i in top_idx if centroid[i] > 0]


def get_top_terms_from_text(texts, n_terms=15):
    """Extract top terms from raw text by word frequency."""
    if not texts:
        return []
    from collections import Counter
    all_words = []
    for text in texts:
        all_words.extend(text.split())
    counter = Counter(all_words)
    top_words = counter.most_common(n_terms)
    return [word for word, _ in top_words]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", default="restricted",
                    help="Tag matching prior clustering (default 'restricted').")
    ap.add_argument("--inspect", action="store_true",
                    help="Print all clusters with their FOIAs and top terms (inspection mode, no changes).")
    ap.add_argument("--drop-clusters", default="",
                    help="Comma-separated list of cluster IDs to drop (e.g. '50,99'). "
                         "FOIAs in these clusters will be removed.")
    ap.add_argument("--n-terms", type=int, default=15,
                    help="Number of top terms to show per cluster (default 15).")
    ap.add_argument("--scibert", action="store_true",
                    help="Use SciBERT clustering instead of TF-IDF.")
    args = ap.parse_args()

    tag = args.tag
    if tag and not tag.startswith("_"):
        tag = "_" + tag

    # Paths (TF-IDF or SciBERT)
    if args.scibert:
        foia_clusters_path = f"{OUT_DIR}foia_clusters_K15_scibert{tag}.csv"
        suffix = "_scibert"
    else:
        foia_clusters_path = f"{OUT_DIR}foia_clusters_K15{tag}.csv"
        suffix = ""

    foia_text_path = f"{OUT_DIR}foia_author_text_final.csv"
    tfidf_foia_path = f"{OUT_DIR}tfidf_foia{tag}.npz"
    feature_names_path = f"{OUT_DIR}feature_names{tag}.pkl"
    foia_ids_path = f"{OUT_DIR}foia_ids_ordered{tag}.csv"

    output_text_path = f"{OUT_DIR}foia_author_text_validated{suffix}{tag}.csv"
    output_audit_path = f"{OUT_DIR}foia_validation_audit{suffix}{tag}.csv"

    # Check inputs
    for p in (foia_clusters_path, foia_text_path):
        if not os.path.exists(p):
            raise SystemExit(f"missing: {p}")

    print("Loading FOIA clusters and text...")
    foia_clusters = pd.read_csv(foia_clusters_path)
    foia_text = pd.read_csv(foia_text_path)

    merged = foia_clusters.merge(foia_text, on='athr_id')
    print(f"  Total FOIAs: {len(merged)}")
    print(f"  Clusters: {merged['cluster'].max() + 1}")

    # Load TF-IDF or text data for top-terms extraction (if available)
    feature_names = None
    tfidf_foia = None
    if args.inspect and not args.scibert and os.path.exists(tfidf_foia_path) and os.path.exists(feature_names_path):
        print("Loading TF-IDF vectors and vocabulary for top-terms...")
        tfidf_foia = scipy.sparse.load_npz(tfidf_foia_path).tocsr()
        with open(feature_names_path, "rb") as f:
            feature_names = pickle.load(f)
        print(f"  TF-IDF shape: {tfidf_foia.shape}  vocab size: {len(feature_names)}")

    # INSPECTION MODE
    if args.inspect:
        print("\n" + "="*80)
        if args.scibert:
            print("FOIA CLUSTERS (SciBERT) - INSPECT AND DECIDE WHICH TO DROP")
        else:
            print("FOIA CLUSTERS (TF-IDF) - INSPECT AND DECIDE WHICH TO DROP")
        print("="*80)
        for c in sorted(merged['cluster'].unique()):
            sub = merged[merged['cluster'] == c]
            print(f"\nCLUSTER {c}: {len(sub)} FOIAs")
            print(sub[['athr_id']].to_string(index=False))

            if args.scibert:
                # For SciBERT, extract top terms from raw text
                cluster_texts = sub['processed_text'].tolist()
                top_terms = get_top_terms_from_text(cluster_texts, args.n_terms)
                if top_terms:
                    print("  Top terms (by frequency):", ", ".join(top_terms))
            elif feature_names is not None and tfidf_foia is not None:
                # For TF-IDF, use TF-IDF centroid
                cluster_indices = np.where(merged['cluster'] == c)[0]
                top_terms = get_top_terms(cluster_indices, tfidf_foia, feature_names, args.n_terms)
                if top_terms:
                    print("  Top terms (by TF-IDF):", ", ".join([f"{term}" for term, _ in top_terms]))

        print("\n" + "="*80)
        print("After reviewing, run:")
        scibert_flag = " --scibert" if args.scibert else ""
        print(f"  python 0b_validate_foia_clusters.py --tag {args.tag}{scibert_flag} "
              f"--drop-clusters '...'")
        print("="*80)
        return

    # FILTERING MODE
    if not args.drop_clusters:
        print("\nNo clusters to drop. Use --drop-clusters 'ID1,ID2' to filter.")
        return

    drop_cluster_list = [int(c.strip()) for c in args.drop_clusters.split(',')]
    print(f"\nDropping clusters: {drop_cluster_list}")

    # Identify FOIAs to drop
    drop_mask = merged['cluster'].isin(drop_cluster_list)
    n_drop = drop_mask.sum()
    n_keep = (~drop_mask).sum()

    print(f"  FOIAs to drop:  {n_drop}")
    print(f"  FOIAs to keep:  {n_keep}")

    # Create audit trail
    dropped_foias = merged.loc[drop_mask].copy()
    dropped_foias['reason'] = 'non_life_science_cluster'
    dropped_foias = dropped_foias[['athr_id', 'cluster', 'reason']]

    # Filter text file
    keep_athr_ids = merged.loc[~drop_mask, 'athr_id'].values
    validated_text = foia_text[foia_text['athr_id'].isin(keep_athr_ids)].reset_index(drop=True)

    # Save outputs
    print(f"\nSaving validated FOIAs -> {output_text_path}")
    validated_text.to_csv(output_text_path, index=False)

    print(f"Saving audit -> {output_audit_path}")
    dropped_foias.to_csv(output_audit_path, index=False)

    print("\nNext steps:")
    print(f"  1. Update your vectorization to use the validated FOIA text:")
    print(f"     - Edit 0_get_foia_text.py output path or use a new tag")
    print(f"  2. Re-run vectorization with validated FOIAs:")
    print(f"     python 1_vectorize.py --tag restricted")
    print(f"  3. Continue with imputation pipeline")


if __name__ == "__main__":
    main()
