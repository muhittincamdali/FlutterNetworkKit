import 'dart:async';
import 'dart:collection';

import 'request_metrics.dart';

/// Monitors network activity and collects performance metrics.
///
/// The [NetworkMonitor] tracks all network requests and provides
/// statistics about request performance, error rates, and more.
///
/// Example:
/// ```dart
/// final monitor = NetworkMonitor(
///   historyLimit: 100,
///   onSlowRequest: (metrics) => print('Slow request: ${metrics.path}'),
/// );
///
/// final client = NetworkClient(
///   configuration: config,
///   monitor: monitor,
/// );
///
/// // Later...
/// print('Average response time: ${monitor.averageResponseTime}');
/// print('Error rate: ${monitor.errorRate}');
/// ```
class NetworkMonitor {
  /// Creates a new [NetworkMonitor].
  NetworkMonitor({
    this.historyLimit = 100,
    this.slowRequestThreshold = const Duration(seconds: 3),
    this.onSlowRequest,
    this.onError,
    this.enabled = true,
  });

  /// Maximum number of metrics to keep in history.
  final int historyLimit;

  /// Threshold for considering a request slow.
  final Duration slowRequestThreshold;

  /// Called when a slow request is detected.
  final void Function(RequestMetrics metrics)? onSlowRequest;

  /// Called when a request error occurs.
  final void Function(RequestMetrics metrics)? onError;

  /// Whether monitoring is enabled.
  bool enabled;

  final Queue<RequestMetrics> _history = Queue();
  final _metricsController = StreamController<RequestMetrics>.broadcast();

  int _totalRequests = 0;
  int _successfulRequests = 0;
  int _failedRequests = 0;
  int _totalResponseTime = 0;
  int _slowRequests = 0;
  final Map<String, int> _requestsByPath = {};
  final Map<int, int> _requestsByStatusCode = {};
  final Map<String, int> _requestsByMethod = {};

  /// Stream of all recorded metrics.
  Stream<RequestMetrics> get metricsStream => _metricsController.stream;

  /// Returns the request history.
  List<RequestMetrics> get history => List.unmodifiable(_history);

  /// Total number of requests made.
  int get totalRequests => _totalRequests;

  /// Number of successful requests.
  int get successfulRequests => _successfulRequests;

  /// Number of failed requests.
  int get failedRequests => _failedRequests;

  /// Number of slow requests.
  int get slowRequests => _slowRequests;

  /// Success rate (0.0 to 1.0).
  double get successRate {
    if (_totalRequests == 0) return 1.0;
    return _successfulRequests / _totalRequests;
  }

  /// Error rate (0.0 to 1.0).
  double get errorRate {
    if (_totalRequests == 0) return 0.0;
    return _failedRequests / _totalRequests;
  }

  /// Average response time.
  Duration get averageResponseTime {
    if (_totalRequests == 0) return Duration.zero;
    return Duration(milliseconds: _totalResponseTime ~/ _totalRequests);
  }

  /// Records metrics for a completed request.
  void recordMetrics(RequestMetrics metrics) {
    if (!enabled) return;

    _totalRequests++;

    if (metrics.isSuccess) {
      _successfulRequests++;
    } else {
      _failedRequests++;
      onError?.call(metrics);
    }

    if (metrics.duration != null) {
      _totalResponseTime += metrics.duration!.inMilliseconds;

      if (metrics.duration! > slowRequestThreshold) {
        _slowRequests++;
        onSlowRequest?.call(metrics);
      }
    }

    // Track by path
    _requestsByPath[metrics.path] = (_requestsByPath[metrics.path] ?? 0) + 1;

    // Track by status code
    if (metrics.statusCode != null) {
      _requestsByStatusCode[metrics.statusCode!] =
          (_requestsByStatusCode[metrics.statusCode!] ?? 0) + 1;
    }

    // Track by method
    _requestsByMethod[metrics.method.value] =
        (_requestsByMethod[metrics.method.value] ?? 0) + 1;

    // Add to history
    _history.add(metrics);
    while (_history.length > historyLimit) {
      _history.removeFirst();
    }

    _metricsController.add(metrics);
  }

  /// Returns metrics for a specific time range.
  List<RequestMetrics> getMetricsInRange(DateTime start, DateTime end) {
    return _history
        .where((m) =>
            m.startTime.isAfter(start) &&
            m.startTime.isBefore(end))
        .toList();
  }

  /// Returns the most frequent paths.
  List<MapEntry<String, int>> get topPaths {
    final sorted = _requestsByPath.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(10).toList();
  }

  /// Returns the distribution of status codes.
  Map<int, int> get statusCodeDistribution => Map.unmodifiable(_requestsByStatusCode);

  /// Returns the distribution of HTTP methods.
  Map<String, int> get methodDistribution => Map.unmodifiable(_requestsByMethod);

  /// Returns the slowest requests.
  List<RequestMetrics> get slowestRequests {
    final sorted = _history.where((m) => m.duration != null).toList()
      ..sort((a, b) => b.duration!.compareTo(a.duration!));
    return sorted.take(10).toList();
  }

  /// Returns the most recent errors.
  List<RequestMetrics> get recentErrors {
    return _history.where((m) => !m.isSuccess).take(10).toList();
  }

  /// Returns summary statistics.
  MonitoringSummary get summary {
    return MonitoringSummary(
      totalRequests: _totalRequests,
      successfulRequests: _successfulRequests,
      failedRequests: _failedRequests,
      slowRequests: _slowRequests,
      averageResponseTime: averageResponseTime,
      successRate: successRate,
      errorRate: errorRate,
    );
  }

  /// Generates a report of the monitoring data.
  String generateReport() {
    final buffer = StringBuffer();

    buffer.writeln('=== Network Monitoring Report ===');
    buffer.writeln();
    buffer.writeln('Total Requests: $_totalRequests');
    buffer.writeln('Successful: $_successfulRequests (${(successRate * 100).toStringAsFixed(1)}%)');
    buffer.writeln('Failed: $_failedRequests (${(errorRate * 100).toStringAsFixed(1)}%)');
    buffer.writeln('Slow: $_slowRequests');
    buffer.writeln();
    buffer.writeln('Average Response Time: ${averageResponseTime.inMilliseconds}ms');
    buffer.writeln();

    buffer.writeln('Top Paths:');
    for (final entry in topPaths.take(5)) {
      buffer.writeln('  ${entry.key}: ${entry.value} requests');
    }
    buffer.writeln();

    buffer.writeln('Status Code Distribution:');
    for (final entry in statusCodeDistribution.entries) {
      buffer.writeln('  ${entry.key}: ${entry.value}');
    }
    buffer.writeln();

    buffer.writeln('Method Distribution:');
    for (final entry in methodDistribution.entries) {
      buffer.writeln('  ${entry.key}: ${entry.value}');
    }

    return buffer.toString();
  }

  /// Resets all statistics.
  void reset() {
    _totalRequests = 0;
    _successfulRequests = 0;
    _failedRequests = 0;
    _totalResponseTime = 0;
    _slowRequests = 0;
    _requestsByPath.clear();
    _requestsByStatusCode.clear();
    _requestsByMethod.clear();
    _history.clear();
  }

  /// Disposes the monitor and releases resources.
  void dispose() {
    _metricsController.close();
  }
}

/// Summary of monitoring statistics.
class MonitoringSummary {
  /// Creates a new [MonitoringSummary].
  const MonitoringSummary({
    required this.totalRequests,
    required this.successfulRequests,
    required this.failedRequests,
    required this.slowRequests,
    required this.averageResponseTime,
    required this.successRate,
    required this.errorRate,
  });

  final int totalRequests;
  final int successfulRequests;
  final int failedRequests;
  final int slowRequests;
  final Duration averageResponseTime;
  final double successRate;
  final double errorRate;

  /// Converts to JSON.
  Map<String, dynamic> toJson() {
    return {
      'totalRequests': totalRequests,
      'successfulRequests': successfulRequests,
      'failedRequests': failedRequests,
      'slowRequests': slowRequests,
      'averageResponseTimeMs': averageResponseTime.inMilliseconds,
      'successRate': successRate,
      'errorRate': errorRate,
    };
  }

  @override
  String toString() {
    return 'MonitoringSummary('
        'total: $totalRequests, '
        'success: ${(successRate * 100).toStringAsFixed(1)}%, '
        'avgTime: ${averageResponseTime.inMilliseconds}ms'
        ')';
  }
}

/// Extension for monitoring with Flutter widgets.
extension NetworkMonitorExtension on NetworkMonitor {
  /// Creates a stream of summaries updated every [interval].
  Stream<MonitoringSummary> summaryStream(Duration interval) {
    return Stream.periodic(interval, (_) => summary);
  }

  /// Returns true if the network appears healthy.
  bool get isHealthy => errorRate < 0.1 && slowRequests < totalRequests * 0.2;
}
