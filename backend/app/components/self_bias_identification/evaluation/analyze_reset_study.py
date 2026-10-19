"""Analyse the Mood Reset study.

Run:  python analyze_reset_study.py study_resets.csv

Input: CSV from export_study_data.py with one row per Mood Reset:
  participant, condition (breathing|control), before_stress, after_stress,
  self_before, self_after   (stress values are 0-1 facial scores, self_* are 1-5)

Reports:
  A. Facial validity: Spearman correlation between the facial stress score and
     self-reported stress, over every before and after reading.
  B. Effect of the reset on the facial stress change (before - after), breathing
     vs control: per-condition summary, paired Wilcoxon over participants who
     did both conditions, Mann-Whitney over all resets, and Cohen's d.
  C. The same comparison on self-reported stress.

A positive change means stress went DOWN. Small samples give wide uncertainty,
so read the effect sizes and confidence intervals, not only the p-values.
"""
import pathlib
import sys

import numpy as np
import pandas as pd
from scipy.stats import mannwhitneyu, spearmanr, wilcoxon

def fmt_p(p: float) -> str:
    return "< 0.0001" if p < 0.0001 else f"= {p:.4f}"


NOISE = 0.05  # facial change below this is treated as "no change" in the summary


def cohens_d(a: np.ndarray, b: np.ndarray) -> float:
    if len(a) < 2 or len(b) < 2:
        return float("nan")
    pooled = np.sqrt(((len(a) - 1) * a.var(ddof=1) + (len(b) - 1) * b.var(ddof=1))
                     / (len(a) + len(b) - 2))
    return float((a.mean() - b.mean()) / pooled) if pooled > 0 else float("nan")


def boot_ci(x: np.ndarray, n: int = 5000, seed: int = 1) -> tuple[float, float]:
    if len(x) < 2:
        return float("nan"), float("nan")
    rng = np.random.default_rng(seed)
    means = rng.choice(x, size=(n, len(x)), replace=True).mean(axis=1)
    return float(np.percentile(means, 2.5)), float(np.percentile(means, 97.5))


def describe(name: str, x: np.ndarray, out: list) -> None:
    if len(x) == 0:
        out.append(f"- {name}: no data")
        return
    lo, hi = boot_ci(x)
    out.append(f"- {name}: n={len(x)}, mean change {x.mean():+.3f} "
               f"(95% CI {lo:+.3f} to {hi:+.3f})")


def compare_block(title: str, df: pd.DataFrame, col: str, out: list) -> None:
    out.append(f"\n### {title}\n")
    b = df.loc[df.condition == "breathing", col].dropna().to_numpy(float)
    c = df.loc[df.condition == "control", col].dropna().to_numpy(float)
    describe("Breathing", b, out)
    describe("Control (quiet rest)", c, out)
    if len(b) >= 2 and len(c) >= 2:
        u = mannwhitneyu(b, c, alternative="two-sided")
        out.append(f"- All resets, Mann-Whitney U: p {fmt_p(u.pvalue)}")
        out.append(f"- Effect size (Cohen's d, breathing - control): {cohens_d(b, c):+.2f}")

    per = (df.dropna(subset=[col]).groupby(["participant", "condition"])[col]
             .mean().unstack("condition"))
    if {"breathing", "control"} <= set(per.columns):
        both = per.dropna(subset=["breathing", "control"])
        if len(both) >= 5:
            diff = both["breathing"] - both["control"]
            if np.allclose(diff, 0):
                out.append("- Paired Wilcoxon: all differences are zero")
            else:
                w = wilcoxon(both["breathing"], both["control"])
                out.append(f"- Paired Wilcoxon over {len(both)} participants who did both "
                           f"conditions: p {fmt_p(w.pvalue)}")
        else:
            out.append(f"- Paired test skipped: only {len(both)} participants did both "
                       "conditions (need at least 5)")


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit("usage: python analyze_reset_study.py study_resets.csv")
    path = pathlib.Path(sys.argv[1])
    df = pd.read_csv(path)
    out = [f"# Mood Reset study analysis\n\nFile: `{path.name}`, {len(df)} resets, "
           f"{df.participant.nunique()} participants\n"]

    df["facial_change"] = df["before_stress"] - df["after_stress"]
    df["self_change"] = df["self_before"] - df["self_after"]

    # A. Facial validity
    pairs = pd.concat([
        df[["before_stress", "self_before"]].set_axis(["facial", "self"], axis=1),
        df[["after_stress", "self_after"]].set_axis(["facial", "self"], axis=1),
    ]).dropna()
    out.append("## A. Does the facial stress score track self-reported stress?\n")
    if len(pairs) >= 8:
        r = spearmanr(pairs["facial"], pairs["self"])
        out.append(f"- Spearman rho = {r.statistic:+.2f} (p {fmt_p(r.pvalue)}) over {len(pairs)} readings")
        out.append("- Interpretation guide: |rho| below 0.3 is weak, 0.3 to 0.5 moderate, above 0.5 strong")
    else:
        out.append(f"- Not enough paired readings yet ({len(pairs)}; need at least 8)")

    # B / C. Intervention effect
    out.append("\n## B. Did the reset change facial stress, versus quiet rest?")
    compare_block("Facial stress change (before - after, 0-1 scale)", df, "facial_change", out)
    out.append("\n## C. Did the reset change self-reported stress?")
    compare_block("Self-reported stress change (before - after, 1-5 scale)", df, "self_change", out)

    within = (df["facial_change"].abs() < NOISE).mean()
    out.append(f"\n**Measurement noise:** {within:.0%} of resets changed facial stress by "
               f"less than {NOISE:.2f}; treat differences of that size as noise.")

    report = "\n".join(out) + "\n"
    out_path = path.with_suffix(".analysis.md")
    out_path.write_text(report, encoding="utf-8")
    print(report)
    print(f"Saved to {out_path}")


if __name__ == "__main__":
    main()
