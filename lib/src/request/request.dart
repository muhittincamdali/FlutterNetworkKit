import 'dart:convert';

import 'package:dio/dio.dart';

import '../client/base_client.dart';

/// Represents an HTTP request with all its components.
///
/// This class encapsulates the request method, URL, headers, body,
/// and other request configuration options.
///
/// Example:
/// ```dart
/// final request = NetworkRequest(
///   method: HttpMethod.post,
///   path: '/users',
///   body: {'name': 'John', 'email': 'john@example.com'},
///   headers: {'Authorization': 'Bearer token'},
/// );
/// ```
class NetworkRequest {
  /// Creates a new [NetworkRequest].
  const NetworkRequest({
    required this.method,
    required this.path,
    this.baseUrl,
    this.queryParameters,
    this.headers,
    this.body,
    this.contentType,
    this.responseType = ResponseType.json,
    this.extra,
    this.followRedirects = true,
    this.maxRedirects = 5,
    this.receiveTimeout,
    this.sendTimeout,
    this.validateStatus,
    this.cancelToken,
  });

  /// Creates a [NetworkRequest] from Dio [RequestOptions].
  factory NetworkRequest.fromDioOptions(RequestOptions options) {
    return NetworkRequest(
      method: HttpMethodExtension.fromString(options.method),
      path: options.path,
      baseUrl: options.baseUrl,
      queryParameters: options.queryParameters,
      headers: options.headers.map((key, value) => MapEntry(key, value.toString())),
      body: options.data,
      contentType: options.contentType,
      responseType: options.responseType,
      extra: options.extra,
      followRedirects: options.followRedirects,
      maxRedirects: options.maxRedirects,
      receiveTimeout: options.receiveTimeout,
      sendTimeout: options.sendTimeout,
      validateStatus: options.validateStatus,
    );
  }

  /// Creates a GET request.
  factory NetworkRequest.get(
    String path, {
    String? baseUrl,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
  }) {
    return NetworkRequest(
      method: HttpMethod.get,
      path: path,
      baseUrl: baseUrl,
      queryParameters: queryParameters,
      headers: headers,
    );
  }

  /// Creates a POST request.
  factory NetworkRequest.post(
    String path, {
    String? baseUrl,
    dynamic body,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
  }) {
    return NetworkRequest(
      method: HttpMethod.post,
      path: path,
      baseUrl: baseUrl,
      body: body,
      queryParameters: queryParameters,
      headers: headers,
    );
  }

  /// Creates a PUT request.
  factory NetworkRequest.put(
    String path, {
    String? baseUrl,
    dynamic body,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
  }) {
    return NetworkRequest(
      method: HttpMethod.put,
      path: path,
      baseUrl: baseUrl,
      body: body,
      queryParameters: queryParameters,
      headers: headers,
    );
  }

  /// Creates a PATCH request.
  factory NetworkRequest.patch(
    String path, {
    String? baseUrl,
    dynamic body,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
  }) {
    return NetworkRequest(
      method: HttpMethod.patch,
      path: path,
      baseUrl: baseUrl,
      body: body,
      queryParameters: queryParameters,
      headers: headers,
    );
  }

  /// Creates a DELETE request.
  factory NetworkRequest.delete(
    String path, {
    String? baseUrl,
    dynamic body,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
  }) {
    return NetworkRequest(
      method: HttpMethod.delete,
      path: path,
      baseUrl: baseUrl,
      body: body,
      queryParameters: queryParameters,
      headers: headers,
    );
  }

  /// The HTTP method for this request.
  final HttpMethod method;

  /// The URL path for this request.
  final String path;

  /// The base URL to use for this request.
  final String? baseUrl;

  /// Query parameters to append to the URL.
  final Map<String, dynamic>? queryParameters;

  /// Headers to include in the request.
  final Map<String, String>? headers;

  /// The request body.
  final dynamic body;

  /// The content type of the request body.
  final String? contentType;

  /// The expected response type.
  final ResponseType responseType;

  /// Extra data associated with this request.
  final Map<String, dynamic>? extra;

  /// Whether to follow redirects.
  final bool followRedirects;

  /// Maximum number of redirects to follow.
  final int maxRedirects;

  /// The receive timeout for this request.
  final Duration? receiveTimeout;

  /// The send timeout for this request.
  final Duration? sendTimeout;

  /// Custom status validation function.
  final bool Function(int?)? validateStatus;

  /// Token to cancel this request.
  final CancelToken? cancelToken;

  /// Returns the full URL including query parameters.
  String get fullUrl {
    final uri = baseUrl != null
        ? Uri.parse(baseUrl!).resolve(path)
        : Uri.parse(path);

    if (queryParameters == null || queryParameters!.isEmpty) {
      return uri.toString();
    }

    return uri.replace(
      queryParameters: queryParameters!.map(
        (key, value) => MapEntry(key, value.toString()),
      ),
    ).toString();
  }

  /// Returns true if this request has a body.
  bool get hasBody => body != null;

  /// Returns true if this is a GET request.
  bool get isGet => method == HttpMethod.get;

  /// Returns true if this is a POST request.
  bool get isPost => method == HttpMethod.post;

  /// Returns true if this is a PUT request.
  bool get isPut => method == HttpMethod.put;

  /// Returns true if this is a PATCH request.
  bool get isPatch => method == HttpMethod.patch;

  /// Returns true if this is a DELETE request.
  bool get isDelete => method == HttpMethod.delete;

  /// Converts this request to Dio [RequestOptions].
  RequestOptions toDioOptions() {
    return RequestOptions(
      method: method.value,
      path: path,
      baseUrl: baseUrl ?? '',
      queryParameters: queryParameters ?? {},
      headers: headers ?? {},
      data: body,
      contentType: contentType,
      responseType: responseType,
      extra: extra ?? {},
      followRedirects: followRedirects,
      maxRedirects: maxRedirects,
      receiveTimeout: receiveTimeout,
      sendTimeout: sendTimeout,
      validateStatus: validateStatus,
    );
  }

  /// Creates a copy of this request with the specified overrides.
  NetworkRequest copyWith({
    HttpMethod? method,
    String? path,
    String? baseUrl,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    dynamic body,
    String? contentType,
    ResponseType? responseType,
    Map<String, dynamic>? extra,
    bool? followRedirects,
    int? maxRedirects,
    Duration? receiveTimeout,
    Duration? sendTimeout,
    bool Function(int?)? validateStatus,
    CancelToken? cancelToken,
  }) {
    return NetworkRequest(
      method: method ?? this.method,
      path: path ?? this.path,
      baseUrl: baseUrl ?? this.baseUrl,
      queryParameters: queryParameters ?? this.queryParameters,
      headers: headers ?? this.headers,
      body: body ?? this.body,
      contentType: contentType ?? this.contentType,
      responseType: responseType ?? this.responseType,
      extra: extra ?? this.extra,
      followRedirects: followRedirects ?? this.followRedirects,
      maxRedirects: maxRedirects ?? this.maxRedirects,
      receiveTimeout: receiveTimeout ?? this.receiveTimeout,
      sendTimeout: sendTimeout ?? this.sendTimeout,
      validateStatus: validateStatus ?? this.validateStatus,
      cancelToken: cancelToken ?? this.cancelToken,
    );
  }

  /// Returns a JSON representation of this request for logging.
  Map<String, dynamic> toJson() {
    return {
      'method': method.value,
      'path': path,
      if (baseUrl != null) 'baseUrl': baseUrl,
      if (queryParameters != null) 'queryParameters': queryParameters,
      if (headers != null) 'headers': headers,
      if (body != null) 'body': _serializeBody(body),
      if (contentType != null) 'contentType': contentType,
      'responseType': responseType.name,
    };
  }

  dynamic _serializeBody(dynamic body) {
    if (body == null) return null;
    if (body is String) return body;
    if (body is Map || body is List) return body;
    try {
      return body.toJson();
    } catch (_) {
      return body.toString();
    }
  }

  @override
  String toString() {
    return 'NetworkRequest('
        'method: ${method.value}, '
        'path: $path, '
        'baseUrl: $baseUrl, '
        'hasBody: $hasBody'
        ')';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NetworkRequest &&
        other.method == method &&
        other.path == path &&
        other.baseUrl == baseUrl;
  }

  @override
  int get hashCode => Object.hash(method, path, baseUrl);
}

/// Extension methods for request manipulation.
extension NetworkRequestExtension on NetworkRequest {
  /// Adds a header to this request.
  NetworkRequest addHeader(String name, String value) {
    final newHeaders = Map<String, String>.from(headers ?? {});
    newHeaders[name] = value;
    return copyWith(headers: newHeaders);
  }

  /// Removes a header from this request.
  NetworkRequest removeHeader(String name) {
    if (headers == null) return this;
    final newHeaders = Map<String, String>.from(headers!);
    newHeaders.remove(name);
    return copyWith(headers: newHeaders);
  }

  /// Adds a query parameter to this request.
  NetworkRequest addQueryParameter(String name, dynamic value) {
    final newParams = Map<String, dynamic>.from(queryParameters ?? {});
    newParams[name] = value;
    return copyWith(queryParameters: newParams);
  }

  /// Removes a query parameter from this request.
  NetworkRequest removeQueryParameter(String name) {
    if (queryParameters == null) return this;
    final newParams = Map<String, dynamic>.from(queryParameters!);
    newParams.remove(name);
    return copyWith(queryParameters: newParams);
  }

  /// Adds extra data to this request.
  NetworkRequest addExtra(String key, dynamic value) {
    final newExtra = Map<String, dynamic>.from(extra ?? {});
    newExtra[key] = value;
    return copyWith(extra: newExtra);
  }

  /// Sets the authorization header.
  NetworkRequest withAuthorization(String token, {String type = 'Bearer'}) {
    return addHeader('Authorization', '$type $token');
  }

  /// Sets the content type header.
  NetworkRequest withContentType(String contentType) {
    return copyWith(contentType: contentType);
  }

  /// Sets the accept header.
  NetworkRequest withAccept(String accept) {
    return addHeader('Accept', accept);
  }
}
