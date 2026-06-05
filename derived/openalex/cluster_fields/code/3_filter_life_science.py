"""
Flag clusters as life-science vs not by top-term inspection. This step
runs BEFORE the FOIA-similarity pipeline, so we can't anchor on FOIA
labels.

Workflow:
  1. First pass: heuristic scoring. Counts top-15 stemmed terms against
     a hand-curated bio lexicon and a non-life-science anti-lexicon.
     Writes a worksheet CSV with a pre-populated `keep` column.
  2. Skim the audit text file. Edit `keep` in the worksheet CSV by hand
     to override the heuristic where you disagree (eyeballing the top
     terms of 100 clusters is ~15 min).
  3. Re-run with --use-manual to apply your edited keep flags and emit
     the filtered author list.

Outputs:
  ../output/cluster_label_worksheet_{K}.csv     human-editable
  ../output/life_science_authors_{K}.csv        filtered (athr_id, cluster_label)
  ../output/cluster_filter_audit_{K}.txt        kept/dropped breakdown
"""
import argparse
import os
import re
import pandas as pd

OUT_DIR = "../output"

# Curated stemmed-term roots. We match the cluster's top-15 Porter-stemmed
# terms EXACTLY against this set (no substring, to avoid false hits like
# "art" matching "arteri"). When a term has multiple stem forms (e.g.,
# "phosphat" vs "phosphoryl"), list both.
BIO_LEXICON = {
    # cellular / molecular biology
    "cell", "cellular", "protein", "enzym", "kinas", "phosphat", "phosphoryl",
    "receptor", "antibodi", "antigen", "immun", "lymph", "cytokin",
    "interleukin", "tnf", "il",
    "dna", "rna", "mrna", "trna", "ribosom", "transcript", "translat", "splic",
    "gene", "genom", "express", "regul", "promot", "epigenet", "methyl",
    "mitochondri", "cytoplasm", "membran", "vesicl", "organel", "nuclear",
    "chromosom", "telomer", "centromer", "histon", "chromatin",
    # tissues / organs / physiology
    "tissu", "organ", "muscl", "bone", "cartilag", "tendon", "ligament",
    "neuron", "neural", "axon", "dendrit", "synaps", "cortex", "hippocampu",
    "cerebr", "cerebellar", "brain",
    "cardiac", "myocardi", "myocard", "vascul", "vessel", "arteri", "venou",
    "vein", "venti", "ventricl", "atrial", "aortic", "valv", "coronari",
    "platelet", "erythrocyt", "rbc",
    "renal", "kidney", "glomerular", "nephropathi", "dialysi", "hemodialysi",
    "transplant",
    "hepat", "liver", "biliari", "pulmonari", "lung", "respiratori",
    "pancrea", "intestin", "colon", "gastric", "gastrin", "splee", "thymus",
    "thyroid", "adrenal", "ovari", "ovarian", "uterin", "uteru", "cervic",
    "vagin", "prostat", "testicular",
    # eye / ENT (whole specialties were missing)
    "eye", "ocular", "corneal", "cornea", "retin", "retinal", "glaucoma",
    "cataract", "intraocular", "len", "lens", "macular",
    "ear", "audit", "auditori", "cochlear", "tympan",
    # disease / clinical bio
    "tumor", "tumour", "cancer", "carcinoma", "leukemia", "lymphoma",
    "myeloma", "sarcoma", "neoplasm", "metastas", "oncogen", "oncolog",
    "apoptosi", "fibrosi", "necrosi", "inflamm", "infect", "infecti",
    "pathogen", "viru", "virus", "viral",
    "bacteri", "bacterium", "fungal", "fungi", "parasit",
    "diabet", "diabetic", "insulin", "glucos", "glycem",
    "hypertens", "hypotens", "atherosclerosi", "ischem", "ischemia",
    "thrombo", "thrombosi", "embol", "stroke", "infarct", "aneurysm",
    "alzheim", "parkinson", "sclerosi", "dementia",
    # imaging / clinical methods (largely missed before)
    "mri", "ct", "pet", "scan", "imag", "tomographi", "reson", "magnet",
    "ultrasound", "ultrason", "echocardiograph", "angiograph", "radiolog",
    "endoscop", "biopsi", "ultras",
    # pain / anesthesia
    "pain", "analges", "analgesia", "opioid", "morphin", "anesthet",
    "anesthesia", "anaesth",
    # nutrition / metabolism
    "nutrit", "dietari", "diet", "vitamin", "obes", "obesity", "metabol",
    "lipid", "cholesterol", "fatti", "trigl", "lipoprotein", "hdl", "ldl",
    "vldl", "adipos", "adipocyt",
    # drugs / treatments / lab inputs
    "agonist", "antagonist", "inhibit", "drug", "ligand", "substrat",
    "binding", "vaccin", "vaccine", "adjuvant", "antiviral", "antibiot",
    "antimicrobi", "antifung", "chemotherap", "radiat", "radiotherap",
    "pharmacokinet", "pharmacolog", "pharmaceut",
    # methods that strongly imply lab work
    "pcr", "elisa", "western", "blot", "chromatograph", "spectroscop",
    "microscop", "crystallograph", "cytomet", "sequenc", "knockout",
    "transgen", "crispr", "rnai", "sirna", "shrna", "assay",
    "phenotyp", "genotyp",
    # animal models
    "mous", "mice", "rat", "rodent", "primat", "drosophila", "zebrafish",
    "rabbit", "porcin", "bovin", "canin", "felin",
    # OB/GYN and reproductive
    "pregnan", "pregnanc", "gestat", "fetal", "fetu", "neonat", "infant",
    "maternal", "menopaus", "menstrual", "contracept", "hpv",
    # orthopedics / rheumatology
    "knee", "hip", "shoulder", "joint", "synovi", "rheumatoid", "arthriti",
    "osteoarthr", "osteoporo", "fracture",
    # injury
    "injuri", "wound", "burn", "tbi",
    # endocrine
    "estrogen", "testosteron", "progesteron", "cortisol", "leptin",
    "ghrelin", "androgen",
    # neurotransmitters
    "dopamin", "serotonin", "glutam", "gaba", "acetylcholin",
    # electrolytes
    "calcium", "potassium", "sodium", "magnesium",
    # core terms
    "mbp", "myelin", "encephalomyel",
    # epidemiology / clinical research signals
    "serum", "plasma", "blood", "urin",
    # sleep medicine / pulmonology
    "sleep", "apnea", "apnoea", "osa", "airway", "insomnia", "wake",
    "eeg", "rem", "snore",
    # environmental health / water quality / pollution toxicology
    "water", "pollut", "contamin", "sediment", "wastewat", "river", "lake",
    "drink", "environment", "toxicolog", "toxic", "exposur",
    # plant / soil / agricultural biology
    "soil", "plant", "microbi", "microbiom", "microbial", "agricultur",
    "crop", "forest", "rhizospher", "phyt",
    # biomaterials / nanomedicine (bioengineering -- often used for drug
    # delivery, biosensors, tissue scaffolds)
    "nanotub", "nanoparticl", "graphen", "electrod", "biosensor", "biomateri",
    "scaffold", "polym",
}

# Strong "this is NOT life science / lab work" signals. EXACT-match only
# (no substring) to avoid catastrophes like "art" hitting "arteri". Keep
# this list tight -- the cost of a false positive (dropping a real life-
# science cluster) is much higher than a false negative (keeping a borderline
# social-science cluster that you can manually drop).
#
# Notable exclusions:
#   - "histori": stems for medical/family history (genetic-linkage clusters
#     legitimately use this). Removed because it killed C60 (genetics).
#   - "trauma", "behavior", "depress", "stress": all have substantial bench
#     and clinical-medicine research; removed to avoid killing trauma
#     medicine, behavioral neuroscience, depression pharmacology, etc.
#   - "labor", "consum", "migrat": collide with biomedical uses (childbirth
#     labor, nutritional consumption, cell migration).
ANTI_LEXICON = {
    # psychology / psychiatry (clinical psych, not bench neuroscience)
    "psychiatri", "psycholog", "psychotherap", "psychotherapi", "psychosomat",
    "psychiatric", "psychologist",
    # education research
    "school", "student", "colleg", "educ", "teacher", "teach", "curricul",
    "literaci", "pedagog",
    # sociology / anthropology / ethnography
    "sociolog", "ethnograph", "ethnic", "anthropolog",
    # criminology / law / political science
    "criminolog", "crimin", "prison", "incarcer", "judici", "judicial",
    "court", "election", "vote", "voter", "democra",
    # economics / business / public policy
    "polici", "polit", "economi", "econom", "tax", "wage", "marketing",
    "welfare", "poverti", "unemploy",
    # demography / geography (as social-science disciplines)
    "demograph", "geograph",
    # arts / humanities / religion (kept tight; histori removed)
    "music", "literatur", "religi", "religion", "theolog", "philosoph",
    # bibliometrics / library science
    "bibliograph", "bibliometri", "citat", "scholar",
}


def parse_descriptions(path: str) -> dict[int, list[str]]:
    """Return {cluster_id: [term, ...]} from descriptions txt. Accepts
    both the original 'Cluster N: ...' format and the new 'Cluster N
    (n=NNN): ...' format that 2_cluster.py now writes."""
    out = {}
    pat = re.compile(r"^Cluster\s+(\d+)\s*(?:\([^)]*\))?\s*:\s*(.*)$")
    with open(path) as f:
        for line in f:
            m = pat.match(line.strip())
            if m:
                terms = [t.strip() for t in m.group(2).split(",") if t.strip()]
                out[int(m.group(1))] = terms
    return out


def score_terms(terms: list[str]) -> tuple[int, int, list[str], list[str]]:
    """Return (bio_hits, anti_hits, matched_bio_terms, matched_anti_terms).
    Match each top-15 term EXACTLY against the lexicons. Substring matching
    was causing catastrophic false positives (e.g. "art" matching "arteri"
    killed cardiology/imaging clusters). Multi-word top-terms (very rare)
    split on whitespace so "16 rrna" matches "rna"."""
    bio_hits, anti_hits = [], []
    for t in terms:
        tokens = t.split()
        if any(tok in BIO_LEXICON for tok in tokens):
            bio_hits.append(t)
        if any(tok in ANTI_LEXICON for tok in tokens):
            anti_hits.append(t)
    return len(bio_hits), len(anti_hits), bio_hits, anti_hits


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--k", type=int, default=100)
    ap.add_argument("--use-manual", action="store_true",
                    help="Apply the hand-edited 'keep' column from "
                         "cluster_label_worksheet_{k}.csv. Without this, "
                         "the keep column is recomputed by heuristic.")
    args = ap.parse_args()

    clusters_csv = f"{OUT_DIR}/author_static_clusters_{args.k}.csv"
    desc_txt     = f"{OUT_DIR}/static_cluster_descriptions_{args.k}.txt"
    work_csv     = f"{OUT_DIR}/cluster_label_worksheet_{args.k}.csv"
    out_authors  = f"{OUT_DIR}/life_science_authors_{args.k}.csv"
    audit_txt    = f"{OUT_DIR}/cluster_filter_audit_{args.k}.txt"

    for p in (clusters_csv, desc_txt):
        if not os.path.exists(p):
            raise SystemExit(f"missing: {p}")

    print(f"Loading {clusters_csv}")
    df = pd.read_csv(clusters_csv, dtype={"athr_id": str, "cluster_label": int})
    print(f"  authors: {len(df):,}   clusters present: {df['cluster_label'].nunique()}")

    sizes = df["cluster_label"].value_counts().sort_index()
    descs = parse_descriptions(desc_txt)

    rows = []
    for cid, terms in descs.items():
        bio_n, anti_n, bio_t, anti_t = score_terms(terms)
        # Heuristic default: keep iff there's at least one bio hit AND
        # bio hits outnumber anti hits. A cluster that is half-and-half
        # (e.g., neurology terms mixed with psych terms) ends up at 0 ->
        # gets DROPPED by this rule; flip it manually if borderline.
        auto_keep = int(bio_n >= 1 and bio_n > anti_n)
        rows.append({
            "cluster_label": cid,
            "n_authors": int(sizes.get(cid, 0)),
            "bio_hits": bio_n,
            "anti_hits": anti_n,
            "score": bio_n - anti_n,
            "keep_auto": auto_keep,
            "matched_bio": "|".join(bio_t),
            "matched_anti": "|".join(anti_t),
            "top_terms": ", ".join(terms),
        })
    agg = pd.DataFrame(rows).sort_values("score", ascending=False).reset_index(drop=True)

    if args.use_manual and os.path.exists(work_csv):
        print(f"Reading manual keep flags from {work_csv}")
        prior = pd.read_csv(work_csv)[["cluster_label", "keep"]]
        agg = agg.merge(prior, on="cluster_label", how="left")
        # Fill anything missing with the auto suggestion
        agg["keep"] = agg["keep"].fillna(agg["keep_auto"]).astype(int)
    else:
        agg["keep"] = agg["keep_auto"]

    # Reorder columns: identifying info first, then the editable bit
    cols = ["cluster_label", "n_authors", "score", "bio_hits", "anti_hits",
            "keep_auto", "keep", "matched_bio", "matched_anti", "top_terms"]
    agg = agg[cols]
    agg.to_csv(work_csv, index=False)
    print(f"Saved worksheet (edit 'keep' column here): {work_csv}")

    keep_clusters = set(agg.loc[agg["keep"] == 1, "cluster_label"])
    df_keep = df[df["cluster_label"].isin(keep_clusters)][["athr_id", "cluster_label"]]
    df_keep.to_csv(out_authors, index=False)
    print(f"Saved {out_authors}  "
          f"({len(df_keep):,} authors in {len(keep_clusters)} kept clusters; "
          f"dropped {len(df) - len(df_keep):,} authors in "
          f"{len(agg) - len(keep_clusters)} clusters)")

    # Human-readable audit
    with open(audit_txt, "w") as f:
        f.write(f"Cluster filter audit  K={args.k}  "
                f"({'MANUAL' if args.use_manual else 'HEURISTIC'} keep flags)\n")
        f.write(f"  total authors: {len(df):,}\n")
        f.write(f"  kept clusters: {(agg['keep']==1).sum()}   "
                f"kept authors: {df_keep.shape[0]:,}\n")
        f.write(f"  dropped clusters: {(agg['keep']==0).sum()}   "
                f"dropped authors: {len(df) - df_keep.shape[0]:,}\n\n")
        for status, sub in [("KEPT", agg[agg["keep"] == 1]),
                            ("DROPPED", agg[agg["keep"] == 0])]:
            f.write(f"== {status} ==\n")
            for _, r in sub.iterrows():
                tag = ""
                if args.use_manual and r["keep"] != r["keep_auto"]:
                    tag = "  [MANUAL OVERRIDE]"
                f.write(f"  C{int(r['cluster_label']):3d}  "
                        f"n={int(r['n_authors']):>8,}  "
                        f"bio={r['bio_hits']}  anti={r['anti_hits']}{tag}\n"
                        f"      top: {r['top_terms']}\n")
            f.write("\n")
    print(f"Saved {audit_txt}")

    # Console preview of borderline cases
    print("\nBorderline clusters (auto-keep != 1 and bio_hits >= 1, OR "
          "auto-keep == 1 and anti_hits >= 1) -- review these first:")
    borderline = agg[((agg["keep_auto"] == 0) & (agg["bio_hits"] >= 1)) |
                     ((agg["keep_auto"] == 1) & (agg["anti_hits"] >= 1))]
    print(borderline[["cluster_label", "n_authors", "score", "bio_hits",
                      "anti_hits", "keep_auto", "top_terms"]].to_string(index=False))


if __name__ == "__main__":
    main()
