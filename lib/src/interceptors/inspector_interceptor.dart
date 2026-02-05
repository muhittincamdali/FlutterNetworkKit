import 'dart:async';

import '../inspector/network_inspector.dart';
import '../request/request.dart';
import '../response/response.dart';
import '../response/api_error.dart';
import 'interceptor.dart';

/// Interceptor that records requests and responses for the network inspector.
///
/// Example:
/// ```dart
/// final inspector = NetworkInspector();
///
/// final client = NetworkClient(
///   configuration: NetworkConfiguration(baseUrl: 'https://api.example.com'),
///   interceptors: [
///     InspectorInterceptor(inspector),
///   ],
/// );
///
/// // Show inspector UI
/// NetworkInspectorOverlay.show(context, inspector);
/// ```
class InspectorInterceptor implements NetworkInterceptor {
  /// Creates a new [InspectorInterceptor].
  InspectorInterceptor(this._inspector);

  final NetworkInspector _inspector;
  final Map<int, String> _requestIds = {};

  @override
  Future<InterceptorResult<NetworkRequest>> onRequest(NetworkRequest request) async {
    final id = _inspector.recordRequest(
      method: request.method.name.toUpperCase(),
      url: request.fullUrl,
      headers: request.headers,
      body: request.body,
      requestSize: _calculateSize(request.body),
    );

    // Store the ID for matching response
    _requestIds[request.hashCode] = id;

    return InterceptorResult.next(request);
  }

  @override
  Future<InterceptorResult<NetworkResponse>> onResponse(NetworkResponse response) async {
    final id = _requestIds.remove(response.request?.hashCode);

    if (id != null) {
      _inspector.recordResponse(
        id: id,
        statusCode: response.statusCode,
        headers: response.headers,
        body: response.data,
        duration: response.requestTime,
        responseSize: _calculateSize(response.data),
        fromCache: response.fromCache,
      );
    }

    return InterceptorResult.next(response);
  }

  @override
  Future<InterceptorResult<ApiError>> onError(ApiError error) async {
    final id = _requestIds.remove(error.request?.hashCode);

    if (id != null) {
      _inspector.recordError(
        id: id,
        error: error.message,
      );
    }

    return InterceptorResult.next(error);
  }

  int _calculateSize(dynamic data) {
    if (data == null) return 0;
    if (data is String) return data.length;
    if (data is List<int>) return data.length;
    return data.toString().length;
  }
}
