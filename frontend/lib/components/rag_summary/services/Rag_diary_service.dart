import '../../../core/network/dio_client.dart';
import '../models/Diary_entry.dart';

class RagDiaryService {
  final DioClient dioClient;

  RagDiaryService(this.dioClient);

  Future<List<DiaryEntry>> getDiaryEntries({
    required String userId,
    int limit = 50,
  }) async {
    final response = await dioClient.dio.get(
      '/api/v1/rag-summary/entries',
      queryParameters: {'user_id': userId, 'limit': limit},
    );

    final data = response.data as List;

    return data
        .map((item) => DiaryEntry.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}
