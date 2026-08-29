import 'Citation.dart';

class RagSummaryPoint {
  final String? claimId;
  final String text;
  final List<Citation> citations;

  RagSummaryPoint({
    this.claimId,
    required this.text,
    required this.citations,
  });

  factory RagSummaryPoint.fromJson(Map<String, dynamic> json) {
    final rawCitations = json['citations'];
    final citations = rawCitations is List
        ? rawCitations
              .whereType<Map>()
              .map((item) => Citation.fromJson(Map<String, dynamic>.from(item)))
              .toList()
        : <Citation>[];

    final claimId = json['claim_id']?.toString().trim();
    return RagSummaryPoint(
      claimId: claimId == null || claimId.isEmpty ? null : claimId,
      text: json['text'] ?? '',
      citations: citations,
    );
  }
}
