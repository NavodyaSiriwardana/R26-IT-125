# ─────────────────────────────────────────────
# HTGPS ENGINE — HYBRID TEMPORAL GRAPH
#               PATTERN SCORING
# ─────────────────────────────────────────────
# Combines DFS + Louvain + FFT scores into
# one final confidence value using weighted
# formula. Weights are initial heuristics
# validated through ablation study.
# ─────────────────────────────────────────────

# HTGPS weights
# DFS gets highest weight (0.4) because
# temporal order is strongest causal evidence
DFS_WEIGHT     = 0.4
LOUVAIN_WEIGHT = 0.3
FFT_WEIGHT     = 0.3

# Pattern level thresholds
STRONG_THRESHOLD   = 0.75
MODERATE_THRESHOLD = 0.50


class HTGPSEngine:

    # ─────────────────────────────────────────
    # COMPUTE HTGPS SCORE
    # ─────────────────────────────────────────

    def compute(
        self,
        dfs_score    : float,
        louvain_score: float,
        fft_score    : float,
    ):
        """
        Apply HTGPS weighted formula:
        HTGPS = (0.4 × dfsScore)
              + (0.3 × louvainScore)
              + (0.3 × fftScore)

        All input scores must be 0-1.
        Returns htgpsScore and patternLevel.
        """
        htgps_score = (
            (DFS_WEIGHT     * dfs_score)     +
            (LOUVAIN_WEIGHT * louvain_score) +
            (FFT_WEIGHT     * fft_score)
        )

        htgps_score = round(htgps_score, 4)
        htgps_score = max(0.0, min(1.0, htgps_score))

        pattern_level = self._get_pattern_level(htgps_score)

        print(f"[HTGPSEngine] DFS={dfs_score} "
              f"Louvain={louvain_score} "
              f"FFT={fft_score} "
              f"HTGPS={htgps_score} "
              f"Level={pattern_level}")

        return {
            "htgpsScore"   : htgps_score,
            "patternLevel" : pattern_level,
            "dfsWeight"    : DFS_WEIGHT,
            "louvainWeight": LOUVAIN_WEIGHT,
            "fftWeight"    : FFT_WEIGHT,
        }

    # ─────────────────────────────────────────
    # GET PATTERN LEVEL
    # ─────────────────────────────────────────

    def _get_pattern_level(self, score: float):
        """
        Classify pattern strength:
        Strong   = htgpsScore >= 0.75
        Moderate = htgpsScore >= 0.50
        Weak     = htgpsScore < 0.50
        """
        if score >= STRONG_THRESHOLD:
            return "Strong"
        elif score >= MODERATE_THRESHOLD:
            return "Moderate"
        return "Weak"

    # ─────────────────────────────────────────
    # GENERATE ALGORITHM EXPLANATION
    # ─────────────────────────────────────────

    def generate_explanation(
        self,
        dfs_score    : float,
        louvain_score: float,
        fft_score    : float,
        dfs_result   : dict,
        louvain_result: dict,
        fft_result   : dict,
    ):
        """
        Generate plain English explanation
        for each algorithm score.
        This is the XAI output.
        """
        # DFS explanation
        confirmed = dfs_result.get("confirmed", 0)
        total     = dfs_result.get("totalTriggers", 0)
        ptype     = dfs_result.get("patternType", "same_entry")

        if ptype == "cross_entry":
            dfs_explanation = (
                f"Outcome confirmed in next diary entry "
                f"after trigger in {confirmed} of {total} cases "
                f"using temporal chain traversal."
            )
        else:
            dfs_explanation = (
                f"Outcome confirmed in same diary entry "
                f"as trigger in {confirmed} of {total} cases."
            )

        # Louvain explanation
        relation = louvain_result.get("clusterRelation", "unknown")
        relation_text = {
            "same_cluster"      : "Trigger and outcome belong to the same behavioral cluster.",
            "adjacent_cluster"  : "Trigger and outcome are in adjacent behavioral clusters.",
            "different_cluster" : "Trigger and outcome are in different behavioral clusters.",
            "not_found"         : "Concepts not found in graph — neutral score applied.",
            "unknown"           : "Cluster relationship could not be determined.",
        }
        louvain_explanation = relation_text.get(
            relation,
            "Cluster relationship unknown."
        )

        # FFT explanation
        method         = fft_result.get("method", "unknown")
        is_weekly      = fft_result.get("isWeeklyCycle", False)
        dominant_period = fft_result.get("dominantPeriod", 0)

        if method == "fft":
            if is_weekly:
                fft_explanation = (
                    f"Strong {dominant_period:.0f}-day weekly cycle detected. "
                    f"Pattern repeats consistently every week."
                )
            else:
                fft_explanation = (
                    f"No strong weekly cycle detected. "
                    f"Pattern dominant period is {dominant_period:.0f} days."
                )
        else:
            fft_explanation = (
                f"Weekly repetition analysis using count method. "
                f"Pattern shows {'regular' if is_weekly else 'irregular'} "
                f"weekly occurrence."
            )

        return {
            "dfsExplanation"    : dfs_explanation,
            "louvainExplanation": louvain_explanation,
            "fftExplanation"    : fft_explanation,
        }

    # ─────────────────────────────────────────
    # FULL HTGPS ANALYSIS — SINGLE PATTERN
    # ─────────────────────────────────────────

    def analyse_pattern(
        self,
        dfs_score    : float,
        louvain_score: float,
        fft_score    : float,
        dfs_result   : dict,
        louvain_result: dict,
        fft_result   : dict,
        base_pattern : dict,
    ):
        """
        Full HTGPS analysis for one pattern.
        Combines scores, generates explanation,
        updates pattern with PP2 fields.
        Returns enhanced pattern dict.
        """
        # Compute HTGPS score
        htgps_result = self.compute(
            dfs_score     = dfs_score,
            louvain_score = louvain_score,
            fft_score     = fft_score,
        )

        # Generate XAI explanations
        explanations = self.generate_explanation(
            dfs_score      = dfs_score,
            louvain_score  = louvain_score,
            fft_score      = fft_score,
            dfs_result     = dfs_result,
            louvain_result = louvain_result,
            fft_result     = fft_result,
        )

        # Merge evidence dates from both
        # PP1 baseline and DFS cross-entry
        base_dates = base_pattern.get("evidenceDates", [])
        dfs_dates  = dfs_result.get("evidenceDates", [])
        all_dates  = sorted(set(base_dates + dfs_dates))

        # Build enhanced pattern
        enhanced = {
            **base_pattern,
            "dfsScore"          : dfs_score,
            "louvainScore"      : louvain_score,
            "fftScore"          : fft_score,
            "htgpsScore"        : htgps_result["htgpsScore"],
            "patternLevel"      : htgps_result["patternLevel"],
            "dfsExplanation"    : explanations["dfsExplanation"],
            "louvainExplanation": explanations["louvainExplanation"],
            "fftExplanation"    : explanations["fftExplanation"],
            "evidenceDates"     : all_dates,
            "analysisVersion"   : "HTGPS_V4",
        }

        return enhanced


htgps_engine = HTGPSEngine()