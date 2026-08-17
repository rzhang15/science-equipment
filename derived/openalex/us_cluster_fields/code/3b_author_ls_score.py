"""
Author-level life-science lab mask.

Applies the four lexicon classes defined in 3_filter_life_science.py to each
author's full TF-IDF vector:

    BENCH_CORE
    BIO_CONTEXT
    CLINICAL_PRACTICE
    ANTI_LEXICON

Cluster membership plays no role.

Why author-level scoring differs from cluster scoring
-----------------------------------------------------
Cluster centroids summarize tens of thousands of authors, so generic bench
vocabulary can surface among the cluster's top terms. Individual author TF-IDF
vectors instead emphasize rare/discriminating stems, and many ubiquitous bench
terms (e.g. cell, dna, protein, enzym, antibodi, antigen) are absent from the
vocabulary entirely because 1_vectorize.py drops terms appearing in >10% of
documents.

Therefore the cluster rule should NOT be transplanted verbatim to authors.

At author level:

  * evidence is measured as TF-IDF MASS over the author's full vector;
  * any BENCH_CORE mass counts as positive bench evidence;
  * BIO_CONTEXT mass >= --min-bio-shr can carry an author when direct bench
    evidence is absent;
  * clinical + anti mass cannot dominate positive biological evidence.

Default keep rule
-----------------
evidence:
    BENCH_CORE mass > 0
    OR BIO_CONTEXT mass >= --min-bio-shr

dominance:
    (CLINICAL_PRACTICE + ANTI_LEXICON) mass
        <= --dominance-ratio * (BENCH_CORE + BIO_CONTEXT) mass

keep:
    evidence AND not dominated AND non-empty TF-IDF row

The default rule is calibrated for identifying authors plausibly doing
life-science research in a lab while compensating for the upstream max_df
vocabulary truncation.

--require-bench removes the BIO_CONTEXT rescue and requires observed
BENCH_CORE mass in the retained TF-IDF vocabulary. This is a stricter
lab-evidence specification, but it mechanically misses some known lab
researchers because common bench terms are removed upstream.

Inputs
------
../output/tfidf_matrix.npz
../output/feature_names.pkl
../output/author_ids_aligned.parquet

Outputs
-------
../output/author_ls_scores_indiv{suffix}.csv
../output/author_ls_authors_indiv{suffix}.csv
"""

import argparse
import importlib.util
import os
import pickle

import numpy as np
import pandas as pd
import scipy.sparse as sp


OUT_DIR = "../output"


# ---------------------------------------------------------------------
# Load taxonomy from cluster filter
# ---------------------------------------------------------------------

spec = importlib.util.spec_from_file_location(
    "ls_filter",
    os.path.join(
        os.path.dirname(os.path.abspath(__file__)),
        "3_filter_life_science.py",
    ),
)

ls_filter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ls_filter)


REQUIRED_OBJECTS = {
    "BENCH_CORE",
    "BIO_CONTEXT",
    "CLINICAL_PRACTICE",
    "ANTI_LEXICON",
    "term_tokens",
}

missing = [
    name
    for name in REQUIRED_OBJECTS
    if not hasattr(ls_filter, name)
]

if missing:
    raise ImportError(
        "3_filter_life_science.py is missing required objects: "
        + ", ".join(sorted(missing))
    )


# ---------------------------------------------------------------------
# Vocabulary classification
# ---------------------------------------------------------------------

def classify_vocab(feature_names):
    """
    Flag each TF-IDF feature under the four lexicons.

    Classes are evaluated independently, matching the taxonomy used in
    3_filter_life_science.py.
    """

    def flag(lexicon):
        return np.array(
            [
                any(
                    tok in lexicon
                    for tok in ls_filter.term_tokens(term)
                )
                for term in feature_names
            ],
            dtype=bool,
        )

    return (
        flag(ls_filter.BENCH_CORE),
        flag(ls_filter.BIO_CONTEXT),
        flag(ls_filter.CLINICAL_PRACTICE),
        flag(ls_filter.ANTI_LEXICON),
    )


def top_term_hits(M, flags, k_top):
    """
    Count class matches among each author's top-k TF-IDF features.

    These columns are diagnostic only. The keep rule uses full-vector mass.
    """

    n = M.shape[0]

    out = [
        np.zeros(n, dtype=np.int16)
        for _ in flags
    ]

    indptr = M.indptr
    indices = M.indices
    data = M.data

    for i in range(n):

        lo = indptr[i]
        hi = indptr[i + 1]
        nnz = hi - lo

        if nnz == 0:
            continue

        if nnz > k_top:

            local_data = data[lo:hi]

            sel = np.argpartition(
                local_data,
                nnz - k_top,
            )[nnz - k_top:]

            cols = indices[lo + sel]

        else:

            cols = indices[lo:hi]

        for arr, feature_flag in zip(out, flags):
            arr[i] = int(
                feature_flag[cols].sum()
            )

    return out


# ---------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------

def main():

    ap = argparse.ArgumentParser()

    ap.add_argument(
        "--top-terms",
        type=int,
        default=15,
        help=(
            "Number of each author's highest-TF-IDF features used for "
            "diagnostic hit counts. The keep rule itself uses full-vector "
            "mass."
        ),
    )

    ap.add_argument(
        "--min-bio-shr",
        type=float,
        default=0.01,
        help=(
            "Minimum BIO_CONTEXT TF-IDF mass share that can carry an author "
            "with no observed BENCH_CORE mass. Default=0.01."
        ),
    )

    ap.add_argument(
        "--dominance-ratio",
        type=float,
        default=1.0,
        help=(
            "Drop when clinical + anti mass exceeds this multiple of "
            "bench + bio mass. Default=1.0."
        ),
    )

    ap.add_argument(
        "--require-bench",
        action="store_true",
        help=(
            "Require observed BENCH_CORE mass in the retained TF-IDF "
            "vocabulary, dropping the BIO_CONTEXT rescue clause. This is a "
            "stricter lab-evidence specification, but mechanically misses "
            "some known lab researchers because common bench terms are "
            "removed upstream by max_df. Pair with --out-sfx."
        ),
    )

    ap.add_argument(
        "--always-keep",
        default="",
        help=(
            "CSV containing an athr_id column. These authors are retained "
            "regardless of the automatic rule, except authors with empty "
            "TF-IDF rows. Useful for an anchor roster."
        ),
    )

    ap.add_argument(
        "--out-sfx",
        default="",
        help=(
            "Suffix for output files. Example: '_bench' writes "
            "author_ls_scores_indiv_bench.csv and "
            "author_ls_authors_indiv_bench.csv."
        ),
    )

    args = ap.parse_args()


    # ------------------------------------------------------------------
    # Validate arguments
    # ------------------------------------------------------------------

    if args.top_terms <= 0:
        raise ValueError("--top-terms must be > 0")

    if args.min_bio_shr < 0:
        raise ValueError("--min-bio-shr must be >= 0")

    if args.dominance_ratio < 0:
        raise ValueError("--dominance-ratio must be >= 0")


    # ------------------------------------------------------------------
    # Load TF-IDF artifacts
    # ------------------------------------------------------------------

    matrix_path = f"{OUT_DIR}/tfidf_matrix.npz"
    features_path = f"{OUT_DIR}/feature_names.pkl"
    ids_path = f"{OUT_DIR}/author_ids_aligned.parquet"

    for path in (
        matrix_path,
        features_path,
        ids_path,
    ):
        if not os.path.exists(path):
            raise FileNotFoundError(
                f"Missing required input: {path}"
            )

    print("Loading TF-IDF artifacts ...")

    M = sp.load_npz(
        matrix_path
    ).tocsr()

    with open(
        features_path,
        "rb",
    ) as f:
        feature_names = pickle.load(f)

    ids = pd.read_parquet(
        ids_path
    )

    if "athr_id" not in ids.columns:
        raise ValueError(
            f"{ids_path} must contain athr_id"
        )

    ids["athr_id"] = (
        ids["athr_id"]
        .astype(str)
    )

    if M.shape[0] != len(ids):
        raise ValueError(
            "TF-IDF row count does not match aligned author IDs: "
            f"{M.shape[0]:,} vs {len(ids):,}"
        )

    if M.shape[1] != len(feature_names):
        raise ValueError(
            "TF-IDF column count does not match feature_names: "
            f"{M.shape[1]:,} vs {len(feature_names):,}"
        )

    print(
        f"  matrix {M.shape[0]:,} x {M.shape[1]:,}"
        f"  nnz {M.nnz:,}"
    )


    # ------------------------------------------------------------------
    # Classify vocabulary
    # ------------------------------------------------------------------

    (
        is_bench,
        is_bio,
        is_clin,
        is_anti,
    ) = classify_vocab(
        feature_names
    )

    print(
        "  vocab features flagged:"
        f" bench={is_bench.sum():,}"
        f"  bio={is_bio.sum():,}"
        f"  clin={is_clin.sum():,}"
        f"  anti={is_anti.sum():,}"
        f"  of {len(feature_names):,}"
    )


    # ------------------------------------------------------------------
    # Full-vector TF-IDF mass shares
    # ------------------------------------------------------------------

    tot_mass = np.asarray(
        M.sum(axis=1)
    ).ravel()

    empty = (
        tot_mass <= 0
    )

    safe_tot = np.maximum(
        tot_mass,
        1e-12,
    )

    def share(flag):

        matched_mass = np.asarray(
            M @ flag.astype(np.float64)
        ).ravel()

        return (
            matched_mass
            / safe_tot
        )


    bench_shr = share(
        is_bench
    )

    bio_shr = share(
        is_bio
    )

    clin_shr = share(
        is_clin
    )

    anti_shr = share(
        is_anti
    )

    positive_shr = (
        bench_shr
        + bio_shr
    )

    nonlab_shr = (
        clin_shr
        + anti_shr
    )

    lab_margin = (
        positive_shr
        - nonlab_shr
    )


    # ------------------------------------------------------------------
    # Diagnostic top-term hits
    # ------------------------------------------------------------------

    print(
        f"Counting top {args.top_terms} "
        "terms per author ..."
    )

    (
        bench_hits,
        bio_hits,
        clin_hits,
        anti_hits,
    ) = top_term_hits(
        M,
        [
            is_bench,
            is_bio,
            is_clin,
            is_anti,
        ],
        args.top_terms,
    )


    # ------------------------------------------------------------------
    # Evidence rule
    # ------------------------------------------------------------------

    has_bench = (
        bench_shr > 0
    )

    if args.min_bio_shr > 0:

        has_bio = (
            bio_shr
            >= args.min_bio_shr
        )

    else:

        has_bio = np.zeros(
            len(ids),
            dtype=bool,
        )

    bio_only = (
        has_bio
        & ~has_bench
    )

    if args.require_bench:

        evidence = (
            has_bench
        )

    else:

        evidence = (
            has_bench
            | has_bio
        )


    # ------------------------------------------------------------------
    # Dominance rule
    # ------------------------------------------------------------------

    dominated = (
        nonlab_shr
        > args.dominance_ratio
        * positive_shr
    )


    # ------------------------------------------------------------------
    # Automatic classification
    # ------------------------------------------------------------------

    auto_keep = (
        evidence
        & ~dominated
        & ~empty
    )

    keep = (
        auto_keep.copy()
    )


    # ------------------------------------------------------------------
    # Diagnostics
    # ------------------------------------------------------------------

    print(
        f"  evidence: bench mass "
        f"{has_bench.sum():,}"
        + (
            ""
            if args.require_bench
            else (
                f", bio-context only "
                f"{bio_only.sum():,}"
            )
        )
    )

    print(
        "  nonlab dominance cut "
        f"{(evidence & dominated & ~empty).sum():,}"
    )


    # ------------------------------------------------------------------
    # Classification reason
    # ------------------------------------------------------------------

    route = np.full(
        len(ids),
        "DROP_NO_EVIDENCE",
        dtype=object,
    )

    route[
        empty
    ] = "DROP_EMPTY"

    route[
        evidence
        & dominated
        & ~empty
    ] = "DROP_NONLAB_DOMINATES"

    route[
        auto_keep
        & has_bench
    ] = "KEEP_BENCH"

    route[
        auto_keep
        & ~has_bench
        & has_bio
    ] = "KEEP_BIO_CONTEXT"


    # ------------------------------------------------------------------
    # Optional always-keep roster
    # ------------------------------------------------------------------

    forced = np.zeros(
        len(ids),
        dtype=bool,
    )

    if args.always_keep:

        if not os.path.exists(
            args.always_keep
        ):
            raise FileNotFoundError(
                f"--always-keep file not found: "
                f"{args.always_keep}"
            )

        ak_df = pd.read_csv(
            args.always_keep,
            dtype={"athr_id": str},
        )

        if "athr_id" not in ak_df.columns:
            raise ValueError(
                "--always-keep CSV must contain athr_id"
            )

        ak = set(
            ak_df["athr_id"]
            .astype(str)
        )

        forced = (
            ids["athr_id"]
            .isin(ak)
            .to_numpy()
            & ~keep
            & ~empty
        )

        keep |= forced

        route[
            forced
        ] = "KEEP_FORCED"

        print(
            f"  always-keep list ({args.always_keep}): "
            f"{len(ak):,} ids, "
            f"{forced.sum():,} force-kept beyond the rule"
        )


    # ------------------------------------------------------------------
    # Final summary
    # ------------------------------------------------------------------

    print(
        f"  kept {keep.sum():,}/{len(ids):,} authors "
        f"({keep.mean():.1%})"
    )

    print(
        f"  dropped {(~keep).sum():,}, "
        f"of which {empty.sum():,} empty rows"
    )

    if not args.require_bench:

        print(
            f"  kept via BIO_CONTEXT alone: "
            f"{(auto_keep & bio_only).sum():,}"
        )


    # ------------------------------------------------------------------
    # Save scores
    # ------------------------------------------------------------------

    scores = pd.DataFrame({

        "athr_id":
            ids["athr_id"],

        # Top-term diagnostics
        "bench_hits":
            bench_hits,

        "bio_hits":
            bio_hits,

        "clin_hits":
            clin_hits,

        "anti_hits":
            anti_hits,

        # Continuous TF-IDF mass shares
        "bench_shr":
            bench_shr,

        "bio_shr":
            bio_shr,

        "clin_shr":
            clin_shr,

        "anti_shr":
            anti_shr,

        "positive_shr":
            positive_shr,

        "nonlab_shr":
            nonlab_shr,

        "lab_margin":
            lab_margin,

        # Rule components
        "has_bench":
            has_bench.astype(int),

        "has_bio_context":
            has_bio.astype(int),

        "bio_only":
            bio_only.astype(int),

        "dominated":
            dominated.astype(int),

        "auto_keep":
            auto_keep.astype(int),

        "keep":
            keep.astype(int),

        "forced":
            forced.astype(int),

        "route":
            route,
    })


    # ------------------------------------------------------------------
    # Write outputs
    # ------------------------------------------------------------------

    sfx = args.out_sfx

    scores_path = (
        f"{OUT_DIR}/"
        f"author_ls_scores_indiv{sfx}.csv"
    )

    authors_path = (
        f"{OUT_DIR}/"
        f"author_ls_authors_indiv{sfx}.csv"
    )

    scores.to_csv(
        scores_path,
        index=False,
    )

    scores.loc[
        scores["keep"] == 1,
        ["athr_id"],
    ].to_csv(
        authors_path,
        index=False,
    )

    print(
        f"Saved {scores_path}"
    )

    print(
        f"Saved {authors_path}"
    )


    # ------------------------------------------------------------------
    # Classification-route summary
    # ------------------------------------------------------------------

    print(
        "\nClassification routes:"
    )

    route_tab = (
        scores["route"]
        .value_counts()
        .rename_axis("route")
        .to_frame("n")
    )

    route_tab["share"] = (
        route_tab["n"]
        / len(scores)
    )

    print(
        route_tab
        .assign(
            share=lambda x:
            x["share"].map(
                lambda v: f"{v:.1%}"
            )
        )
        .to_string()
    )


    # ------------------------------------------------------------------
    # Cluster diagnostics
    # ------------------------------------------------------------------

    cl_path = (
        f"{OUT_DIR}/"
        "author_static_clusters_30.csv"
    )

    ls_path = (
        f"{OUT_DIR}/"
        "author_static_clusters_30_ls.csv"
    )

    if os.path.exists(
        cl_path
    ):

        cl = pd.read_csv(
            cl_path,
            dtype={
                "athr_id": str,
                "cluster_label": int,
            },
        )

        m = scores.merge(
            cl[
                [
                    "athr_id",
                    "cluster_label",
                ]
            ],
            on="athr_id",
            how="left",
        )

        tab = (
            m
            .groupby(
                "cluster_label",
                dropna=False,
            )
            .agg(
                keep_rate=(
                    "keep",
                    "mean",
                ),
                bench_rate=(
                    "has_bench",
                    "mean",
                ),
                bio_only_rate=(
                    "bio_only",
                    "mean",
                ),
                dominated_rate=(
                    "dominated",
                    "mean",
                ),
                mean_bench_shr=(
                    "bench_shr",
                    "mean",
                ),
                mean_bio_shr=(
                    "bio_shr",
                    "mean",
                ),
                mean_nonlab_shr=(
                    "nonlab_shr",
                    "mean",
                ),
                n=(
                    "athr_id",
                    "size",
                ),
            )
        )

        print(
            "\nAuthor-level keep rate "
            "by K=30 cluster:"
        )

        print(
            tab
            .round(4)
            .to_string()
        )


    # ------------------------------------------------------------------
    # Agreement with cluster mask
    # ------------------------------------------------------------------

    if os.path.exists(
        ls_path
    ):

        ls = set(
            pd.read_csv(
                ls_path,
                dtype={"athr_id": str},
            )["athr_id"]
            .astype(str)
        )

        in_cluster_mask = (
            scores["athr_id"]
            .isin(ls)
            .to_numpy()
        )

        author_keep = (
            scores["keep"]
            .astype(bool)
            .to_numpy()
        )

        agree = (
            author_keep
            == in_cluster_mask
        ).mean()

        print(
            "\nAgreement with cluster-level "
            f"_ls mask: {agree:.1%}"
        )

        print(
            "  kept here but cluster-dropped: "
            f"{(author_keep & ~in_cluster_mask).sum():,}"
        )

        print(
            "  dropped here but cluster-kept: "
            f"{(~author_keep & in_cluster_mask).sum():,}"
        )


if __name__ == "__main__":
    main()