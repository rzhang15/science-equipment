import pandas as pd
import numpy as np
import re
import html
import torch
from transformers import AutoTokenizer, T5EncoderModel  # not used in classification now
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity
from rapidfuzz.fuzz import partial_ratio, token_sort_ratio
import spacy
from spacy.matcher import Matcher
import nltk
from nltk.stem import WordNetLemmatizer

# Download required NLTK data (if not already installed)
nltk.download('wordnet')
nltk.download('omw-1.4')

# ==============================================================================
# (Optional) SciFive Model Loading -- Not used for classification now
# ==============================================================================
# device = torch.device("mps" if torch.backends.mps.is_available() else "cpu")
# print("Using device:", device)
# MODEL_NAME = "razent/SciFive-base-Pubmed_PMC"
# tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)
# model = T5EncoderModel.from_pretrained(MODEL_NAME)
# model.to(device)
# model.eval()

# ==============================================================================
# Load spaCy model and set up Matcher for unit extraction.
# ==============================================================================
nlp = spacy.load("en_core_web_sm")
matcher = Matcher(nlp.vocab)
# Pattern to capture unit-like expressions (e.g., "500/box")
unit_pattern = [
    {"LIKE_NUM": True},
    {"TEXT": "/", "OP": "?"},
    {"IS_ALPHA": True, "LENGTH": {"<=": 10}}
]
matcher.add("UNIT_PATTERN", [unit_pattern])

# ==============================================================================
# Helper Function to Normalize Category
# ==============================================================================
def normalize_category(cat_str: str) -> str:
    lemmatizer = WordNetLemmatizer()
    words = cat_str.lower().split()
    normalized_words = [lemmatizer.lemmatize(word) for word in words]
    return " ".join(normalized_words)

# ==============================================================================
# Utility Function: Remove Long Hash Content
# ==============================================================================
def remove_long_hash_content(text: str, min_length: int = 10) -> str:
    if text.count('#') >= 2:
        first = text.find('#')
        last = text.rfind('#')
        if last - first - 1 >= min_length:
            return (text[:first] + text[last+1:]).strip()
    return text.replace("#", "").strip()

# ==============================================================================
# Unit Extraction using spaCy
# ==============================================================================
def extract_units(text: str) -> (str, str):
    doc = nlp(text)
    matches = matcher(doc)
    units = []
    spans = []
    for match_id, start, end in matches:
        span = doc[start:end]
        if "/" in span.text:
            units.append(span.text)
            spans.append(span)
    spans = sorted(spans, key=lambda span: span.start_char, reverse=True)
    cleaned = text
    for span in spans:
        cleaned = cleaned[:span.start_char] + cleaned[span.end_char:]
    cleaned = re.sub(r"\s+", " ", cleaned).strip()
    extracted_units = ", ".join(units)
    return cleaned, extracted_units

# ==============================================================================
# spaCy-Based Product Description Cleaning
# ==============================================================================
def spacy_clean_product_description(text: str) -> str:
    """
    Cleans a product description using spaCy.

    - Skips catalog markers ("cat", "cat#") and, if they occur, also skips the following token if it appears SKU-like.
    - Skips tokens that contain "/" (assumed to be unit expressions).
    - Skips very short tokens (length < 7) that are mostly numeric.
    - Preserves descriptive words and chemical names (even if they include hyphens or start with digits).

    Examples:
      Input: "Cat# C18384-15 / Thermogrid PCR plate, 384 well"
      Output: "thermogrid pcr plate, 384 well"

      Input: "2-Amino-5-methoxybenzoic acid"
      Output: "2-amino-5-methoxybenzoic acid"
    """
    doc = nlp(text)
    tokens = []
    skip_next = False
    for i, token in enumerate(doc):
        t = token.text.strip()
        if not t:
            continue
        if skip_next:
            if re.fullmatch(r"[A-Za-z]{0,2}\d+(-\d+)?", t):
                skip_next = False
                continue
            skip_next = False
        if t.lower() in {"cat", "cat#"}:
            skip_next = True
            continue
        if "/" in t:
            continue
        if len(t) < 7:
            digit_count = sum(ch.isdigit() for ch in t)
            if len(t) > 0 and (digit_count / len(t)) > 0.6:
                continue
        tokens.append(t.lower())
    return " ".join(tokens)

# ==============================================================================
# Parse Complex Description Function (SKU Extraction Updated)
# ==============================================================================
def parse_complex_description(full_text: str) -> (str, str):
    """
    Extracts a candidate SKU and produces a cleaned version of the product description.

    Uses explicit patterns (e.g. "cat#" etc.) and generic patterns.
    Does not enforce a fixed-length rule but uses heuristics to guess SKU-like tokens.
    """
    if not isinstance(full_text, str):
        full_text = str(full_text)
    text = html.unescape(full_text)
    text = remove_long_hash_content(text, min_length=10)
    text = text.lower()

    explicit_patterns = [
        r"(?:product\s*catalog|cat(?:alog)?#?)\s*[:\-]?\s*([a-z0-9\-_\.]{5,})"
    ]
    extracted_sku = ""
    for pattern in explicit_patterns:
        m = re.search(pattern, text)
        if m:
            extracted_sku = m.group(1)
            break
    if extracted_sku and not re.search(r"\d", extracted_sku):
        extracted_sku = ""
    if not extracted_sku:
        sku_pattern = re.compile(r"\b(?=.*\d)[a-z0-9\-_\.]{5,}\b")
        m = sku_pattern.search(text)
        if m:
            candidate = m.group(0)
            if '-' in candidate:
                extracted_sku = candidate
            else:
                extracted_sku = ""
    text = re.sub(r"[^\w\s,\.\-_]", " ", text)
    text = re.sub(r"\s+", " ", text).strip()
    tokens = text.split()
    if len(tokens) > 1:
        tokens = [token for token in tokens if token != "shipping"]
    cleaned_text = " ".join(tokens)

    return extracted_sku, cleaned_text

# ==============================================================================
# UT Dallas Data Processing Functions
# ==============================================================================
def clean_text(text: str) -> str:
    if not isinstance(text, str):
        text = str(text)
    text = html.unescape(text)
    text = remove_long_hash_content(text, min_length=10)
    text = text.lower()
    text = re.sub(r"[^\w\s,\.\-_]", " ", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text

def load_utd_data(file_path: str, product_col: str, sku_col: str, category_col: str) -> pd.DataFrame:
    """
    Loads the UT Dallas data, applies cleaning & category replacement,
    normalizes the category, and cleans the product description using spacy_clean_product_description.
    """
    df = pd.read_excel(file_path)
    if "category" in df.columns:
        def replace_cat(row):
            current = str(row[category_col]).strip()
            alt = str(row["category"]).strip()
            if alt and alt.lower() != "nan" and current.lower() not in ["primary antibody", "secondary antibody"]:
                return alt
            return current
        df[category_col] = df.apply(replace_cat, axis=1)
    df[category_col] = df[category_col].apply(normalize_category)
    df = df[[product_col, sku_col, category_col]].copy()
    df.dropna(subset=[category_col], inplace=True)
    df.fillna("", inplace=True)
    df["cleaned_product_desc"] = df[product_col].apply(spacy_clean_product_description)
    _, extracted_units = zip(*df[product_col].apply(extract_units))
    df["extracted_units"] = extracted_units
    df["cleaned_sku"] = df[sku_col].astype(str).str.strip()
    df["combined_text"] = df["cleaned_product_desc"] + " " + df["cleaned_sku"]
    return df

def merge_utd_data(combined_path: str, raw_path: str, sku_var: str, supplier_id_var: str) -> pd.DataFrame:
    combined_df = pd.read_excel(combined_path)
    raw_df = pd.read_excel(raw_path)
    raw_df.columns = raw_df.columns.str.replace(" ", "", regex=True).str.lower()
    raw_df.columns = raw_df.columns.str.replace("/", "", regex=True).str.replace("#", "", regex=True)
    rename_mapping = {
        "purchaseorderidentifier": "purchase_id",
        "purchasedate": "purchase_date",
        "suppliernumber": "supplier_id",
        "productdescription": "product_desc",
        "projectid": "project_id",
        "skucatalog": "sku",
        "unitprice": "price",
        "quantity": "qty"
    }
    raw_df.rename(columns=rename_mapping, inplace=True)
    combined_df.columns = combined_df.columns.str.lower()
    print("Raw UT Dallas columns after renaming:", raw_df.columns.tolist())
    print("Combined UT Dallas columns:", combined_df.columns.tolist())
    if sku_var not in raw_df.columns or supplier_id_var not in raw_df.columns:
        raise KeyError(f"Raw UT Dallas file does not contain required columns: {sku_var} and {supplier_id_var}")
    merged_df = raw_df.merge(combined_df, on=[sku_var, supplier_id_var], how="left", suffixes=("", "_combined"))
    return merged_df

def aggregate_utd_data(utd_df: pd.DataFrame, group_col: str, sku_col: str, supplier_col: str) -> pd.DataFrame:
    def agg_func(x):
        return " ".join(x)
    def unique_concat(series):
        uniques = series.dropna().unique()
        return " ".join([str(u) for u in uniques if u])
    agg_df = utd_df.groupby(group_col).agg({
        "combined_text": agg_func,
        sku_col: lambda s: unique_concat(s),
        supplier_col: lambda s: unique_concat(s)
    }).reset_index()
    agg_df.rename(columns={
        "combined_text": "agg_text",
        sku_col: "agg_skus",
        supplier_col: "agg_supplier"
    }, inplace=True)
    return agg_df

# ==============================================================================
# TF-IDF Functions for Aggregated Data
# ==============================================================================
def build_tfidf_model(agg_df: pd.DataFrame, text_col: str, group_col: str, ngram_range=(1,3)):
    categories = agg_df[group_col].values
    documents = agg_df[text_col].tolist()
    vectorizer = TfidfVectorizer(ngram_range=ngram_range)
    X = vectorizer.fit_transform(documents)
    return vectorizer, X, categories

# ==============================================================================
# Helper Function to Check if a Text is SKU-Like
# ==============================================================================
def is_sku_like(text: str) -> bool:
    tokens = text.split()
    if len(tokens) < 3:
        return True
    numeric_tokens = sum(1 for t in tokens if re.fullmatch(r"\d+", t))
    if numeric_tokens / len(tokens) > 0.8:
        return True
    return False

# ==============================================================================
# Classification Function (Multi-Step Approach using TF-IDF)
# ==============================================================================
def classify_new_items_tfidf_sku(
    df_new: pd.DataFrame,
    product_col: str,
    supplier_col: str,
    vectorizer,
    X_agg,
    categories,
    sku_map_agg: dict,
    utd_transactions_df: pd.DataFrame,   # UT Dallas transaction-level data for fallback fuzzy matching
    tfidf_threshold: float = 0.25,
    token_overlap_threshold: float = 0.6,
    supplier_fuzzy_threshold: int = 95,
    final_fuzzy_threshold: int = 95,
    sku_fuzzy_threshold: int = 90
):
    """
    Classify new UT Austin items using a multi-step approach.

    Primary steps (using aggregated UT Dallas data):
      - TF-IDF matching: if cosine similarity >= tfidf_threshold, mark as "TF-IDF".
      - Token Overlap matching: if token overlap >= token_overlap_threshold, mark as "Token Overlap".
    Fallback steps:
      A. SKU Fuzzy Matching: using UT Dallas transaction-level data.
      B. Final Fuzzy Matching: compare cleaned descriptions with UT Dallas transaction-level descriptions.

    Returns the modified UT Austin dataframe with columns:
       "parsed_sku", "cleaned_product_desc", "extracted_units",
       "predicted_category", and "classification_stage",
    and the TF-IDF similarity matrix.
    """
    parsed_skus = []
    cleaned_descs = []
    extracted_units_list = []
    for idx, row in df_new.iterrows():
        raw_text = str(row[product_col])
        sku_val, desc_val = parse_complex_description(raw_text)
        parsed_skus.append(sku_val)
        cleaned_descs.append(desc_val)
        _, extracted_units = extract_units(raw_text)
        extracted_units_list.append(extracted_units)
    df_new["parsed_sku"] = parsed_skus
    df_new["cleaned_product_desc"] = cleaned_descs
    df_new["extracted_units"] = extracted_units_list

    new_docs = df_new["cleaned_product_desc"].str.lower().tolist()
    X_new_tfidf = vectorizer.transform(new_docs)
    tfidf_sim_matrix = cosine_similarity(X_new_tfidf, X_agg)

    # Compute best TF-IDF similarity per document.
    best_tfidf_scores = np.max(tfidf_sim_matrix, axis=1)
    new_token_sets = [set(doc.split()) for doc in new_docs]
    agg_token_sets = [set(" ".join(doc).split()) for doc in vectorizer.inverse_transform(X_agg)]

    predicted_categories = []
    classification_stages = []
    for i in range(tfidf_sim_matrix.shape[0]):
        tfidf_scores = tfidf_sim_matrix[i]
        best_tfidf = tfidf_scores.max()
        best_cat_tfidf = categories[tfidf_scores.argmax()]
        if best_tfidf >= tfidf_threshold:
            predicted_categories.append(best_cat_tfidf)
            classification_stages.append("TF-IDF")
        else:
            best_overlap = 0.0
            best_overlap_cat = "no match"
            for j, agg_tokens in enumerate(agg_token_sets):
                overlap = len(new_token_sets[i].intersection(agg_tokens)) / (len(new_token_sets[i]) or 1)
                if overlap > best_overlap:
                    best_overlap = overlap
                    best_overlap_cat = categories[j]
            if best_overlap >= token_overlap_threshold:
                predicted_categories.append(best_overlap_cat)
                classification_stages.append("Token Overlap")
            else:
                sku_candidate = df_new.iloc[i]["parsed_sku"]
                fallback_cat = "no match"
                if sku_candidate:
                    for cat, info in sku_map_agg.items():
                        if sku_candidate in info["agg_skus"]:
                            new_supplier = str(df_new.iloc[i][supplier_col]).lower().strip()
                            agg_supplier = str(info["agg_supplier"]).lower()
                            score = partial_ratio(new_supplier, agg_supplier)
                            if score >= supplier_fuzzy_threshold:
                                fallback_cat = cat
                                break
                predicted_categories.append(fallback_cat)
                classification_stages.append("SKU Fuzzy" if fallback_cat != "no match" else "No match")
        if predicted_categories[-1] == "no match":
            new_text = df_new.iloc[i]["cleaned_product_desc"].lower()
            candidate_scores = {cat: partial_ratio(cat.lower(), new_text) for cat in categories}
            best_candidate = max(candidate_scores, key=candidate_scores.get)
            if candidate_scores[best_candidate] >= final_fuzzy_threshold:
                predicted_categories[-1] = best_candidate
                classification_stages[-1] = "Final Fuzzy"
    df_new["predicted_category"] = predicted_categories
    df_new["classification_stage"] = classification_stages
    return df_new, tfidf_sim_matrix

# ==============================================================================
# Additional Helpers: Token Overlap and Aggregated SKU Map
# ==============================================================================
def build_token_lists(df: pd.DataFrame, text_col: str) -> list:
    token_sets = []
    for txt in df[text_col]:
        tokens = set(txt.split())
        token_sets.append(tokens)
    return token_sets

def token_overlap_ratio(tokensA: set, tokensB: set) -> float:
    if len(tokensA) == 0:
        return 0.0
    return float(len(tokensA.intersection(tokensB))) / float(len(tokensA))

def build_sku_map_agg(agg_df: pd.DataFrame, sku_col: str, group_col: str) -> dict:
    sku_map = {}
    for _, row in agg_df.iterrows():
        cat = row[group_col]
        skus = row["agg_skus"].split()  # Assuming space-separated.
        supplier = row["agg_supplier"]
        sku_map[cat] = {"agg_skus": set(skus), "agg_supplier": supplier}
    return sku_map

# ==============================================================================
# End of model_builder.py
# ==============================================================================
