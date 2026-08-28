# ─────────────────────────────────────────────
# CONSTRAINTS AND INDEXES
# ─────────────────────────────────────────────

CREATE_USER_CONSTRAINT = """
CREATE CONSTRAINT unique_user_id IF NOT EXISTS
FOR (u:User) REQUIRE u.userId IS UNIQUE
"""

CREATE_ENTRY_CONSTRAINT = """
CREATE CONSTRAINT unique_entry_id IF NOT EXISTS
FOR (e:DiaryEntry) REQUIRE e.entryId IS UNIQUE
"""

CREATE_ENTRY_DATETIME_INDEX = """
CREATE INDEX entry_datetime_index IF NOT EXISTS
FOR (e:DiaryEntry) ON (e.userId, e.entryDateTime)
"""

CREATE_MOOD_INDEX = """
CREATE INDEX mood_value_index IF NOT EXISTS
FOR (m:Mood) ON (m.value)
"""

CREATE_CATEGORY_INDEX = """
CREATE INDEX category_name_index IF NOT EXISTS
FOR (c:ActivityCategory) ON (c.name)
"""

CREATE_PERSON_INDEX = """
CREATE INDEX person_name_index IF NOT EXISTS
FOR (p:Person) ON (p.name)
"""

# ─────────────────────────────────────────────
# USER NODE
# ─────────────────────────────────────────────

MERGE_USER_NODE = """
MERGE (u:User {userId: $userId})
ON CREATE SET
    u.createdAt   = $createdAt,
    u.source      = $source,
    u.version     = $version,
    u.isActive    = true
RETURN u
"""

# ─────────────────────────────────────────────
# DIARY ENTRY NODE
# ─────────────────────────────────────────────

CREATE_DIARY_ENTRY = """
MATCH (u:User {userId: $userId})
CREATE (e:DiaryEntry {
    entryId           : $entryId,
    userId            : $userId,
    activityName      : $activityName,
    entryDate         : $entryDate,
    startTime         : $startTime,
    endTime           : $endTime,
    timePeriod        : $timePeriod,
    duration          : $duration,
    locationType      : $locationType,
    customLocation    : $customLocation,
    specificPerson    : $specificPerson,
    notes             : $notes,
    entryDateTime     : $entryDateTime,
    createdAt         : $createdAt,
    updatedAt         : $updatedAt,
    version           : $version,
    source            : $source,
    isActive          : true
})
CREATE (u)-[:HAS_ENTRY {
    userId        : $userId,
    entryDateTime : $entryDateTime,
    createdAt     : $createdAt,
    version       : $version,
    source        : $source
}]->(e)
RETURN e.entryId AS entryId
"""

# ─────────────────────────────────────────────
# SHARED NODES — MERGE (reuse existing nodes)
# ─────────────────────────────────────────────

MERGE_ACTIVITY_CATEGORY = """
MATCH (e:DiaryEntry {entryId: $entryId})
MERGE (c:ActivityCategory {name: $activityCategory})
ON CREATE SET c.createdAt = $createdAt
CREATE (e)-[:HAS_CATEGORY {
    userId        : $userId,
    entryDateTime : $entryDateTime,
    createdAt     : $createdAt,
    version       : $version,
    source        : $source
}]->(c)
"""

MERGE_SOCIAL_CONTEXT = """
MATCH (e:DiaryEntry {entryId: $entryId})
MERGE (s:SocialContext {withWhom: $withWhom})
ON CREATE SET s.createdAt = $createdAt
CREATE (e)-[:WITH_SOCIAL_CONTEXT {
    userId        : $userId,
    entryDateTime : $entryDateTime,
    createdAt     : $createdAt,
    version       : $version,
    source        : $source
}]->(s)
"""

MERGE_MOOD_BEFORE = """
MATCH (e:DiaryEntry {entryId: $entryId})
MERGE (m:Mood {value: $moodBefore})
ON CREATE SET m.createdAt = $createdAt
CREATE (e)-[:MOOD_BEFORE {
    userId        : $userId,
    entryDateTime : $entryDateTime,
    createdAt     : $createdAt,
    version       : $version,
    source        : $source
}]->(m)
"""

MERGE_MOOD_AFTER = """
MATCH (e:DiaryEntry {entryId: $entryId})
MERGE (m:Mood {value: $moodAfter})
ON CREATE SET m.createdAt = $createdAt
CREATE (e)-[:MOOD_AFTER {
    userId        : $userId,
    entryDateTime : $entryDateTime,
    createdAt     : $createdAt,
    version       : $version,
    source        : $source
}]->(m)
"""

MERGE_PRODUCTIVITY = """
MATCH (e:DiaryEntry {entryId: $entryId})
MERGE (p:Productivity {level: $productivityLevel})
ON CREATE SET p.createdAt = $createdAt
CREATE (e)-[:HAS_PRODUCTIVITY {
    userId        : $userId,
    entryDateTime : $entryDateTime,
    createdAt     : $createdAt,
    version       : $version,
    source        : $source
}]->(p)
"""

MERGE_HEALTH_STATUS = """
MATCH (e:DiaryEntry {entryId: $entryId})
MERGE (h:HealthStatus {status: $healthStatus})
ON CREATE SET h.createdAt = $createdAt
CREATE (e)-[:HAS_HEALTH_STATUS {
    userId        : $userId,
    entryDateTime : $entryDateTime,
    createdAt     : $createdAt,
    version       : $version,
    source        : $source
}]->(h)
"""

MERGE_TASK_OUTCOME = """
MATCH (e:DiaryEntry {entryId: $entryId})
MERGE (t:TaskOutcome {outcome: $taskOutcome})
ON CREATE SET t.createdAt = $createdAt
CREATE (e)-[:HAS_TASK_OUTCOME {
    userId        : $userId,
    entryDateTime : $entryDateTime,
    createdAt     : $createdAt,
    version       : $version,
    source        : $source
}]->(t)
"""

MERGE_SPECIFIC_PERSON = """
MATCH (e:DiaryEntry {entryId: $entryId})
MERGE (p:Person {name: $specificPerson})
ON CREATE SET p.createdAt = $createdAt
CREATE (e)-[:MET_WITH {
    userId        : $userId,
    entryDateTime : $entryDateTime,
    createdAt     : $createdAt,
    version       : $version,
    source        : $source
}]->(p)
"""

# ─────────────────────────────────────────────
# NEXT_ENTRY CHAIN
# ─────────────────────────────────────────────

DELETE_USER_NEXT_ENTRY = """
MATCH (u:User {userId: $userId})-[:HAS_ENTRY]->(e:DiaryEntry)
MATCH (e)-[r:NEXT_ENTRY]->()
DELETE r
"""

GET_USER_ENTRIES_ORDERED = """
MATCH (u:User {userId: $userId})-[:HAS_ENTRY]->(e:DiaryEntry)
RETURN e.entryId AS entryId, e.entryDateTime AS entryDateTime
ORDER BY e.entryDateTime ASC
"""

CREATE_NEXT_ENTRY_LINK = """
MATCH (a:DiaryEntry {entryId: $fromEntryId})
MATCH (b:DiaryEntry {entryId: $toEntryId})
CREATE (a)-[:NEXT_ENTRY {
    userId        : $userId,
    fromDateTime  : $fromDateTime,
    toDateTime    : $toDateTime,
    createdAt     : $createdAt,
    version       : $version,
    source        : $source
}]->(b)
"""

# ─────────────────────────────────────────────
# FETCH USER DIARY DATA FOR PATTERN ENGINE
# ─────────────────────────────────────────────

FETCH_USER_DIARY_DATA = """
MATCH (u:User {userId: $userId})-[:HAS_ENTRY]->(e:DiaryEntry)
MATCH (e)-[:HAS_CATEGORY]->(c:ActivityCategory)
MATCH (e)-[:WITH_SOCIAL_CONTEXT]->(s:SocialContext)
MATCH (e)-[:MOOD_BEFORE]->(mb:Mood)
MATCH (e)-[:MOOD_AFTER]->(ma:Mood)
MATCH (e)-[:HAS_PRODUCTIVITY]->(p:Productivity)
MATCH (e)-[:HAS_HEALTH_STATUS]->(h:HealthStatus)
MATCH (e)-[:HAS_TASK_OUTCOME]->(t:TaskOutcome)
OPTIONAL MATCH (e)-[:MET_WITH]->(person:Person)
RETURN
    e.entryId          AS entryId,
    e.entryDateTime    AS entryDateTime,
    e.entryDate        AS entryDate,
    e.timePeriod       AS timePeriod,
    e.specificPerson   AS specificPerson,
    c.name             AS activityCategory,
    s.withWhom         AS withWhom,
    mb.value           AS moodBefore,
    ma.value           AS moodAfter,
    p.level            AS productivityLevel,
    h.status           AS healthStatus,
    t.outcome          AS taskOutcome,
    person.name        AS personNode
ORDER BY e.entryDateTime ASC
"""

# ─────────────────────────────────────────────
# PATTERN INSIGHT NODES — PP2
# ─────────────────────────────────────────────

CREATE_PATTERN_INSIGHT = """
MERGE (pi:PatternInsight {
    patternId: $patternId
})
SET
    pi.userId               = $userId,
    pi.insightText          = $insightText,
    pi.trigger              = $trigger,
    pi.outcome              = $outcome,
    pi.matchedCount         = $matchedCount,
    pi.totalTriggerCount    = $totalTriggerCount,
    pi.confidencePercentage = $confidencePercentage,
    pi.patternLevel         = $patternLevel,
    pi.createdAt            = $createdAt,
    pi.version              = $version
RETURN pi.patternId AS patternId
"""

LINK_USER_TO_PATTERN = """
MATCH (u:User {userId: $userId})
MATCH (pi:PatternInsight {patternId: $patternId})
MERGE (u)-[:HAS_PATTERN {
    userId    : $userId,
    createdAt : $createdAt,
    version   : $version
}]->(pi)
"""

LINK_PATTERN_TO_EVIDENCE = """
MATCH (pi:PatternInsight {patternId: $patternId})
MATCH (e:DiaryEntry {userId: $userId, entryDate: $entryDate})
MERGE (pi)-[:SUPPORTED_BY {
    userId        : $userId,
    entryDateTime : e.entryDateTime,
    createdAt     : $createdAt,
    version       : $version
}]->(e)
"""

FETCH_USER_PATTERNS = """
MATCH (u:User {userId: $userId})-[:HAS_PATTERN]->(pi:PatternInsight)
RETURN
    pi.patternId            AS patternId,
    pi.insightText          AS insightText,
    pi.trigger              AS trigger,
    pi.outcome              AS outcome,
    pi.matchedCount         AS matchedCount,
    pi.totalTriggerCount    AS totalTriggerCount,
    pi.confidencePercentage AS confidencePercentage,
    pi.patternLevel         AS patternLevel,
    pi.createdAt            AS createdAt
ORDER BY pi.confidencePercentage DESC
"""