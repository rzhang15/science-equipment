import torch, sentence_transformers as st, sys, transformers
print("Python :", sys.version.split()[0])
print("Torch   :", torch.__version__, "CUDA:", torch.cuda.is_available())
print("HF ok?  ", hasattr(transformers, "PreTrainedModel"))
print("Dim     :", st.SentenceTransformer("allenai/scibert_scivocab_uncased")
                 .get_sentence_embedding_dimension())
