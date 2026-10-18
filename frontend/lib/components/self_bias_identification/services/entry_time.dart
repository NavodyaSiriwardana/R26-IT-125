/// Extracts the creation timestamp (ms since epoch) from an entry id.
///
/// Handles both id shapes this component produces: `ENT_<ms>` (manual
/// form) and `ENT_LEADER_<ms>` (mapped from the shared diaryEntries
/// collection). Returns null when the id carries no trailing number.
int? entryTimestampMs(Object? entryId) {
  final match = RegExp(r'(\d+)$').firstMatch(entryId?.toString() ?? '');
  return match == null ? null : int.tryParse(match.group(1)!);
}
