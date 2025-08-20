# 2_build_text_field.py
from nltk.corpus import stopwords
import re, string, nltk

# (1) initialize your NLTK stopwords & extended list
nltk.download("stopwords", quiet=True)
nltk.download("punkt", quiet=True)

nltk_stopwords = set(stopwords.words("english"))
additional_stopwords = {
    "university", "department", "center", "centre", "school",
    "institute", "college", "hospital", "medicine", "medical",
    "research", "science", "sciences", "google", "scholar",
    "pubmed", "scopus", "usasearch", "caspubmedweb"
}
custom_stopwords = nltk_stopwords.union(additional_stopwords)

# (2) update your clean/token functions to drop these tokens
def tokenize(text):
    text = str(text).lower()
    text = re.sub(r"[^\w\s]", " ", text)   # remove punctuation
    text = re.sub(r"\s+", " ", text).strip()
    tokens = text.split()
    # remove any word in custom_stopwords
    tokens = [t for t in tokens if t not in custom_stopwords]
    return tokens

def clean(txt):
    txt = str(txt).lower()
    txt = re.sub(r"[^\w\s]", " ", txt)
    txt = re.sub(r"\s+", " ", txt).strip()
    return txt

# (3) apply tokenize() when building your 'text' column
titles = pub[["id", "title"]].drop_duplicates()
titles["title_clean"] = titles["title"].map(clean)
titles["title_tok"]   = titles["title_clean"].map(tokenize)

ab["abstract_clean"]   = ab["abstract"].map(clean)
ab["abstract_tok"]     = ab["abstract_clean"].map(tokenize)

mesh_text = (mesh.groupby("id")["gen_mesh"]
                 .apply(lambda s: " ".join(s))
                 .reset_index())
mesh_text["mesh_tok"] = mesh_text["gen_mesh"].map(lambda x: x.split("_"))

# (4) concatenate token lists (already cleaned out unwanted words)
text = (
    titles[["id","title_tok"]]
    .merge(ab[["id","abstract_tok"]], on="id", how="left")
    .merge(mesh_text[["id","mesh_tok"]], on="id", how="left")
)
text["text"] = text[["title_tok","abstract_tok","mesh_tok"]].apply(
    lambda row: " ".join([w for tok in row for w in (tok or [])]),
    axis=1
)
text.to_parquet(OUT / "paper_text.parquet", index=False)
