import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../request/request.dart';
import '../response/response.dart';

/// Represents a queued request that will be executed when network is available.
class QueuedRequest {
  /// Creates a new [QueuedRequest].
  QueuedRequest({
    required this.id,
    required this.request,
    required this.createdAt,
    this.priority = 0,
    this.maxRetries = 3,
    this.retryCount = 0,
    this.expiresAt,
    this.metadata,
  });

  /// Unique identifier for this queued request.
  final String id;

  /// The network request to execute.
  final NetworkRequest request;

  /// When this request was queued.
  final DateTime createdAt;

  /// Priority level (higher = more important).
  final int priority;

  /// Maximum number of retry attempts.
  final int maxRetries;

  /// Current retry count.
  int retryCount;

  /// When this request expires (null = never).
  final DateTime? expiresAt;

  /// Additional metadata for the request.
  final Map<String, dynamic>? metadata;

  /// Whether this request has expired.
  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);

  /// Whether this request can be retried.
  bool get canRetry => retryCount < maxRetries;

  /// Converts to JSON for persistence.
  Map<String, dynamic> toJson() => {
        'id': id,
        'request': request.toJson(),
        'createdAt': createdAt.toIso8601String(),
        'priority': priority,
        'maxRetries': maxRetries,
        'retryCount': retryCount,
        'expiresAt': expiresAt?.toIso8601String(),
        'metadata': metadata,
      };

  /// Creates from JSON.
  factory QueuedRequest.fromJson(Map<String, dynamic> json) => QueuedRequest(
        id: json['id'] as String,
        request: NetworkRequest.fromJson(json['request'] as Map<String, dynamic>),
        createdAt: DateTime.parse(json['createdAt'] as String),
        priority: json['priority'] as int? ?? 0,
        maxRetries: json['maxRetries'] as int? ?? 3,
        retryCount: json['retryCount'] as int? ?? 0,
        expiresAt: json['expiresAt'] != null
            ? DateTime.parse(json['expiresAt'] as String)
            : null,
        metadata: json['metadata'] as Map<String, dynamic>?,
      );
}

/// Result of executing a queued request.
sealed class QueueExecutionResult {
  const QueueExecutionResult();
}

/// Request was executed successfully.
class QueueExecutionSuccess extends QueueExecutionResult {
  const QueueExecutionSuccess(this.response);
  final NetworkResponse response;
}

/// Request execution failed.
class QueueExecutionFailure extends QueueExecutionResult {
  const QueueExecutionFailure(this.error, {this.shouldRetry = true});
  final Object error;
  final bool shouldRetry;
}

/// Request was skipped (expired, cancelled, etc).
class QueueExecutionSkipped extends QueueExecutionResult {
  const QueueExecutionSkipped(this.reason);
  final String reason;
}

/// Callback for executing a queued request.
typedef RequestExecutor = Future<NetworkResponse> Function(NetworkRequest request);

/// Configuration for the offline queue.
class OfflineQueueConfig {
  /// Creates a new [OfflineQueueConfig].
  const OfflineQueueConfig({
    this.maxQueueSize = 100,
    this.processingInterval = const Duration(seconds: 5),
    this.persistQueue = true,
    this.processOnReconnect = true,
    this.maxConcurrentRequests = 3,
    this.defaultPriority = 0,
    this.defaultMaxRetries = 3,
    this.defaultExpiration,
  });

  /// Maximum number of requests in the queue.
  final int maxQueueSize;

  /// Interval for processing the queue when online.
  final Duration processingInterval;

  /// Whether to persist the queue to disk.
  final bool persistQueue;

  /// Whether to process queue immediately on reconnect.
  final bool processOnReconnect;

  /// Maximum concurrent requests when processing queue.
  final int maxConcurrentRequests;

  /// Default priority for new requests.
  final int defaultPriority;

  /// Default max retries for new requests.
  final int defaultMaxRetries;

  /// Default expiration duration for new requests.
  final Duration? defaultExpiration;
}

/// Manages a queue of requests to be executed when network is available.
///
/// The [OfflineQueue] automatically queues failed requests when offline
/// and processes them when connectivity is restored.
///
/// Example:
/// ```dart
/// final queue = OfflineQueue(
///   executor: (request) => client.execute(request),
///   config: OfflineQueueConfig(
///     maxQueueSize: 50,
///     processOnReconnect: true,
///   ),
/// );
///
/// await queue.initialize();
///
/// // Queue a request
/// final id = await queue.enqueue(request);
///
/// // Listen for results
/// queue.resultStream.listen((result) {
///   print('Request ${result.requestId} completed');
/// });
/// ```
class OfflineQueue {
  /// Creates a new [OfflineQueue].
  OfflineQueue({
    required RequestExecutor executor,
    OfflineQueueConfig? config,
  })  : _executor = executor,
        _config = config ?? const OfflineQueueConfig();

  final RequestExecutor _executor;
  final OfflineQueueConfig _config;
  final Uuid _uuid = const Uuid();

  Box<String>? _box;
  final List<QueuedRequest> _queue = [];
  final Map<String, Completer<QueueExecutionResult>> _completers = {};

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _processingTimer;
  bool _isProcessing = false;
  bool _isOnline = true;
  bool _isInitialized = false;

  final _resultController = StreamController<QueuedRequestResult>.broadcast();
  final _queueChangeController = StreamController<QueueChangeEvent>.broadcast();

  /// Stream of request execution results.
  Stream<QueuedRequestResult> get resultStream => _resultController.stream;

  /// Stream of queue change events.
  Stream<QueueChangeEvent> get queueChangeStream => _queueChangeController.stream;

  /// Current queue size.
  int get queueSize => _queue.length;

  /// Whether the queue is currently processing.
  bool get isProcessing => _isProcessing;

  /// Whether the device is online.
  bool get isOnline => _isOnline;

  /// Current queued requests (read-only).
  List<QueuedRequest> get queuedRequests => List.unmodifiable(_queue);

  /// Initializes the offline queue.
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Load persisted queue
    if (_config.persistQueue) {
      _box = await Hive.openBox<String>('offline_queue');
      await _loadPersistedQueue();
    }

    // Monitor connectivity
    _connectivitySubscription = Connectivity()
        .onConnectivityChanged
        .listen(_handleConnectivityChange);

    // Check initial connectivity
    final result = await Connectivity().checkConnectivity();
    _isOnline = !result.contains(ConnectivityResult.none);

    // Start processing timer
    if (_isOnline) {
      _startProcessingTimer();
    }

    _isInitialized = true;
  }

  Future<void> _loadPersistedQueue() async {
    if (_box == null) return;

    final keys = _box!.keys.toList();
    for (final key in keys) {
      try {
        final json = _box!.get(key);
        if (json != null) {
          final request = QueuedRequest.fromJson(
            jsonDecode(json) as Map<String, dynamic>,
          );
          if (!request.isExpired) {
            _queue.add(request);
          } else {
            await _box!.delete(key);
          }
        }
      } catch (e) {
        // Remove corrupted entries
        await _box!.delete(key);
      }
    }

    // Sort by priority
    _sortQueue();
  }

  void _handleConnectivityChange(List<ConnectivityResult> results) {
    final wasOnline = _isOnline;
    _isOnline = !results.contains(ConnectivityResult.none);

    if (!wasOnline && _isOnline) {
      // Just came online
      if (_config.processOnReconnect) {
        processQueue();
      }
      _startProcessingTimer();
    } else if (wasOnline && !_isOnline) {
      // Just went offline
      _stopProcessingTimer();
    }
  }

  void _startProcessingTimer() {
    _processingTimer?.cancel();
    _processingTimer = Timer.periodic(
      _config.processingInterval,
      (_) => processQueue(),
    );
  }

  void _stopProcessingTimer() {
    _processingTimer?.cancel();
    _processingTimer = null;
  }

  /// Enqueues a request to be executed when online.
  ///
  /// Returns the unique ID of the queued request.
  Future<String> enqueue(
    NetworkRequest request, {
    int? priority,
    int? maxRetries,
    Duration? expiration,
    Map<String, dynamic>? metadata,
  }) async {
    if (_queue.length >= _config.maxQueueSize) {
      throw OfflineQueueFullException(_config.maxQueueSize);
    }

    final id = _uuid.v4();
    final queuedRequest = QueuedRequest(
      id: id,
      request: request,
      createdAt: DateTime.now(),
      priority: priority ?? _config.defaultPriority,
      maxRetries: maxRetries ?? _config.defaultMaxRetries,
      expiresAt: (expiration ?? _config.defaultExpiration) != null
          ? DateTime.now().add(expiration ?? _config.defaultExpiration!)
          : null,
      metadata: metadata,
    );

    _queue.add(queuedRequest);
    _sortQueue();

    // Persist
    await _persistRequest(queuedRequest);

    _queueChangeController.add(QueueChangeEvent.added(queuedRequest));

    // If online, try to process immediately
    if (_isOnline && !_isProcessing) {
      processQueue();
    }

    return id;
  }

  /// Enqueues a request and waits for its result.
  Future<QueueExecutionResult> enqueueAndWait(
    NetworkRequest request, {
    int? priority,
    int? maxRetries,
    Duration? expiration,
    Map<String, dynamic>? metadata,
    Duration? timeout,
  }) async {
    final id = await enqueue(
      request,
      priority: priority,
      maxRetries: maxRetries,
      expiration: expiration,
      metadata: metadata,
    );

    final completer = Completer<QueueExecutionResult>();
    _completers[id] = completer;

    if (timeout != null) {
      return completer.future.timeout(
        timeout,
        onTimeout: () {
          _completers.remove(id);
          return QueueExecutionSkipped('Timeout waiting for execution');
        },
      );
    }

    return completer.future;
  }

  /// Removes a request from the queue.
  Future<bool> remove(String id) async {
    final index = _queue.indexWhere((r) => r.id == id);
    if (index == -1) return false;

    final request = _queue.removeAt(index);
    await _removePersistedRequest(id);

    _queueChangeController.add(QueueChangeEvent.removed(request));

    final completer = _completers.remove(id);
    completer?.complete(QueueExecutionSkipped('Removed from queue'));

    return true;
  }

  /// Clears all requests from the queue.
  Future<void> clear() async {
    final requests = List<QueuedRequest>.from(_queue);
    _queue.clear();

    if (_box != null) {
      await _box!.clear();
    }

    for (final request in requests) {
      _queueChangeController.add(QueueChangeEvent.removed(request));
      final completer = _completers.remove(request.id);
      completer?.complete(QueueExecutionSkipped('Queue cleared'));
    }
  }

  /// Processes the queue, executing pending requests.
  Future<void> processQueue() async {
    if (!_isOnline || _isProcessing || _queue.isEmpty) return;

    _isProcessing = true;

    try {
      // Process requests in batches
      while (_queue.isNotEmpty && _isOnline) {
        // Get next batch
        final batch = _queue
            .where((r) => !r.isExpired)
            .take(_config.maxConcurrentRequests)
            .toList();

        if (batch.isEmpty) {
          // All remaining are expired, clean them up
          await _cleanupExpired();
          break;
        }

        // Execute batch concurrently
        await Future.wait(
          batch.map((request) => _executeRequest(request)),
        );
      }
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _executeRequest(QueuedRequest queuedRequest) async {
    try {
      final response = await _executor(queuedRequest.request);

      // Success - remove from queue
      _queue.remove(queuedRequest);
      await _removePersistedRequest(queuedRequest.id);

      final result = QueueExecutionSuccess(response);
      _resultController.add(QueuedRequestResult(queuedRequest.id, result));
      _queueChangeController.add(QueueChangeEvent.completed(queuedRequest));

      final completer = _completers.remove(queuedRequest.id);
      completer?.complete(result);
    } catch (e) {
      queuedRequest.retryCount++;

      if (queuedRequest.canRetry) {
        // Update persisted state
        await _persistRequest(queuedRequest);
        _queueChangeController.add(QueueChangeEvent.retrying(queuedRequest));
      } else {
        // Max retries exceeded - remove from queue
        _queue.remove(queuedRequest);
        await _removePersistedRequest(queuedRequest.id);

        final result = QueueExecutionFailure(e, shouldRetry: false);
        _resultController.add(QueuedRequestResult(queuedRequest.id, result));
        _queueChangeController.add(QueueChangeEvent.failed(queuedRequest, e));

        final completer = _completers.remove(queuedRequest.id);
        completer?.complete(result);
      }
    }
  }

  Future<void> _cleanupExpired() async {
    final expired = _queue.where((r) => r.isExpired).toList();
    for (final request in expired) {
      _queue.remove(request);
      await _removePersistedRequest(request.id);

      final result = QueueExecutionSkipped('Request expired');
      _resultController.add(QueuedRequestResult(request.id, result));
      _queueChangeController.add(QueueChangeEvent.expired(request));

      final completer = _completers.remove(request.id);
      completer?.complete(result);
    }
  }

  void _sortQueue() {
    _queue.sort((a, b) {
      // Higher priority first
      final priorityCompare = b.priority.compareTo(a.priority);
      if (priorityCompare != 0) return priorityCompare;
      // Older first (FIFO within same priority)
      return a.createdAt.compareTo(b.createdAt);
    });
  }

  Future<void> _persistRequest(QueuedRequest request) async {
    if (_box == null) return;
    await _box!.put(request.id, jsonEncode(request.toJson()));
  }

  Future<void> _removePersistedRequest(String id) async {
    if (_box == null) return;
    await _box!.delete(id);
  }

  /// Disposes the queue and releases resources.
  Future<void> dispose() async {
    _processingTimer?.cancel();
    await _connectivitySubscription?.cancel();
    await _resultController.close();
    await _queueChangeController.close();
    await _box?.close();

    for (final completer in _completers.values) {
      if (!completer.isCompleted) {
        completer.complete(QueueExecutionSkipped('Queue disposed'));
      }
    }
    _completers.clear();
  }
}

/// Result of a queued request execution.
class QueuedRequestResult {
  /// Creates a new [QueuedRequestResult].
  const QueuedRequestResult(this.requestId, this.result);

  /// The ID of the request.
  final String requestId;

  /// The execution result.
  final QueueExecutionResult result;
}

/// Event representing a change to the queue.
sealed class QueueChangeEvent {
  const QueueChangeEvent(this.request);
  final QueuedRequest request;

  /// Request was added to the queue.
  factory QueueChangeEvent.added(QueuedRequest request) = QueueAddedEvent;

  /// Request was removed from the queue.
  factory QueueChangeEvent.removed(QueuedRequest request) = QueueRemovedEvent;

  /// Request completed successfully.
  factory QueueChangeEvent.completed(QueuedRequest request) = QueueCompletedEvent;

  /// Request failed and is being retried.
  factory QueueChangeEvent.retrying(QueuedRequest request) = QueueRetryingEvent;

  /// Request failed after max retries.
  factory QueueChangeEvent.failed(QueuedRequest request, Object error) = QueueFailedEvent;

  /// Request expired.
  factory QueueChangeEvent.expired(QueuedRequest request) = QueueExpiredEvent;
}

class QueueAddedEvent extends QueueChangeEvent {
  const QueueAddedEvent(super.request);
}

class QueueRemovedEvent extends QueueChangeEvent {
  const QueueRemovedEvent(super.request);
}

class QueueCompletedEvent extends QueueChangeEvent {
  const QueueCompletedEvent(super.request);
}

class QueueRetryingEvent extends QueueChangeEvent {
  const QueueRetryingEvent(super.request);
}

class QueueFailedEvent extends QueueChangeEvent {
  const QueueFailedEvent(super.request, this.error);
  final Object error;
}

class QueueExpiredEvent extends QueueChangeEvent {
  const QueueExpiredEvent(super.request);
}

/// Exception thrown when the queue is full.
class OfflineQueueFullException implements Exception {
  /// Creates a new [OfflineQueueFullException].
  const OfflineQueueFullException(this.maxSize);

  /// The maximum queue size.
  final int maxSize;

  @override
  String toString() => 'OfflineQueueFullException: Queue is full (max $maxSize)';
}
