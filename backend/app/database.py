from neo4j import GraphDatabase
from neo4j.exceptions import ServiceUnavailable, AuthError
from app.config import settings


class Neo4jConnection:
    def __init__(self):
        self._driver = None
        self._connect()

    def _connect(self):
        try:
            self._driver = GraphDatabase.driver(
                settings.NEO4J_URI,
                auth=(settings.NEO4J_USERNAME, settings.NEO4J_PASSWORD),
                max_connection_lifetime=200,
                max_connection_pool_size=50,
                connection_acquisition_timeout=30,
            )
            print("[Neo4j] Driver created successfully")
        except AuthError:
            print("[Neo4j] ERROR: Invalid credentials")
        except Exception as e:
            print(f"[Neo4j] ERROR: {e}")

    def get_session(self):
        try:
            return self._driver.session(
                database=settings.NEO4J_DATABASE
            )
        except Exception:
            print("[Neo4j] Session failed — reconnecting...")
            self._connect()
            return self._driver.session(
                database=settings.NEO4J_DATABASE
            )

    def verify_connection(self):
        try:
            with self.get_session() as session:
                result = session.run(
                    "RETURN 'Neo4j AuraDB connected successfully' AS message"
                )
                message = result.single()["message"]
                print(f"[Neo4j] {message}")
                return message
        except ServiceUnavailable:
            print("[Neo4j] ERROR: Database unavailable")
            return None
        except Exception as e:
            print(f"[Neo4j] ERROR: {e}")
            return None

    def close(self):
        if self._driver:
            self._driver.close()
            print("[Neo4j] Connection closed")


neo4j_conn = Neo4jConnection()