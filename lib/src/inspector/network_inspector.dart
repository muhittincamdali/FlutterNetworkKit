import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../monitoring/request_metrics.dart';

/// Recorded network request for inspection.
class InspectorRequest {
  /// Creates a new [InspectorRequest].
  InspectorRequest({
    required this.id,
    required this.method,
    required this.url,
    required this.timestamp,
    this.requestHeaders,
    this.requestBody,
    this.responseHeaders,
    this.responseBody,
    this.statusCode,
    this.duration,
    this.error,
    this.responseSize,
    this.requestSize,
    this.fromCache = false,
  });

  /// Unique identifier.
  final String id;

  /// HTTP method.
  final String method;

  /// Request URL.
  final String url;

  /// When the request was made.
  final DateTime timestamp;

  /// Request headers.
  final Map<String, dynamic>? requestHeaders;

  /// Request body.
  final dynamic requestBody;

  /// Response headers.
  final Map<String, List<String>>? responseHeaders;

  /// Response body.
  final dynamic responseBody;

  /// HTTP status code.
  final int? statusCode;

  /// Request duration.
  final Duration? duration;

  /// Error if request failed.
  final String? error;

  /// Response size in bytes.
  final int? responseSize;

  /// Request size in bytes.
  final int? requestSize;

  /// Whether response was from cache.
  final bool fromCache;

  /// Whether the request was successful.
  bool get isSuccess => statusCode != null && statusCode! >= 200 && statusCode! < 300;

  /// Whether the request failed.
  bool get isFailed => statusCode != null && statusCode! >= 400 || error != null;

  /// Whether the request is pending.
  bool get isPending => statusCode == null && error == null;

  /// Status code category.
  String get statusCategory {
    if (isPending) return 'Pending';
    if (error != null) return 'Error';
    if (statusCode == null) return 'Unknown';
    if (statusCode! < 200) return '1xx';
    if (statusCode! < 300) return '2xx';
    if (statusCode! < 400) return '3xx';
    if (statusCode! < 500) return '4xx';
    return '5xx';
  }

  /// Formatted request body for display.
  String get formattedRequestBody {
    if (requestBody == null) return '';
    if (requestBody is String) return requestBody;
    try {
      return const JsonEncoder.withIndent('  ').convert(requestBody);
    } catch (_) {
      return requestBody.toString();
    }
  }

  /// Formatted response body for display.
  String get formattedResponseBody {
    if (responseBody == null) return '';
    if (responseBody is String) return responseBody;
    try {
      return const JsonEncoder.withIndent('  ').convert(responseBody);
    } catch (_) {
      return responseBody.toString();
    }
  }

  /// Converts to JSON for export.
  Map<String, dynamic> toJson() => {
        'id': id,
        'method': method,
        'url': url,
        'timestamp': timestamp.toIso8601String(),
        'requestHeaders': requestHeaders,
        'requestBody': requestBody,
        'responseHeaders': responseHeaders,
        'responseBody': responseBody,
        'statusCode': statusCode,
        'duration': duration?.inMilliseconds,
        'error': error,
        'responseSize': responseSize,
        'requestSize': requestSize,
        'fromCache': fromCache,
      };
}

/// Configuration for the network inspector.
class InspectorConfig {
  /// Creates a new [InspectorConfig].
  const InspectorConfig({
    this.maxRequests = 500,
    this.enabled = true,
    this.recordRequestBodies = true,
    this.recordResponseBodies = true,
    this.maxBodySize = 100 * 1024, // 100KB
  });

  /// Maximum number of requests to keep.
  final int maxRequests;

  /// Whether the inspector is enabled.
  final bool enabled;

  /// Whether to record request bodies.
  final bool recordRequestBodies;

  /// Whether to record response bodies.
  final bool recordResponseBodies;

  /// Maximum body size to record (in bytes).
  final int maxBodySize;
}

/// Network inspector for debugging and monitoring HTTP requests.
///
/// Example:
/// ```dart
/// final inspector = NetworkInspector();
///
/// // Record a request
/// final id = inspector.recordRequest(
///   method: 'GET',
///   url: 'https://api.example.com/users',
///   headers: {'Authorization': 'Bearer token'},
/// );
///
/// // Later, record the response
/// inspector.recordResponse(
///   id: id,
///   statusCode: 200,
///   body: responseBody,
/// );
///
/// // Show the inspector UI
/// NetworkInspectorOverlay.show(context, inspector);
/// ```
class NetworkInspector {
  /// Creates a new [NetworkInspector].
  NetworkInspector({
    InspectorConfig? config,
  }) : _config = config ?? const InspectorConfig();

  final InspectorConfig _config;
  final List<InspectorRequest> _requests = [];
  int _requestCounter = 0;

  final _requestsController = StreamController<List<InspectorRequest>>.broadcast();

  /// Stream of request updates.
  Stream<List<InspectorRequest>> get requestsStream => _requestsController.stream;

  /// Current configuration.
  InspectorConfig get config => _config;

  /// All recorded requests.
  List<InspectorRequest> get requests => List.unmodifiable(_requests);

  /// Records a new request and returns its ID.
  String recordRequest({
    required String method,
    required String url,
    Map<String, dynamic>? headers,
    dynamic body,
    int? requestSize,
  }) {
    if (!_config.enabled) return '';

    final id = 'req_${++_requestCounter}';
    final request = InspectorRequest(
      id: id,
      method: method,
      url: url,
      timestamp: DateTime.now(),
      requestHeaders: headers,
      requestBody: _config.recordRequestBodies ? _truncateBody(body) : null,
      requestSize: requestSize,
    );

    _requests.insert(0, request);
    _trimRequests();
    _notifyListeners();

    return id;
  }

  /// Records a response for a previously recorded request.
  void recordResponse({
    required String id,
    required int statusCode,
    Map<String, List<String>>? headers,
    dynamic body,
    Duration? duration,
    int? responseSize,
    bool fromCache = false,
  }) {
    if (!_config.enabled) return;

    final index = _requests.indexWhere((r) => r.id == id);
    if (index == -1) return;

    final original = _requests[index];
    _requests[index] = InspectorRequest(
      id: original.id,
      method: original.method,
      url: original.url,
      timestamp: original.timestamp,
      requestHeaders: original.requestHeaders,
      requestBody: original.requestBody,
      requestSize: original.requestSize,
      responseHeaders: headers,
      responseBody: _config.recordResponseBodies ? _truncateBody(body) : null,
      statusCode: statusCode,
      duration: duration ?? DateTime.now().difference(original.timestamp),
      responseSize: responseSize,
      fromCache: fromCache,
    );

    _notifyListeners();
  }

  /// Records an error for a previously recorded request.
  void recordError({
    required String id,
    required String error,
    Duration? duration,
  }) {
    if (!_config.enabled) return;

    final index = _requests.indexWhere((r) => r.id == id);
    if (index == -1) return;

    final original = _requests[index];
    _requests[index] = InspectorRequest(
      id: original.id,
      method: original.method,
      url: original.url,
      timestamp: original.timestamp,
      requestHeaders: original.requestHeaders,
      requestBody: original.requestBody,
      requestSize: original.requestSize,
      error: error,
      duration: duration ?? DateTime.now().difference(original.timestamp),
    );

    _notifyListeners();
  }

  dynamic _truncateBody(dynamic body) {
    if (body == null) return null;

    String stringBody;
    if (body is String) {
      stringBody = body;
    } else {
      try {
        stringBody = jsonEncode(body);
      } catch (_) {
        stringBody = body.toString();
      }
    }

    if (stringBody.length > _config.maxBodySize) {
      return '${stringBody.substring(0, _config.maxBodySize)}...[truncated]';
    }

    return body;
  }

  void _trimRequests() {
    while (_requests.length > _config.maxRequests) {
      _requests.removeLast();
    }
  }

  void _notifyListeners() {
    _requestsController.add(List.unmodifiable(_requests));
  }

  /// Clears all recorded requests.
  void clear() {
    _requests.clear();
    _notifyListeners();
  }

  /// Exports all requests as JSON.
  String exportAsJson() {
    return const JsonEncoder.withIndent('  ')
        .convert(_requests.map((r) => r.toJson()).toList());
  }

  /// Gets requests filtered by method.
  List<InspectorRequest> filterByMethod(String method) {
    return _requests.where((r) => r.method == method).toList();
  }

  /// Gets requests filtered by status.
  List<InspectorRequest> filterByStatus(int minStatus, int maxStatus) {
    return _requests
        .where((r) =>
            r.statusCode != null &&
            r.statusCode! >= minStatus &&
            r.statusCode! < maxStatus)
        .toList();
  }

  /// Gets failed requests.
  List<InspectorRequest> get failedRequests {
    return _requests.where((r) => r.isFailed).toList();
  }

  /// Gets pending requests.
  List<InspectorRequest> get pendingRequests {
    return _requests.where((r) => r.isPending).toList();
  }

  /// Gets statistics about recorded requests.
  InspectorStats get stats => InspectorStats(
        totalRequests: _requests.length,
        successfulRequests: _requests.where((r) => r.isSuccess).length,
        failedRequests: _requests.where((r) => r.isFailed).length,
        pendingRequests: _requests.where((r) => r.isPending).length,
        averageDuration: _calculateAverageDuration(),
        cachedRequests: _requests.where((r) => r.fromCache).length,
      );

  Duration _calculateAverageDuration() {
    final completed = _requests.where((r) => r.duration != null).toList();
    if (completed.isEmpty) return Duration.zero;

    final totalMs =
        completed.fold<int>(0, (sum, r) => sum + r.duration!.inMilliseconds);
    return Duration(milliseconds: totalMs ~/ completed.length);
  }

  /// Disposes the inspector.
  void dispose() {
    _requestsController.close();
  }
}

/// Statistics about recorded requests.
class InspectorStats {
  /// Creates new [InspectorStats].
  const InspectorStats({
    required this.totalRequests,
    required this.successfulRequests,
    required this.failedRequests,
    required this.pendingRequests,
    required this.averageDuration,
    required this.cachedRequests,
  });

  /// Total number of requests.
  final int totalRequests;

  /// Number of successful requests.
  final int successfulRequests;

  /// Number of failed requests.
  final int failedRequests;

  /// Number of pending requests.
  final int pendingRequests;

  /// Average request duration.
  final Duration averageDuration;

  /// Number of cached responses.
  final int cachedRequests;

  /// Success rate percentage.
  double get successRate {
    final completed = totalRequests - pendingRequests;
    if (completed == 0) return 0;
    return (successfulRequests / completed) * 100;
  }

  /// Cache hit rate percentage.
  double get cacheHitRate {
    final completed = totalRequests - pendingRequests;
    if (completed == 0) return 0;
    return (cachedRequests / completed) * 100;
  }
}

/// Overlay widget for displaying the network inspector.
class NetworkInspectorOverlay extends StatefulWidget {
  /// Creates a new [NetworkInspectorOverlay].
  const NetworkInspectorOverlay({
    super.key,
    required this.inspector,
  });

  /// The network inspector to display.
  final NetworkInspector inspector;

  /// Shows the inspector overlay.
  static void show(BuildContext context, NetworkInspector inspector) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => NetworkInspectorOverlay(
          inspector: inspector,
        ),
      ),
    );
  }

  @override
  State<NetworkInspectorOverlay> createState() => _NetworkInspectorOverlayState();
}

class _NetworkInspectorOverlayState extends State<NetworkInspectorOverlay> {
  String _filter = '';
  String? _methodFilter;
  List<InspectorRequest> _filteredRequests = [];

  @override
  void initState() {
    super.initState();
    _updateFilteredRequests();
    widget.inspector.requestsStream.listen((_) {
      if (mounted) {
        setState(() {
          _updateFilteredRequests();
        });
      }
    });
  }

  void _updateFilteredRequests() {
    var requests = widget.inspector.requests;

    if (_filter.isNotEmpty) {
      requests = requests
          .where((r) =>
              r.url.toLowerCase().contains(_filter.toLowerCase()) ||
              r.method.toLowerCase().contains(_filter.toLowerCase()))
          .toList();
    }

    if (_methodFilter != null) {
      requests = requests.where((r) => r.method == _methodFilter).toList();
    }

    _filteredRequests = requests;
  }

  @override
  Widget build(BuildContext context) {
    final stats = widget.inspector.stats;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Network Inspector'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              widget.inspector.clear();
              setState(() {
                _updateFilteredRequests();
              });
            },
            tooltip: 'Clear all',
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () {
              final json = widget.inspector.exportAsJson();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Exported ${_filteredRequests.length} requests')),
              );
            },
            tooltip: 'Export',
          ),
        ],
      ),
      body: Column(
        children: [
          // Stats bar
          Container(
            padding: const EdgeInsets.all(8),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatChip(
                  label: 'Total',
                  value: stats.totalRequests.toString(),
                  color: Colors.blue,
                ),
                _StatChip(
                  label: 'Success',
                  value: stats.successfulRequests.toString(),
                  color: Colors.green,
                ),
                _StatChip(
                  label: 'Failed',
                  value: stats.failedRequests.toString(),
                  color: Colors.red,
                ),
                _StatChip(
                  label: 'Avg',
                  value: '${stats.averageDuration.inMilliseconds}ms',
                  color: Colors.orange,
                ),
              ],
            ),
          ),

          // Filter bar
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Filter by URL...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (value) {
                      setState(() {
                        _filter = value;
                        _updateFilteredRequests();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String?>(
                  value: _methodFilter,
                  hint: const Text('Method'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All')),
                    ...['GET', 'POST', 'PUT', 'PATCH', 'DELETE'].map(
                      (m) => DropdownMenuItem(value: m, child: Text(m)),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _methodFilter = value;
                      _updateFilteredRequests();
                    });
                  },
                ),
              ],
            ),
          ),

          // Request list
          Expanded(
            child: ListView.builder(
              itemCount: _filteredRequests.length,
              itemBuilder: (context, index) {
                final request = _filteredRequests[index];
                return _RequestTile(
                  request: request,
                  onTap: () => _showRequestDetails(context, request),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showRequestDetails(BuildContext context, InspectorRequest request) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _RequestDetailsPage(request: request),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({
    required this.request,
    required this.onTap,
  });

  final InspectorRequest request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: _MethodBadge(method: request.method),
      title: Text(
        Uri.parse(request.url).path,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        request.url,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _StatusBadge(request: request),
          if (request.duration != null)
            Text(
              '${request.duration!.inMilliseconds}ms',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _MethodBadge extends StatelessWidget {
  const _MethodBadge({required this.method});

  final String method;

  @override
  Widget build(BuildContext context) {
    final color = switch (method) {
      'GET' => Colors.blue,
      'POST' => Colors.green,
      'PUT' => Colors.orange,
      'PATCH' => Colors.purple,
      'DELETE' => Colors.red,
      _ => Colors.grey,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        method,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 10,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.request});

  final InspectorRequest request;

  @override
  Widget build(BuildContext context) {
    if (request.isPending) {
      return const SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    final color = request.isSuccess
        ? Colors.green
        : request.isFailed
            ? Colors.red
            : Colors.grey;

    final text = request.statusCode?.toString() ?? 'ERR';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _RequestDetailsPage extends StatelessWidget {
  const _RequestDetailsPage({required this.request});

  final InspectorRequest request;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(request.method),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Request'),
              Tab(text: 'Response'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _OverviewTab(request: request),
            _RequestTab(request: request),
            _ResponseTab(request: request),
          ],
        ),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.request});

  final InspectorRequest request;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _DetailRow(label: 'URL', value: request.url),
        _DetailRow(label: 'Method', value: request.method),
        _DetailRow(
          label: 'Status',
          value: request.statusCode?.toString() ?? 'Pending',
        ),
        _DetailRow(
          label: 'Duration',
          value: request.duration != null
              ? '${request.duration!.inMilliseconds}ms'
              : 'N/A',
        ),
        _DetailRow(
          label: 'Time',
          value: request.timestamp.toString(),
        ),
        if (request.fromCache)
          _DetailRow(label: 'Cache', value: 'From cache'),
        if (request.error != null)
          _DetailRow(label: 'Error', value: request.error!),
      ],
    );
  }
}

class _RequestTab extends StatelessWidget {
  const _RequestTab({required this.request});

  final InspectorRequest request;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Headers', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (request.requestHeaders != null)
          ...request.requestHeaders!.entries.map(
            (e) => _DetailRow(label: e.key, value: e.value.toString()),
          )
        else
          const Text('No headers'),
        const SizedBox(height: 16),
        Text('Body', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
          child: SelectableText(
            request.formattedRequestBody.isEmpty
                ? 'No body'
                : request.formattedRequestBody,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _ResponseTab extends StatelessWidget {
  const _ResponseTab({required this.request});

  final InspectorRequest request;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Headers', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (request.responseHeaders != null)
          ...request.responseHeaders!.entries.map(
            (e) => _DetailRow(label: e.key, value: e.value.join(', ')),
          )
        else
          const Text('No headers'),
        const SizedBox(height: 16),
        Text('Body', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
          child: SelectableText(
            request.formattedResponseBody.isEmpty
                ? 'No body'
                : request.formattedResponseBody,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}
