"""How sensitive is the PAS score to its hand-picked weights?

Run:  python pas_sensitivity.py [path/to/bias_dataset.csv]

Reports, on the dataset's entries:
  1. Face validity: mean PAS per bias type under the current weights.
  2. Equal weights and drop-one-component comparisons.
  3. +/-50% perturbation of each weight (renormalised to sum to 1).
  4. 2,000 random weight vectors drawn around the current weights.
  5. Weights learned from the data (logistic regression, accurate vs biased)
     next to the hand-picked ones.

PAS has six components (duration, focus, activity, location, calendar, stress).
Rank correlation (Spearman) says whether entries stay in the same order;
level agreement says how often an entry keeps the same PAS level label.
The default dataset is SYNTHETIC, so these numbers show robustness of the
formula, not real-world validity.
"""
import importlib.util
import pathlib
import sys

import numpy as np
import pandas as pd
from scipy.stats import spearmanr

HERE = pathlib.Path(__file__).resolve().parent
COMP = HERE.parent
DEFAULT_CSV = COMP / "synthetic_data" / "output" / "bias_dataset_v2.csv"
OUT_DIR = HERE / "output"

# Load PASCalculator straight from its file: importing through the `app`
# package would pull in unrelated components.
spec = importlib.util.spec_from_file_location(
    "pas_calculator", COMP / "services" / "pas_calculator.py")
_mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(_mod)
PASCalculator = _mod.PASCalculator

NAMES = list(PASCalculator.WEIGHTS)
BASE_W = np.array([PASCalculator.WEIGHTS[n] for n in NAMES])
LEVELS = [(85, 0), (70, 1), (50, 2), (30, 3), (-1, 4)]  # same cut-offs as _get_level


def components(df: pd.DataFrame) -> np.ndarray:
    """The six 0-100 component scores, in WEIGHTS order, as PASCalculator.calculate()."""
    return np.column_stack([
        np.minimum(df["duration_match_ratio"] * 100, 100),
        df["focus_quality_score"] * 100,
        np.where(df["activity_match"] == 1, 100, 25),
        np.where(df["location_match"] == 1, 100, 30),
        np.where(df["calendar_match"] == 1, 100, 50),
        np.where(df["stress_mismatch"] == 1, 30, 100),
    ])


def level(scores: np.ndarray) -> np.ndarray:
    out = np.full(scores.shape, 4)
    for cut, idx in reversed(LEVELS):
        out = np.where(np.round(scores) >= cut, idx, out)
    return out


def pas(comp: np.ndarray, w: np.ndarray) -> np.ndarray:
    return comp @ (w / w.sum())


def compare(base: np.ndarray, other: np.ndarray) -> tuple[float, float]:
    rho = spearmanr(base, other).statistic
    agree = float(np.mean(level(base) == level(other)))
    return float(rho), agree


def main() -> None:
    csv = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_CSV
    df = pd.read_csv(csv)
    comp = components(df)
    base = pas(comp, BASE_W)
    OUT_DIR.mkdir(exist_ok=True)
    lines = [f"# PAS weight sensitivity\n\nDataset: `{csv.name}` ({len(df)} entries)\n"]

    # 1. Face validity
    lines.append("## 1. Mean PAS per bias type (current weights)\n")
    lines.append("| Bias type | n | Mean PAS |\n|---|---|---|")
    for bt, grp in df.assign(pas=base).groupby("bias_type"):
        lines.append(f"| {bt} | {len(grp)} | {grp['pas'].mean():.1f} |")

    # 2. Alternative weightings
    lines.append("\n## 2. Alternative weightings vs current\n")
    lines.append("| Scheme | Spearman rho | Same level |\n|---|---|---|")
    schemes = {"Equal weights": np.ones(len(NAMES)) / len(NAMES)}
    for i, n in enumerate(NAMES):
        w = BASE_W.copy(); w[i] = 0
        schemes[f"Drop {n}"] = w
    for name, w in schemes.items():
        rho, agree = compare(base, pas(comp, w))
        lines.append(f"| {name} | {rho:.3f} | {agree:.1%} |")

    # 3. +/-50% on each weight
    lines.append("\n## 3. Each weight changed by +/-50% (renormalised)\n")
    lines.append("| Weight | Change | Spearman rho | Same level |\n|---|---|---|---|")
    for i, n in enumerate(NAMES):
        for factor in (0.5, 1.5):
            w = BASE_W.copy(); w[i] *= factor
            rho, agree = compare(base, pas(comp, w))
            lines.append(f"| {n} | x{factor} | {rho:.3f} | {agree:.1%} |")

    # 4. Random weights around the current ones
    rng = np.random.default_rng(42)
    rhos, agrees = [], []
    for w in rng.dirichlet(BASE_W * 30, size=2000):
        rho, agree = compare(base, pas(comp, w))
        rhos.append(rho); agrees.append(agree)
    lines.append("\n## 4. 2,000 random weight vectors (Dirichlet around current weights)\n")
    lines.append(f"- Spearman rho: median {np.median(rhos):.3f}, 5th percentile {np.percentile(rhos, 5):.3f}")
    lines.append(f"- Same level: median {np.median(agrees):.1%}, 5th percentile {np.percentile(agrees, 5):.1%}")

    # 5. Weights learned from data
    from sklearn.linear_model import LogisticRegression
    y = (df["bias_type"] == "accurate_perception").astype(int)
    if y.nunique() == 2:
        model = LogisticRegression(max_iter=2000).fit(comp / 100, y)
        coef = np.clip(model.coef_[0], 0, None)
        learned = coef / coef.sum() if coef.sum() > 0 else coef
        lines.append("\n## 5. Hand-picked vs data-learned weights\n")
        lines.append("Logistic regression separating accurate_perception from every biased "
                     "entry, coefficients clipped at 0 and normalised.\n")
        lines.append("| Component | Hand-picked | Learned |\n|---|---|---|")
        for n, b, l in zip(NAMES, BASE_W, learned):
            lines.append(f"| {n} | {b:.2f} | {l:.2f} |")
        rho, agree = compare(base, pas(comp, learned))
        lines.append(f"\nLearned weights vs current: Spearman rho {rho:.3f}, same level {agree:.1%}.")
    else:
        lines.append("\n## 5. Learned weights\n\nSkipped: dataset has no accurate_perception contrast.")

    report = "\n".join(lines) + "\n"
    (OUT_DIR / "pas_sensitivity.md").write_text(report, encoding="utf-8")
    print(report)
    print(f"Saved to {OUT_DIR / 'pas_sensitivity.md'}")


if __name__ == "__main__":
    main()
