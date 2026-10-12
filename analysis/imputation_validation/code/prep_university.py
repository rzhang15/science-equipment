import hashlib
import json
from pathlib import Path

import pandas as pd


CODE_DIR = Path(__file__).resolve().parent
EXTERNAL_DIR = CODE_DIR.parent / "external"
TEMP_DIR = CODE_DIR.parent / "temp"


def main():
    ids = pd.read_csv(
        EXTERNAL_DIR / "exposure" / "foia_ids_ordered.csv",
        dtype={"athr_id": str},
    )[["athr_id"]]
    assert len(ids) == 208, "Expected the baseline bank of 208 FOIA donors"
    assert ids["athr_id"].is_unique, "FOIA donor IDs must be unique"

    records = []
    sources = []
    for path in sorted((EXTERNAL_DIR / "foias").glob("*_pi.dta")):
        donors = pd.read_stata(
            path, columns=["athr_id"], convert_categoricals=False
        )
        donors["athr_id"] = donors["athr_id"].astype(str)
        donors = donors.loc[donors["athr_id"].isin(ids["athr_id"])].drop_duplicates()
        donors["university"] = path.stem.removesuffix("_pi")
        records.append(donors)
        stat = path.stat()
        sources.append({
            "path": str(path.resolve()), "size": stat.st_size,
            "mtime_ns": stat.st_mtime_ns,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        })

    assert records, "No university PI mapping tables found in external/foias"
    university = pd.concat(records, ignore_index=True).drop_duplicates()
    university = university.groupby("athr_id", as_index=False).agg(
        university=("university", lambda x: ";".join(sorted(set(x)))),
        n_universities=("university", "nunique"),
    )
    university = ids.merge(university, on="athr_id", how="left", validate="one_to_one")
    uncovered = university.loc[university["university"].isna(), "athr_id"].tolist()
    assert not uncovered, f"Donor PIs without purchasing university: {uncovered}"
    university["n_universities"] = university["n_universities"].astype("int16")
    university["university_multi"] = (university["n_universities"] > 1).astype("int8")

    TEMP_DIR.mkdir(parents=True, exist_ok=True)
    university.to_csv(TEMP_DIR / "foia_university.csv", index=False)
    university.to_stata(
        TEMP_DIR / "foia_university.dta", write_index=False, version=118
    )
    (TEMP_DIR / "university_sources.json").write_text(
        json.dumps(sources, indent=2) + "\n"
    )
    print(
        f"Purchasing university metadata: {len(university)} FOIA PIs; "
        f"{university['university_multi'].sum()} PI linked to multiple universities"
    )


if __name__ == "__main__":
    main()
