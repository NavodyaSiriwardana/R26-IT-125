import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Every request this component makes to its own server goes through here, so
/// none of them can wait forever when the server hangs or the network drops
/// halfway. A request that gets no answer in time throws a
/// [TimeoutException], which `AppToast.friendlyError` turns into plain words.
class ApiClient {
  /// Ordinary requests: history, locations, consent, resets.
  static Duration quickTimeout = const Duration(seconds: 15);

  /// Analysis and facial scans run machine-learning models on the server and
  /// take longer, especially the first one after the server starts.
  static Duration slowTimeout = const Duration(seconds: 60);

  /// Lets tests answer requests with a fake client instead of the network.
  @visibleForTesting
  static http.Client? clientOverride;

  static Duration timeoutFor(Uri url) {
    final path = url.path;
    return path.contains('/analyze') || path.contains('/facial')
        ? slowTimeout
        : quickTimeout;
  }

  static Future<http.Response> get(Uri url, {Map<String, String>? headers}) {
    final client = clientOverride;
    final request = client != null
        ? client.get(url, headers: headers)
        : http.get(url, headers: headers);
    return request.timeout(timeoutFor(url));
  }

  static Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) {
    final client = clientOverride;
    final request = client != null
        ? client.post(url, headers: headers, body: body)
        : http.post(url, headers: headers, body: body);
    return request.timeout(timeoutFor(url));
  }

  static Future<http.Response> delete(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) {
    final client = clientOverride;
    final request = client != null
        ? client.delete(url, headers: headers, body: body)
        : http.delete(url, headers: headers, body: body);
    return request.timeout(timeoutFor(url));
  }
}
