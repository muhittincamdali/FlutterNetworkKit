/// Configuration for retry behavior.
///
/// This class defines when requests should be retried, how many times,
/// and which HTTP methods and status codes are eligible for retry.
///
/// Example:
/// ```dart
/// final policy = RetryPolicy(
///   maxRetries: 3,
///   retryStatusCodes: [500, 502, 503, 504],
///   retryOnNetworkError: true,
/// );
/// ```
class RetryPolicy {
  /// Creates a new [RetryPolicy].
  const RetryPolicy({
    this.maxRetries = 3,
    this.retryStatusCodes = const [500, 502, 503, 504, 429],
    this.retryMethods = const ['GET', 'HEAD', 'OPTIONS', 'PUT', 'DELETE'],
    this.retryOnNetworkError = true,
    this.retryOnTimeout = true,
    this.retryCondition,
  });

  /// Creates a standard retry policy with sensible defaults.
  factory RetryPolicy.standard({int maxRetries = 3}) {
    return RetryPolicy(
      maxRetries: maxRetries,
      retryStatusCodes: const [500, 502, 503, 504, 429],
      retryMethods: const ['GET', 'HEAD', 'OPTIONS', 'PUT', 'DELETE'],
      retryOnNetworkError: true,
      retryOnTimeout: true,
    );
  }

  /// Creates an aggressive retry policy that retries most errors.
  factory RetryPolicy.aggressive({int maxRetries = 5}) {
    return RetryPolicy(
      maxRetries: maxRetries,
      retryStatusCodes: const [408, 429, 500, 502, 503, 504],
      retryMethods: const ['GET', 'HEAD', 'OPTIONS', 'PUT', 'DELETE', 'POST', 'PATCH'],
      retryOnNetworkError: true,
      retryOnTimeout: true,
    );
  }

  /// Creates a conservative retry policy that only retries safe operations.
  factory RetryPolicy.conservative({int maxRetries = 2}) {
    return RetryPolicy(
      maxRetries: maxRetries,
      retryStatusCodes: const [502, 503, 504],
      retryMethods: const ['GET', 'HEAD', 'OPTIONS'],
      retryOnNetworkError: true,
      retryOnTimeout: false,
    );
  }

  /// Creates a policy that never retries.
  factory RetryPolicy.noRetry() {
    return const RetryPolicy(
      maxRetries: 0,
      retryStatusCodes: [],
      retryMethods: [],
      retryOnNetworkError: false,
      retryOnTimeout: false,
    );
  }

  /// Maximum number of retry attempts.
  final int maxRetries;

  /// HTTP status codes that should trigger a retry.
  final List<int> retryStatusCodes;

  /// HTTP methods that are eligible for retry.
  final List<String> retryMethods;

  /// Whether to retry on network errors (no connection).
  final bool retryOnNetworkError;

  /// Whether to retry on timeout errors.
  final bool retryOnTimeout;

  /// Custom retry condition function.
  final bool Function(int statusCode, int attempt)? retryCondition;

  /// Returns true if the given status code should trigger a retry.
  bool shouldRetryStatus(int statusCode) {
    return retryStatusCodes.contains(statusCode);
  }

  /// Returns true if the given HTTP method is eligible for retry.
  bool shouldRetryMethod(String method) {
    return retryMethods.contains(method.toUpperCase());
  }

  /// Returns true if a retry should be attempted.
  bool shouldRetry({
    required int attempt,
    int? statusCode,
    String? method,
    bool isNetworkError = false,
    bool isTimeout = false,
  }) {
    // Check retry limit
    if (attempt >= maxRetries) {
      return false;
    }

    // Custom condition takes precedence
    if (retryCondition != null && statusCode != null) {
      return retryCondition!(statusCode, attempt);
    }

    // Check network error
    if (isNetworkError && retryOnNetworkError) {
      return true;
    }

    // Check timeout
    if (isTimeout && retryOnTimeout) {
      return true;
    }

    // Check method eligibility
    if (method != null && !shouldRetryMethod(method)) {
      return false;
    }

    // Check status code
    if (statusCode != null && shouldRetryStatus(statusCode)) {
      return true;
    }

    return false;
  }

  /// Returns the number of remaining retries.
  int remainingRetries(int currentAttempt) {
    return (maxRetries - currentAttempt).clamp(0, maxRetries);
  }

  /// Creates a copy with the specified overrides.
  RetryPolicy copyWith({
    int? maxRetries,
    List<int>? retryStatusCodes,
    List<String>? retryMethods,
    bool? retryOnNetworkError,
    bool? retryOnTimeout,
    bool Function(int statusCode, int attempt)? retryCondition,
  }) {
    return RetryPolicy(
      maxRetries: maxRetries ?? this.maxRetries,
      retryStatusCodes: retryStatusCodes ?? this.retryStatusCodes,
      retryMethods: retryMethods ?? this.retryMethods,
      retryOnNetworkError: retryOnNetworkError ?? this.retryOnNetworkError,
      retryOnTimeout: retryOnTimeout ?? this.retryOnTimeout,
      retryCondition: retryCondition ?? this.retryCondition,
    );
  }

  @override
  String toString() {
    return 'RetryPolicy('
        'maxRetries: $maxRetries, '
        'statusCodes: $retryStatusCodes, '
        'methods: $retryMethods, '
        'networkError: $retryOnNetworkError, '
        'timeout: $retryOnTimeout'
        ')';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RetryPolicy &&
        other.maxRetries == maxRetries &&
        _listEquals(other.retryStatusCodes, retryStatusCodes) &&
        _listEquals(other.retryMethods, retryMethods) &&
        other.retryOnNetworkError == retryOnNetworkError &&
        other.retryOnTimeout == retryOnTimeout;
  }

  @override
  int get hashCode {
    return Object.hash(
      maxRetries,
      Object.hashAll(retryStatusCodes),
      Object.hashAll(retryMethods),
      retryOnNetworkError,
      retryOnTimeout,
    );
  }

  bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Extension methods for retry policies.
extension RetryPolicyExtension on RetryPolicy {
  /// Adds a status code to the retry list.
  RetryPolicy withStatusCode(int statusCode) {
    if (retryStatusCodes.contains(statusCode)) return this;
    return copyWith(retryStatusCodes: [...retryStatusCodes, statusCode]);
  }

  /// Removes a status code from the retry list.
  RetryPolicy withoutStatusCode(int statusCode) {
    return copyWith(
      retryStatusCodes: retryStatusCodes.where((c) => c != statusCode).toList(),
    );
  }

  /// Adds an HTTP method to the retry list.
  RetryPolicy withMethod(String method) {
    final upperMethod = method.toUpperCase();
    if (retryMethods.contains(upperMethod)) return this;
    return copyWith(retryMethods: [...retryMethods, upperMethod]);
  }

  /// Removes an HTTP method from the retry list.
  RetryPolicy withoutMethod(String method) {
    final upperMethod = method.toUpperCase();
    return copyWith(
      retryMethods: retryMethods.where((m) => m != upperMethod).toList(),
    );
  }

  /// Creates a policy that includes POST requests.
  RetryPolicy withPost() => withMethod('POST');

  /// Creates a policy that includes PATCH requests.
  RetryPolicy withPatch() => withMethod('PATCH');

  /// Returns true if this policy allows any retries.
  bool get allowsRetry => maxRetries > 0;
}
