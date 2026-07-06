"""
Cluster FOIAs using SciBERT semantic embeddings + linguistic signals.

Instead of TF-IDF word counts, uses a pretrained SciBERT model to understand
scientific semantics. Combines embeddings with signals like text length,
vocabulary diversity to improve cluster coherence.

Usage:
  python cluster_foias_scibert.py --tag restricted --n-clusters 15

Output:
  output/foia_clusters_K15_scibert_{tag}.csv
  output/foia_scibert_embeddings_{tag}.npy
"""
import argparse
import os
import numpy as np
import pandas as pd
from sklearn.cluster import KMeans
from sklearn.preprocessing import StandardScaler

try:
    from sentence_transformers import SentenceTransformer
except ImportError:
    raise ImportError("Install: pip install sentence-transformers")

OUT_DIR = "../output/"


def compute_linguistic_signals(texts):
    """Extract text-based features: length, word count, vocabulary diversity."""
    features = []
    for text in texts:
        words = text.split()
        vocab = len(set(words))
        features.append({
            'text_chars': len(text),
            'word_count': len(words),
            'vocab_diversity': vocab / max(len(words), 1),  # vocab / total_words
        })
    return pd.DataFrame(features)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", default="restricted",
                    help="Tag for outputs (default 'restricted').")
    ap.add_argument("--n-clusters", type=int, default=15,
                    help="Number of clusters (default 15).")
    ap.add_argument("--min-chars", type=int, default=250,
                    help="Minimum text length in chars (default 250).")
    ap.add_argument("--model", default="allenai/scibert_scivocab_uncased",
                    help="SciBERT model name.")
    ap.add_argument("--batch-size", type=int, default=32,
                    help="Embedding batch size (default 32).")
    ap.add_argument("--signal-weight", type=float, default=0.1,
                    help="Weight of linguistic signals vs embeddings (0-1, default 0.1).")
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()

    tag = args.tag
    if tag and not tag.startswith("_"):
        tag = "_" + tag

    foia_text_path = f"{OUT_DIR}foia_author_text_final.csv"
    output_clusters_path = f"{OUT_DIR}foia_clusters_K{args.n_clusters}_scibert{tag}.csv"
    output_embeddings_path = f"{OUT_DIR}foia_scibert_embeddings{tag}.npy"

    if not os.path.exists(foia_text_path):
        raise SystemExit(f"Missing: {foia_text_path}")

    print("Loading FOIA text...")
    df_foia = pd.read_csv(foia_text_path)
    print(f"  Loaded {len(df_foia)} FOIAs")

    # Filter by minimum text length
    text_lens = df_foia["processed_text"].fillna("").str.len()
    keep_mask = text_lens >= args.min_chars
    n_drop = (~keep_mask).sum()
    if n_drop > 0:
        print(f"  Dropping {n_drop} FOIAs with <{args.min_chars} chars")
        dropped = df_foia.loc[~keep_mask, 'athr_id'].tolist()
        print(f"    {dropped}")
        df_foia = df_foia.loc[keep_mask].reset_index(drop=True)

    texts = df_foia["processed_text"].tolist()
    print(f"  Final pool: {len(texts)} FOIAs")

    # Load SciBERT and embed
    print(f"Loading {args.model}...")
    model = SentenceTransformer(args.model)

    print(f"Embedding {len(texts)} FOIA texts (batch_size={args.batch_size})...")
    embeddings = model.encode(texts, batch_size=args.batch_size, show_progress_bar=True)
    print(f"  Embedding shape: {embeddings.shape}")

    # Compute linguistic signals
    print("Computing linguistic signals...")
    signals = compute_linguistic_signals(texts)
    print(f"  Signals:\n{signals.describe()}")

    # Combine embeddings with signals (scale signals to embedding scale)
    signals_scaled = StandardScaler().fit_transform(signals.values)
    # Scale signals to match embedding magnitude
    signals_scaled = signals_scaled * (args.signal_weight * np.linalg.norm(embeddings) / np.linalg.norm(signals_scaled))
    # Concatenate: embeddings (768d) + scaled signals (3d)
    combined = np.hstack([embeddings, signals_scaled])
    print(f"  Combined features shape: {combined.shape}")
    print(f"  (embeddings: 768d, signals: 3d, signal_weight={args.signal_weight})")

    # Cluster
    print(f"Clustering into K={args.n_clusters}...")
    kmeans = KMeans(n_clusters=args.n_clusters, random_state=args.seed, n_init=10)
    clusters = kmeans.fit_predict(combined)

    # Output
    df_clusters = df_foia[['athr_id']].copy()
    df_clusters['cluster'] = clusters

    print(f"Cluster distribution:")
    print(df_clusters['cluster'].value_counts().sort_index())

    df_clusters.to_csv(output_clusters_path, index=False)
    print(f"Saved: {output_clusters_path}")

    np.save(output_embeddings_path, embeddings)
    print(f"Saved embeddings: {output_embeddings_path}")


if __name__ == "__main__":
    main()
