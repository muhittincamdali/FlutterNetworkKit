import 'dart:convert';

import 'package:dio/dio.dart';

/// Represents an HTTP response with parsed data.
///
/// This class encapsulates the response status, headers, body,
/// and timing information.
///
/// Example:
/// ```dart
/// final response = await client.get<User>('/users/1');
/// print('Status: ${response.statusCode}');
/// print('Data: ${response.data}');
/// ```
class NetworkResponse<T> {
  /// Creates a new [NetworkResponse].
  const NetworkResponse({
    required this.data,
    required this.statusCode,
    this.statusMessage,
    this.headers,
    this.requestTime,
    this.fromCache = false,
    this.extra,
  });

  /// Creates a [NetworkResponse] from a Dio [Response].
  factory NetworkResponse.fromDioResponse(Response response) {
    return NetworkResponse(
      data: response.data as T,
      statusCode: response.statusCode ?? 0,
      statusMessage: response.statusMessage,
      headers: response.headers.map,
      extra: response.extra,
    );
  }

  /// Creates an empty success response.
  factory NetworkResponse.empty() {
    return NetworkResponse(
      data: null as T,
      statusCode: 204,
    );
  }

  /// Creates a response with custom data.
  factory NetworkResponse.withData(T data, {int statusCode = 200}) {
    return NetworkResponse(
      data: data,
      statusCode: statusCode,
    );
  }

  /// The parsed response data.
  final T data;

  /// The HTTP status code.
  final int statusCode;

  /// The HTTP status message.
  final String? statusMessage;

  /// The response headers.
  final Map<String, List<String>>? headers;

  /// The time taken for the request.
  final Duration? requestTime;

  /// Whether this response came from cache.
  final bool fromCache;

  /// Extra data associated with this response.
  final Map<String, dynamic>? extra;

  /// Returns true if the status code indicates success (2xx).
  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  /// Returns true if the status code indicates redirection (3xx).
  bool get isRedirect => statusCode >= 300 && statusCode < 400;

  /// Returns true if the status code indicates client error (4xx).
  bool get isClientError => statusCode >= 400 && statusCode < 500;

  /// Returns true if the status code indicates server error (5xx).
  bool get isServerError => statusCode >= 500;

  /// Returns true if there is an error (4xx or 5xx).
  bool get hasError => isClientError || isServerError;

  /// Returns a specific header value.
  String? header(String name) {
    final values = headers?[name.toLowerCase()];
    return values?.firstOrNull;
  }

  /// Returns all values for a header.
  List<String>? headerValues(String name) {
    return headers?[name.toLowerCase()];
  }

  /// Returns the Content-Type header.
  String? get contentType => header('content-type');

  /// Returns the Content-Length header.
  int? get contentLength {
    final length = header('content-length');
    return length != null ? int.tryParse(length) : null;
  }

  /// Returns the ETag header.
  String? get etag => header('etag');

  /// Returns the Last-Modified header.
  String? get lastModified => header('last-modified');

  /// Returns the Cache-Control header.
  String? get cacheControl => header('cache-control');

  /// Converts the response to Dio [Response].
  Response<T> toDioResponse() {
    return Response<T>(
      requestOptions: RequestOptions(path: ''),
      data: data,
      statusCode: statusCode,
      statusMessage: statusMessage,
      headers: Headers.fromMap(headers ?? {}),
      extra: extra ?? {},
    );
  }

  /// Maps the data to a new type.
  NetworkResponse<R> map<R>(R Function(T data) mapper) {
    return NetworkResponse<R>(
      data: mapper(data),
      statusCode: statusCode,
      statusMessage: statusMessage,
      headers: headers,
      requestTime: requestTime,
      fromCache: fromCache,
      extra: extra,
    );
  }

  /// Maps the data if not null.
  NetworkResponse<R?> mapNullable<R>(R Function(T data)? mapper) {
    if (mapper == null || data == null) {
      return NetworkResponse<R?>(
        data: null,
        statusCode: statusCode,
        statusMessage: statusMessage,
        headers: headers,
        requestTime: requestTime,
        fromCache: fromCache,
        extra: extra,
      );
    }
    return NetworkResponse<R?>(
      data: mapper(data),
      statusCode: statusCode,
      statusMessage: statusMessage,
      headers: headers,
      requestTime: requestTime,
      fromCache: fromCache,
      extra: extra,
    );
  }

  /// Creates a copy with the specified overrides.
  NetworkResponse<T> copyWith({
    T? data,
    int? statusCode,
    String? statusMessage,
    Map<String, List<String>>? headers,
    Duration? requestTime,
    bool? fromCache,
    Map<String, dynamic>? extra,
  }) {
    return NetworkResponse<T>(
      data: data ?? this.data,
      statusCode: statusCode ?? this.statusCode,
      statusMessage: statusMessage ?? this.statusMessage,
      headers: headers ?? this.headers,
      requestTime: requestTime ?? this.requestTime,
      fromCache: fromCache ?? this.fromCache,
      extra: extra ?? this.extra,
    );
  }

  /// Returns a JSON representation for logging.
  Map<String, dynamic> toJson() {
    return {
      'statusCode': statusCode,
      if (statusMessage != null) 'statusMessage': statusMessage,
      'data': _serializeData(data),
      if (requestTime != null) 'requestTimeMs': requestTime!.inMilliseconds,
      'fromCache': fromCache,
    };
  }

  dynamic _serializeData(dynamic data) {
    if (data == null) return null;
    if (data is String || data is num || data is bool) return data;
    if (data is Map || data is List) return data;
    try {
      return (data as dynamic).toJson();
    } catch (_) {
      return data.toString();
    }
  }

  @override
  String toString() {
    return 'NetworkResponse('
        'statusCode: $statusCode, '
        'statusMessage: $statusMessage, '
        'fromCache: $fromCache, '
        'hasData: ${data != null}'
        ')';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NetworkResponse<T> &&
        other.statusCode == statusCode &&
        other.data == data;
  }

  @override
  int get hashCode => Object.hash(statusCode, data);
}

/// Extension methods for working with responses.
extension NetworkResponseExtension<T> on NetworkResponse<T> {
  /// Throws if the response has an error status.
  NetworkResponse<T> throwIfError() {
    if (hasError) {
      throw ResponseException(
        statusCode: statusCode,
        message: statusMessage ?? 'Request failed',
      );
    }
    return this;
  }

  /// Returns the data or throws if error.
  T get dataOrThrow {
    throwIfError();
    return data;
  }

  /// Returns the data or null if error.
  T? get dataOrNull => hasError ? null : data;

  /// Returns the data or a default value if error.
  T dataOrElse(T defaultValue) => hasError ? defaultValue : data;
}

/// Exception thrown when a response has an error status.
class ResponseException implements Exception {
  /// Creates a new [ResponseException].
  const ResponseException({
    required this.statusCode,
    required this.message,
  });

  /// The HTTP status code.
  final int statusCode;

  /// The error message.
  final String message;

  @override
  String toString() => 'ResponseException($statusCode): $message';
}
