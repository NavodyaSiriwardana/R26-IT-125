import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/components/rag_summary/models/Compare_summary_response.dart';
import 'package:frontend/components/rag_summary/screens/Summary_generation_details_screen.dart';
import 'package:frontend/components/rag_summary/screens/Summary_result_screen.dart';

void main() {
  testWidgets(
    'weekly result shows uncited RAG text without verification jargon',
    (tester) async {
      final summary = _summary();

      await tester.pumpWidget(
        MaterialApp(
          home: SummaryResultScreen(
            userId: 'test-user',
            preloadedSummary: summary,
          ),
        ),
      );
      await tester.pump();

      expect(
        find.text(
          'A personalized weekly reflection. A recovery walk improved my mood.',
        ),
        findsOneWidget,
      );
      expect(find.text('WEEKLY HIGHLIGHT'), findsNothing);
      expect(find.text('Keep the routine that helped.'), findsOneWidget);
      expect(find.textContaining('not enough'), findsNothing);
      expect(find.textContaining('citation'), findsNothing);
      expect(find.textContaining('unsupported'), findsNothing);
    },
  );

  testWidgets('generation details explain exactly two conditions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: SummaryGenerationDetailsScreen(summary: _summary())),
    );
    await tester.pump();

    expect(find.text('Plain text compared with grounded RAG'), findsOneWidget);
    expect(find.text('Estimated hallucination comparison'), findsOneWidget);
    expect(find.textContaining('RAG had 40.0 points fewer'), findsOneWidget);
    expect(find.text('Condition A: Plain summary'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Condition B: Grounded RAG summary'),
      300,
    );
    expect(find.text('Condition B: Grounded RAG summary'), findsOneWidget);
    expect(find.textContaining('context gain'), findsNothing);
    expect(find.textContaining('memory pool'), findsNothing);
    expect(find.textContaining('Verified RAG'), findsNothing);
    expect(find.textContaining('Unsupported claims'), findsNothing);
    expect(find.textContaining('Citation precision'), findsNothing);
  });
}

CompareSummaryResponse _summary() {
  return CompareSummaryResponse.fromJson({
    'query': 'Summarize my week',
    'summary_type': 'weekly_plain_text_vs_chroma_rag',
    'summary_points': [
      {
        'claim_id': 'CLM-001',
        'text': 'This week: A personalized weekly reflection.',
        'citations': <dynamic>[],
      },
      {
        'claim_id': 'CLM-002',
        'text': 'This week: A recovery walk improved my mood.',
        'citations': <dynamic>[],
      },
    ],
    'feedback': {
      'feedback_type': 'wellbeing_productivity',
      'mood_signal': 'mostly_positive',
      'productivity_signal': 'high',
      'message': 'Keep the routine that helped.',
      'action': 'Try the same routine next week.',
      'evidence_ids': ['EV-001'],
      'based_on_evidence_ids': ['EV-001'],
      'abstained': false,
      'generation_method': 'rule_based',
    },
    'user_id': 'test-user',
    'week_start': '2026-08-24',
    'week_end': '2026-08-30',
    'saved_summary_id': 'summary-001',
    'additional_data': {
      'displayed_condition': 'rag',
      'plain_slm': {
        'status': 'success',
        'summary_text': 'A plain weekly reflection.',
        'generation': {'model_name': 'google/flan-t5-large'},
        'evaluation': {
          'status': 'available',
          'grounded_claim_rate': 0.4,
          'unsupported_claim_rate': 0.6,
        },
      },
      'rag': {
        'status': 'success',
        'summary_points': [
          {
            'claim_id': 'CLM-001',
            'text': 'A personalized weekly reflection.',
            'citations': <dynamic>[],
          },
        ],
        'generation': {'model_name': 'google/flan-t5-large'},
        'retrieval': {'retrieved_evidence_count': 2, 'retrieval_coverage': 0.5},
        'evaluation': {
          'status': 'available',
          'grounded_claim_rate': 0.8,
          'unsupported_claim_rate': 0.2,
        },
      },
      'comparison': {'status': 'ready_for_evaluation'},
    },
  });
}
