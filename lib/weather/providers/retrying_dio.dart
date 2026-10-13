import 'dart:async';

import 'package:dio/dio.dart';

class RetryingDio {
  RetryingDio(this.dio);
  final Dio dio;
  final Map<String, Future<Response<dynamic>>> _inFlight = {};

  Future<Response<dynamic>> get(
    String url, {
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
  }) async {
    final key = _key(url, queryParameters, headers);
    final previous = _inFlight[key];
    if (previous != null) return previous;

    final future = _request(url, queryParameters: queryParameters, headers: headers);
    _inFlight[key] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(key);
    }
  }

  Future<Response<dynamic>> _request(
    String url, {
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
  }) async {
    Object? lastError;
    StackTrace? lastStack;
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        final response = await dio.get<dynamic>(
          url,
          queryParameters: queryParameters,
          options: Options(
            headers: headers,
            receiveTimeout: const Duration(seconds: 12),
            sendTimeout: const Duration(seconds: 7),
            validateStatus: (status) => status != null && status >= 200 && status < 500,
          ),
        );
        if (response.statusCode == 429 || response.statusCode == 408 || (response.statusCode ?? 0) >= 500) {
          if (attempt == 3) return response;
          await Future<void>.delayed(Duration(milliseconds: 500 * (1 << attempt)));
          continue;
        }
        return response;
      } on DioException catch (error, stack) {
        lastError = error;
        lastStack = stack;
        if (attempt == 3 || !_isRetryable(error)) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 500 * (1 << attempt)));
      }
    }
    Error.throwWithStackTrace(lastError ?? StateError('Network request failed'), lastStack ?? StackTrace.current);
  }

  bool _isRetryable(DioException error) {
    return error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.unknown;
  }

  String _key(String url, Map<String, dynamic>? query, Map<String, String>? headers) {
    final q = (query ?? {}).entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    final h = (headers ?? {}).entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return '$url|$q|$h';
  }
}
