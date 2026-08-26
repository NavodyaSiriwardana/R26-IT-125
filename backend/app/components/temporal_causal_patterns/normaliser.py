# ─────────────────────────────────────────────
# NORMALISER — SCORE NORMALISATION LAYER
# ─────────────────────────────────────────────
# All three algorithm scores must be
# confirmed as 0-1 floats before HTGPS.
# Without this the weighted sum is wrong.
# ─────────────────────────────────────────────


class Normaliser:

    # ─────────────────────────────────────────
    # NORMALISE DFS SCORE
    # ─────────────────────────────────────────

    def normalise_dfs(self, dfs_result: dict):
        """
        DFS score is already 0-1 ratio.
        confirmed / totalTriggers
        Just validate and clamp.
        """
        score = dfs_result.get("dfsScore", 0.0)

        try:
            score = float(score)
        except:
            score = 0.0

        # Clamp to 0-1
        score = max(0.0, min(1.0, score))

        if score < 0.0 or score > 1.0:
            print(f"[Normaliser] WARNING: DFS score {score} out of range")

        print(f"[Normaliser] DFS normalised: {score}")
        return round(score, 4)

    # ─────────────────────────────────────────
    # NORMALISE LOUVAIN SCORE
    # ─────────────────────────────────────────

    def normalise_louvain(self, louvain_result: dict):
        """
        Louvain returns cluster relation.
        Map to 0-1 scale:
          same_cluster      = 1.0
          adjacent_cluster  = 0.5
          different_cluster = 0.0
          not_found/unknown = 0.5 (neutral)
        """
        score    = louvain_result.get("louvainScore", 0.5)
        relation = louvain_result.get("clusterRelation", "unknown")

        # Map based on cluster relation
        mapping = {
            "same_cluster"      : 1.0,
            "adjacent_cluster"  : 0.5,
            "different_cluster" : 0.0,
            "not_found"         : 0.5,
            "unknown"           : 0.5,
        }

        if relation in mapping:
            score = mapping[relation]
        else:
            try:
                score = float(score)
                score = max(0.0, min(1.0, score))
            except:
                score = 0.5

        print(f"[Normaliser] Louvain normalised: {score} ({relation})")
        return round(score, 4)

    # ─────────────────────────────────────────
    # NORMALISE FFT SCORE
    # ─────────────────────────────────────────

    def normalise_fft(self, fft_result: dict):
        """
        FFT score is already normalised
        amplitude / max_amplitude → 0-1.
        Validate and clamp.
        """
        score  = fft_result.get("fftScore", 0.0)
        method = fft_result.get("method", "unknown")

        try:
            score = float(score)
        except:
            score = 0.0

        # Clamp to 0-1
        score = max(0.0, min(1.0, score))

        if score < 0.0 or score > 1.0:
            print(f"[Normaliser] WARNING: FFT score {score} out of range")

        print(f"[Normaliser] FFT normalised: {score} (method={method})")
        return round(score, 4)

    # ─────────────────────────────────────────
    # VALIDATE ALL THREE SCORES
    # ─────────────────────────────────────────

    def validate_all(
        self,
        dfs_score: float,
        louvain_score: float,
        fft_score: float,
    ):
        """
        Final validation before HTGPS.
        Assert all scores are 0-1.
        Log warning if any out of range.
        Returns validated scores.
        """
        scores = {
            "dfs"    : dfs_score,
            "louvain": louvain_score,
            "fft"    : fft_score,
        }

        validated = {}
        for name, score in scores.items():
            try:
                s = float(score)
                s = max(0.0, min(1.0, s))
                validated[name] = round(s, 4)
                if score != s:
                    print(f"[Normaliser] WARNING: {name} score "
                          f"clamped from {score} to {s}")
            except:
                print(f"[Normaliser] WARNING: {name} score invalid — set to 0.0")
                validated[name] = 0.0

        print(f"[Normaliser] All scores validated: "
              f"DFS={validated['dfs']} "
              f"Louvain={validated['louvain']} "
              f"FFT={validated['fft']}")

        return (
            validated["dfs"],
            validated["louvain"],
            validated["fft"],
        )


normaliser = Normaliser()