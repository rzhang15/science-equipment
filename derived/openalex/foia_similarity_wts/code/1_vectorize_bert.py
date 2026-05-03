"""
Dense BERT/SciBERT/SPECTER embeddings for the FOIA validation pipeline.

For LOOV validation we only need the 188 FOIA authors (FOIA-vs-FOIA similarity).
A `--universe` flag adds embeddings for the full ~2.66M-author universe, which
is needed for the production imputation step but not for validation.

NOTE on text quality: the input parquet contains Porter-stemmed text. Subword
tokenizers expect real words, so embedding quality is degraded. To run on
un-stemmed text, modify cluster_fields/code/0_combine_data.py to also save
`full_text_lifetime` and point this script at that column.
"""
import argparse
import os
import time
import numpy as np
import pandas as pd
import polars as pl
import torch
from sentence_transformers import SentenceTransformer

DEFAULT_MODEL = "allenai-specter"  # other options:
# "pritamdeka/S-Scibert-snli-multinli-stsb"
# "allenai/scibert_scivocab_uncased"

UNIVERSE_PARQUET = "../external/us_appended_text/cleaned_static_author_text_pre_us.parquet"
FOIA_CSV = "../output/foia_author_text_final.csv"
OUT_DIR = "../output/"

ROW_BATCH = 4096
ENCODE_BATCH = 256
CHUNK_WORDS = 200
MAX_CHUNKS_PER_AUTHOR = 20
TEXT_COL = "processed_text"


def chunk_text(text: str, chunk_words: int, max_chunks: int) -> list[str]:
    if not text:
        return [""]
    words = text.split()
    chunks = [
        " ".join(words[i:i + chunk_words])
        for i in range(0, len(words), chunk_words)
    ]
    return chunks[:max_chunks] if chunks else [""]


def encode_authors(model, ids: list[str], texts: list[str]) -> np.ndarray:
    flat_chunks: list[str] = []
    boundaries: list[tuple[int, int]] = []
    for t in texts:
        chunks = chunk_text(t or "", CHUNK_WORDS, MAX_CHUNKS_PER_AUTHOR)
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

    out = np.zeros((len(boundaries), chunk_embs.shape[1]), dtype=np.float32)
    for i, (s, e) in enumerate(boundaries):
        out[i] = chunk_embs[s:e].mean(axis=0)
    # re-normalize after mean pooling so cosine == dot
    norms = np.linalg.norm(out, axis=1, keepdims=True)
    norms[norms == 0] = 1.0
    out = out / norms
    return out


def embed_foia(model, out_emb: str, out_ids: str) -> None:
    print("Loading FOIA texts...")
    df = pd.read_csv(FOIA_CSV)
    df[TEXT_COL] = df[TEXT_COL].fillna("").astype(str)
    print(f"FOIA authors: {len(df)}")

    embs = encode_authors(model, df["athr_id"].tolist(), df[TEXT_COL].tolist())
    print(f"FOIA embedding shape: {embs.shape}")

    np.save(out_emb, embs)
    df[["athr_id"]].to_csv(out_ids, index=False)
    print(f"Saved {out_emb} and {out_ids}")


def embed_universe(model, out_emb: str, out_ids: str, limit: int | None) -> None:
    lf = pl.scan_parquet(UNIVERSE_PARQUET).select(["athr_id", TEXT_COL])
    n_total = lf.select(pl.len()).collect().item()
    if limit:
        n_total = min(n_total, limit)
    print(f"Universe authors to embed: {n_total:,}")

    dim = model.get_sentence_embedding_dimension()
    embeddings = np.zeros((n_total, dim), dtype=np.float32)
    author_ids: list[str] = []

    t0 = time.time()
    written = 0
    offset = 0
    while offset < n_total:
        take = min(ROW_BATCH, n_total - offset)
        batch_df = lf.slice(offset, take).collect(streaming=True)
        ids = batch_df["athr_id"].to_list()
        texts = batch_df[TEXT_COL].fill_null("").to_list()

        embs = encode_authors(model, ids, texts)
        embeddings[written:written + len(ids)] = embs
        author_ids.extend(ids)
        written += len(ids)
        offset += take

        elapsed = time.time() - t0
        rate = written / elapsed if elapsed else 0.0
        eta = (n_total - written) / rate if rate else float("inf")
        print(f"  {written:,}/{n_total:,}  ({rate:.1f}/s, ETA {eta/3600:.2f}h)", flush=True)

    np.save(out_emb, embeddings)
    pl.DataFrame({"athr_id": author_ids}).write_parquet(out_ids)
    print(f"Saved {out_emb} shape={embeddings.shape} and {out_ids}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default=DEFAULT_MODEL,
                        help="HF SentenceTransformer model name.")
    parser.add_argument("--universe", action="store_true",
                        help="Also embed the full universe (slow; needs GPU).")
    parser.add_argument("--limit", type=int, default=None,
                        help="Cap universe rows (smoke test).")
    args = parser.parse_args()

    device = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"Device: {device}")
    if args.universe and device == "cpu":
        print("WARNING: --universe on CPU will be extremely slow.")

    print(f"Loading model: {args.model}")
    model = SentenceTransformer(args.model, device=device)
    if device == "cuda":
        model = model.half()

    model_tag = args.model.replace("/", "_")
    foia_emb = os.path.join(OUT_DIR, f"bert_foia_{model_tag}.npy")
    foia_ids = os.path.join(OUT_DIR, f"bert_foia_ids_{model_tag}.csv")
    embed_foia(model, foia_emb, foia_ids)

    if args.universe:
        univ_emb = os.path.join(OUT_DIR, f"bert_universe_{model_tag}.npy")
        univ_ids = os.path.join(OUT_DIR, f"bert_universe_ids_{model_tag}.parquet")
        embed_universe(model, univ_emb, univ_ids, args.limit)


if __name__ == "__main__":
    main()
