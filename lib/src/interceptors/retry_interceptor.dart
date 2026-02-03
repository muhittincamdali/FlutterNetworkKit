import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';

import '../request/request.dart';
import '../response/response.dart';
import '../response/api_error.dart';
import '../retry/retry_policy.dart';
import '../retry/exponential_backoff.dart';
import 'interceptor.dart';

/// Interceptor that automatically retries failed requests.
///
/// This interceptor uses configurable retry policies to determine
/// when and how to retry failed requests.
///
/// Example:
/// ```dart
/// final retryInterceptor = RetryInterceptor(
///   policy: RetryPolicy(
///     maxRetries: 3,
///     retryOn: [500, 502, 503, 504],
///   ),
///   backoff: ExponentialBackoff(
///     initialDelay: Duration(seconds: 1),
///     maxDelay: Duration(seconds: 30),
///   ),
/// );
/// ```
class RetryInterceptor extends NetworkInterceptor {
  /// Creates a new [RetryInterceptor].
  RetryInterceptor({
    RetryPolicy? policy,
    BackoffStrategy? backoff,
    this.onRetry,
    this.shouldRetry,
  })  : _policy = policy ?? RetryPolicy.standard(),
        _backoff = backoff ?? ExponentialBackoff();

  final RetryPolicy _policy;
  final BackoffStrategy _backoff;

  /// Called before each retry attempt.
  final void Function(int attempt, ApiError error)? onRetry;

  /// Custom function to determine if a request should be retried.
  final bool Function(ApiError error, int attempt)? shouldRetry;

  final Map<String, int> _retryCounters = {};

  @override
  int get priority => 50;

  @override
  String get name => 'RetryInterceptor';

  @override
  Future<InterceptorResult<NetworkRequest>> onRequest(
    NetworkRequest request,
  ) async {
    // Store the request ID for retry tracking
    final requestId = _generateRequestId(request);
    final modifiedRequest = request.copyWith(
      extra: {...?request.extra, '_retryRequestId': requestId},
    );
    return InterceptorResult.next(modifiedRequest);
  }

  @override
  Future<ErrorInterceptorResult<ApiError>> onError(ApiError error) async {
    // Check if this error should trigger a retry
    if (!_shouldRetry(error)) {
      _cleanup(error);
      return ErrorInterceptorResult.next(error);
    }

    final requestId = error.details?['_retryRequestId'] as String? ??
        _generateErrorId(error);
    final currentAttempt = _retryCounters[requestId] ?? 0;

    // Check if we've exceeded max retries
    if (currentAttempt >= _policy.maxRetries) {
      _cleanup(error);
      return ErrorInterceptorResult.next(
        ApiError(
          statusCode: error.statusCode,
          message: '${error.message} (after ${_policy.maxRetries} retries)',
          errorCode: error.errorCode,
          details: error.details,
          validationErrors: error.validationErrors,
          requestPath: error.requestPath,
          requestMethod: error.requestMethod,
        ),
      );
    }

    // Custom retry check
    if (shouldRetry != null && !shouldRetry!(error, currentAttempt)) {
      _cleanup(error);
      return ErrorInterceptorResult.next(error);
    }

    // Increment retry counter
    _retryCounters[requestId] = currentAttempt + 1;

    // Calculate delay
    final delay = _backoff.getDelay(currentAttempt);

    // Notify retry callback
    onRetry?.call(currentAttempt + 1, error);

    // Wait before retry
    await Future<void>.delayed(delay);

    // Signal that this request should be retried
    // The actual retry mechanism is handled by the client
    return ErrorInterceptorResult.next(
      ApiError(
        statusCode: error.statusCode,
        message: 'Retry attempt ${currentAttempt + 1}/${_policy.maxRetries}',
        errorCode: 'RETRY_REQUESTED',
        details: {
          ...?error.details,
          '_retryAttempt': currentAttempt + 1,
          '_maxRetries': _policy.maxRetries,
        },
        requestPath: error.requestPath,
        requestMethod: error.requestMethod,
      ),
    );
  }

  bool _shouldRetry(ApiError error) {
    // Network errors should be retried
    if (error.isNetworkError && _policy.retryOnNetworkError) {
      return true;
    }

    // Timeout errors should be retried
    if (error.isTimeout && _policy.retryOnTimeout) {
      return true;
    }

    // Check specific status codes
    if (_policy.retryStatusCodes.contains(error.statusCode)) {
      return true;
    }

    // Check for specific methods
    if (error.requestMethod != null) {
      final method = error.requestMethod!.toUpperCase();
      if (_policy.retryMethods.contains(method)) {
        return _policy.retryStatusCodes.contains(error.statusCode) ||
            error.isNetworkError ||
            error.isTimeout;
      }
    }

    return false;
  }

  void _cleanup(ApiError error) {
    final requestId = error.details?['_retryRequestId'] as String?;
    if (requestId != null) {
      _retryCounters.remove(requestId);
    }
  }

  String _generateRequestId(NetworkRequest request) {
    return '${request.method.value}_${request.path}_${DateTime.now().microsecondsSinceEpoch}';
  }

  String _generateErrorId(ApiError error) {
    return '${error.requestMethod}_${error.requestPath}_${DateTime.now().microsecondsSinceEpoch}';
  }

  /// Resets all retry counters.
  void reset() {
    _retryCounters.clear();
  }
}

/// A simple retry interceptor with default settings.
class SimpleRetryInterceptor extends RetryInterceptor {
  /// Creates a simple retry interceptor with 3 retries.
  SimpleRetryInterceptor({
    int maxRetries = 3,
    Duration initialDelay = const Duration(seconds: 1),
  }) : super(
          policy: RetryPolicy(
            maxRetries: maxRetries,
            retryStatusCodes: [500, 502, 503, 504, 408],
            retryOnNetworkError: true,
            retryOnTimeout: true,
          ),
          backoff: ExponentialBackoff(
            initialDelay: initialDelay,
            maxDelay: const Duration(seconds: 30),
            multiplier: 2.0,
          ),
        );
}

/// A retry interceptor that only retries on network errors.
class NetworkErrorRetryInterceptor extends RetryInterceptor {
  /// Creates a network-error-only retry interceptor.
  NetworkErrorRetryInterceptor({
    int maxRetries = 3,
    Duration delay = const Duration(seconds: 2),
  }) : super(
          policy: RetryPolicy(
            maxRetries: maxRetries,
            retryStatusCodes: [],
            retryOnNetworkError: true,
            retryOnTimeout: true,
          ),
          backoff: LinearBackoff(delay: delay),
        );
}

/// A retry interceptor with jitter for distributed systems.
class JitteredRetryInterceptor extends RetryInterceptor {
  /// Creates a retry interceptor with random jitter.
  JitteredRetryInterceptor({
    int maxRetries = 3,
    Duration baseDelay = const Duration(seconds: 1),
    Duration maxDelay = const Duration(seconds: 30),
  }) : super(
          policy: RetryPolicy.standard(maxRetries: maxRetries),
          backoff: JitteredExponentialBackoff(
            initialDelay: baseDelay,
            maxDelay: maxDelay,
          ),
        );
}

/// A backoff strategy that uses linear delays.
class LinearBackoff implements BackoffStrategy {
  /// Creates a linear backoff strategy.
  const LinearBackoff({
    this.delay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 60),
  });

  /// The delay between retries.
  final Duration delay;

  /// The maximum delay.
  final Duration maxDelay;

  @override
  Duration getDelay(int attempt) {
    final totalDelay = delay * (attempt + 1);
    return totalDelay > maxDelay ? maxDelay : totalDelay;
  }

  @override
  void reset() {}
}

/// A backoff strategy with random jitter.
class JitteredExponentialBackoff implements BackoffStrategy {
  /// Creates a jittered exponential backoff.
  JitteredExponentialBackoff({
    this.initialDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
    this.multiplier = 2.0,
    this.jitterFactor = 0.5,
  }) : _random = Random();

  /// The initial delay before the first retry.
  final Duration initialDelay;

  /// The maximum delay between retries.
  final Duration maxDelay;

  /// The multiplier for each subsequent retry.
  final double multiplier;

  /// The jitter factor (0.0 to 1.0).
  final double jitterFactor;

  final Random _random;

  @override
  Duration getDelay(int attempt) {
    final baseDelay = initialDelay.inMilliseconds * pow(multiplier, attempt);
    final jitter = baseDelay * jitterFactor * (_random.nextDouble() * 2 - 1);
    final totalDelay = (baseDelay + jitter).round();

    if (totalDelay > maxDelay.inMilliseconds) {
      return maxDelay;
    }
    if (totalDelay < 0) {
      return Duration.zero;
    }
    return Duration(milliseconds: totalDelay);
  }

  @override
  void reset() {}
}
