#!/usr/bin/env python
"""
3_embed_specter.py
------------------
Encode the pre-merger paper texts (paper_text.parquet) with SPECTER-2
and save ../output/embeddings.npy   (shape: [n_papers, 768])

• Works with sentence-transformers 2.6 (uses models.Transformer)
• Requires PyTorch CUDA build if you want GPU speed
"""

from pathlib import Path
import numpy as np
import pandas as pd
import torch
from sentence_transformers import SentenceTransformer, models

# -------------------------------------------------------------------
# 0.  Constants & paths
# -------------------------------------------------------------------
MODEL_NAME = "allenai/specter2_base"   # SPECTER-2 checkpoint
BATCH      = 128                       # lower if memory is tight

BASE = Path(__file__).resolve().parent.parent     # …/cluster_fields
OUT  = BASE / "output"
TEXT = OUT / "paper_text.parquet"
EMB  = OUT / "embeddings.npy"

device = "cuda" if torch.cuda.is_available() else "cpu"

# DEBUG block --------------------------------------------------------
print("=== DEBUG ==========================================")
print("Node           :", Path('/proc/sys/kernel/hostname').read_text().strip())
print("Torch version  :", torch.__version__)
print("CUDA available :", torch.cuda.is_available(),
      "device count:", torch.cuda.device_count())
print("Using device   :", device)
print("====================================================\n")

# -------------------------------------------------------------------
# 1.  Load paper text
# -------------------------------------------------------------------
df = pd.read_parquet(TEXT)
sentences = df["text"].tolist()
print("Sentences to encode :", len(sentences))

# -------------------------------------------------------------------
# 2.  Build S-T model (Transformer + mean pooling)
# -------------------------------------------------------------------
print("Loading SPECTER-2 model …")
word_emb = models.Transformer(
            MODEL_NAME,
            max_seq_length=512)        # ST 2.6: no trust_remote_code kwarg

pool     = models.Pooling(
            word_emb.get_word_embedding_dimension(),
            pooling_mode_mean_tokens=True)

model = SentenceTransformer(
            modules=[word_emb, pool],
            device=device)

print("Embedding dimension :", model.get_sentence_embedding_dimension())
print("Starting encoding …")

# -------------------------------------------------------------------
# 3.  Encode
# -------------------------------------------------------------------
embeddings = model.encode(
                sentences,
                batch_size=BATCH,
                show_progress_bar=True,
                convert_to_numpy=True,
                normalize_embeddings=True)

print("\nFinished.  Embedding matrix shape:", embeddings.shape)
np.save(EMB, embeddings)
print("Saved →", EMB.resolve())
