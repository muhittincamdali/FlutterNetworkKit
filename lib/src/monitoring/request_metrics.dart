import '../client/base_client.dart';

/// Metrics collected for a single network request.
///
/// This class captures timing, size, and status information
/// for network requests.
///
/// Example:
/// ```dart
/// final metrics = RequestMetrics.start(HttpMethod.get, '/users');
///
/// // ... perform request ...
///
/// metrics.complete(
///   statusCode: 200,
///   responseSize: 1024,
/// );
///
/// print('Request took: ${metrics.duration}');
/// ```
class RequestMetrics {
  RequestMetrics._({
    required this.method,
    required this.path,
    required this.startTime,
    this.endTime,
    this.statusCode,
    this.responseSize,
    this.requestSize,
    this.error,
    this.fromCache = false,
    this.retryCount = 0,
  });

  /// Creates and starts tracking a new request.
  factory RequestMetrics.start(HttpMethod method, String path) {
    return RequestMetrics._(
      method: method,
      path: path,
      startTime: DateTime.now(),
    );
  }

  /// Creates completed metrics.
  factory RequestMetrics.completed({
    required HttpMethod method,
    required String path,
    required DateTime startTime,
    required DateTime endTime,
    int? statusCode,
    int? responseSize,
    int? requestSize,
    String? error,
    bool fromCache = false,
    int retryCount = 0,
  }) {
    return RequestMetrics._(
      method: method,
      path: path,
      startTime: startTime,
      endTime: endTime,
      statusCode: statusCode,
      responseSize: responseSize,
      requestSize: requestSize,
      error: error,
      fromCache: fromCache,
      retryCount: retryCount,
    );
  }

  /// The HTTP method used.
  final HttpMethod method;

  /// The request path.
  final String path;

  /// When the request started.
  final DateTime startTime;

  /// When the request completed.
  DateTime? endTime;

  /// The HTTP status code.
  int? statusCode;

  /// The response size in bytes.
  int? responseSize;

  /// The request size in bytes.
  int? requestSize;

  /// Error message if the request failed.
  String? error;

  /// Whether the response came from cache.
  bool fromCache;

  /// Number of retry attempts.
  int retryCount;

  /// Returns true if the request completed.
  bool get isCompleted => endTime != null;

  /// Returns true if the request was successful.
  bool get isSuccess {
    if (statusCode == null) return error == null;
    return statusCode! >= 200 && statusCode! < 300;
  }

  /// Returns true if this was a client error (4xx).
  bool get isClientError {
    if (statusCode == null) return false;
    return statusCode! >= 400 && statusCode! < 500;
  }

  /// Returns true if this was a server error (5xx).
  bool get isServerError {
    if (statusCode == null) return false;
    return statusCode! >= 500;
  }

  /// The duration of the request.
  Duration? get duration {
    if (endTime == null) return null;
    return endTime!.difference(startTime);
  }

  /// Marks the request as completed.
  void complete({
    int? statusCode,
    int? responseSize,
    int? requestSize,
    String? error,
    bool fromCache = false,
  }) {
    endTime = DateTime.now();
    this.statusCode = statusCode;
    this.responseSize = responseSize;
    this.requestSize = requestSize;
    this.error = error;
    this.fromCache = fromCache;
  }

  /// Increments the retry count.
  void recordRetry() {
    retryCount++;
  }

  /// Converts to JSON.
  Map<String, dynamic> toJson() {
    return {
      'method': method.value,
      'path': path,
      'startTime': startTime.toIso8601String(),
      if (endTime != null) 'endTime': endTime!.toIso8601String(),
      if (statusCode != null) 'statusCode': statusCode,
      if (responseSize != null) 'responseSize': responseSize,
      if (requestSize != null) 'requestSize': requestSize,
      if (error != null) 'error': error,
      'fromCache': fromCache,
      'retryCount': retryCount,
      if (duration != null) 'durationMs': duration!.inMilliseconds,
    };
  }

  @override
  String toString() {
    final durationStr = duration != null ? '${duration!.inMilliseconds}ms' : 'pending';
    return 'RequestMetrics('
        '${method.value} $path, '
        'status: $statusCode, '
        'duration: $durationStr, '
        'cache: $fromCache'
        ')';
  }
}

/// Aggregated metrics for a time period.
class AggregatedMetrics {
  /// Creates new [AggregatedMetrics].
  const AggregatedMetrics({
    required this.period,
    required this.totalRequests,
    required this.successfulRequests,
    required this.failedRequests,
    required this.totalDuration,
    required this.totalResponseSize,
    required this.cachedRequests,
  });

  /// Creates aggregated metrics from a list of request metrics.
  factory AggregatedMetrics.fromList(
    Duration period,
    List<RequestMetrics> metrics,
  ) {
    var totalDuration = Duration.zero;
    var totalResponseSize = 0;
    var successfulRequests = 0;
    var failedRequests = 0;
    var cachedRequests = 0;

    for (final m in metrics) {
      if (m.duration != null) {
        totalDuration += m.duration!;
      }
      if (m.responseSize != null) {
        totalResponseSize += m.responseSize!;
      }
      if (m.isSuccess) {
        successfulRequests++;
      } else {
        failedRequests++;
      }
      if (m.fromCache) {
        cachedRequests++;
      }
    }

    return AggregatedMetrics(
      period: period,
      totalRequests: metrics.length,
      successfulRequests: successfulRequests,
      failedRequests: failedRequests,
      totalDuration: totalDuration,
      totalResponseSize: totalResponseSize,
      cachedRequests: cachedRequests,
    );
  }

  /// The time period for these metrics.
  final Duration period;

  /// Total number of requests.
  final int totalRequests;

  /// Number of successful requests.
  final int successfulRequests;

  /// Number of failed requests.
  final int failedRequests;

  /// Total duration of all requests.
  final Duration totalDuration;

  /// Total response size in bytes.
  final int totalResponseSize;

  /// Number of requests served from cache.
  final int cachedRequests;

  /// Average request duration.
  Duration get averageDuration {
    if (totalRequests == 0) return Duration.zero;
    return Duration(
      microseconds: totalDuration.inMicroseconds ~/ totalRequests,
    );
  }

  /// Average response size in bytes.
  double get averageResponseSize {
    if (totalRequests == 0) return 0;
    return totalResponseSize / totalRequests;
  }

  /// Success rate (0.0 to 1.0).
  double get successRate {
    if (totalRequests == 0) return 1.0;
    return successfulRequests / totalRequests;
  }

  /// Cache hit rate (0.0 to 1.0).
  double get cacheHitRate {
    if (totalRequests == 0) return 0.0;
    return cachedRequests / totalRequests;
  }

  /// Requests per second.
  double get requestsPerSecond {
    if (period.inSeconds == 0) return 0;
    return totalRequests / period.inSeconds;
  }

  /// Converts to JSON.
  Map<String, dynamic> toJson() {
    return {
      'periodSeconds': period.inSeconds,
      'totalRequests': totalRequests,
      'successfulRequests': successfulRequests,
      'failedRequests': failedRequests,
      'averageDurationMs': averageDuration.inMilliseconds,
      'averageResponseSize': averageResponseSize,
      'successRate': successRate,
      'cacheHitRate': cacheHitRate,
      'requestsPerSecond': requestsPerSecond,
    };
  }

  @override
  String toString() {
    return 'AggregatedMetrics('
        'requests: $totalRequests, '
        'success: ${(successRate * 100).toStringAsFixed(1)}%, '
        'avgTime: ${averageDuration.inMilliseconds}ms'
        ')';
  }
}

/// Real-time metrics tracker.
class MetricsTracker {
  /// Creates a new [MetricsTracker].
  MetricsTracker({
    this.windowSize = const Duration(minutes: 5),
    this.bucketSize = const Duration(seconds: 30),
  });

  /// The total window size for tracking.
  final Duration windowSize;

  /// The size of each time bucket.
  final Duration bucketSize;

  final List<_MetricsBucket> _buckets = [];

  /// Records a metric.
  void record(RequestMetrics metrics) {
    final now = DateTime.now();
    _cleanOldBuckets(now);

    final bucket = _getOrCreateBucket(now);
    bucket.add(metrics);
  }

  /// Returns aggregated metrics for the current window.
  AggregatedMetrics getAggregated() {
    final now = DateTime.now();
    _cleanOldBuckets(now);

    final allMetrics = _buckets.expand((b) => b.metrics).toList();
    return AggregatedMetrics.fromList(windowSize, allMetrics);
  }

  /// Returns metrics grouped by bucket.
  List<AggregatedMetrics> getBuckets() {
    final now = DateTime.now();
    _cleanOldBuckets(now);

    return _buckets
        .map((b) => AggregatedMetrics.fromList(bucketSize, b.metrics))
        .toList();
  }

  void _cleanOldBuckets(DateTime now) {
    final cutoff = now.subtract(windowSize);
    _buckets.removeWhere((b) => b.endTime.isBefore(cutoff));
  }

  _MetricsBucket _getOrCreateBucket(DateTime now) {
    if (_buckets.isEmpty || _buckets.last.endTime.isBefore(now)) {
      final bucket = _MetricsBucket(
        startTime: now,
        endTime: now.add(bucketSize),
      );
      _buckets.add(bucket);
      return bucket;
    }
    return _buckets.last;
  }
}

class _MetricsBucket {
  _MetricsBucket({
    required this.startTime,
    required this.endTime,
  });

  final DateTime startTime;
  final DateTime endTime;
  final List<RequestMetrics> metrics = [];

  void add(RequestMetrics metric) {
    metrics.add(metric);
  }
}
