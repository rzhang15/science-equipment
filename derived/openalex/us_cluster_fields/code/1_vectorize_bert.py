"""
Generate dense BERT/SciBERT-style embeddings for each US author's lifetime text.

NOTE on text quality: the input parquet contains Porter-stemmed text
(`processed_text`). Transformer tokenizers expect real words, so embedding
quality will be degraded relative to running on un-stemmed text. To get the
best results, regenerate cleaned_static_author_text_pre_us.parquet from
0_combine_data.py without the stemming step and point this script at the
un-stemmed column.

Streams the parquet in row batches so memory stays bounded even with 2.66M
authors. Long author corpora are split into ~CHUNK_WORDS-word chunks; chunk
embeddings are mean-pooled per author.
"""
import argparse
import os
import time
import numpy as np
import polars as pl
import torch
from sentence_transformers import SentenceTransformer

MODEL_NAME = "allenai-specter"  # sci-tuned sentence model. Alternatives:
# "pritamdeka/S-Scibert-snli-multinli-stsb"  # SciBERT fine-tuned for similarity
# "allenai/scibert_scivocab_uncased"         # raw SciBERT (worse for similarity)

INPUT_PARQUET = "../output/cleaned_static_author_text_pre_us.parquet"
OUT_EMB = "../output/scibert_embeddings.npy"
OUT_IDS = "../output/author_ids_aligned.parquet"

ROW_BATCH = 4096          # authors per parquet read batch
ENCODE_BATCH = 256        # chunks per GPU forward pass
CHUNK_WORDS = 200         # ~ fits in 512 BERT tokens after subword expansion
MAX_CHUNKS_PER_AUTHOR = 20  # cap per-author work; 20 * 200 = 4000 words covered


def chunk_text(text: str, chunk_words: int, max_chunks: int) -> list[str]:
    if not text:
        return [""]
    words = text.split()
    chunks = [
        " ".join(words[i:i + chunk_words])
        for i in range(0, len(words), chunk_words)
    ]
    return chunks[:max_chunks] if chunks else [""]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, default=None,
                        help="Process only first N authors (for smoke tests).")
    args = parser.parse_args()

    device = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"Device: {device}")
    if device == "cpu":
        print("WARNING: running on CPU will be extremely slow for 2.66M authors.")

    print(f"Loading model: {MODEL_NAME}")
    model = SentenceTransformer(MODEL_NAME, device=device)
    if device == "cuda":
        model = model.half()  # fp16 for ~2x throughput on A100/H100/H200
    dim = model.get_sentence_embedding_dimension()
    print(f"Embedding dim: {dim}")

    lf = pl.scan_parquet(INPUT_PARQUET).select(["athr_id", "processed_text"])
    n_total = lf.select(pl.len()).collect().item()
    if args.limit:
        n_total = min(n_total, args.limit)
    print(f"Authors to embed: {n_total:,}")

    embeddings = np.zeros((n_total, dim), dtype=np.float32)
    author_ids: list[str] = []

    t0 = time.time()
    written = 0
    offset = 0

    while offset < n_total:
        take = min(ROW_BATCH, n_total - offset)
        batch_df = (
            lf.slice(offset, take)
              .collect(streaming=True)
        )
        ids = batch_df["athr_id"].to_list()
        texts = batch_df["processed_text"].fill_null("").to_list()

        # Build flat chunk list with author boundaries.
        flat_chunks: list[str] = []
        boundaries: list[tuple[int, int]] = []  # (start, end) per author in flat_chunks
        for t in texts:
            chunks = chunk_text(t, CHUNK_WORDS, MAX_CHUNKS_PER_AUTHOR)
            start = len(flat_chunks)
            flat_chunks.extend(chunks)
            boundaries.append((start, len(flat_chunks)))

        chunk_embs = model.encode(
            flat_chunks,
            batch_size=ENCODE_BATCH,
            convert_to_numpy=True,
            normalize_embeddings=True,
            show_progress_bar=False,
        ).astype(np.float32)

        for (start, end) in boundaries:
            embeddings[written] = chunk_embs[start:end].mean(axis=0)
            written += 1
        author_ids.extend(ids)

        offset += take
        elapsed = time.time() - t0
        rate = written / elapsed if elapsed else 0
        eta = (n_total - written) / rate if rate else float("inf")
        print(f"  {written:,}/{n_total:,} authors  "
              f"({rate:.1f}/s, ETA {eta/3600:.2f}h)", flush=True)

    print("Saving embeddings...")
    np.save(OUT_EMB, embeddings)
    pl.DataFrame({"athr_id": author_ids}).write_parquet(OUT_IDS)
    print(f"Done. {OUT_EMB}  shape={embeddings.shape}")


if __name__ == "__main__":
    main()
