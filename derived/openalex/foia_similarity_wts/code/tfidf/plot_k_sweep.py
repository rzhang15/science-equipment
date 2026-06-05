"""
Plot coauthor-validation metrics (corr, MAE) across the K sweep to visually
justify the K choice. Reads the per-K summary files we just generated under
output/coauthor_validation_summary_tfidf_restricted_k{K}.txt.

Run:
  python3 plot_k_sweep.py
Output:
  ../../output/figures/k_sweep_validation.pdf
"""
import os
import re
import matplotlib.pyplot as plt

OUT_DIR = "../../output"
FIG_DIR = f"{OUT_DIR}/figures"
os.makedirs(FIG_DIR, exist_ok=True)

KS = [1, 3, 5, 10, 20]


def parse(k):
    f = f"{OUT_DIR}/coauthor_validation_summary_tfidf_restricted_k{k}.txt"
    if not os.path.exists(f):
        raise FileNotFoundError(f"Missing: {f}. Run the K sweep first.")
    with open(f) as fh:
        text = fh.read()
    corr = float(re.search(r"corr\(imputed_coauthor_exposure, true_FOIA_exposure\):\s+([\d.]+)", text).group(1))
    mae_paired = float(re.search(r"MAE \(true coauthor pairing\):\s+([\d.]+)", text).group(1))
    mae_random = float(re.search(r"MAE \(random FOIA reshuffled\):\s+([\d.]+)", text).group(1))
    return corr, mae_paired, mae_random


corr_vals, mae_paired, mae_random = zip(*[parse(k) for k in KS])

fig, axes = plt.subplots(1, 2, figsize=(12, 5))

# --- Correlation panel ---
ax = axes[0]
ax.plot(KS, corr_vals, "o-", color="C0", linewidth=2, markersize=10)
best_k = KS[corr_vals.index(max(corr_vals))]
ax.axvline(best_k, color="red", linestyle="--", alpha=0.5, label=f"best: K={best_k}")
for k, c in zip(KS, corr_vals):
    ax.annotate(f"{c:.4f}", (k, c), textcoords="offset points",
                xytext=(0, 10), ha="center", fontsize=9)
ax.set_xscale("log")
ax.set_xticks(KS)
ax.set_xticklabels(KS)
ax.set_xlabel("K (number of nearest FOIA neighbors)")
ax.set_ylabel("Correlation: imputed vs. true exposure")
ax.set_title("Imputation accuracy by K (higher is better)")
ax.legend()
ax.grid(alpha=0.3)

# --- MAE panel ---
ax = axes[1]
ax.plot(KS, mae_paired, "o-", color="C0", linewidth=2, markersize=10, label="paired (truth)")
ax.plot(KS, mae_random, "s--", color="gray", linewidth=1.5, markersize=8, label="random benchmark")
# Highlight the gap = signal over noise
for k, mp, mr in zip(KS, mae_paired, mae_random):
    ax.annotate(f"{mp:.4f}", (k, mp), textcoords="offset points",
                xytext=(0, -15), ha="center", fontsize=9)
ax.axvline(5, color="red", linestyle="--", alpha=0.5, label="chosen K=5")
ax.set_xscale("log")
ax.set_xticks(KS)
ax.set_xticklabels(KS)
ax.set_xlabel("K (number of nearest FOIA neighbors)")
ax.set_ylabel("MAE: |imputed - true exposure|")
ax.set_title("Prediction error by K (lower is better)")
ax.legend()
ax.grid(alpha=0.3)

plt.suptitle("Coauthor validation: choosing K\n"
             "(predict each coauthor's exposure from text-similar FOIAs; "
             "compare against their actual FOIA partner's true exposure)",
             y=1.02, fontsize=11)
plt.tight_layout()

out = f"{FIG_DIR}/k_sweep_validation.pdf"
plt.savefig(out, bbox_inches="tight")
print(f"Saved {out}")
