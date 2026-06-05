"""
Train a classifier mapping BERT embeddings -> buyer-cluster mixture.

This is the PRODUCTION model: trained on ALL FOIA authors (the rigorous
fold-aware NMF + classifier validation is in 4_validate.py).

  - Multinomial logistic regression on top-1 cluster (predict_proba gives mixture)
  - L2-regularized; small grid search over C via 5-fold accuracy

Output: ../output/classifier.pkl              (sklearn pipeline)
        ../output/classifier_train_report.txt
"""
import pickle
import numpy as np
import pandas as pd
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import GridSearchCV
from sklearn.preprocessing import StandardScaler
from sklearn.pipeline import Pipeline
import config as cfg


def load_aligned():
    """Return (BERT embeddings, top-1 cluster labels) aligned by athr_id."""
    emb = np.load(cfg.BERT_EMB)
    bert_ids = pd.read_csv(cfg.BERT_IDS, dtype={"athr_id": str})["athr_id"].tolist()

    auth = pd.read_csv(cfg.OUT / "buyer_authors.csv", dtype={"athr_id": str})
    bert_pos = {a: i for i, a in enumerate(bert_ids)}
    auth["bert_idx"] = auth["athr_id"].map(bert_pos)
    matched = auth.dropna(subset=["bert_idx"]).copy()
    matched["bert_idx"] = matched["bert_idx"].astype(int)
    print(f"FOIA authors with BERT embedding: {len(matched)} / {len(auth)}")

    X = emb[matched["bert_idx"].values]
    y = matched["top1_cluster"].values.astype(int)
    return X, y, matched["athr_id"].tolist()


def main():
    X, y, ids = load_aligned()
    print(f"X={X.shape}  y bins: {np.bincount(y, minlength=cfg.K)}")

    # Some buyer clusters may have <3 authors with BERT embeddings -> drop them
    # from training (classifier can't learn from too few examples). Authors whose
    # top-1 sits in a dropped cluster fall back to the closest remaining cluster
    # via predict_proba at scoring time.
    keep_classes = np.where(np.bincount(y, minlength=cfg.K) >= 3)[0]
    keep_mask = np.isin(y, keep_classes)
    print(f"keeping {len(keep_classes)}/{cfg.K} clusters with >=3 training authors "
          f"({keep_mask.sum()} / {len(y)} authors retained)")
    Xk, yk = X[keep_mask], y[keep_mask]

    pipe = Pipeline([
        ("scale", StandardScaler(with_mean=True, with_std=True)),
        ("lr", LogisticRegression(max_iter=2000,
                                  solver="lbfgs", class_weight="balanced",
                                  random_state=cfg.RNG_SEED)),
    ])

    grid = GridSearchCV(
        pipe,
        param_grid={"lr__C": [0.1, 0.3, 1.0, 3.0, 10.0]},
        cv=5, scoring="accuracy", n_jobs=-1,
    )
    grid.fit(Xk, yk)
    print(f"best C={grid.best_params_['lr__C']}, "
          f"5-fold accuracy={grid.best_score_:.3f} "
          f"(chance = {1/len(keep_classes):.3f})")

    with open(cfg.OUT / "classifier.pkl", "wb") as f:
        pickle.dump({"pipeline": grid.best_estimator_,
                     "classes_": grid.best_estimator_.classes_,
                     "kept_clusters": keep_classes.tolist(),
                     "K_total": cfg.K}, f)

    with open(cfg.OUT / "classifier_train_report.txt", "w") as f:
        f.write(f"N train authors: {len(yk)}\n")
        f.write(f"kept clusters: {keep_classes.tolist()}\n")
        f.write(f"best C: {grid.best_params_['lr__C']}\n")
        f.write(f"5-fold accuracy: {grid.best_score_:.4f}\n")
        f.write(f"chance: {1/len(keep_classes):.4f}\n")
        f.write("\n--- per-fold scores ---\n")
        for i, s in enumerate(grid.cv_results_['split0_test_score']):
            f.write(f"  C={grid.cv_results_['param_lr__C'][i]} -> {s:.3f}\n")


if __name__ == "__main__":
    main()
