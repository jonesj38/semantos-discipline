---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/semantos_ffi/lib/src/adapters/http_network_adapter.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.009894+00:00
---

# platforms/flutter/semantos_ffi/lib/src/adapters/http_network_adapter.dart

```dart
// HttpNetworkAdapter — REST-based network adapter for publishing and
// resolving objects via the Semantos network.

import 'dart:convert' show json, utf8;
import 'dart:typed_data' show Uint8List;

import 'package:dio/dio.dart';

/// HTTP network adapter for object publication and resolution.
class HttpNetworkAdapter {
  final Dio _dio;
  final String _endpoint;

  HttpNetworkAdapter({
    required String endpoint,
    Dio? dio,
    Duration connectTimeout = const Duration(seconds: 10),
    Duration receiveTimeout = const Duration(seconds: 30),
    int maxRetries = 3,
  })  : _endpoint = endpoint,
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: connectTimeout,
              receiveTimeout: receiveTimeout,
            )) {
    if (dio == null && maxRetries > 0) {
      _dio.interceptors.add(_RetryInterceptor(maxRetries: maxRetries));
    }
  }

  /// Publish a JSON object to the network.
  Future<void> publish(Uint8List objectJson) async {
    final body = json.decode(utf8.decode(objectJson));
    final response = await _dio.post(
      '$_endpoint/network/publish',
      data: body,
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw NetworkException(
        'Publish failed: HTTP ${response.statusCode}',
      );
    }
  }

  /// Query the network and return matching results as JSON bytes.
  Future<Uint8List> resolve(Uint8List queryJson) async {
    final query = json.decode(utf8.decode(queryJson));
    final response = await _dio.post<dynamic>(
      '$_endpoint/network/resolve',
      data: query,
    );
    if (response.statusCode == 200 && response.data != null) {
      final resultJson = json.encode(response.data);
      return Uint8List.fromList(utf8.encode(resultJson));
    }
    throw NetworkException(
      'Resolve failed: HTTP ${response.statusCode}',
    );
  }

  /// Check connectivity to the network endpoint.
  Future<bool> isOnline() async {
    try {
      final response = await _dio.get(
        '$_endpoint/health',
        options: Options(
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      return response.statusCode == 200;
    } on DioException {
      return false;
    }
  }
}

/// Exception for network adapter errors.
class NetworkException implements Exception {
  final String message;
  NetworkException(this.message);

  @override
  String toString() => 'NetworkException: $message';
}

/// Retry interceptor for transient network failures.
class _RetryInterceptor extends Interceptor {
  final int maxRetries;

  _RetryInterceptor({required this.maxRetries});

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final attempt = (err.requestOptions.extra['_retry_count'] as int?) ?? 0;

    if (attempt < maxRetries && _isRetryable(err)) {
      err.requestOptions.extra['_retry_count'] = attempt + 1;

      // Exponential backoff: 200ms, 400ms, 800ms...
      await Future.delayed(Duration(milliseconds: 200 * (1 << attempt)));

      try {
        final dio = Dio(BaseOptions(
          connectTimeout: err.requestOptions.connectTimeout,
          receiveTimeout: err.requestOptions.receiveTimeout,
        ));
        final response = await dio.fetch(err.requestOptions);
        handler.resolve(response);
        return;
      } on DioException catch (retryErr) {
        handler.next(retryErr);
        return;
      }
    }
    handler.next(err);
  }

  bool _isRetryable(DioException err) {
    if (err.type == DioExceptionType.connectionTimeout) return true;
    if (err.type == DioExceptionType.sendTimeout) return true;
    if (err.type == DioExceptionType.receiveTimeout) return true;
    if (err.type == DioExceptionType.connectionError) return true;
    final status = err.response?.statusCode;
    if (status != null && (status == 502 || status == 503 || status == 504)) {
      return true;
    }
    return false;
  }
}

```
