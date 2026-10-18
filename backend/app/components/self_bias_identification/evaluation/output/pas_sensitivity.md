# PAS weight sensitivity

Dataset: `bias_dataset_v2.csv` (2500 entries)

## 1. Mean PAS per bias type (current weights)

| Bias type | n | Mean PAS |
|---|---|---|
| accurate_perception | 516 | 91.2 |
| context_mismatch | 482 | 62.0 |
| focus_mismatch | 494 | 65.3 |
| productivity_overestimation | 521 | 49.2 |
| stress_underestimation | 487 | 66.4 |

## 2. Alternative weightings vs current

| Scheme | Spearman rho | Same level |
|---|---|---|
| Equal weights | 0.948 | 82.2% |
| Drop duration | 0.905 | 80.2% |
| Drop focus | 0.952 | 77.6% |
| Drop activity | 0.899 | 73.0% |
| Drop location | 0.970 | 75.5% |
| Drop calendar | 0.986 | 90.9% |
| Drop stress | 0.977 | 82.1% |

## 3. Each weight changed by +/-50% (renormalised)

| Weight | Change | Spearman rho | Same level |
|---|---|---|---|
| duration | x0.5 | 0.983 | 92.1% |
| duration | x1.5 | 0.995 | 92.4% |
| focus | x0.5 | 0.986 | 91.6% |
| focus | x1.5 | 0.988 | 90.2% |
| activity | x0.5 | 0.986 | 89.0% |
| activity | x1.5 | 0.998 | 90.7% |
| location | x0.5 | 0.991 | 88.8% |
| location | x1.5 | 0.991 | 90.5% |
| calendar | x0.5 | 0.997 | 95.2% |
| calendar | x1.5 | 0.997 | 95.6% |
| stress | x0.5 | 0.994 | 91.6% |
| stress | x1.5 | 0.994 | 93.5% |

## 4. 2,000 random weight vectors (Dirichlet around current weights)

- Spearman rho: median 0.973, 5th percentile 0.900
- Same level: median 84.2%, 5th percentile 70.8%

## 5. Hand-picked vs data-learned weights

Logistic regression separating accurate_perception from every biased entry, coefficients clipped at 0 and normalised.

| Component | Hand-picked | Learned |
|---|---|---|
| duration | 0.27 | 0.21 |
| focus | 0.23 | 0.33 |
| activity | 0.18 | 0.06 |
| location | 0.14 | 0.18 |
| calendar | 0.09 | 0.01 |
| stress | 0.10 | 0.21 |

Learned weights vs current: Spearman rho 0.900, same level 80.2%.
