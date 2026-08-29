import '../../../core/network/dio_client.dart';
import '../models/dashboard_data.dart';

class DashboardService {
  final DioClient dioClient;

  DashboardService(this.dioClient);

  Future<DashboardData> getWeeklyDashboard({
    required String userId,
    String? weekStart,
    String? weekEnd,
  }) async {
    final response = await dioClient.dio.get(
      '/api/v1/rag-summary/dashboard',
      queryParameters: {
        'user_id': userId,
        'week_start': ?weekStart,
        'week_end': ?weekEnd,
      },
    );

    final rawData = response.data;
    if (rawData is! Map) {
      throw const FormatException('Dashboard response must be a JSON object.');
    }

    return DashboardData.fromJson(Map<String, dynamic>.from(rawData));
  }
}
