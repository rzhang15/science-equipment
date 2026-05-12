"""
Leave-one-out validation for BERT-based FOIA similarity weights.

Mirrors loov.py but: (a) reads dense BERT validation weights produced by
gen_validation_wts_bert.py, and (b) reports the *best-K* correlation/R2/plot
rather than whichever K happened to be last in the loop.
"""
import argparse
import numpy as np
import pandas as pd
import scipy.sparse
import matplotlib.pyplot as plt
import seaborn as sns
from sklearn.metrics import r2_score


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default="allenai-specter",
                        help="Model tag matching gen_validation_wts_bert.py output.")
    parser.add_argument("--source-k", type=int, default=50,
                        help="K used when building validation_weights (cap on neighbors available).")
    parser.add_argument("--tag-suffix", default="",
                        help="Appended to model tag so variants don't clobber each other.")
    args = parser.parse_args()

    tag = args.model.replace("/", "_") + args.tag_suffix
    weights_file = f"../../output/validation_weights_bert_{tag}_k{args.source_k}.npz"
    foia_ids_file = f"../../output/foia_ids_ordered_bert_{tag}.csv"
    exposure_file = "../../external/exposure_wts/athr_exposure.dta"
    plot_file = f"../../output/validation_plot_bert_{tag}.png"

    print("--- BERT LOOV ---")
    W = scipy.sparse.load_npz(weights_file).toarray()  # (n_foia, n_foia)
    df_foia = pd.read_csv(foia_ids_file)
    df_exp = pd.read_stata(exposure_file)

    df_merged = pd.merge(df_foia, df_exp, on="athr_id", how="left")
    df_merged["exposure"] = df_merged["exposure"].fillna(0)
    E_actual = df_merged["exposure"].values
    n = len(E_actual)
    print(f"Aligned {n} authors. Weight shape: {W.shape}")

    # K sweep — cap at min(source_k, n-1) since gen_validation_wts_bert pre-filters.
    k_values = [k for k in [3, 5, 7, 10, 15, 20, 50, 100, n - 1] if k <= min(args.source_k, n - 1)]
    k_values = sorted(set(k_values))
    print(f"K sweep: {k_values}")

    results: dict[int, tuple[float, float, np.ndarray]] = {}
    for k in k_values:
        E_pred = np.zeros(n)
        for i in range(n):
            w = W[i].copy()
            w[i] = 0.0  # leave-one-out: zero self
            if k < n - 1:
                top_k = np.argpartition(w, -k)[-k:]
                mask = np.zeros_like(w, dtype=bool)
                mask[top_k] = True
                w[~mask] = 0.0
            s = w.sum()
            E_pred[i] = (w @ E_actual) / s if s > 0 else 0.0
        r = np.corrcoef(E_pred, E_actual)[0, 1]
        r2 = r2_score(E_actual, E_pred)
        results[k] = (r, r2, E_pred)
        print(f"K={k:>4} -> r={r:.4f}, R2={r2:.4f}")

    best_k = max(results, key=lambda k: results[k][0])
    best_r, best_r2, best_pred = results[best_k]
    print("-" * 40)
    print(f"BEST: K={best_k} -> r={best_r:.4f}, R2={best_r2:.4f}")
    print("-" * 40)

    plt.figure(figsize=(8, 6))
    sns.regplot(x=best_pred, y=E_actual,
                scatter_kws={"alpha": 0.6}, line_kws={"color": "red"})
    plt.title(f"BERT LOOV ({tag}, K={best_k})\nr={best_r:.3f}, R²={best_r2:.3f}, N={n}")
    plt.xlabel("Imputed Exposure (BERT cosine)")
    plt.ylabel("Actual Exposure")
    plt.grid(True, linestyle="--", alpha=0.5)
    plt.tight_layout()
    plt.savefig(plot_file)
    print(f"Plot: {plot_file}")


if __name__ == "__main__":
    main()
