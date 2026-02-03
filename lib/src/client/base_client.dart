import 'dart:async';

import 'package:dio/dio.dart';

import '../response/response.dart';
import 'network_configuration.dart';

/// HTTP methods supported by the client.
enum HttpMethod {
  /// GET method for retrieving resources.
  get,

  /// POST method for creating resources.
  post,

  /// PUT method for replacing resources.
  put,

  /// PATCH method for partial updates.
  patch,

  /// DELETE method for removing resources.
  delete,

  /// HEAD method for retrieving headers only.
  head,

  /// OPTIONS method for retrieving supported methods.
  options,
}

/// Extension to convert [HttpMethod] to string.
extension HttpMethodExtension on HttpMethod {
  /// Returns the HTTP method name in uppercase.
  String get value {
    switch (this) {
      case HttpMethod.get:
        return 'GET';
      case HttpMethod.post:
        return 'POST';
      case HttpMethod.put:
        return 'PUT';
      case HttpMethod.patch:
        return 'PATCH';
      case HttpMethod.delete:
        return 'DELETE';
      case HttpMethod.head:
        return 'HEAD';
      case HttpMethod.options:
        return 'OPTIONS';
    }
  }

  /// Parses a string to [HttpMethod].
  static HttpMethod fromString(String method) {
    switch (method.toUpperCase()) {
      case 'GET':
        return HttpMethod.get;
      case 'POST':
        return HttpMethod.post;
      case 'PUT':
        return HttpMethod.put;
      case 'PATCH':
        return HttpMethod.patch;
      case 'DELETE':
        return HttpMethod.delete;
      case 'HEAD':
        return HttpMethod.head;
      case 'OPTIONS':
        return HttpMethod.options;
      default:
        throw ArgumentError('Unknown HTTP method: $method');
    }
  }
}

/// Abstract base class for network clients.
///
/// This class defines the contract for all network client implementations
/// and provides common functionality.
abstract class BaseClient {
  /// Creates a new [BaseClient] with the given configuration.
  BaseClient({required this.configuration});

  /// The configuration for this client.
  final NetworkConfiguration configuration;

  /// Performs a GET request.
  ///
  /// [path] is the URL path relative to the base URL.
  /// [queryParameters] are appended to the URL as query string.
  /// [headers] are merged with the default headers.
  /// [cancelToken] can be used to cancel the request.
  /// [decoder] is an optional function to parse the response.
  /// [useCache] determines whether to use cached responses.
  Future<NetworkResponse<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    CancelToken? cancelToken,
    T Function(dynamic)? decoder,
    bool useCache = true,
  });

  /// Performs a POST request.
  ///
  /// [path] is the URL path relative to the base URL.
  /// [body] is the request body.
  /// [queryParameters] are appended to the URL as query string.
  /// [headers] are merged with the default headers.
  /// [cancelToken] can be used to cancel the request.
  /// [decoder] is an optional function to parse the response.
  Future<NetworkResponse<T>> post<T>(
    String path, {
    dynamic body,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    CancelToken? cancelToken,
    T Function(dynamic)? decoder,
  });

  /// Performs a PUT request.
  ///
  /// [path] is the URL path relative to the base URL.
  /// [body] is the request body.
  /// [queryParameters] are appended to the URL as query string.
  /// [headers] are merged with the default headers.
  /// [cancelToken] can be used to cancel the request.
  /// [decoder] is an optional function to parse the response.
  Future<NetworkResponse<T>> put<T>(
    String path, {
    dynamic body,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    CancelToken? cancelToken,
    T Function(dynamic)? decoder,
  });

  /// Performs a PATCH request.
  ///
  /// [path] is the URL path relative to the base URL.
  /// [body] is the request body.
  /// [queryParameters] are appended to the URL as query string.
  /// [headers] are merged with the default headers.
  /// [cancelToken] can be used to cancel the request.
  /// [decoder] is an optional function to parse the response.
  Future<NetworkResponse<T>> patch<T>(
    String path, {
    dynamic body,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    CancelToken? cancelToken,
    T Function(dynamic)? decoder,
  });

  /// Performs a DELETE request.
  ///
  /// [path] is the URL path relative to the base URL.
  /// [body] is an optional request body.
  /// [queryParameters] are appended to the URL as query string.
  /// [headers] are merged with the default headers.
  /// [cancelToken] can be used to cancel the request.
  /// [decoder] is an optional function to parse the response.
  Future<NetworkResponse<T>> delete<T>(
    String path, {
    dynamic body,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    CancelToken? cancelToken,
    T Function(dynamic)? decoder,
  });

  /// Disposes the client and releases resources.
  void dispose();
}

/// Mixin that provides request building capabilities.
mixin RequestBuilderMixin {
  /// Builds a complete URL from path and query parameters.
  String buildUrl(
    String baseUrl,
    String path, {
    Map<String, dynamic>? queryParameters,
  }) {
    final uri = Uri.parse(baseUrl).resolve(path);

    if (queryParameters == null || queryParameters.isEmpty) {
      return uri.toString();
    }

    return uri.replace(
      queryParameters: {
        ...uri.queryParameters,
        ...queryParameters.map((key, value) => MapEntry(key, value.toString())),
      },
    ).toString();
  }

  /// Merges two header maps, with [override] taking precedence.
  Map<String, String> mergeHeaders(
    Map<String, String> base,
    Map<String, String>? override,
  ) {
    if (override == null || override.isEmpty) {
      return Map.from(base);
    }
    return {...base, ...override};
  }

  /// Validates that the path is not empty.
  void validatePath(String path) {
    if (path.isEmpty) {
      throw ArgumentError('Path cannot be empty');
    }
  }
}

/// A simple result type for handling success and failure cases.
sealed class Result<T> {
  const Result._();

  /// Creates a success result.
  const factory Result.success(T data) = Success<T>;

  /// Creates a failure result.
  const factory Result.failure(Exception error) = Failure<T>;

  /// Returns true if this is a success result.
  bool get isSuccess => this is Success<T>;

  /// Returns true if this is a failure result.
  bool get isFailure => this is Failure<T>;

  /// Returns the data if success, otherwise throws.
  T get data {
    if (this is Success<T>) {
      return (this as Success<T>)._data;
    }
    throw (this as Failure<T>)._error;
  }

  /// Returns the error if failure, otherwise null.
  Exception? get error {
    if (this is Failure<T>) {
      return (this as Failure<T>)._error;
    }
    return null;
  }

  /// Transforms the result using the given functions.
  R fold<R>({
    required R Function(T data) onSuccess,
    required R Function(Exception error) onFailure,
  }) {
    if (this is Success<T>) {
      return onSuccess((this as Success<T>)._data);
    }
    return onFailure((this as Failure<T>)._error);
  }

  /// Maps the success value to a new type.
  Result<R> map<R>(R Function(T data) mapper) {
    if (this is Success<T>) {
      return Result.success(mapper((this as Success<T>)._data));
    }
    return Result.failure((this as Failure<T>)._error);
  }

  /// Maps the error to a new type.
  Result<T> mapError(Exception Function(Exception error) mapper) {
    if (this is Failure<T>) {
      return Result.failure(mapper((this as Failure<T>)._error));
    }
    return this;
  }

  /// Returns the data or a default value.
  T getOrElse(T defaultValue) {
    if (this is Success<T>) {
      return (this as Success<T>)._data;
    }
    return defaultValue;
  }

  /// Returns the data or computes a default value.
  T getOrCompute(T Function() compute) {
    if (this is Success<T>) {
      return (this as Success<T>)._data;
    }
    return compute();
  }
}

/// A successful result containing data.
final class Success<T> extends Result<T> {
  /// Creates a success result with the given data.
  const Success(this._data) : super._();

  final T _data;

  @override
  String toString() => 'Success($_data)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Success<T> && other._data == _data;
  }

  @override
  int get hashCode => _data.hashCode;
}

/// A failed result containing an error.
final class Failure<T> extends Result<T> {
  /// Creates a failure result with the given error.
  const Failure(this._error) : super._();

  final Exception _error;

  @override
  String toString() => 'Failure($_error)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Failure<T> && other._error == _error;
  }

  @override
  int get hashCode => _error.hashCode;
}
