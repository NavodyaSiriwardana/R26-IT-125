import '../../../core/network/dio_client.dart';
import '../models/User.dart';

class UserService {
  final DioClient dioClient;

  UserService(this.dioClient);

  Future<List<User>> getUsers() async {
    final response = await dioClient.dio.get('/users');

    return (response.data as List).map((json) => User.fromJson(json)).toList();
  }
}
