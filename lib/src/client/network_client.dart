import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../interceptors/interceptor.dart';
import '../request/request.dart';
import '../request/request_builder.dart';
import '../request/multipart_request.dart';
import '../response/response.dart' as network;
import '../response/api_error.dart';
import '../cache/cache_manager.dart';
import '../monitoring/network_monitor.dart';
import '../monitoring/request_metrics.dart';
import 'network_configuration.dart';
import 'base_client.dart';

/// Main network client for making HTTP requests.
///
/// The [NetworkClient] provides a comprehensive API for making HTTP requests
/// with support for interceptors, caching, retry logic, and monitoring.
///
/// Example:
/// ```dart
/// final client = NetworkClient(
///   configuration: NetworkConfiguration(
///     baseUrl: 'https://api.example.com',
///   ),
/// );
///
/// // GET request
/// final users = await client.get<List<User>>('/users');
///
/// // POST request with body
/// final newUser = await client.post<User>('/users', body: userData);
/// ```
class NetworkClient extends BaseClient {
  /// Creates a new [NetworkClient] with the given configuration.
  NetworkClient({
    required NetworkConfiguration configuration,
    List<NetworkInterceptor>? interceptors,
    CacheManager? cacheManager,
    NetworkMonitor? monitor,
  })  : _configuration = configuration,
        _interceptors = interceptors ?? [],
        _cacheManager = cacheManager,
        _monitor = monitor ?? NetworkMonitor(),
        super(configuration: configuration) {
    _initializeDio();
  }

  final NetworkConfiguration _configuration;
  final List<NetworkInterceptor> _interceptors;
  final CacheManager? _cacheManager;
  final NetworkMonitor _monitor;
  late final Dio _dio;

  /// The underlying Dio instance for advanced use cases.
  Dio get dio => _dio;

  /// The current configuration.
  NetworkConfiguration get configuration => _configuration;

  /// The list of registered interceptors.
  List<NetworkInterceptor> get interceptors => List.unmodifiable(_interceptors);

  /// The cache manager instance.
  CacheManager? get cacheManager => _cacheManager;

  /// The network monitor instance.
  NetworkMonitor get monitor => _monitor;

  void _initializeDio() {
    _dio = Dio(BaseOptions(
      baseUrl: _configuration.baseUrl,
      connectTimeout: _configuration.connectTimeout,
      receiveTimeout: _configuration.receiveTimeout,
      sendTimeout: _configuration.sendTimeout,
      headers: _configuration.defaultHeaders,
      validateStatus: _configuration.validateStatus,
      followRedirects: _configuration.followRedirects,
      maxRedirects: _configuration.maxRedirects,
    ));

    // Add interceptors to Dio
    for (final interceptor in _interceptors) {
      _dio.interceptors.add(_wrapInterceptor(interceptor));
    }
  }

  InterceptorsWrapper _wrapInterceptor(NetworkInterceptor interceptor) {
    return InterceptorsWrapper(
      onRequest: (options, handler) async {
        final request = NetworkRequest.fromDioOptions(options);
        final result = await interceptor.onRequest(request);
        result.when(
          next: (req) => handler.next(req.toDioOptions()),
          reject: (error) => handler.reject(DioException(
            requestOptions: options,
            error: error,
          )),
          resolve: (response) => handler.resolve(Response(
            requestOptions: options,
            data: response.data,
            statusCode: response.statusCode,
          )),
        );
      },
      onResponse: (response, handler) async {
        final networkResponse = network.NetworkResponse.fromDioResponse(response);
        final result = await interceptor.onResponse(networkResponse);
        result.when(
          next: (res) => handler.next(res.toDioResponse()),
          reject: (error) => handler.reject(DioException(
            requestOptions: response.requestOptions,
            error: error,
          )),
        );
      },
      onError: (error, handler) async {
        final apiError = ApiError.fromDioError(error);
        final result = await interceptor.onError(apiError);
        result.when(
          next: (err) => handler.next(DioException(
            requestOptions: error.requestOptions,
            error: err,
          )),
          resolve: (response) => handler.resolve(Response(
            requestOptions: error.requestOptions,
            data: response.data,
            statusCode: response.statusCode,
          )),
        );
      },
    );
  }

  /// Performs a GET request to the specified [path].
  ///
  /// [T] is the expected response type.
  /// [queryParameters] are appended to the URL.
  /// [headers] are merged with default headers.
  /// [cancelToken] can be used to cancel the request.
  ///
  /// Returns a [NetworkResponse] containing the parsed data.
  ///
  /// Throws [ApiError] if the request fails.
  @override
  Future<network.NetworkResponse<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    CancelToken? cancelToken,
    T Function(dynamic)? decoder,
    bool useCache = true,
  }) async {
    final metrics = RequestMetrics.start(HttpMethod.get, path);

    try {
      // Check cache first if enabled
      if (useCache && _cacheManager != null) {
        final cached = await _cacheManager!.get<T>(
          _buildCacheKey(path, queryParameters),
        );
        if (cached != null) {
          metrics.complete(statusCode: 200, fromCache: true);
          _monitor.recordMetrics(metrics);
          return network.NetworkResponse<T>(
            data: cached,
            statusCode: 200,
            fromCache: true,
          );
        }
      }

      final response = await _dio.get<dynamic>(
        path,
        queryParameters: queryParameters,
        options: Options(headers: headers),
        cancelToken: cancelToken,
      );

      final parsedData = decoder != null
          ? decoder(response.data)
          : response.data as T;

      // Store in cache if enabled
      if (useCache && _cacheManager != null) {
        await _cacheManager!.set(
          _buildCacheKey(path, queryParameters),
          parsedData,
        );
      }

      metrics.complete(
        statusCode: response.statusCode,
        responseSize: _calculateResponseSize(response),
      );
      _monitor.recordMetrics(metrics);

      return network.NetworkResponse<T>(
        data: parsedData,
        statusCode: response.statusCode ?? 200,
        headers: response.headers.map,
        requestTime: metrics.duration,
      );
    } on DioException catch (e) {
      metrics.complete(
        statusCode: e.response?.statusCode,
        error: e.message,
      );
      _monitor.recordMetrics(metrics);
      throw ApiError.fromDioError(e);
    }
  }

  /// Performs a POST request to the specified [path].
  ///
  /// [body] is the request body, which will be serialized to JSON.
  /// [T] is the expected response type.
  @override
  Future<network.NetworkResponse<T>> post<T>(
    String path, {
    dynamic body,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    CancelToken? cancelToken,
    T Function(dynamic)? decoder,
  }) async {
    final metrics = RequestMetrics.start(HttpMethod.post, path);

    try {
      final response = await _dio.post<dynamic>(
        path,
        data: body,
        queryParameters: queryParameters,
        options: Options(headers: headers),
        cancelToken: cancelToken,
      );

      final parsedData = decoder != null
          ? decoder(response.data)
          : response.data as T;

      metrics.complete(
        statusCode: response.statusCode,
        responseSize: _calculateResponseSize(response),
      );
      _monitor.recordMetrics(metrics);

      return network.NetworkResponse<T>(
        data: parsedData,
        statusCode: response.statusCode ?? 200,
        headers: response.headers.map,
        requestTime: metrics.duration,
      );
    } on DioException catch (e) {
      metrics.complete(
        statusCode: e.response?.statusCode,
        error: e.message,
      );
      _monitor.recordMetrics(metrics);
      throw ApiError.fromDioError(e);
    }
  }

  /// Performs a PUT request to the specified [path].
  @override
  Future<network.NetworkResponse<T>> put<T>(
    String path, {
    dynamic body,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    CancelToken? cancelToken,
    T Function(dynamic)? decoder,
  }) async {
    final metrics = RequestMetrics.start(HttpMethod.put, path);

    try {
      final response = await _dio.put<dynamic>(
        path,
        data: body,
        queryParameters: queryParameters,
        options: Options(headers: headers),
        cancelToken: cancelToken,
      );

      final parsedData = decoder != null
          ? decoder(response.data)
          : response.data as T;

      metrics.complete(
        statusCode: response.statusCode,
        responseSize: _calculateResponseSize(response),
      );
      _monitor.recordMetrics(metrics);

      return network.NetworkResponse<T>(
        data: parsedData,
        statusCode: response.statusCode ?? 200,
        headers: response.headers.map,
        requestTime: metrics.duration,
      );
    } on DioException catch (e) {
      metrics.complete(
        statusCode: e.response?.statusCode,
        error: e.message,
      );
      _monitor.recordMetrics(metrics);
      throw ApiError.fromDioError(e);
    }
  }

  /// Performs a PATCH request to the specified [path].
  @override
  Future<network.NetworkResponse<T>> patch<T>(
    String path, {
    dynamic body,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    CancelToken? cancelToken,
    T Function(dynamic)? decoder,
  }) async {
    final metrics = RequestMetrics.start(HttpMethod.patch, path);

    try {
      final response = await _dio.patch<dynamic>(
        path,
        data: body,
        queryParameters: queryParameters,
        options: Options(headers: headers),
        cancelToken: cancelToken,
      );

      final parsedData = decoder != null
          ? decoder(response.data)
          : response.data as T;

      metrics.complete(
        statusCode: response.statusCode,
        responseSize: _calculateResponseSize(response),
      );
      _monitor.recordMetrics(metrics);

      return network.NetworkResponse<T>(
        data: parsedData,
        statusCode: response.statusCode ?? 200,
        headers: response.headers.map,
        requestTime: metrics.duration,
      );
    } on DioException catch (e) {
      metrics.complete(
        statusCode: e.response?.statusCode,
        error: e.message,
      );
      _monitor.recordMetrics(metrics);
      throw ApiError.fromDioError(e);
    }
  }

  /// Performs a DELETE request to the specified [path].
  @override
  Future<network.NetworkResponse<T>> delete<T>(
    String path, {
    dynamic body,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    CancelToken? cancelToken,
    T Function(dynamic)? decoder,
  }) async {
    final metrics = RequestMetrics.start(HttpMethod.delete, path);

    try {
      final response = await _dio.delete<dynamic>(
        path,
        data: body,
        queryParameters: queryParameters,
        options: Options(headers: headers),
        cancelToken: cancelToken,
      );

      final parsedData = decoder != null
          ? decoder(response.data)
          : response.data as T;

      // Invalidate cache for this resource
      if (_cacheManager != null) {
        await _cacheManager!.remove(_buildCacheKey(path, null));
      }

      metrics.complete(
        statusCode: response.statusCode,
        responseSize: _calculateResponseSize(response),
      );
      _monitor.recordMetrics(metrics);

      return network.NetworkResponse<T>(
        data: parsedData,
        statusCode: response.statusCode ?? 200,
        headers: response.headers.map,
        requestTime: metrics.duration,
      );
    } on DioException catch (e) {
      metrics.complete(
        statusCode: e.response?.statusCode,
        error: e.message,
      );
      _monitor.recordMetrics(metrics);
      throw ApiError.fromDioError(e);
    }
  }

  /// Performs a HEAD request to the specified [path].
  Future<network.NetworkResponse<void>> head(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    CancelToken? cancelToken,
  }) async {
    final metrics = RequestMetrics.start(HttpMethod.head, path);

    try {
      final response = await _dio.head<void>(
        path,
        queryParameters: queryParameters,
        options: Options(headers: headers),
        cancelToken: cancelToken,
      );

      metrics.complete(statusCode: response.statusCode);
      _monitor.recordMetrics(metrics);

      return network.NetworkResponse<void>(
        data: null,
        statusCode: response.statusCode ?? 200,
        headers: response.headers.map,
        requestTime: metrics.duration,
      );
    } on DioException catch (e) {
      metrics.complete(
        statusCode: e.response?.statusCode,
        error: e.message,
      );
      _monitor.recordMetrics(metrics);
      throw ApiError.fromDioError(e);
    }
  }

  /// Uploads a file using multipart form data.
  ///
  /// [request] contains the file data and form fields.
  /// [onProgress] is called with upload progress (0.0 to 1.0).
  Future<network.NetworkResponse<T>> upload<T>(
    String path,
    MultipartRequest request, {
    Map<String, String>? headers,
    CancelToken? cancelToken,
    void Function(double progress)? onProgress,
    T Function(dynamic)? decoder,
  }) async {
    final metrics = RequestMetrics.start(HttpMethod.post, path);

    try {
      final formData = await request.toFormData();

      final response = await _dio.post<dynamic>(
        path,
        data: formData,
        options: Options(headers: headers),
        cancelToken: cancelToken,
        onSendProgress: (sent, total) {
          if (onProgress != null && total > 0) {
            onProgress(sent / total);
          }
        },
      );

      final parsedData = decoder != null
          ? decoder(response.data)
          : response.data as T;

      metrics.complete(
        statusCode: response.statusCode,
        responseSize: _calculateResponseSize(response),
      );
      _monitor.recordMetrics(metrics);

      return network.NetworkResponse<T>(
        data: parsedData,
        statusCode: response.statusCode ?? 200,
        headers: response.headers.map,
        requestTime: metrics.duration,
      );
    } on DioException catch (e) {
      metrics.complete(
        statusCode: e.response?.statusCode,
        error: e.message,
      );
      _monitor.recordMetrics(metrics);
      throw ApiError.fromDioError(e);
    }
  }

  /// Downloads a file from the specified [url] to [savePath].
  ///
  /// [onProgress] is called with download progress (0.0 to 1.0).
  /// Returns the path to the downloaded file.
  Future<String> download(
    String url,
    String savePath, {
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
    CancelToken? cancelToken,
    void Function(double progress)? onProgress,
    bool deleteOnError = true,
  }) async {
    final metrics = RequestMetrics.start(HttpMethod.get, url);

    try {
      await _dio.download(
        url,
        savePath,
        queryParameters: queryParameters,
        options: Options(headers: headers),
        cancelToken: cancelToken,
        deleteOnError: deleteOnError,
        onReceiveProgress: (received, total) {
          if (onProgress != null && total > 0) {
            onProgress(received / total);
          }
        },
      );

      metrics.complete(statusCode: 200);
      _monitor.recordMetrics(metrics);

      return savePath;
    } on DioException catch (e) {
      metrics.complete(
        statusCode: e.response?.statusCode,
        error: e.message,
      );
      _monitor.recordMetrics(metrics);
      throw ApiError.fromDioError(e);
    }
  }

  /// Creates a new request builder for constructing complex requests.
  RequestBuilder request() {
    return RequestBuilder(client: this);
  }

  /// Adds an interceptor to the chain.
  void addInterceptor(NetworkInterceptor interceptor) {
    _interceptors.add(interceptor);
    _dio.interceptors.add(_wrapInterceptor(interceptor));
  }

  /// Removes an interceptor from the chain.
  void removeInterceptor(NetworkInterceptor interceptor) {
    _interceptors.remove(interceptor);
    // Note: Dio doesn't support removing specific interceptors easily,
    // so we rebuild the interceptor chain
    _rebuildInterceptors();
  }

  void _rebuildInterceptors() {
    _dio.interceptors.clear();
    for (final interceptor in _interceptors) {
      _dio.interceptors.add(_wrapInterceptor(interceptor));
    }
  }

  String _buildCacheKey(String path, Map<String, dynamic>? queryParameters) {
    final buffer = StringBuffer(path);
    if (queryParameters != null && queryParameters.isNotEmpty) {
      final sortedParams = Map.fromEntries(
        queryParameters.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key)),
      );
      buffer.write('?');
      buffer.write(sortedParams.entries
          .map((e) => '${e.key}=${e.value}')
          .join('&'));
    }
    return buffer.toString();
  }

  int _calculateResponseSize(Response response) {
    if (response.data == null) return 0;
    if (response.data is String) {
      return (response.data as String).length;
    }
    try {
      return json.encode(response.data).length;
    } catch (_) {
      return 0;
    }
  }

  /// Clears all cached responses.
  Future<void> clearCache() async {
    await _cacheManager?.clear();
  }

  /// Cancels all pending requests.
  void cancelAllRequests() {
    _dio.close(force: true);
    _initializeDio();
  }

  /// Disposes the client and releases resources.
  @override
  void dispose() {
    _dio.close();
    _monitor.dispose();
  }
}
