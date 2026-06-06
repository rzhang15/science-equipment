"""
Map rf_athrs (full imputed-PI panel) to the cluster_fields K=100 clustering
and aggregate to the 5 broad fields used in the FOIA-PI breakdown.

Inputs:
  - process_foias/foia_expenditure/temp/rf_athrs.dta
  - openalex/cluster_fields/output/author_static_clusters_100.csv
  - openalex/foia_similarity_wts/output/foia_ids_ordered.csv

Output:
  - rf_athrs_field_shares_K100.csv   (broad-field shares, rf_athrs vs FOIA)
  - rf_athrs_cluster_shares_K100.csv (per-fine-cluster shares)
"""
import pandas as pd
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]  # .../sci_eq/derived
RF_ATHRS = ROOT / "process_foias/foia_expenditure/temp/rf_athrs.dta"
CLUSTER_DIR = ROOT / "openalex/cluster_fields/output"
FOIA_IDS = HERE.parents[1] / "output/foia_ids_ordered.csv"
OUT_DIR = HERE.parents[1] / "output"

FIELD_MAP = {
    "Molecular biology, biochemistry & structural biology":
        [52, 15, 22, 95, 29, 41, 92, 56, 82, 27, 40, 26, 62, 37, 60],
    "Clinical & translational medicine":
        [57, 75, 78, 77, 85, 7, 11, 72, 3, 18, 8, 53, 47, 80, 91, 45, 5, 83],
    "Microbiology, virology & infectious disease":
        [1, 66, 67, 32, 64, 84, 59],
    "Plant & environmental biology":
        [50, 58, 89],
    "Neuroscience":
        [43, 30, 90],
}


def load_top_terms_100():
    path = CLUSTER_DIR / "static_cluster_descriptions_100.txt"
    terms = {}
    for line in path.read_text().splitlines():
        if not line.startswith("Cluster"):
            continue
        cid, rest = line.split(":", 1)
        cid = cid.replace("Cluster", "").strip()
        cid = int(cid.split()[0])  # strip optional "(n=...)"
        terms[cid] = ", ".join(t.strip() for t in rest.split(",")[:8])
    return terms


def main():
    rf = pd.read_stata(RF_ATHRS)[["athr_id"]].drop_duplicates()
    foia = pd.read_csv(FOIA_IDS)[["athr_id"]].drop_duplicates()
    print(f"rf_athrs PIs:  {len(rf):,}")
    print(f"FOIA-only PIs: {len(foia):,}")

    cl = pd.read_csv(CLUSTER_DIR / "author_static_clusters_100.csv")
    terms = load_top_terms_100()

    rf_m = rf.merge(cl, on="athr_id", how="left")
    foia_m = foia.merge(cl, on="athr_id", how="left")
    print(
        f"rf_athrs unmatched: {rf_m['cluster_label'].isna().sum()}, "
        f"FOIA unmatched: {foia_m['cluster_label'].isna().sum()}"
    )

    cluster_to_field = {}
    for field, cids in FIELD_MAP.items():
        for c in cids:
            cluster_to_field[c] = field
    rf_m["field"] = rf_m["cluster_label"].map(cluster_to_field)
    foia_m["field"] = foia_m["cluster_label"].map(cluster_to_field)

    # ---- Broad-field roll-up (denominator = mapped authors only,
    #      to mirror how the FOIA percentages are constructed) ----
    rf_field = rf_m.dropna(subset=["field"])
    foia_field = foia_m.dropna(subset=["field"])

    field_tbl = pd.DataFrame({
        "rf_n": rf_field["field"].value_counts(),
        "rf_share": rf_field["field"].value_counts(normalize=True) * 100,
        "foia_n": foia_field["field"].value_counts(),
        "foia_share": foia_field["field"].value_counts(normalize=True) * 100,
    }).reindex(list(FIELD_MAP.keys())).fillna(0)
    field_tbl[["rf_n", "foia_n"]] = field_tbl[["rf_n", "foia_n"]].astype(int)
    field_tbl[["rf_share", "foia_share"]] = field_tbl[["rf_share", "foia_share"]].round(1)

    rf_total_mapped = field_tbl["rf_n"].sum()
    foia_total_mapped = field_tbl["foia_n"].sum()
    rf_total = len(rf_m)
    foia_total = len(foia_m)
    print()
    print(f"rf_athrs: {rf_total_mapped:,} of {rf_total:,} authors fall in mapped clusters "
          f"({100*rf_total_mapped/rf_total:.1f}%)")
    print(f"FOIA:     {foia_total_mapped:,} of {foia_total:,} authors fall in mapped clusters "
          f"({100*foia_total_mapped/foia_total:.1f}%)")
    print()
    print("=" * 90)
    print("Broad-field shares (denominator = authors in mapped clusters)")
    print("=" * 90)
    with pd.option_context("display.max_colwidth", 70, "display.width", 200):
        print(field_tbl)

    out_field = OUT_DIR / "rf_athrs_field_shares_K100.csv"
    field_tbl.to_csv(out_field)
    print(f"\n-> wrote {out_field}")

    # ---- Per-fine-cluster table for inspection ----
    rf_n = rf_m["cluster_label"].value_counts(dropna=True).rename("rf_n")
    foia_n = foia_m["cluster_label"].value_counts(dropna=True).rename("foia_n")
    cl_tbl = pd.concat([rf_n, foia_n], axis=1).fillna(0).astype(int)
    cl_tbl.index.name = "cluster"
    cl_tbl["rf_share"] = (cl_tbl["rf_n"] / rf_total * 100).round(2)
    cl_tbl["foia_share"] = (cl_tbl["foia_n"] / foia_total * 100).round(2)
    cl_tbl["field"] = cl_tbl.index.map(cluster_to_field).fillna("(unmapped)")
    cl_tbl["top_terms"] = cl_tbl.index.map(terms)
    cl_tbl = cl_tbl.sort_values(["field", "rf_n"], ascending=[True, False])
    out_cl = OUT_DIR / "rf_athrs_cluster_shares_K100.csv"
    cl_tbl[["field", "rf_n", "rf_share", "foia_n", "foia_share", "top_terms"]].to_csv(out_cl)
    print(f"-> wrote {out_cl}")


if __name__ == "__main__":
    main()
