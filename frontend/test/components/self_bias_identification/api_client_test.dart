import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/components/self_bias_identification/services/api_client.dart';
import 'package:frontend/components/self_bias_identification/services/api_service.dart';
import 'package:frontend/components/self_bias_identification/widgets/app_toast.dart';

void main() {
  late HttpServer server;
  late String base;
  late Duration savedQuick;
  late Duration savedSlow;
  late String savedBase;
  Duration serverDelay = Duration.zero;
  var hang = false;

  setUp(() async {
    // flutter_test stubs HTTP to answer 400; these tests need the real thing.
    HttpOverrides.global = null;
    savedQuick = ApiClient.quickTimeout;
    savedSlow = ApiClient.slowTimeout;
    savedBase = ApiService.baseUrl;
    serverDelay = Duration.zero;
    hang = false;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    ApiService.baseUrl = base;
    server.listen((request) async {
      if (hang) return; // accept the connection and never answer
      await Future<void>.delayed(serverDelay);
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'ok': true, 'path': request.uri.path}));
      await request.response.close();
    });
  });

  tearDown(() async {
    ApiClient.quickTimeout = savedQuick;
    ApiClient.slowTimeout = savedSlow;
    ApiService.baseUrl = savedBase;
    await server.close(force: true);
  });

  group('ApiClient', () {
    test('a normal request just works', () async {
      final r = await ApiClient.get(Uri.parse('$base/api/bias/history/u1'));
      expect(r.statusCode, 200);
      expect(jsonDecode(r.body)['path'], '/api/bias/history/u1');
    });

    test('a server that never answers times out instead of hanging', () async {
      hang = true;
      ApiClient.quickTimeout = const Duration(milliseconds: 300);
      final started = DateTime.now();
      await expectLater(
        ApiClient.get(Uri.parse('$base/api/bias/history/u1')),
        throwsA(isA<TimeoutException>()),
      );
      expect(DateTime.now().difference(started).inSeconds, lessThan(3));
    });

    test('post and delete time out too', () async {
      hang = true;
      ApiClient.quickTimeout = const Duration(milliseconds: 300);
      await expectLater(
        ApiClient.post(Uri.parse('$base/api/bias/consent/u1'), body: '{}'),
        throwsA(isA<TimeoutException>()),
      );
      await expectLater(
        ApiClient.delete(Uri.parse('$base/api/bias/participant/u1/data')),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('analysis and facial requests get the longer limit', () {
      expect(
        ApiClient.timeoutFor(Uri.parse('$base/api/bias/analyze-from-diary/u1')),
        ApiClient.slowTimeout,
      );
      expect(
        ApiClient.timeoutFor(Uri.parse('$base/api/bias/facial/analyze')),
        ApiClient.slowTimeout,
      );
      expect(
        ApiClient.timeoutFor(Uri.parse('$base/api/bias/history/u1')),
        ApiClient.quickTimeout,
      );
      expect(ApiClient.slowTimeout, greaterThan(ApiClient.quickTimeout));
    });

    test('a slow analysis is waited for, a slow history call is not', () async {
      serverDelay = const Duration(milliseconds: 600);
      ApiClient.quickTimeout = const Duration(milliseconds: 250);
      ApiClient.slowTimeout = const Duration(seconds: 5);

      final analysis =
          await ApiClient.post(Uri.parse('$base/api/bias/analyze-from-diary/u1'));
      expect(analysis.statusCode, 200);

      await expectLater(
        ApiClient.get(Uri.parse('$base/api/bias/history/u1')),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('the typed ApiService helpers are covered by the same limit', () async {
      hang = true;
      ApiClient.quickTimeout = const Duration(milliseconds: 300);
      await expectLater(
        ApiService.getMoodResets('u1').timeout(const Duration(seconds: 3)),
        completion(isEmpty), // swallowed into "no resets", never a hang
      );
      await expectLater(
        ApiService.deleteMyData('u1'),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('a timeout reads as plain words, not an exception', () {
      final text = AppToast.friendlyError(
        TimeoutException('x', const Duration(seconds: 15)),
      );
      expect(text, 'The server is taking too long to answer. Try again in a moment.');
      expect(text.contains('Exception'), isFalse);
    });
  });
}
