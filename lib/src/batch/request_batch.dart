import 'dart:async';

import '../request/request.dart';
import '../response/response.dart';
import '../response/api_error.dart';

/// Represents a single request within a batch.
class BatchRequest {
  /// Creates a new [BatchRequest].
  BatchRequest({
    required this.request,
    this.id,
    this.dependsOn,
    this.priority = 0,
  });

  /// The network request.
  final NetworkRequest request;

  /// Unique identifier for this batch request.
  final String? id;

  /// IDs of requests this depends on.
  final List<String>? dependsOn;

  /// Priority within the batch.
  final int priority;
}

/// Result of a batch request execution.
sealed class BatchRequestResult {
  const BatchRequestResult();
}

/// Successful batch request result.
class BatchRequestSuccess extends BatchRequestResult {
  const BatchRequestSuccess(this.response);
  final NetworkResponse response;
}

/// Failed batch request result.
class BatchRequestFailure extends BatchRequestResult {
  const BatchRequestFailure(this.error);
  final ApiError error;
}

/// Skipped batch request (due to dependency failure).
class BatchRequestSkipped extends BatchRequestResult {
  const BatchRequestSkipped(this.reason);
  final String reason;
}

/// Configuration for batch execution.
class BatchConfig {
  /// Creates a new [BatchConfig].
  const BatchConfig({
    this.maxConcurrent = 5,
    this.stopOnError = false,
    this.timeout,
    this.delayBetweenRequests,
  });

  /// Maximum concurrent requests.
  final int maxConcurrent;

  /// Whether to stop processing on first error.
  final bool stopOnError;

  /// Timeout for the entire batch.
  final Duration? timeout;

  /// Delay between consecutive requests.
  final Duration? delayBetweenRequests;
}

/// Callback for executing a request.
typedef BatchRequestExecutor = Future<NetworkResponse> Function(NetworkRequest request);

/// Manages batch execution of multiple requests.
///
/// The [RequestBatch] allows executing multiple requests together with
/// support for dependencies, priorities, and concurrent execution limits.
///
/// Example:
/// ```dart
/// final batch = RequestBatch(
///   executor: (request) => client.execute(request),
///   config: BatchConfig(maxConcurrent: 3),
/// );
///
/// batch.add(BatchRequest(
///   request: NetworkRequest.get('/users'),
///   id: 'users',
/// ));
///
/// batch.add(BatchRequest(
///   request: NetworkRequest.get('/posts'),
///   id: 'posts',
///   dependsOn: ['users'],
/// ));
///
/// final results = await batch.execute();
/// ```
class RequestBatch {
  /// Creates a new [RequestBatch].
  RequestBatch({
    required BatchRequestExecutor executor,
    BatchConfig? config,
  })  : _executor = executor,
        _config = config ?? const BatchConfig();

  final BatchRequestExecutor _executor;
  final BatchConfig _config;
  final List<BatchRequest> _requests = [];
  final Map<String, BatchRequestResult> _results = {};

  bool _isExecuting = false;
  bool _isCancelled = false;

  final _progressController = StreamController<BatchProgress>.broadcast();

  /// Stream of batch progress updates.
  Stream<BatchProgress> get progressStream => _progressController.stream;

  /// Number of requests in the batch.
  int get requestCount => _requests.length;

  /// Whether the batch is currently executing.
  bool get isExecuting => _isExecuting;

  /// Adds a request to the batch.
  void add(BatchRequest request) {
    if (_isExecuting) {
      throw StateError('Cannot add requests while batch is executing');
    }
    _requests.add(request);
  }

  /// Adds multiple requests to the batch.
  void addAll(Iterable<BatchRequest> requests) {
    if (_isExecuting) {
      throw StateError('Cannot add requests while batch is executing');
    }
    _requests.addAll(requests);
  }

  /// Removes a request from the batch by ID.
  bool remove(String id) {
    if (_isExecuting) {
      throw StateError('Cannot remove requests while batch is executing');
    }
    final index = _requests.indexWhere((r) => r.id == id);
    if (index == -1) return false;
    _requests.removeAt(index);
    return true;
  }

  /// Clears all requests from the batch.
  void clear() {
    if (_isExecuting) {
      throw StateError('Cannot clear batch while executing');
    }
    _requests.clear();
    _results.clear();
  }

  /// Executes all requests in the batch.
  ///
  /// Returns a map of request IDs/indices to their results.
  Future<Map<String, BatchRequestResult>> execute() async {
    if (_isExecuting) {
      throw StateError('Batch is already executing');
    }

    _isExecuting = true;
    _isCancelled = false;
    _results.clear();

    try {
      // Sort by priority and dependency order
      final orderedRequests = _buildExecutionOrder();

      // Execute with timeout if specified
      if (_config.timeout != null) {
        return await Future.any([
          _executeOrdered(orderedRequests),
          Future.delayed(_config.timeout!, () {
            _isCancelled = true;
            throw TimeoutException('Batch execution timed out', _config.timeout);
          }),
        ]);
      }

      return await _executeOrdered(orderedRequests);
    } finally {
      _isExecuting = false;
    }
  }

  List<List<BatchRequest>> _buildExecutionOrder() {
    // Group requests by dependency level
    final levels = <List<BatchRequest>>[];
    final processed = <String>{};
    final remaining = List<BatchRequest>.from(_requests);

    while (remaining.isNotEmpty) {
      final currentLevel = <BatchRequest>[];

      // Find requests with satisfied dependencies
      for (final request in remaining.toList()) {
        final deps = request.dependsOn ?? [];
        if (deps.isEmpty || deps.every((d) => processed.contains(d))) {
          currentLevel.add(request);
          remaining.remove(request);
        }
      }

      if (currentLevel.isEmpty && remaining.isNotEmpty) {
        // Circular dependency detected - just process remaining
        currentLevel.addAll(remaining);
        remaining.clear();
      }

      // Sort by priority within level
      currentLevel.sort((a, b) => b.priority.compareTo(a.priority));
      levels.add(currentLevel);

      // Mark as processed
      for (final req in currentLevel) {
        if (req.id != null) processed.add(req.id!);
      }
    }

    return levels;
  }

  Future<Map<String, BatchRequestResult>> _executeOrdered(
    List<List<BatchRequest>> levels,
  ) async {
    var completed = 0;
    final total = _requests.length;

    for (final level in levels) {
      if (_isCancelled) break;

      // Execute level with concurrency limit
      await _executeConcurrent(level, (request, result) {
        completed++;
        _progressController.add(BatchProgress(
          completed: completed,
          total: total,
          currentRequest: request,
          result: result,
        ));
      });

      // Check for stop on error
      if (_config.stopOnError && _results.values.any((r) => r is BatchRequestFailure)) {
        // Mark remaining as skipped
        for (final remainingLevel in levels.skip(levels.indexOf(level) + 1)) {
          for (final request in remainingLevel) {
            final id = request.id ?? _getRequestIndex(request).toString();
            _results[id] = const BatchRequestSkipped('Stopped due to previous error');
          }
        }
        break;
      }
    }

    return Map.unmodifiable(_results);
  }

  Future<void> _executeConcurrent(
    List<BatchRequest> requests,
    void Function(BatchRequest request, BatchRequestResult result) onComplete,
  ) async {
    final semaphore = _Semaphore(_config.maxConcurrent);

    await Future.wait(
      requests.map((request) async {
        await semaphore.acquire();
        try {
          if (_isCancelled) {
            final id = request.id ?? _getRequestIndex(request).toString();
            final result = const BatchRequestSkipped('Batch cancelled');
            _results[id] = result;
            onComplete(request, result);
            return;
          }

          // Check dependencies
          final deps = request.dependsOn ?? [];
          final failedDep = deps.firstWhere(
            (d) => _results[d] is BatchRequestFailure || _results[d] is BatchRequestSkipped,
            orElse: () => '',
          );

          if (failedDep.isNotEmpty) {
            final id = request.id ?? _getRequestIndex(request).toString();
            final result = BatchRequestSkipped('Dependency "$failedDep" failed');
            _results[id] = result;
            onComplete(request, result);
            return;
          }

          // Add delay if configured
          if (_config.delayBetweenRequests != null) {
            await Future.delayed(_config.delayBetweenRequests!);
          }

          // Execute request
          final result = await _executeSingle(request);
          onComplete(request, result);
        } finally {
          semaphore.release();
        }
      }),
    );
  }

  Future<BatchRequestResult> _executeSingle(BatchRequest request) async {
    final id = request.id ?? _getRequestIndex(request).toString();

    try {
      final response = await _executor(request.request);
      final result = BatchRequestSuccess(response);
      _results[id] = result;
      return result;
    } catch (e) {
      final error = e is ApiError ? e : ApiError.unknown(e);
      final result = BatchRequestFailure(error);
      _results[id] = result;
      return result;
    }
  }

  int _getRequestIndex(BatchRequest request) {
    return _requests.indexOf(request);
  }

  /// Cancels the batch execution.
  void cancel() {
    _isCancelled = true;
  }

  /// Disposes resources.
  void dispose() {
    _progressController.close();
  }
}

/// Progress of batch execution.
class BatchProgress {
  /// Creates a new [BatchProgress].
  const BatchProgress({
    required this.completed,
    required this.total,
    required this.currentRequest,
    required this.result,
  });

  /// Number of completed requests.
  final int completed;

  /// Total number of requests.
  final int total;

  /// The request that just completed.
  final BatchRequest currentRequest;

  /// Result of the completed request.
  final BatchRequestResult result;

  /// Progress percentage (0.0 to 1.0).
  double get progress => total > 0 ? completed / total : 0;
}

/// Simple semaphore for limiting concurrency.
class _Semaphore {
  _Semaphore(this.maxConcurrent);

  final int maxConcurrent;
  int _current = 0;
  final _queue = <Completer<void>>[];

  Future<void> acquire() async {
    if (_current < maxConcurrent) {
      _current++;
      return;
    }

    final completer = Completer<void>();
    _queue.add(completer);
    await completer.future;
  }

  void release() {
    if (_queue.isNotEmpty) {
      final completer = _queue.removeAt(0);
      completer.complete();
    } else {
      _current--;
    }
  }
}

/// Builder for creating request batches fluently.
class BatchBuilder {
  /// Creates a new [BatchBuilder].
  BatchBuilder({
    required BatchRequestExecutor executor,
  }) : _executor = executor;

  final BatchRequestExecutor _executor;
  final List<BatchRequest> _requests = [];
  BatchConfig _config = const BatchConfig();

  /// Configures the batch execution.
  BatchBuilder config(BatchConfig config) {
    _config = config;
    return this;
  }

  /// Adds a GET request.
  BatchBuilder get(
    String path, {
    String? id,
    List<String>? dependsOn,
    int priority = 0,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
  }) {
    _requests.add(BatchRequest(
      request: NetworkRequest(
        method: HttpMethod.get,
        path: path,
        queryParameters: queryParameters,
        headers: headers,
      ),
      id: id,
      dependsOn: dependsOn,
      priority: priority,
    ));
    return this;
  }

  /// Adds a POST request.
  BatchBuilder post(
    String path, {
    String? id,
    List<String>? dependsOn,
    int priority = 0,
    dynamic body,
    Map<String, String>? headers,
  }) {
    _requests.add(BatchRequest(
      request: NetworkRequest(
        method: HttpMethod.post,
        path: path,
        body: body,
        headers: headers,
      ),
      id: id,
      dependsOn: dependsOn,
      priority: priority,
    ));
    return this;
  }

  /// Adds a PUT request.
  BatchBuilder put(
    String path, {
    String? id,
    List<String>? dependsOn,
    int priority = 0,
    dynamic body,
    Map<String, String>? headers,
  }) {
    _requests.add(BatchRequest(
      request: NetworkRequest(
        method: HttpMethod.put,
        path: path,
        body: body,
        headers: headers,
      ),
      id: id,
      dependsOn: dependsOn,
      priority: priority,
    ));
    return this;
  }

  /// Adds a DELETE request.
  BatchBuilder delete(
    String path, {
    String? id,
    List<String>? dependsOn,
    int priority = 0,
    Map<String, String>? headers,
  }) {
    _requests.add(BatchRequest(
      request: NetworkRequest(
        method: HttpMethod.delete,
        path: path,
        headers: headers,
      ),
      id: id,
      dependsOn: dependsOn,
      priority: priority,
    ));
    return this;
  }

  /// Builds and executes the batch.
  Future<Map<String, BatchRequestResult>> execute() {
    final batch = RequestBatch(executor: _executor, config: _config);
    batch.addAll(_requests);
    return batch.execute();
  }

  /// Builds the batch without executing.
  RequestBatch build() {
    final batch = RequestBatch(executor: _executor, config: _config);
    batch.addAll(_requests);
    return batch;
  }
}
