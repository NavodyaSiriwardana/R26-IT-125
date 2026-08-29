import '../../../core/network/dio_client.dart';
import '../models/Compare_summary_response.dart';
import '../models/Diary_entry.dart';

class RagSummaryService {
  final DioClient dioClient;

  RagSummaryService(this.dioClient);

  Future<CompareSummaryResponse> generateWeeklySummary({
    required String userId,
    String query =
        'Summarize my activity, productivity and mood for this week and give feedback',
    String? weekStart,
    String? weekEnd,
    int topK = 8,
    String retrievalMode = 'auto',
    bool enableSlmFeedback = false,
  }) async {
    final response = await dioClient.dio.post(
      '/api/v1/rag-summary/weekly-summary',
      data: {
        'user_id': userId,
        'query': query,
        'week_start': weekStart,
        'week_end': weekEnd,
        'top_k': topK,
        'retrieval_mode': retrievalMode,
        'enable_slm_feedback': enableSlmFeedback,
      },
    );

    return CompareSummaryResponse.fromJson(response.data);
  }

  Future<CompareSummaryResponse> getLatestWeeklySummary({
    required String userId,
    String? weekStart,
    String? weekEnd,
  }) async {
    final response = await dioClient.dio.get(
      '/api/v1/rag-summary/weekly-summary/latest',
      queryParameters: {
        'user_id': userId,
        'week_start': ?weekStart,
        'week_end': ?weekEnd,
      },
    );

    return CompareSummaryResponse.fromJson(response.data);
  }

  Future<CompareSummaryResponse> compareSummary({
    required String userId,
    required String query,
    String? weekStart,
    String? weekEnd,
    int topK = 8,
    String retrievalMode = 'auto',
  }) async {
    final response = await dioClient.dio.post(
      '/api/v1/rag-summary/compare-summary',
      data: {
        'user_id': userId,
        'query': query,
        'week_start': weekStart,
        'week_end': weekEnd,
        'top_k': topK,
        'retrieval_mode': retrievalMode,
      },
    );

    return CompareSummaryResponse.fromJson(response.data);
  }

  Future<DiaryEntry> getEvidenceById({
    required String userId,
    required String evidenceId,
  }) async {
    final response = await dioClient.dio.get(
      '/api/v1/rag-summary/evidence/$evidenceId',
      queryParameters: {'user_id': userId},
    );

    return DiaryEntry.fromJson(response.data);
  }
}
