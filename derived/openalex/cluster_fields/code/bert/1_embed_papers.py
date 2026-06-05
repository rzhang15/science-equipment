"""
SPECTER embeddings, one per paper.

Streams the parquet so memory stays bounded. Each paper's text is truncated
inside the SentenceTransformer tokenizer (max_seq_length); papers in OpenAlex
are title + abstract + a few MeSH terms, so one forward pass per paper is fine.

Output:
  ../../output/bert/paper_embeddings.npy    (float16, shape [N, D])
  ../../output/bert/papers_aligned.parquet  (id column in the same order)
"""
import argparse
import os
import time
import numpy as np
import polars as pl
import torch
from sentence_transformers import SentenceTransformer

MODEL_NAME = "allenai-specter"  # matches existing pipelines in foia_similarity_wts / us_cluster_fields
INPUT_PARQUET = "../../output/bert/papers_text.parquet"
OUT_DIR = "../../output/bert"
OUT_EMB = f"{OUT_DIR}/paper_embeddings.npy"
OUT_IDS = f"{OUT_DIR}/papers_aligned.parquet"

ROW_BATCH = 16384          # papers per parquet slice
ENCODE_BATCH = 256         # papers per GPU forward pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, default=None, help="Smoke-test cap.")
    parser.add_argument("--model", type=str, default=MODEL_NAME)
    args = parser.parse_args()

    device = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"Device: {device}")
    if device == "cpu":
        print("WARNING: CPU will be unusably slow at corpus scale. Use --limit for a smoke test.")

    print(f"Loading model: {args.model}")
    model = SentenceTransformer(args.model, device=device)
    if device == "cuda":
        model = model.half()
    dim = model.get_sentence_embedding_dimension()
    print(f"Embedding dim: {dim}")

    lf = pl.scan_parquet(INPUT_PARQUET).select(["id", "paper_text"])
    n_total = lf.select(pl.len()).collect().item()
    if args.limit:
        n_total = min(n_total, args.limit)
    print(f"Papers to embed: {n_total:,}")

    os.makedirs(OUT_DIR, exist_ok=True)
    # Pre-allocate as float16 to halve disk and RAM.
    embeddings = np.zeros((n_total, dim), dtype=np.float16)
    paper_ids: list[str] = []

    t0 = time.time()
    written = 0
    offset = 0
    while offset < n_total:
        take = min(ROW_BATCH, n_total - offset)
        batch_df = lf.slice(offset, take).collect(streaming=True)
        ids = batch_df["id"].to_list()
        texts = batch_df["paper_text"].fill_null("").to_list()

        embs = model.encode(
            texts,
            batch_size=ENCODE_BATCH,
            convert_to_numpy=True,
            normalize_embeddings=True,
            show_progress_bar=False,
        ).astype(np.float16)

        embeddings[written:written + take] = embs
        paper_ids.extend(ids)
        written += take
        offset += take

        elapsed = time.time() - t0
        rate = written / elapsed if elapsed else 0
        eta = (n_total - written) / rate if rate else float("inf")
        print(f"  {written:,}/{n_total:,} ({rate:.0f}/s, ETA {eta/3600:.2f}h)", flush=True)

    print("Saving embeddings...")
    np.save(OUT_EMB, embeddings)
    pl.DataFrame({"id": paper_ids}).write_parquet(OUT_IDS)
    print(f"Done. {OUT_EMB}  shape={embeddings.shape}  dtype={embeddings.dtype}")


if __name__ == "__main__":
    main()
