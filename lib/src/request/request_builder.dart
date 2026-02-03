import 'dart:async';

import 'package:dio/dio.dart';

import '../client/base_client.dart';
import '../client/network_client.dart';
import '../response/response.dart';
import 'request.dart';
import 'multipart_request.dart';

/// A fluent builder for constructing HTTP requests.
///
/// The [RequestBuilder] provides a chainable API for building requests
/// with all necessary options before execution.
///
/// Example:
/// ```dart
/// final response = await client.request()
///     .path('/users')
///     .method(HttpMethod.get)
///     .queryParam('page', 1)
///     .header('X-Custom', 'value')
///     .execute<List<User>>();
/// ```
class RequestBuilder {
  /// Creates a new [RequestBuilder] with the given client.
  RequestBuilder({required this.client});

  /// The network client to use for execution.
  final NetworkClient client;

  HttpMethod _method = HttpMethod.get;
  String _path = '';
  String? _baseUrl;
  final Map<String, dynamic> _queryParameters = {};
  final Map<String, String> _headers = {};
  dynamic _body;
  String? _contentType;
  ResponseType _responseType = ResponseType.json;
  final Map<String, dynamic> _extra = {};
  bool _followRedirects = true;
  int _maxRedirects = 5;
  Duration? _receiveTimeout;
  Duration? _sendTimeout;
  bool Function(int?)? _validateStatus;
  CancelToken? _cancelToken;
  bool _useCache = true;

  /// Sets the HTTP method for this request.
  RequestBuilder method(HttpMethod method) {
    _method = method;
    return this;
  }

  /// Sets the request to GET method.
  RequestBuilder get() {
    _method = HttpMethod.get;
    return this;
  }

  /// Sets the request to POST method.
  RequestBuilder post() {
    _method = HttpMethod.post;
    return this;
  }

  /// Sets the request to PUT method.
  RequestBuilder put() {
    _method = HttpMethod.put;
    return this;
  }

  /// Sets the request to PATCH method.
  RequestBuilder patch() {
    _method = HttpMethod.patch;
    return this;
  }

  /// Sets the request to DELETE method.
  RequestBuilder delete() {
    _method = HttpMethod.delete;
    return this;
  }

  /// Sets the URL path for this request.
  RequestBuilder path(String path) {
    _path = path;
    return this;
  }

  /// Sets the base URL for this request.
  RequestBuilder baseUrl(String baseUrl) {
    _baseUrl = baseUrl;
    return this;
  }

  /// Adds a query parameter to this request.
  RequestBuilder queryParam(String name, dynamic value) {
    _queryParameters[name] = value;
    return this;
  }

  /// Adds multiple query parameters to this request.
  RequestBuilder queryParams(Map<String, dynamic> params) {
    _queryParameters.addAll(params);
    return this;
  }

  /// Adds a header to this request.
  RequestBuilder header(String name, String value) {
    _headers[name] = value;
    return this;
  }

  /// Adds multiple headers to this request.
  RequestBuilder headers(Map<String, String> headers) {
    _headers.addAll(headers);
    return this;
  }

  /// Sets the authorization header with a Bearer token.
  RequestBuilder authorization(String token) {
    _headers['Authorization'] = 'Bearer $token';
    return this;
  }

  /// Sets the authorization header with a custom type.
  RequestBuilder authorizationWith(String token, String type) {
    _headers['Authorization'] = '$type $token';
    return this;
  }

  /// Sets basic authentication.
  RequestBuilder basicAuth(String username, String password) {
    final credentials = '$username:$password';
    final encoded = Uri.encodeComponent(credentials);
    _headers['Authorization'] = 'Basic $encoded';
    return this;
  }

  /// Sets the request body.
  RequestBuilder body(dynamic body) {
    _body = body;
    return this;
  }

  /// Sets the request body as JSON.
  RequestBuilder json(Map<String, dynamic> json) {
    _body = json;
    _contentType = 'application/json';
    return this;
  }

  /// Sets the request body as form data.
  RequestBuilder form(Map<String, dynamic> form) {
    _body = FormData.fromMap(form);
    _contentType = 'application/x-www-form-urlencoded';
    return this;
  }

  /// Sets the content type for this request.
  RequestBuilder contentType(String contentType) {
    _contentType = contentType;
    return this;
  }

  /// Sets the expected response type.
  RequestBuilder responseType(ResponseType type) {
    _responseType = type;
    return this;
  }

  /// Expects JSON response.
  RequestBuilder expectJson() {
    _responseType = ResponseType.json;
    return this;
  }

  /// Expects plain text response.
  RequestBuilder expectText() {
    _responseType = ResponseType.plain;
    return this;
  }

  /// Expects stream response.
  RequestBuilder expectStream() {
    _responseType = ResponseType.stream;
    return this;
  }

  /// Expects bytes response.
  RequestBuilder expectBytes() {
    _responseType = ResponseType.bytes;
    return this;
  }

  /// Adds extra data to this request.
  RequestBuilder extra(String key, dynamic value) {
    _extra[key] = value;
    return this;
  }

  /// Sets whether to follow redirects.
  RequestBuilder followRedirects(bool follow) {
    _followRedirects = follow;
    return this;
  }

  /// Sets the maximum number of redirects.
  RequestBuilder maxRedirects(int max) {
    _maxRedirects = max;
    return this;
  }

  /// Sets the receive timeout.
  RequestBuilder receiveTimeout(Duration timeout) {
    _receiveTimeout = timeout;
    return this;
  }

  /// Sets the send timeout.
  RequestBuilder sendTimeout(Duration timeout) {
    _sendTimeout = timeout;
    return this;
  }

  /// Sets both receive and send timeouts.
  RequestBuilder timeout(Duration timeout) {
    _receiveTimeout = timeout;
    _sendTimeout = timeout;
    return this;
  }

  /// Sets a custom status validation function.
  RequestBuilder validateStatus(bool Function(int?) validator) {
    _validateStatus = validator;
    return this;
  }

  /// Accepts any status code.
  RequestBuilder acceptAnyStatus() {
    _validateStatus = (_) => true;
    return this;
  }

  /// Sets a cancel token for this request.
  RequestBuilder cancelToken(CancelToken token) {
    _cancelToken = token;
    return this;
  }

  /// Sets whether to use cache for this request.
  RequestBuilder useCache(bool use) {
    _useCache = use;
    return this;
  }

  /// Disables caching for this request.
  RequestBuilder noCache() {
    _useCache = false;
    return this;
  }

  /// Builds the [NetworkRequest] without executing it.
  NetworkRequest build() {
    return NetworkRequest(
      method: _method,
      path: _path,
      baseUrl: _baseUrl,
      queryParameters: _queryParameters.isNotEmpty ? _queryParameters : null,
      headers: _headers.isNotEmpty ? _headers : null,
      body: _body,
      contentType: _contentType,
      responseType: _responseType,
      extra: _extra.isNotEmpty ? _extra : null,
      followRedirects: _followRedirects,
      maxRedirects: _maxRedirects,
      receiveTimeout: _receiveTimeout,
      sendTimeout: _sendTimeout,
      validateStatus: _validateStatus,
      cancelToken: _cancelToken,
    );
  }

  /// Executes the request and returns the response.
  ///
  /// [T] is the expected response type.
  /// [decoder] is an optional function to parse the response.
  Future<NetworkResponse<T>> execute<T>({
    T Function(dynamic)? decoder,
  }) async {
    switch (_method) {
      case HttpMethod.get:
        return client.get<T>(
          _path,
          queryParameters: _queryParameters.isNotEmpty ? _queryParameters : null,
          headers: _headers.isNotEmpty ? _headers : null,
          cancelToken: _cancelToken,
          decoder: decoder,
          useCache: _useCache,
        );
      case HttpMethod.post:
        return client.post<T>(
          _path,
          body: _body,
          queryParameters: _queryParameters.isNotEmpty ? _queryParameters : null,
          headers: _headers.isNotEmpty ? _headers : null,
          cancelToken: _cancelToken,
          decoder: decoder,
        );
      case HttpMethod.put:
        return client.put<T>(
          _path,
          body: _body,
          queryParameters: _queryParameters.isNotEmpty ? _queryParameters : null,
          headers: _headers.isNotEmpty ? _headers : null,
          cancelToken: _cancelToken,
          decoder: decoder,
        );
      case HttpMethod.patch:
        return client.patch<T>(
          _path,
          body: _body,
          queryParameters: _queryParameters.isNotEmpty ? _queryParameters : null,
          headers: _headers.isNotEmpty ? _headers : null,
          cancelToken: _cancelToken,
          decoder: decoder,
        );
      case HttpMethod.delete:
        return client.delete<T>(
          _path,
          body: _body,
          queryParameters: _queryParameters.isNotEmpty ? _queryParameters : null,
          headers: _headers.isNotEmpty ? _headers : null,
          cancelToken: _cancelToken,
          decoder: decoder,
        );
      case HttpMethod.head:
      case HttpMethod.options:
        throw UnsupportedError('${_method.value} method not supported in builder');
    }
  }

  /// Resets the builder to its initial state.
  RequestBuilder reset() {
    _method = HttpMethod.get;
    _path = '';
    _baseUrl = null;
    _queryParameters.clear();
    _headers.clear();
    _body = null;
    _contentType = null;
    _responseType = ResponseType.json;
    _extra.clear();
    _followRedirects = true;
    _maxRedirects = 5;
    _receiveTimeout = null;
    _sendTimeout = null;
    _validateStatus = null;
    _cancelToken = null;
    _useCache = true;
    return this;
  }

  @override
  String toString() {
    return 'RequestBuilder('
        'method: ${_method.value}, '
        'path: $_path'
        ')';
  }
}

/// A builder for batch requests.
class BatchRequestBuilder {
  /// Creates a new [BatchRequestBuilder].
  BatchRequestBuilder({required this.client});

  /// The network client to use for execution.
  final NetworkClient client;

  final List<RequestBuilder> _requests = [];

  /// Adds a request to the batch.
  BatchRequestBuilder add(RequestBuilder request) {
    _requests.add(request);
    return this;
  }

  /// Creates and adds a GET request to the batch.
  BatchRequestBuilder get(String path, {Map<String, dynamic>? queryParameters}) {
    _requests.add(
      RequestBuilder(client: client)
          .get()
          .path(path)
          ..queryParams(queryParameters ?? {}),
    );
    return this;
  }

  /// Creates and adds a POST request to the batch.
  BatchRequestBuilder post(String path, {dynamic body}) {
    _requests.add(
      RequestBuilder(client: client)
          .post()
          .path(path)
          .body(body),
    );
    return this;
  }

  /// Executes all requests in parallel.
  ///
  /// Returns a list of results, one for each request.
  /// Failed requests will have their error in the corresponding position.
  Future<List<BatchResult>> executeParallel() async {
    final futures = _requests.map((r) async {
      try {
        final response = await r.execute<dynamic>();
        return BatchResult.success(response);
      } catch (e) {
        return BatchResult.failure(e as Exception);
      }
    });

    return Future.wait(futures);
  }

  /// Executes all requests sequentially.
  ///
  /// [stopOnError] determines whether to stop on the first error.
  Future<List<BatchResult>> executeSequential({bool stopOnError = false}) async {
    final results = <BatchResult>[];

    for (final request in _requests) {
      try {
        final response = await request.execute<dynamic>();
        results.add(BatchResult.success(response));
      } catch (e) {
        results.add(BatchResult.failure(e as Exception));
        if (stopOnError) break;
      }
    }

    return results;
  }

  /// Clears all requests from the batch.
  void clear() {
    _requests.clear();
  }

  /// Returns the number of requests in the batch.
  int get length => _requests.length;

  /// Returns true if the batch is empty.
  bool get isEmpty => _requests.isEmpty;
}

/// Result of a batch request.
class BatchResult {
  const BatchResult._({
    this.response,
    this.error,
    required this.isSuccess,
  });

  /// Creates a successful batch result.
  factory BatchResult.success(NetworkResponse<dynamic> response) {
    return BatchResult._(response: response, isSuccess: true);
  }

  /// Creates a failed batch result.
  factory BatchResult.failure(Exception error) {
    return BatchResult._(error: error, isSuccess: false);
  }

  /// The response if successful.
  final NetworkResponse<dynamic>? response;

  /// The error if failed.
  final Exception? error;

  /// Whether this result is successful.
  final bool isSuccess;

  /// Whether this result is a failure.
  bool get isFailure => !isSuccess;
}
