import 'dart:async';
import 'dart:math';

import '../client/base_client.dart';
import '../request/request.dart';
import '../response/response.dart';
import '../response/api_error.dart';
import 'interceptor.dart';

/// A mock response configuration.
class MockResponse {
  /// Creates a new [MockResponse].
  const MockResponse({
    required this.data,
    this.statusCode = 200,
    this.headers,
    this.delay,
  });

  /// Creates a mock error response.
  factory MockResponse.error({
    required int statusCode,
    String? message,
    String? errorCode,
    Map<String, List<String>>? validationErrors,
    Duration? delay,
  }) {
    return MockResponse(
      data: {
        'message': message ?? 'Mock error',
        if (errorCode != null) 'code': errorCode,
        if (validationErrors != null) 'errors': validationErrors,
      },
      statusCode: statusCode,
      delay: delay,
    );
  }

  /// The mock response data.
  final dynamic data;

  /// The mock status code.
  final int statusCode;

  /// The mock response headers.
  final Map<String, List<String>>? headers;

  /// Artificial delay before returning the response.
  final Duration? delay;

  /// Whether this is an error response.
  bool get isError => statusCode >= 400;
}

/// Interceptor that returns mock responses for testing.
///
/// This interceptor is useful for development and testing when you want
/// to simulate API responses without making actual network requests.
///
/// Example:
/// ```dart
/// final mockInterceptor = MockInterceptor()
///   ..addMock(
///     method: HttpMethod.get,
///     path: '/users',
///     response: MockResponse(data: [{'id': 1, 'name': 'John'}]),
///   )
///   ..addMock(
///     method: HttpMethod.post,
///     path: '/login',
///     response: MockResponse(data: {'token': 'abc123'}),
///   );
/// ```
class MockInterceptor extends NetworkInterceptor {
  /// Creates a new [MockInterceptor].
  MockInterceptor({
    this.enabled = true,
    this.defaultDelay,
    this.randomDelayRange,
    this.passthrough = false,
    this.onMockHit,
    this.onMockMiss,
  });

  /// Whether this interceptor is enabled.
  bool enabled;

  /// Default delay for all mock responses.
  final Duration? defaultDelay;

  /// Random delay range (min, max) for simulating network latency.
  final (Duration, Duration)? randomDelayRange;

  /// If true, passes through to real network if no mock is found.
  final bool passthrough;

  /// Called when a mock response is found.
  final void Function(NetworkRequest request, MockResponse response)? onMockHit;

  /// Called when no mock response is found.
  final void Function(NetworkRequest request)? onMockMiss;

  final Map<String, MockResponse> _mocks = {};
  final Map<String, MockResponse Function(NetworkRequest)> _dynamicMocks = {};
  final List<MockHandler> _handlers = [];

  final _random = Random();

  @override
  int get priority => 1;

  @override
  String get name => 'MockInterceptor';

  /// Adds a mock response for a specific method and path.
  void addMock({
    required HttpMethod method,
    required String path,
    required MockResponse response,
  }) {
    final key = _buildKey(method, path);
    _mocks[key] = response;
  }

  /// Adds a dynamic mock that generates responses based on the request.
  void addDynamicMock({
    required HttpMethod method,
    required String path,
    required MockResponse Function(NetworkRequest request) handler,
  }) {
    final key = _buildKey(method, path);
    _dynamicMocks[key] = handler;
  }

  /// Adds a custom mock handler.
  void addHandler(MockHandler handler) {
    _handlers.add(handler);
  }

  /// Removes a mock for a specific method and path.
  void removeMock(HttpMethod method, String path) {
    final key = _buildKey(method, path);
    _mocks.remove(key);
    _dynamicMocks.remove(key);
  }

  /// Clears all mocks.
  void clearMocks() {
    _mocks.clear();
    _dynamicMocks.clear();
    _handlers.clear();
  }

  @override
  Future<InterceptorResult<NetworkRequest>> onRequest(
    NetworkRequest request,
  ) async {
    if (!enabled) {
      return InterceptorResult.next(request);
    }

    // Check custom handlers first
    for (final handler in _handlers) {
      if (handler.matches(request)) {
        final response = handler.handle(request);
        onMockHit?.call(request, response);
        await _applyDelay(response.delay);
        return _createResult(response);
      }
    }

    // Check static mocks
    final key = _buildKey(request.method, request.path);
    final mockResponse = _mocks[key];

    if (mockResponse != null) {
      onMockHit?.call(request, mockResponse);
      await _applyDelay(mockResponse.delay);
      return _createResult(mockResponse);
    }

    // Check dynamic mocks
    final dynamicHandler = _dynamicMocks[key];
    if (dynamicHandler != null) {
      final response = dynamicHandler(request);
      onMockHit?.call(request, response);
      await _applyDelay(response.delay);
      return _createResult(response);
    }

    // Check pattern-based mocks
    for (final entry in _mocks.entries) {
      if (_pathMatches(entry.key, request)) {
        onMockHit?.call(request, entry.value);
        await _applyDelay(entry.value.delay);
        return _createResult(entry.value);
      }
    }

    onMockMiss?.call(request);

    if (passthrough) {
      return InterceptorResult.next(request);
    }

    // Return 404 if no mock found and not passthrough
    return InterceptorResult.reject(ApiError(
      statusCode: 404,
      message: 'No mock found for ${request.method.value} ${request.path}',
      errorCode: 'MOCK_NOT_FOUND',
    ));
  }

  String _buildKey(HttpMethod method, String path) {
    return '${method.value}:$path';
  }

  bool _pathMatches(String key, NetworkRequest request) {
    final parts = key.split(':');
    if (parts.length != 2) return false;

    final method = parts[0];
    final pattern = parts[1];

    if (method != request.method.value) return false;

    // Support simple wildcards
    if (pattern.contains('*')) {
      final regex = RegExp('^${pattern.replaceAll('*', '.*')}\$');
      return regex.hasMatch(request.path);
    }

    return pattern == request.path;
  }

  Future<void> _applyDelay(Duration? responseDelay) async {
    final delay = responseDelay ?? defaultDelay;

    if (delay != null) {
      await Future<void>.delayed(delay);
      return;
    }

    if (randomDelayRange != null) {
      final (min, max) = randomDelayRange!;
      final range = max.inMilliseconds - min.inMilliseconds;
      final randomDelay = min.inMilliseconds + _random.nextInt(range);
      await Future<void>.delayed(Duration(milliseconds: randomDelay));
    }
  }

  InterceptorResult<NetworkRequest> _createResult(MockResponse mock) {
    if (mock.isError) {
      return InterceptorResult.reject(ApiError(
        statusCode: mock.statusCode,
        message: mock.data?['message'] as String? ?? 'Mock error',
        errorCode: mock.data?['code'] as String?,
        validationErrors: (mock.data?['errors'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, (v as List).cast<String>()),
        ),
      ));
    }

    return InterceptorResult.resolve(NetworkResponse<dynamic>(
      data: mock.data,
      statusCode: mock.statusCode,
      headers: mock.headers,
    ));
  }
}

/// A custom mock handler for complex matching logic.
abstract class MockHandler {
  /// Returns true if this handler should handle the request.
  bool matches(NetworkRequest request);

  /// Generates a mock response for the request.
  MockResponse handle(NetworkRequest request);
}

/// A mock handler that matches requests by regex pattern.
class RegexMockHandler implements MockHandler {
  /// Creates a new [RegexMockHandler].
  RegexMockHandler({
    required this.pattern,
    this.methods,
    required this.handler,
  });

  /// The regex pattern to match paths.
  final RegExp pattern;

  /// If set, only matches these HTTP methods.
  final Set<HttpMethod>? methods;

  /// The handler function.
  final MockResponse Function(NetworkRequest request, Match match) handler;

  @override
  bool matches(NetworkRequest request) {
    if (methods != null && !methods!.contains(request.method)) {
      return false;
    }
    return pattern.hasMatch(request.path);
  }

  @override
  MockResponse handle(NetworkRequest request) {
    final match = pattern.firstMatch(request.path)!;
    return handler(request, match);
  }
}

/// A mock handler that generates sequence responses.
class SequenceMockHandler implements MockHandler {
  /// Creates a new [SequenceMockHandler].
  SequenceMockHandler({
    required HttpMethod method,
    required String path,
    required this.responses,
    this.loop = false,
  })  : _method = method,
        _path = path;

  final HttpMethod _method;
  final String _path;

  /// The sequence of responses to return.
  final List<MockResponse> responses;

  /// If true, loops back to the first response after the last.
  final bool loop;

  int _index = 0;

  @override
  bool matches(NetworkRequest request) {
    return request.method == _method && request.path == _path;
  }

  @override
  MockResponse handle(NetworkRequest request) {
    if (_index >= responses.length) {
      if (loop) {
        _index = 0;
      } else {
        return responses.last;
      }
    }
    return responses[_index++];
  }

  /// Resets the sequence index.
  void reset() {
    _index = 0;
  }
}
