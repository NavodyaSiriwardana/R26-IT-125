import networkx as nx
import community as community_louvain
from app.database import neo4j_conn


# ─────────────────────────────────────────────
# LOUVAIN ENGINE — COMMUNITY DETECTION
# ─────────────────────────────────────────────

class LouvainEngine:

    # ─────────────────────────────────────────
    # FETCH USER GRAPH FROM AURADB
    # ─────────────────────────────────────────

    def fetch_user_graph(self, user_id: str):
        """
        Fetch all concept nodes and relationships
        for one user from AuraDB.
        Builds edge list for NetworkX graph.
        """
        query = """
        MATCH (e:DiaryEntry {userId: $userId})
              -[r]->(n)
        WHERE NOT n:DiaryEntry
        AND NOT n:User
        OPTIONAL MATCH (e)-[:HAS_CATEGORY]->(cat:ActivityCategory)
        WITH e, r, n, cat,
            CASE labels(n)[0]
                WHEN 'Mood'             THEN n.value
                WHEN 'ActivityCategory' THEN n.name
                WHEN 'SocialContext'    THEN n.withWhom
                WHEN 'HealthStatus'     THEN n.status
                WHEN 'Productivity'     THEN n.level
                WHEN 'TaskOutcome'      THEN n.outcome
                WHEN 'Person'           THEN n.name
                ELSE null
            END AS toConcept
        WHERE toConcept IS NOT NULL
        RETURN
            coalesce(cat.name, e.timePeriod) AS fromConcept,
            type(r)                           AS relType,
            toConcept                         AS toConcept,
            r.entryDateTime                   AS edgeDateTime
        """
        with neo4j_conn.get_session() as session:
            result = session.run(query, {"userId": user_id})
            edges = [record.data() for record in result]

        print(f"[LouvainEngine] Fetched {len(edges)} edges for {user_id}")
        return edges

    # ─────────────────────────────────────────
    # BUILD NETWORKX GRAPH
    # ─────────────────────────────────────────

    def _build_graph(self, edges: list):
        """
        Build NetworkX undirected graph from
        edge list fetched from AuraDB.
        Edge weight = co-occurrence count.
        """
        G = nx.Graph()

        weight_map = {}

        for edge in edges:
            from_node = str(edge.get("fromConcept", "")).strip()
            to_node   = str(edge.get("toConcept",   "")).strip()

            if not from_node or not to_node:
                continue
            if from_node == "None" or to_node == "None":
                continue

            key = (from_node, to_node)
            weight_map[key] = weight_map.get(key, 0) + 1

        for (from_node, to_node), weight in weight_map.items():
            G.add_edge(from_node, to_node, weight=weight)

        print(f"[LouvainEngine] Built graph: "
              f"{G.number_of_nodes()} nodes, "
              f"{G.number_of_edges()} edges")
        return G

    # ─────────────────────────────────────────
    # RUN LOUVAIN PARTITION
    # ─────────────────────────────────────────

    def _run_louvain(self, G: nx.Graph):
        """
        Run Louvain community detection.
        Returns partition dict:
        {node_name: community_id}
        """
        if G.number_of_nodes() < 2:
            print("[LouvainEngine] Graph too small for Louvain")
            return {}

        try:
            partition = community_louvain.best_partition(G)
            communities = len(set(partition.values()))
            print(f"[LouvainEngine] Found {communities} communities")
            return partition
        except Exception as e:
            print(f"[LouvainEngine] ERROR: {e}")
            return {}

    # ─────────────────────────────────────────
    # CHECK IF NODES ARE ADJACENT
    # ─────────────────────────────────────────

    def _are_adjacent(
        self,
        G: nx.Graph,
        partition: dict,
        node_a: str,
        node_b: str
    ):
        """
        Check if two nodes in different
        communities are directly connected
        by an edge — adjacent communities.
        """
        if G.has_edge(node_a, node_b):
            return True

        # Check if they share a common neighbor
        neighbors_a = set(G.neighbors(node_a)) if G.has_node(node_a) else set()
        neighbors_b = set(G.neighbors(node_b)) if G.has_node(node_b) else set()
        shared      = neighbors_a.intersection(neighbors_b)
        return len(shared) > 0

    # ─────────────────────────────────────────
    # VALIDATE PATTERN CLUSTER
    # ─────────────────────────────────────────

    def validate_cluster(
        self,
        user_id: str,
        trigger_concept: str,
        outcome_concept: str,
    ):
        """
        Check if trigger and outcome concepts
        belong to the same behavioral cluster
        in the user's personal knowledge graph.

        Same cluster     = louvainScore 1.0
        Adjacent cluster = louvainScore 0.5
        Different cluster = louvainScore 0.0
        """
        # Fetch graph data from AuraDB
        edges = self.fetch_user_graph(user_id)

        if not edges:
            print("[LouvainEngine] No edges found — returning 0.5")
            return {
                "louvainScore"      : 0.5,
                "triggerCommunity"  : -1,
                "outcomeCommunity"  : -1,
                "clusterRelation"   : "unknown",
            }

        # Build NetworkX graph
        G = self._build_graph(edges)

        # Run Louvain
        partition = self._run_louvain(G)

        if not partition:
            return {
                "louvainScore"     : 0.5,
                "triggerCommunity" : -1,
                "outcomeCommunity" : -1,
                "clusterRelation"  : "unknown",
            }

        # Get community IDs for trigger and outcome
        trigger_community = partition.get(trigger_concept, -1)
        outcome_community = partition.get(outcome_concept, -1)

        # Calculate louvain score
        if trigger_community == -1 or outcome_community == -1:
            # One or both concepts not in graph
            louvain_score    = 0.5
            cluster_relation = "not_found"

        elif trigger_community == outcome_community:
            # Same community — strongest evidence
            louvain_score    = 1.0
            cluster_relation = "same_cluster"

        elif self._are_adjacent(G, partition, trigger_concept, outcome_concept):
            # Adjacent communities — moderate evidence
            louvain_score    = 0.5
            cluster_relation = "adjacent_cluster"

        else:
            # Different communities — weak evidence
            louvain_score    = 0.0
            cluster_relation = "different_cluster"

        print(f"[LouvainEngine] {trigger_concept} -> {outcome_concept}: "
              f"communities ({trigger_community},{outcome_community}) "
              f"score={louvain_score} relation={cluster_relation}")

        return {
            "louvainScore"     : louvain_score,
            "triggerCommunity" : trigger_community,
            "outcomeCommunity" : outcome_community,
            "clusterRelation"  : cluster_relation,
        }


louvain_engine = LouvainEngine()