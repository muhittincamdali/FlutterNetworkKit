import 'dart:io';

import 'package:dio/dio.dart';

/// Represents an API error with detailed information.
///
/// This class provides a structured way to handle and represent
/// HTTP errors with proper error codes, messages, and additional data.
///
/// Example:
/// ```dart
/// try {
///   await client.get('/users/1');
/// } on ApiError catch (e) {
///   print('Error ${e.statusCode}: ${e.message}');
///   print('Errors: ${e.validationErrors}');
/// }
/// ```
class ApiError implements Exception {
  /// Creates a new [ApiError].
  const ApiError({
    required this.statusCode,
    required this.message,
    this.errorCode,
    this.details,
    this.validationErrors,
    this.requestPath,
    this.requestMethod,
    this.timestamp,
    this.traceId,
  });

  /// Creates an [ApiError] from a Dio error.
  factory ApiError.fromDioError(DioException error) {
    final response = error.response;
    final data = response?.data;

    String message = error.message ?? 'Unknown error';
    String? errorCode;
    Map<String, List<String>>? validationErrors;
    Map<String, dynamic>? details;

    // Try to parse error details from response
    if (data is Map<String, dynamic>) {
      message = data['message'] as String? ??
          data['error'] as String? ??
          message;
      errorCode = data['code'] as String? ??
          data['error_code'] as String?;

      if (data['errors'] is Map) {
        validationErrors = (data['errors'] as Map<String, dynamic>).map(
          (key, value) => MapEntry(
            key,
            value is List
                ? value.map((e) => e.toString()).toList()
                : [value.toString()],
          ),
        );
      }

      details = data['details'] as Map<String, dynamic>?;
    }

    return ApiError(
      statusCode: response?.statusCode ?? _mapDioErrorToStatusCode(error.type),
      message: message,
      errorCode: errorCode,
      details: details,
      validationErrors: validationErrors,
      requestPath: error.requestOptions.path,
      requestMethod: error.requestOptions.method,
      timestamp: DateTime.now(),
    );
  }

  /// Creates an [ApiError] from an HTTP response.
  factory ApiError.fromResponse(int statusCode, dynamic data) {
    String message = 'Request failed';
    String? errorCode;
    Map<String, List<String>>? validationErrors;

    if (data is Map<String, dynamic>) {
      message = data['message'] as String? ??
          data['error'] as String? ??
          message;
      errorCode = data['code'] as String?;

      if (data['errors'] is Map) {
        validationErrors = (data['errors'] as Map<String, dynamic>).map(
          (key, value) => MapEntry(
            key,
            value is List
                ? value.map((e) => e.toString()).toList()
                : [value.toString()],
          ),
        );
      }
    } else if (data is String) {
      message = data;
    }

    return ApiError(
      statusCode: statusCode,
      message: message,
      errorCode: errorCode,
      validationErrors: validationErrors,
      timestamp: DateTime.now(),
    );
  }

  /// Creates a network error (no internet connection).
  factory ApiError.network([String? message]) {
    return ApiError(
      statusCode: 0,
      message: message ?? 'Network error. Please check your connection.',
      errorCode: 'NETWORK_ERROR',
      timestamp: DateTime.now(),
    );
  }

  /// Creates a timeout error.
  factory ApiError.timeout([String? message]) {
    return ApiError(
      statusCode: 408,
      message: message ?? 'Request timed out. Please try again.',
      errorCode: 'TIMEOUT_ERROR',
      timestamp: DateTime.now(),
    );
  }

  /// Creates a cancelled error.
  factory ApiError.cancelled([String? message]) {
    return ApiError(
      statusCode: 499,
      message: message ?? 'Request was cancelled.',
      errorCode: 'CANCELLED',
      timestamp: DateTime.now(),
    );
  }

  /// Creates an unauthorized error.
  factory ApiError.unauthorized([String? message]) {
    return ApiError(
      statusCode: 401,
      message: message ?? 'Unauthorized. Please login again.',
      errorCode: 'UNAUTHORIZED',
      timestamp: DateTime.now(),
    );
  }

  /// Creates a forbidden error.
  factory ApiError.forbidden([String? message]) {
    return ApiError(
      statusCode: 403,
      message: message ?? 'Access denied.',
      errorCode: 'FORBIDDEN',
      timestamp: DateTime.now(),
    );
  }

  /// Creates a not found error.
  factory ApiError.notFound([String? message]) {
    return ApiError(
      statusCode: 404,
      message: message ?? 'Resource not found.',
      errorCode: 'NOT_FOUND',
      timestamp: DateTime.now(),
    );
  }

  /// Creates a server error.
  factory ApiError.serverError([String? message]) {
    return ApiError(
      statusCode: 500,
      message: message ?? 'Server error. Please try again later.',
      errorCode: 'SERVER_ERROR',
      timestamp: DateTime.now(),
    );
  }

  /// The HTTP status code.
  final int statusCode;

  /// The error message.
  final String message;

  /// An application-specific error code.
  final String? errorCode;

  /// Additional error details.
  final Map<String, dynamic>? details;

  /// Validation errors keyed by field name.
  final Map<String, List<String>>? validationErrors;

  /// The path of the failed request.
  final String? requestPath;

  /// The HTTP method of the failed request.
  final String? requestMethod;

  /// When the error occurred.
  final DateTime? timestamp;

  /// A trace ID for debugging.
  final String? traceId;

  /// Returns true if this is a network error.
  bool get isNetworkError => statusCode == 0;

  /// Returns true if this is a timeout error.
  bool get isTimeout => statusCode == 408;

  /// Returns true if this is a client error (4xx).
  bool get isClientError => statusCode >= 400 && statusCode < 500;

  /// Returns true if this is a server error (5xx).
  bool get isServerError => statusCode >= 500;

  /// Returns true if this is an unauthorized error.
  bool get isUnauthorized => statusCode == 401;

  /// Returns true if this is a forbidden error.
  bool get isForbidden => statusCode == 403;

  /// Returns true if this is a not found error.
  bool get isNotFound => statusCode == 404;

  /// Returns true if this has validation errors.
  bool get hasValidationErrors =>
      validationErrors != null && validationErrors!.isNotEmpty;

  /// Gets all validation error messages as a flat list.
  List<String> get allValidationErrors {
    if (validationErrors == null) return [];
    return validationErrors!.values.expand((errors) => errors).toList();
  }

  /// Gets the first validation error for a field.
  String? getValidationError(String field) {
    return validationErrors?[field]?.firstOrNull;
  }

  /// Returns a JSON representation.
  Map<String, dynamic> toJson() {
    return {
      'statusCode': statusCode,
      'message': message,
      if (errorCode != null) 'errorCode': errorCode,
      if (details != null) 'details': details,
      if (validationErrors != null) 'validationErrors': validationErrors,
      if (requestPath != null) 'requestPath': requestPath,
      if (requestMethod != null) 'requestMethod': requestMethod,
      if (timestamp != null) 'timestamp': timestamp!.toIso8601String(),
      if (traceId != null) 'traceId': traceId,
    };
  }

  @override
  String toString() {
    final buffer = StringBuffer('ApiError($statusCode): $message');
    if (errorCode != null) buffer.write(' [Code: $errorCode]');
    if (requestPath != null) buffer.write(' [Path: $requestPath]');
    return buffer.toString();
  }

  static int _mapDioErrorToStatusCode(DioExceptionType type) {
    switch (type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 408;
      case DioExceptionType.cancel:
        return 499;
      case DioExceptionType.connectionError:
        return 0;
      default:
        return 0;
    }
  }
}

/// Extension for working with API errors.
extension ApiErrorExtension on ApiError {
  /// Returns a user-friendly error message.
  String get userMessage {
    if (isNetworkError) {
      return 'Unable to connect. Please check your internet connection.';
    }
    if (isTimeout) {
      return 'The request took too long. Please try again.';
    }
    if (isUnauthorized) {
      return 'Your session has expired. Please login again.';
    }
    if (isForbidden) {
      return 'You do not have permission to perform this action.';
    }
    if (isNotFound) {
      return 'The requested resource was not found.';
    }
    if (isServerError) {
      return 'Something went wrong on our end. Please try again later.';
    }
    return message;
  }

  /// Returns true if this error should trigger a retry.
  bool get shouldRetry {
    if (isNetworkError) return true;
    if (isTimeout) return true;
    if (statusCode >= 500 && statusCode < 600) return true;
    return false;
  }

  /// Returns true if this error should trigger token refresh.
  bool get shouldRefreshToken => isUnauthorized;
}
