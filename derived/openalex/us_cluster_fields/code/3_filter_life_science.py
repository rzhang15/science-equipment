"""
Identify clusters corresponding to LIFE-SCIENCE LAB researchers.

Target population
-----------------
Researchers whose scientific work plausibly involves experimental life-science
laboratory activity: molecular biology, cell biology, biochemistry, genetics,
microbiology, immunology, experimental neuroscience, experimental physiology,
preclinical biomedical research, wet-lab pharmacology, etc.

This is intentionally narrower than:
    * all life scientists,
    * all biomedical researchers,
    * all physicians/clinical researchers,
    * all researchers publishing on diseases or biological outcomes.

A disease/anatomy/organism term alone is NOT sufficient. The positive signal
should indicate laboratory production: molecular mechanisms, cells/proteins/
genes, wet-lab methods, experimental model systems, reagents, assays, etc.

Examples
--------
KEEP:
    protein, kinase, phosphorylation, receptor, western blot
    macrophage, cytokine, knockout, mouse, inflammation
    plasmid, transfection, RNA, qPCR, fibroblast
    bacterial, virulence, mutant, gene, sequencing
    tumor, apoptosis, xenograft, antibody, immunohistochemistry

DROP:
    diabetes, insurance, cost, Medicare, hospitalization
    cancer, survival, cohort, questionnaire, patient
    neuron, algorithm, network, simulation, prediction
    exercise, survey, adolescent, obesity, behavior
    biodiversity, habitat, wildlife, ecosystem, conservation
    polymer, catalyst, electrode, nanoparticle, semiconductor

Heuristic
---------
Clusters receive rank-weighted evidence in four categories:

    BENCH_CORE
        Strong evidence of experimental/wet-lab life science.

    BIO_CONTEXT
        Biological/medical subject matter. Supports bench evidence but
        cannot independently make a cluster a lab-science cluster.

    CLINICAL_PRACTICE
        Clinical trials, patient care, epidemiologic/practice-oriented signals.

    ANTI_LEXICON
        Social science, health services, computing, engineering, physical
        science, education, etc.

Default automatic keep rule:

    1. At least --min-bench distinct BENCH_CORE top-term hits; AND
    2. bench weighted score >= --min-bench-score; AND
    3. bench evidence is not dominated by clinical/non-lab evidence.

A particularly strong laboratory cluster can survive some anti/clinical terms,
but disease/anatomy vocabulary by itself cannot make a cluster survive.

Workflow
--------
1. Run once:
       writes cluster_label_worksheet_{K}.csv with `keep` pre-filled,
       author_static_clusters_{K}_ls.csv, and an audit.

2. Hand-edit `keep` in the worksheet for any desired overrides.

3. Re-run:
       existing worksheet values are respected.

4. Use --reset-worksheet to discard manual overrides.

Outputs
-------
../output/cluster_label_worksheet_{K}.csv
../output/author_static_clusters_{K}_ls.csv
../output/cluster_filter_audit_{K}.txt
"""

import argparse
import math
import os
import re

import pandas as pd


OUT_DIR = "../output"


# -------------------------------------------------------------------------
# 1. STRONG POSITIVE EVIDENCE: EXPERIMENTAL LIFE-SCIENCE LAB WORK
# -------------------------------------------------------------------------
#
# Terms here should be difficult to generate in large amounts without doing
# experimental biological / biomedical laboratory research.
#
# These terms CAN carry a cluster.
#
BENCH_CORE = {

    # ------------------------------------------------------------------
    # Molecular biology / genetics
    # ------------------------------------------------------------------
    "dna", "rna", "mrna", "trna",
    "gene", "genom", "epigenet", "epigenom",
    "chromatin", "histon", "chromosom",
    "telomer", "centromer",
    "transcript", "translat", "splic",
    "methyl", "methyltransferas",
    "ribosom",
    "allel", "genotyp", "polymorph",
    "loci", "locu",
    "promot",

    # ------------------------------------------------------------------
    # Proteins / enzymes / signaling
    # ------------------------------------------------------------------
    "protein",
    "enzym",
    "kinas",
    "phosphatas",
    "phosphat",
    "phosphoryl",
    "acetyl",
    "acetyltransferas",
    "acetylas",
    "deacetylas",
    "ubiquitin",
    "proteasom",
    "peptidas",
    "ligas",
    "receptor",
    "ligand",
    "substrat",
    "repressor",

    # ------------------------------------------------------------------
    # Cell biology
    # ------------------------------------------------------------------
    "cell",
    "cellular",
    "cytoplasm",
    "membran",
    "vesicl",
    "organel",
    "mitochondri",
    "apoptosi",
    "necrosi",

    "fibroblast",
    "keratinocyt",
    "hepatocyt",
    "myocyt",
    "chondrocyt",
    "osteoblast",
    "osteoclast",

    # ------------------------------------------------------------------
    # Immunology
    # ------------------------------------------------------------------
    "antibodi",
    "antigen",
    "immun",
    "lymphocyt",
    "macrophag",
    "neutrophil",
    "monocyt",
    "cytokin",
    "interleukin",
    "tnf",
    "ige",
    "eosinophil",
    "epitop",
    "immunogen",
    "antisera",
    "seroconvers",
    "adjuv",
    "virul",

    # ------------------------------------------------------------------
    # Microbiology / virology / parasitology
    # ------------------------------------------------------------------
    "bacteri",
    "bacterium",
    "bacteria",
    "microbi",
    "microbial",
    "microbiom",
    "fungal",
    "fungi",
    "viru",
    "virus",
    "viral",
    "pathogen",
    "parasit",

    "salmonella",
    "escherichia",
    "coli",
    "campylobact",

    "plasmodium",
    "falciparum",
    "leishmania",
    "trypanosom",
    "schistosom",
    "helminth",

    "sporozoit",
    "merozoit",
    "gametocyt",
    "trophozoit",

    # ------------------------------------------------------------------
    # Explicit wet-lab methods
    # ------------------------------------------------------------------
    "pcr",
    "qpcr",
    "primer",
    "plasmid",
    "transfect",
    "knockdown",
    "knockout",
    "crispr",
    "rnai",
    "sirna",
    "shrna",

    "sequenc",
    "microarray",

    "blot",
    "immunoblot",
    "elisa",
    "immunoassay",

    "cytomet",
    "cytometri",

    "electrophoresi",
    "agaros",
    "gel",

    "stain",
    "immunostain",
    "immunohistochem",
    "immunofluoresc",
    "histolog",

    "confoc",
    "microscop",

    "immunoprecipit",

    "luciferas",
    "gfp",

    "reagent",
    "lysat",
    "recombin",

    "incub",
    "centrifug",
    "pipett",
    "dissect",

    # ------------------------------------------------------------------
    # Cell / tissue / experimental systems
    # ------------------------------------------------------------------
    "organoid",
    "spheroid",
    "explant",
    "bioreactor",
    "perfus",
    "hybridoma",
    "monoclon",

    "hela",

    # ------------------------------------------------------------------
    # Experimental model organisms
    # ------------------------------------------------------------------
    "mous",
    "mice",
    "rodent",
    "rat",
    "zebrafish",
    "drosophila",
    "xenopu",
    "xenograft",

    # ------------------------------------------------------------------
    # Experimental neuroscience
    # ------------------------------------------------------------------
    "neuron",
    "axon",
    "dendrit",
    "synaps",
    "synapt",
    "myelin",

    # ------------------------------------------------------------------
    # Experimental hematology
    # ------------------------------------------------------------------
    "platelet",
    "erythrocyt",
    "rbc",
    "fibrinogen",
    "thrombin",
    "globin",
    "hemoglobin",

    # ------------------------------------------------------------------
    # Biological fluids frequently used experimentally
    # ------------------------------------------------------------------
    "serum",
    "plasma",
}


# -------------------------------------------------------------------------
# 2. BIOLOGICAL / BIOMEDICAL CONTEXT
# -------------------------------------------------------------------------
#
# These indicate biological subject matter, but NOT necessarily lab work.
#
# They SUPPORT a BENCH_CORE call but cannot carry the cluster by themselves.
#
BIO_CONTEXT = {

    # anatomy / physiology
    "tissu",
    "muscl",
    "skelet",
    "bone",
    "cartilag",
    "tendon",
    "ligament",

    "brain",
    "cortex",
    "cortic",
    "hippocamp",
    "hippocampu",
    "cerebr",
    "cerebellar",
    "nerv",

    "cardiac",
    "myocardi",
    "myocard",
    "vascul",
    "vessel",
    "arteri",
    "venou",
    "vein",
    "ventricl",
    "atrial",
    "aortic",
    "valv",
    "coronari",

    "renal",
    "kidney",
    "glomerular",

    "hepat",
    "liver",
    "biliari",

    "pulmonari",
    "lung",
    "respiratori",
    "airway",

    "pancrea",
    "pancreat",
    "intestin",
    "colon",
    "gastric",

    "splee",
    "thymus",
    "thyroid",
    "adrenal",

    "ovari",
    "ovarian",
    "uterin",
    "uteru",
    "cervic",
    "prostat",
    "testicular",

    "ocular",
    "corneal",
    "cornea",
    "retin",
    "retinal",

    # disease
    "tumor",
    "tumour",
    "cancer",
    "carcinoma",
    "leukemia",
    "lymphoma",
    "myeloma",
    "sarcoma",
    "neoplasm",
    "metastas",
    "metastat",
    "oncogen",
    "oncolog",
    "malign",

    "fibrosi",
    "inflamm",
    "inflammatori",
    "infect",
    "infecti",

    "diabet",
    "diabetic",
    "insulin",
    "glucos",
    "glycem",
    "islet",

    "hypertens",
    "atherosclerosi",
    "ischem",
    "ischemia",
    "thrombo",
    "thrombosi",
    "stroke",
    "infarct",

    "alzheim",
    "parkinson",
    "sclerosi",
    "dementia",
    "seizur",
    "epilep",

    "asthma",
    "asthmat",
    "allerg",
    "allergen",
    "allergi",

    "obes",
    "metabol",
    "lipid",
    "cholesterol",
    "lipoprotein",
    "triglycerid",
    "adipos",
    "adipocyt",

    "rheumatoid",
    "arthriti",
    "osteoarthr",
    "osteoporo",

    # reproduction/development
    "pregnan",
    "pregnanc",
    "gestat",
    "fetal",
    "fetu",
    "neonat",

    "sperm",
    "spermatozoa",
    "oocyt",
    "embryo",
    "blastocyst",
    "fertil",
    "infertil",
    "ovul",

    # hormones / metabolites
    "estrogen",
    "testosteron",
    "progesteron",
    "cortisol",
    "leptin",
    "ghrelin",
    "androgen",
    "hormon",

    "dopamin",
    "serotonin",
    "glutam",
    "gaba",
    "acetylcholin",

    # pharmacology / therapeutics
    "pharmacokinet",
    "pharmacolog",
    "antiviral",
    "antibiot",
    "antimicrobi",
    "antifung",
    "immunotherapi",

    # generic biological observations
    "phenotyp",
    "biopsi",
    "marrow",
    "lesion",

    # animal/veterinary context
    "rabbit",
    "porcin",
    "bovin",
    "canin",
    "felin",
    "cattl",
}


# -------------------------------------------------------------------------
# 3. CLINICAL / PRACTICE / PATIENT-ORIENTED SIGNALS
# -------------------------------------------------------------------------
#
# These are not "bad research". They simply indicate that the work is likely
# clinical, epidemiologic, health-services, or patient-care oriented rather
# than experimental life-science lab production.
#
CLINICAL_PRACTICE = {

    "randomis",
    "multicent",
    "noninferior",

    "patient",
    "pati",
    "cohort",

    "enrol",
    "followup",

    "questionnair",
    "survey",
    "interview",

    "outpati",
    "inpati",
    "admiss",
    "discharg",
    "readmiss",
    "triag",
    "referr",

    "practition",
    "guidelin",
    "complianc",

    "satisfact",
    "counsel",

    "rehabilit",
    "arthroplasti",

    "comorbid",
    "disabl",

    "prognosi",
    "morbid",
    "sympt",
    "symptomat",

    "surviv",
    "mortali",

    "case",
    "cases",

    "surg",
    "surgic",
    "surgery",

    "tomographi",
    "radiolog",

    "hospital",
    "clinic",
    "clinical",
}


# -------------------------------------------------------------------------
# 4. CLEAR NEGATIVE EVIDENCE
# -------------------------------------------------------------------------
#
# These are areas we generally do NOT want in a lab-life-science PI sample.
#
ANTI_LEXICON = {

    # ---------------------------------------------------------------
    # economics / policy / health services
    # ---------------------------------------------------------------
    "econom",
    "economi",
    "cost",
    "wage",
    "tax",
    "insurance",
    "insur",
    "reimburs",
    "medicar",
    "medicaid",
    "healthcar",
    "servic",
    "polici",
    "welfare",
    "poverti",
    "unemploy",

    # ---------------------------------------------------------------
    # education
    # ---------------------------------------------------------------
    "school",
    "student",
    "colleg",
    "educ",
    "teacher",
    "teach",
    "curricul",
    "literaci",
    "pedagog",

    # ---------------------------------------------------------------
    # social / behavioral science
    # ---------------------------------------------------------------
    "psycholog",
    "psychologist",
    "psychotherap",
    "psychotherapi",

    "sociolog",
    "ethnograph",
    "anthropolog",

    "criminolog",
    "crimin",
    "prison",
    "incarcer",
    "court",

    "demograph",

    "parent",

    "election",
    "vote",
    "voter",
    "polit",

    "marketing",

    # ---------------------------------------------------------------
    # humanities
    # ---------------------------------------------------------------
    "music",
    "literatur",
    "religi",
    "religion",
    "theolog",
    "philosoph",

    # ---------------------------------------------------------------
    # computational / statistical methods
    # ---------------------------------------------------------------
    "algorithm",
    "softwar",
    "processor",
    "wireless",
    "encrypt",
    "comput",
    "simul",
    "machin",
    "network",
    "informat",
    "databas",
    "statist",
    "bayesian",
    "regress",

    # ---------------------------------------------------------------
    # bibliometrics / publication metadata
    # ---------------------------------------------------------------
    "bibliograph",
    "bibliometri",
    "citat",
    "scholar",

    # ---------------------------------------------------------------
    # physical sciences / engineering
    # ---------------------------------------------------------------
    "semiconductor",
    "photovolta",
    "laser",
    "photon",
    "wavelength",
    "infrar",
    "optic",

    "electrochem",
    "nanowir",
    "electrod",

    "adsorpt",
    "corros",
    "alloy",

    "thermodynam",
    "turbul",
    "aerodynam",
    "finit",

    # ---------------------------------------------------------------
    # general chemistry/materials: not sufficient for our target
    # ---------------------------------------------------------------
    "polymer",
    "polym",
    "copolym",
    "catalyz",
    "catalyt",
    "chiral",
    "enantioselect",
    "stereoselect",

    "nanoparticl",
    "nanotub",
    "graphen",

    # ---------------------------------------------------------------
    # ecology / environmental / earth science
    #
    # These can be life science in a broad disciplinary sense, but the
    # target here is laboratory life-science PIs.
    # ---------------------------------------------------------------
    "ecolog",
    "ecosystem",
    "habitat",
    "biodivers",
    "wildlif",
    "fisheri",
    "predat",
    "forest",

    "climat",
    "atmospher",
    "geolog",
    "mineral",

    "river",
    "lake",
    "groundwat",
    "sediment",
    "soil",

    # ---------------------------------------------------------------
    # publisher / scraper junk
    # ---------------------------------------------------------------
    "jama",
    "cooki",
    "forum",
    "archiv",
    "altmetr",
}


# -------------------------------------------------------------------------
# HELPERS
# -------------------------------------------------------------------------

def parse_descriptions(path: str) -> dict[int, list[str]]:
    """Read cluster descriptions and return {cluster_id: [ranked terms]}."""
    out = {}

    pat = re.compile(
        r"^Cluster\s+(\d+)\s*(?:\([^)]*\))?\s*:\s*(.*)$"
    )

    with open(path, encoding="utf-8") as f:
        for line in f:
            m = pat.match(line.strip())

            if not m:
                continue

            cid = int(m.group(1))

            terms = [
                t.strip().lower()
                for t in m.group(2).split(",")
                if t.strip()
            ]

            if cid in out:
                raise ValueError(
                    f"Cluster {cid} appears more than once in {path}"
                )

            out[cid] = terms

    if not out:
        raise ValueError(
            f"No cluster descriptions parsed from {path}"
        )

    return out


def term_tokens(term: str) -> list[str]:
    """
    Tokenize a cluster term.

    Exact token matching is intentional because the lexicons already contain
    stemmed forms corresponding to the TF-IDF vocabulary.
    """
    return re.findall(r"[a-z0-9]+", term.lower())


def term_matches(term: str, lexicon: set[str]) -> bool:
    """Return True if any token in term matches the lexicon exactly."""
    return any(tok in lexicon for tok in term_tokens(term))


def rank_weight(rank: int) -> float:
    """
    Weight high-ranked cluster terms more heavily.

    rank is zero-indexed.

    sqrt decay is deliberately moderate:
        rank 1  -> 1.00
        rank 4  -> 0.50
        rank 9  -> 0.33
        rank 16 -> 0.25
    """
    return 1.0 / math.sqrt(rank + 1)


def score_terms(terms):
    """
    Score ranked cluster terms.

    Returns matched terms and rank-weighted evidence in each category.
    """

    hits = {
        "bench": [],
        "bio": [],
        "clinical": [],
        "anti": [],
    }

    scores = {
        "bench": 0.0,
        "bio": 0.0,
        "clinical": 0.0,
        "anti": 0.0,
    }

    for rank, term in enumerate(terms):

        w = rank_weight(rank)

        # Categories are deliberately NOT mutually exclusive.
        #
        # E.g. a term could theoretically contain evidence belonging to
        # multiple dimensions. We want to preserve that information.

        if term_matches(term, BENCH_CORE):
            hits["bench"].append(term)
            scores["bench"] += w

        if term_matches(term, BIO_CONTEXT):
            hits["bio"].append(term)
            scores["bio"] += w

        if term_matches(term, CLINICAL_PRACTICE):
            hits["clinical"].append(term)
            scores["clinical"] += w

        if term_matches(term, ANTI_LEXICON):
            hits["anti"].append(term)
            scores["anti"] += w

    return hits, scores


def automatic_keep(
    hits,
    scores,
    min_bench: int,
    min_bench_score: float,
    dominance_ratio: float,
):
    """
    Determine whether a cluster belongs to experimental life-science lab work.

    Requirements
    ------------
    1. There must be real BENCH_CORE evidence.
    2. It must reach a minimum rank-weighted strength.
    3. Clinical + anti evidence cannot strongly dominate bench evidence.

    BIO_CONTEXT helps us characterize the cluster but does not independently
    qualify it.
    """

    n_bench = len(hits["bench"])

    if n_bench < min_bench:
        return 0, "INSUFFICIENT_BENCH_HITS"

    if scores["bench"] < min_bench_score:
        return 0, "WEAK_BENCH_RANK"

    nonlab_score = scores["clinical"] + scores["anti"]

    # Strongly non-lab context can veto weak/incidental molecular language.
    if nonlab_score > dominance_ratio * scores["bench"]:
        return 0, "NONLAB_DOMINATES"

    return 1, "BENCH_SUPPORTED"


def validate_manual_worksheet(prior: pd.DataFrame):
    """Fail loudly on malformed manual classification files."""

    required = {"cluster_label", "keep"}

    missing = required - set(prior.columns)

    if missing:
        raise ValueError(
            "Worksheet is missing required columns: "
            + ", ".join(sorted(missing))
        )

    if prior["cluster_label"].duplicated().any():
        dup = (
            prior.loc[
                prior["cluster_label"].duplicated(),
                "cluster_label"
            ]
            .tolist()
        )

        raise ValueError(
            f"Duplicate cluster labels in worksheet: {dup}"
        )

    if prior["keep"].isna().any():
        raise ValueError(
            "Worksheet contains missing values in `keep`."
        )

    if not prior["keep"].isin([0, 1]).all():
        bad = sorted(prior.loc[
            ~prior["keep"].isin([0, 1]),
            "keep"
        ].unique())

        raise ValueError(
            f"`keep` must contain only 0/1. Found: {bad}"
        )


# -------------------------------------------------------------------------
# MAIN
# -------------------------------------------------------------------------

def main():

    ap = argparse.ArgumentParser()

    ap.add_argument(
        "--k",
        type=int,
        default=30,
    )

    ap.add_argument(
        "--min-bench",
        type=int,
        default=2,
        help=(
            "Minimum number of distinct BENCH_CORE top-term hits. "
            "Default=2."
        ),
    )

    ap.add_argument(
        "--min-bench-score",
        type=float,
        default=0.75,
        help=(
            "Minimum rank-weighted BENCH_CORE score. "
            "Default=0.75."
        ),
    )

    ap.add_argument(
        "--dominance-ratio",
        type=float,
        default=1.25,
        help=(
            "Drop cluster if clinical + anti weighted score exceeds "
            "this multiple of bench score. Default=1.25."
        ),
    )

    ap.add_argument(
        "--reset-worksheet",
        action="store_true",
        help=(
            "Regenerate cluster_label_worksheet_{k}.csv and discard "
            "hand-edited keep values."
        ),
    )

    args = ap.parse_args()

    clusters_csv = (
        f"{OUT_DIR}/author_static_clusters_{args.k}.csv"
    )

    desc_txt = (
        f"{OUT_DIR}/static_cluster_descriptions_{args.k}.txt"
    )

    work_csv = (
        f"{OUT_DIR}/cluster_label_worksheet_{args.k}.csv"
    )

    out_authors = (
        f"{OUT_DIR}/author_static_clusters_{args.k}_ls.csv"
    )

    audit_txt = (
        f"{OUT_DIR}/cluster_filter_audit_{args.k}.txt"
    )

    # ------------------------------------------------------------------
    # Validate inputs
    # ------------------------------------------------------------------

    for p in (clusters_csv, desc_txt):
        if not os.path.exists(p):
            raise SystemExit(f"Missing required input: {p}")

    print(f"Loading {clusters_csv}")

    df = pd.read_csv(
        clusters_csv,
        dtype={
            "athr_id": str,
            "cluster_label": int,
        },
    )

    required_cols = {"athr_id", "cluster_label"}

    missing_cols = required_cols - set(df.columns)

    if missing_cols:
        raise ValueError(
            f"{clusters_csv} missing columns: "
            + ", ".join(sorted(missing_cols))
        )

    print(
        f"  authors: {len(df):,}"
        f"   clusters present: "
        f"{df['cluster_label'].nunique():,}"
    )

    sizes = (
        df["cluster_label"]
        .value_counts()
        .sort_index()
    )

    descs = parse_descriptions(desc_txt)

    # ------------------------------------------------------------------
    # Crucial safety check:
    # every assigned cluster must have a description.
    # ------------------------------------------------------------------

    cluster_ids = set(df["cluster_label"].unique())
    description_ids = set(descs)

    missing_descriptions = cluster_ids - description_ids
    extra_descriptions = description_ids - cluster_ids

    if missing_descriptions:
        raise ValueError(
            "Assigned clusters are missing from the description file: "
            f"{sorted(missing_descriptions)}"
        )

    if extra_descriptions:
        print(
            "Warning: description file contains clusters with no "
            f"assigned authors: {sorted(extra_descriptions)}"
        )

    # ------------------------------------------------------------------
    # Score clusters
    # ------------------------------------------------------------------

    rows = []

    for cid in sorted(cluster_ids):

        terms = descs[cid]

        hits, scores = score_terms(terms)

        auto_keep, reason = automatic_keep(
            hits=hits,
            scores=scores,
            min_bench=args.min_bench,
            min_bench_score=args.min_bench_score,
            dominance_ratio=args.dominance_ratio,
        )

        rows.append({

            "cluster_label": cid,

            "n_authors": int(
                sizes.get(cid, 0)
            ),

            "bench_hits": len(hits["bench"]),
            "bio_hits": len(hits["bio"]),
            "clinical_hits": len(hits["clinical"]),
            "anti_hits": len(hits["anti"]),

            "bench_score": round(
                scores["bench"], 4
            ),

            "bio_score": round(
                scores["bio"], 4
            ),

            "clinical_score": round(
                scores["clinical"], 4
            ),

            "anti_score": round(
                scores["anti"], 4
            ),

            "nonlab_score": round(
                scores["clinical"] + scores["anti"],
                4,
            ),

            "keep_auto": auto_keep,

            "auto_reason": reason,

            "matched_bench": "|".join(
                hits["bench"]
            ),

            "matched_bio": "|".join(
                hits["bio"]
            ),

            "matched_clinical": "|".join(
                hits["clinical"]
            ),

            "matched_anti": "|".join(
                hits["anti"]
            ),

            "top_terms": ", ".join(terms),
        })

    agg = pd.DataFrame(rows)

    # Useful ranking for manual inspection:
    # weak bench clusters and mixed clusters appear near one another.
    agg["lab_margin"] = (
        agg["bench_score"] -
        agg["nonlab_score"]
    ).round(4)

    agg = (
        agg
        .sort_values(
            [
                "keep_auto",
                "lab_margin",
                "bench_score",
            ],
            ascending=[
                False,
                False,
                False,
            ],
        )
        .reset_index(drop=True)
    )

    # ------------------------------------------------------------------
    # Manual worksheet
    # ------------------------------------------------------------------

    manual = (
        os.path.exists(work_csv)
        and not args.reset_worksheet
    )

    if manual:

        print(
            "Applying keep flags from existing worksheet: "
            f"{work_csv}"
        )

        prior = pd.read_csv(work_csv)

        validate_manual_worksheet(prior)

        prior = prior[
            ["cluster_label", "keep"]
        ].copy()

        worksheet_clusters = set(
            prior["cluster_label"]
        )

        # Old worksheets can become stale when clustering changes.
        unknown_manual = (
            worksheet_clusters - cluster_ids
        )

        if unknown_manual:
            print(
                "Warning: worksheet contains obsolete clusters: "
                f"{sorted(unknown_manual)}"
            )

        agg = agg.merge(
            prior,
            on="cluster_label",
            how="left",
        )

        # New clusters get the heuristic call.
        agg["keep"] = (
            agg["keep"]
            .fillna(agg["keep_auto"])
            .astype(int)
        )

    else:

        agg["keep"] = agg["keep_auto"]

    # ------------------------------------------------------------------
    # Save worksheet
    # ------------------------------------------------------------------

    cols = [
        "cluster_label",
        "n_authors",

        "keep_auto",
        "keep",
        "auto_reason",

        "lab_margin",

        "bench_hits",
        "bench_score",

        "bio_hits",
        "bio_score",

        "clinical_hits",
        "clinical_score",

        "anti_hits",
        "anti_score",

        "nonlab_score",

        "matched_bench",
        "matched_bio",
        "matched_clinical",
        "matched_anti",

        "top_terms",
    ]

    agg = agg[cols]

    if not manual:

        agg.to_csv(
            work_csv,
            index=False,
        )

        print(
            "Saved worksheet "
            "(edit only the `keep` column for overrides): "
            f"{work_csv}"
        )

    # ------------------------------------------------------------------
    # Produce author-level life-science-lab mask
    # ------------------------------------------------------------------

    keep_clusters = set(
        agg.loc[
            agg["keep"] == 1,
            "cluster_label",
        ]
    )

    df_keep = (
        df[
            df["cluster_label"].isin(
                keep_clusters
            )
        ][
            ["athr_id", "cluster_label"]
        ]
        .copy()
    )

    df_keep.to_csv(
        out_authors,
        index=False,
    )

    n_dropped = (
        len(df) - len(df_keep)
    )

    print(
        f"Saved {out_authors}\n"
        f"  kept authors:   {len(df_keep):,}\n"
        f"  dropped authors:{n_dropped:>10,}\n"
        f"  kept clusters:  {len(keep_clusters):,}\n"
        f"  dropped clusters:"
        f"{len(cluster_ids) - len(keep_clusters):>7,}"
    )

    # ------------------------------------------------------------------
    # Audit
    # ------------------------------------------------------------------

    with open(
        audit_txt,
        "w",
        encoding="utf-8",
    ) as f:

        f.write(
            f"LIFE-SCIENCE LAB CLUSTER FILTER\n"
            f"K={args.k}\n"
            f"min_bench={args.min_bench}\n"
            f"min_bench_score={args.min_bench_score}\n"
            f"dominance_ratio={args.dominance_ratio}\n"
            f"keep_flags="
            f"{'MANUAL' if manual else 'HEURISTIC'}\n\n"
        )

        f.write(
            f"Total authors: {len(df):,}\n"
        )

        f.write(
            f"Kept authors: {len(df_keep):,}\n"
        )

        f.write(
            f"Dropped authors: {n_dropped:,}\n"
        )

        f.write(
            f"Kept clusters: "
            f"{(agg['keep'] == 1).sum():,}\n"
        )

        f.write(
            f"Dropped clusters: "
            f"{(agg['keep'] == 0).sum():,}\n\n"
        )

        for status, sub in [

            (
                "KEPT",
                agg[agg["keep"] == 1],
            ),

            (
                "DROPPED",
                agg[agg["keep"] == 0],
            ),

        ]:

            f.write(
                f"================ {status} ================\n\n"
            )

            for _, r in sub.iterrows():

                manual_tag = ""

                if r["keep"] != r["keep_auto"]:
                    manual_tag = " [MANUAL OVERRIDE]"

                f.write(
                    f"C{int(r['cluster_label']):3d}"
                    f"  n={int(r['n_authors']):>8,}"
                    f"  keep_auto={int(r['keep_auto'])}"
                    f"  reason={r['auto_reason']}"
                    f"{manual_tag}\n"
                )

                f.write(
                    f"    bench:"
                    f" {int(r['bench_hits'])} hits,"
                    f" score={r['bench_score']:.3f}\n"
                )

                f.write(
                    f"    bio:"
                    f" {int(r['bio_hits'])} hits,"
                    f" score={r['bio_score']:.3f}\n"
                )

                f.write(
                    f"    clinical:"
                    f" {int(r['clinical_hits'])} hits,"
                    f" score={r['clinical_score']:.3f}\n"
                )

                f.write(
                    f"    anti:"
                    f" {int(r['anti_hits'])} hits,"
                    f" score={r['anti_score']:.3f}\n"
                )

                f.write(
                    f"    lab margin:"
                    f" {r['lab_margin']:.3f}\n"
                )

                if r["matched_bench"]:
                    f.write(
                        f"    BENCH: {r['matched_bench']}\n"
                    )

                if r["matched_bio"]:
                    f.write(
                        f"    BIO: {r['matched_bio']}\n"
                    )

                if r["matched_clinical"]:
                    f.write(
                        f"    CLINICAL: "
                        f"{r['matched_clinical']}\n"
                    )

                if r["matched_anti"]:
                    f.write(
                        f"    ANTI: {r['matched_anti']}\n"
                    )

                f.write(
                    f"    TOP: {r['top_terms']}\n\n"
                )

    print(
        f"Saved {audit_txt}"
    )

    # ------------------------------------------------------------------
    # Borderline clusters for manual review
    # ------------------------------------------------------------------
    #
    # These deserve inspection:
    #
    # 1. Kept automatically but have meaningful clinical/anti evidence.
    # 2. Dropped despite having some bench evidence.
    #

    borderline = agg[
        (
            (agg["keep_auto"] == 1)
            & (agg["nonlab_score"] > 0)
        )
        |
        (
            (agg["keep_auto"] == 0)
            & (agg["bench_hits"] > 0)
        )
    ].copy()

    borderline = borderline.sort_values(
        ["lab_margin", "n_authors"],
        ascending=[True, False],
    )

    print(
        "\nBorderline clusters -- review these first:\n"
    )

    if borderline.empty:

        print("None.")

    else:

        print(
            borderline[
                [
                    "cluster_label",
                    "n_authors",
                    "keep_auto",
                    "auto_reason",
                    "bench_hits",
                    "bench_score",
                    "clinical_score",
                    "anti_score",
                    "lab_margin",
                    "top_terms",
                ]
            ].to_string(
                index=False
            )
        )


if __name__ == "__main__":
    main()