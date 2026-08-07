"""
Flag US clusters as life-science vs not by top-term inspection, and emit an
author-level keep mask.

Differs from cluster_fields/3_filter_life_science.py in the keep rule. That
version put environmental, materials-science and imaging roots ("water",
"soil", "plant", "nanoparticl", "polym", "electrod", "imag") in the same
lexicon as "protein" and "neuron", so an ecology or nanomaterials cluster
scored as life science on those terms alone. At K=100 that kept 7 clusters /
355k authors that are not lab life science.

Here the lexicon is split: a cluster must show BIO_CORE evidence to be kept.
BIO_ADJACENT terms only break ties among clusters that already have core
evidence, so "soil, plant, water, contamin" no longer carries a cluster on
its own.

Run at high K. At K=30 the clusters are too coarse to split cleanly (a single
US K=30 cluster mixes pain, asthma, stroke and hepatology); at K=100 the
keep/drop call is close to unambiguous. Use the K=100 output as an
author-level mask and keep the K=30 labels for field fixed effects.

Workflow:
  1. First pass: heuristic scoring, writes a worksheet CSV with a
     pre-populated `keep` column.
  2. Skim the audit text file, hand-edit `keep` in the worksheet.
  3. Re-run with --use-manual to apply the edits and emit the author list.

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

# Unambiguous bench/clinical life science. A cluster needs at least
# --min-core of these to survive.
BIO_CORE = {
    "cell", "cellular", "protein", "enzym", "kinas", "phosphat", "phosphoryl",
    "receptor", "antibodi", "antigen", "immun", "lymph", "cytokin",
    "interleukin", "tnf", "il",
    "dna", "rna", "mrna", "trna", "ribosom", "transcript", "translat", "splic",
    "gene", "genom", "epigenet", "methyl",
    "mitochondri", "cytoplasm", "membran", "vesicl", "organel",
    "chromosom", "telomer", "centromer", "histon", "chromatin",
    "tissu", "muscl", "muscular", "skelet", "exercis", "nerv",
    "bone", "cartilag", "tendon", "ligament",
    "neuron", "neural", "axon", "dendrit", "synaps", "synapt", "cortex",
    "cortic", "hippocampu", "hippocamp", "cerebr", "cerebellar", "brain",
    "vision", "saccad", "percept",
    "cardiac", "myocardi", "myocard", "vascul", "vessel", "arteri", "venou",
    "vein", "ventricl", "atrial", "aortic", "valv", "coronari",
    "platelet", "erythrocyt", "rbc",
    "thrombin", "fibrinogen", "thrombocytopenia", "coagul", "heparin",
    "vwf", "willebrand", "transfus", "aggreg", "bleed",
    "renal", "kidney", "glomerular", "nephropathi", "dialysi", "hemodialysi",
    "transplant", "allograft", "graft",
    "hepat", "liver", "biliari", "pulmonari", "lung", "respiratori",
    "asthma", "asthmat", "allerg", "allergen", "allergi", "ige",
    "eosinophil", "bronchial", "rhiniti", "inhal", "smoke", "smoker",
    "cigarett", "tobacco",
    "pancrea", "pancreat", "intestin", "colon", "gastric", "gastrin",
    "splee", "thymus", "thyroid", "adrenal", "ovari", "ovarian", "uterin",
    "uteru", "cervic", "vagin", "prostat", "testicular",
    "ocular", "corneal", "cornea", "retin", "retinal", "glaucoma",
    "cataract", "intraocular", "macular",
    "cochlear", "tympan", "auditori",
    "tumor", "tumour", "cancer", "carcinoma", "leukemia", "lymphoma",
    "myeloma", "sarcoma", "neoplasm", "metastas", "metastat", "oncogen",
    "oncolog", "malign", "biopsi", "chemotherapi", "chemotherap",
    "apoptosi", "fibrosi", "necrosi", "inflamm", "inflammatori", "infect",
    "infecti", "pathogen", "viru", "virus", "viral", "vaccin", "vaccine",
    "bacteri", "bacterium", "fungal", "fungi", "parasit",
    "malaria", "plasmodium", "falciparum", "leishmania", "trypanosom",
    "schistosom", "helminth", "mosquito", "tick", "larva", "dengu",
    "aede", "aegypti", "insect",
    "diabet", "diabetic", "insulin", "glucos", "glycem", "islet",
    "hypertens", "hypotens", "atherosclerosi", "ischem", "ischemia",
    "thrombo", "thrombosi", "embol", "stroke", "infarct", "aneurysm",
    "alzheim", "parkinson", "sclerosi", "dementia", "seizur", "epilep",
    "echocardiograph", "angiograph", "endoscop", "laparoscop",
    "analges", "analgesia", "opioid", "morphin", "anesthet", "anesthesia",
    "anaesth",
    "obes", "metabol", "lipid", "cholesterol", "lipoprotein", "hdl", "ldl",
    "vldl", "apolipoprotein", "triglycerid", "adipos", "adipocyt",
    "agonist", "antagonist", "inhibit", "drug", "ligand", "substrat",
    "adjuvant", "antiviral", "antibiot", "antimicrobi", "antifung",
    "radiotherap", "pharmacokinet", "pharmacolog", "pharmaceut",
    "pcr", "elisa", "blot", "cytomet", "sequenc", "knockout",
    "transgen", "crispr", "rnai", "sirna", "shrna", "assay",
    "phenotyp", "genotyp", "allel", "locu", "loci", "linkag", "polymorph",
    "mous", "mice", "rat", "rodent", "primat", "drosophila", "zebrafish",
    "rabbit", "porcin", "bovin", "canin", "felin",
    "pregnan", "pregnanc", "gestat", "fetal", "fetu", "neonat", "infant",
    "matern", "menopaus", "menstrual", "contracept", "hpv",
    "sperm", "spermatozoa", "oocyt", "embryo", "fertil", "infertil",
    "semen", "blastocyst", "ovul",
    "knee", "hip", "shoulder", "joint", "synovi", "rheumatoid", "arthriti",
    "osteoarthr", "osteoporo", "fractur",
    "injuri", "wound", "tbi",
    "estrogen", "testosteron", "progesteron", "cortisol", "leptin",
    "ghrelin", "androgen", "hormon",
    "dopamin", "serotonin", "glutam", "gaba", "acetylcholin",
    "myelin", "encephalomyel",
    "serum", "plasma", "blood", "urin", "urinari",
    "thalassemia", "globin", "adrenerg", "tgf", "anemia", "hemoglobin",
    "milk", "dairi", "cattl", "calv", "lactat", "herd",
    "nutrit", "dietari", "diet", "vitamin", "intak",
    "irradi", "metabolit",
    "apnea", "apnoea", "osa", "airway", "insomnia",
    "dental", "periodont", "dentin", "enamel", "gingiv", "orthodont",
    "psychiatr", "schizophrenia", "antidepress", "antipsychot", "bipolar",
    "anxieti", "suicid",
    "treadmil", "aerob", "athlet", "endur",
    "lymphocyt", "macrophag", "neutrophil", "monocyt", "marrow",
    "resect", "prognosi", "morbid", "syndrom", "lesion", "sympt",
}

# Supporting evidence only. Never enough on its own: these are the roots that
# let ecology, water quality, nanomaterials and generic imaging clusters pass
# in the worldwide version.
BIO_ADJACENT = {
    "water", "pollut", "contamin", "sediment", "wastewat", "river", "lake",
    "drink", "environment", "toxicolog", "toxic", "exposur",
    "soil", "plant", "microbi", "microbiom", "microbial", "agricultur",
    "crop", "forest", "rhizospher", "phyt",
    "nanotub", "nanoparticl", "graphen", "electrod", "biosensor",
    "biomateri", "scaffold", "polym",
    "mri", "ct", "pet", "scan", "imag", "tomographi", "reson", "magnet",
    "ultrasound", "ultrason", "radiolog", "radiat", "ultras",
    "fatti",
    "western", "chromatograph", "spectroscop", "microscop", "crystallograph",
    "organ", "nuclear", "express", "regul", "promot", "binding", "len",
    "lens", "eye", "ear", "audit", "pain", "sleep", "wake", "eeg", "rem",
    "snore", "calcium", "potassium", "sodium", "magnesium", "burn",
}

# Exact-match only. Expanded past the worldwide version with the fields the
# K=100 audit showed surviving on adjacent terms alone.
ANTI_LEXICON = {
    "psychotherap", "psychotherapi", "psychosomat", "psycholog", "psychologist",
    "school", "student", "colleg", "educ", "teacher", "teach", "curricul",
    "literaci", "pedagog",
    "sociolog", "ethnograph", "ethnic", "anthropolog",
    "criminolog", "crimin", "prison", "incarcer", "judici", "judicial",
    "court", "election", "vote", "voter", "democra",
    "polici", "polit", "economi", "econom", "tax", "wage", "marketing",
    "welfare", "poverti", "unemploy", "cost", "insur", "reimburs",
    "demograph", "geograph",
    "music", "literatur", "religi", "religion", "theolog", "philosoph",
    "bibliograph", "bibliometri", "citat", "scholar",
    # ecology / earth science
    "ecolog", "ecosystem", "habitat", "biodivers", "marin", "sea", "ocean",
    "climat", "fisheri", "predat", "phylogeograph", "taxonom", "vegetat",
    "groundwat", "atmospher", "emiss", "geolog", "mineral",
    # materials / physical science / engineering
    "copolym", "nanowir", "electrochem", "photovolta", "semiconductor",
    "laser", "photon", "wavelength", "infrar", "fiber", "optic",
    "coat", "adsorpt", "sludg", "wast", "reactor", "corros", "alloy",
    "thermodynam", "turbul", "aerodynam", "finit",
    # computing / bibliometric methods
    "algorithm", "softwar", "processor", "wireless", "encrypt",
}


def parse_descriptions(path: str) -> dict[int, list[str]]:
    out = {}
    pat = re.compile(r"^Cluster\s+(\d+)\s*(?:\([^)]*\))?\s*:\s*(.*)$")
    with open(path) as f:
        for line in f:
            m = pat.match(line.strip())
            if m:
                terms = [t.strip() for t in m.group(2).split(",") if t.strip()]
                out[int(m.group(1))] = terms
    return out


def score_terms(terms):
    core, adj, anti = [], [], []
    for t in terms:
        tokens = t.split()
        if any(tok in BIO_CORE for tok in tokens):
            core.append(t)
        elif any(tok in BIO_ADJACENT for tok in tokens):
            adj.append(t)
        if any(tok in ANTI_LEXICON for tok in tokens):
            anti.append(t)
    return core, adj, anti


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--k", type=int, default=100)
    ap.add_argument("--min-core", type=int, default=2,
                    help="Minimum BIO_CORE top-term hits required to keep a "
                         "cluster. Raise to drop more.")
    ap.add_argument("--use-manual", action="store_true",
                    help="Apply the hand-edited 'keep' column from "
                         "cluster_label_worksheet_{k}.csv.")
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
        core, adj, anti = score_terms(terms)
        auto_keep = int(len(core) >= args.min_core and len(core) > len(anti))
        rows.append({
            "cluster_label": cid,
            "n_authors": int(sizes.get(cid, 0)),
            "core_hits": len(core),
            "adj_hits": len(adj),
            "anti_hits": len(anti),
            "score": len(core) - len(anti),
            "keep_auto": auto_keep,
            "matched_core": "|".join(core),
            "matched_adj": "|".join(adj),
            "matched_anti": "|".join(anti),
            "top_terms": ", ".join(terms),
        })
    agg = pd.DataFrame(rows).sort_values("score", ascending=False).reset_index(drop=True)

    if args.use_manual and os.path.exists(work_csv):
        print(f"Reading manual keep flags from {work_csv}")
        prior = pd.read_csv(work_csv)[["cluster_label", "keep"]]
        agg = agg.merge(prior, on="cluster_label", how="left")
        agg["keep"] = agg["keep"].fillna(agg["keep_auto"]).astype(int)
    else:
        agg["keep"] = agg["keep_auto"]

    cols = ["cluster_label", "n_authors", "score", "core_hits", "adj_hits",
            "anti_hits", "keep_auto", "keep", "matched_core", "matched_adj",
            "matched_anti", "top_terms"]
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

    with open(audit_txt, "w") as f:
        f.write(f"US cluster filter audit  K={args.k}  min_core={args.min_core}  "
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
                        f"core={r['core_hits']}  adj={r['adj_hits']}  "
                        f"anti={r['anti_hits']}{tag}\n"
                        f"      top: {r['top_terms']}\n")
            f.write("\n")
    print(f"Saved {audit_txt}")

    print("\nBorderline clusters -- review these first:")
    borderline = agg[((agg["keep_auto"] == 0) & (agg["core_hits"] >= 1)) |
                     ((agg["keep_auto"] == 1) & (agg["anti_hits"] >= 1))]
    print(borderline[["cluster_label", "n_authors", "core_hits", "adj_hits",
                      "anti_hits", "keep_auto", "top_terms"]].to_string(index=False))


if __name__ == "__main__":
    main()
