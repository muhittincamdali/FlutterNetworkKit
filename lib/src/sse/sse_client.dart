import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Represents a Server-Sent Event.
class ServerSentEvent {
  /// Creates a new [ServerSentEvent].
  const ServerSentEvent({
    this.id,
    this.event,
    this.data,
    this.retry,
  });

  /// Event ID.
  final String? id;

  /// Event type.
  final String? event;

  /// Event data.
  final String? data;

  /// Retry interval in milliseconds.
  final int? retry;

  /// Whether this is a comment event.
  bool get isComment => event == null && data == null;

  /// Parses JSON data.
  dynamic get jsonData {
    if (data == null) return null;
    try {
      return jsonDecode(data!);
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() => 'ServerSentEvent(id: $id, event: $event, data: $data)';
}

/// Connection state of the SSE client.
enum SSEConnectionState {
  /// Not connected.
  disconnected,

  /// Connecting.
  connecting,

  /// Connected and receiving events.
  connected,

  /// Reconnecting after disconnection.
  reconnecting,

  /// Connection closed.
  closed,
}

/// Configuration for SSE client.
class SSEConfig {
  /// Creates a new [SSEConfig].
  const SSEConfig({
    this.reconnect = true,
    this.maxReconnectAttempts = 5,
    this.initialReconnectDelay = const Duration(seconds: 1),
    this.maxReconnectDelay = const Duration(seconds: 30),
    this.reconnectDelayMultiplier = 2.0,
    this.timeout = const Duration(minutes: 5),
    this.headers,
  });

  /// Whether to automatically reconnect on disconnection.
  final bool reconnect;

  /// Maximum reconnection attempts before giving up.
  final int maxReconnectAttempts;

  /// Initial delay between reconnection attempts.
  final Duration initialReconnectDelay;

  /// Maximum delay between reconnection attempts.
  final Duration maxReconnectDelay;

  /// Multiplier for exponential backoff.
  final double reconnectDelayMultiplier;

  /// Connection timeout.
  final Duration timeout;

  /// Additional headers to send.
  final Map<String, String>? headers;
}

/// Client for Server-Sent Events (SSE).
///
/// Example:
/// ```dart
/// final client = SSEClient(
///   url: 'https://api.example.com/events',
///   config: SSEConfig(reconnect: true),
/// );
///
/// client.events.listen((event) {
///   print('Received: ${event.event} - ${event.data}');
/// });
///
/// await client.connect();
///
/// // Later
/// client.close();
/// ```
class SSEClient {
  /// Creates a new [SSEClient].
  SSEClient({
    required this.url,
    SSEConfig? config,
    http.Client? httpClient,
  })  : _config = config ?? const SSEConfig(),
        _httpClient = httpClient ?? http.Client();

  /// The URL to connect to.
  final String url;

  final SSEConfig _config;
  final http.Client _httpClient;

  StreamSubscription<String>? _subscription;
  int _reconnectAttempts = 0;
  Duration _currentReconnectDelay = Duration.zero;
  String? _lastEventId;
  SSEConnectionState _state = SSEConnectionState.disconnected;

  final _eventController = StreamController<ServerSentEvent>.broadcast();
  final _stateController = StreamController<SSEConnectionState>.broadcast();

  /// Stream of received events.
  Stream<ServerSentEvent> get events => _eventController.stream;

  /// Stream of connection state changes.
  Stream<SSEConnectionState> get stateStream => _stateController.stream;

  /// Current connection state.
  SSEConnectionState get state => _state;

  /// Whether the client is connected.
  bool get isConnected => _state == SSEConnectionState.connected;

  /// Last received event ID.
  String? get lastEventId => _lastEventId;

  void _setState(SSEConnectionState state) {
    _state = state;
    _stateController.add(state);
  }

  /// Connects to the SSE endpoint.
  Future<void> connect() async {
    if (_state == SSEConnectionState.connected ||
        _state == SSEConnectionState.connecting) {
      return;
    }

    _setState(SSEConnectionState.connecting);
    _reconnectAttempts = 0;
    _currentReconnectDelay = _config.initialReconnectDelay;

    await _doConnect();
  }

  Future<void> _doConnect() async {
    try {
      final headers = <String, String>{
        'Accept': 'text/event-stream',
        'Cache-Control': 'no-cache',
        ...?_config.headers,
      };

      // Send last event ID for resumption
      if (_lastEventId != null) {
        headers['Last-Event-ID'] = _lastEventId!;
      }

      final request = http.Request('GET', Uri.parse(url));
      request.headers.addAll(headers);

      final response = await _httpClient.send(request);

      if (response.statusCode != 200) {
        throw SSEException(
          'Failed to connect: HTTP ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }

      _setState(SSEConnectionState.connected);
      _reconnectAttempts = 0;

      // Parse the event stream
      final lineBuffer = StringBuffer();
      _subscription = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          _processLine(line, lineBuffer);
        },
        onDone: () {
          _handleDisconnection();
        },
        onError: (error) {
          _handleError(error);
        },
        cancelOnError: false,
      );
    } catch (e) {
      _handleError(e);
    }
  }

  void _processLine(String line, StringBuffer buffer) {
    if (line.isEmpty) {
      // Empty line means end of event
      final eventText = buffer.toString();
      buffer.clear();

      if (eventText.isNotEmpty) {
        final event = _parseEvent(eventText);
        if (event != null) {
          if (event.id != null) {
            _lastEventId = event.id;
          }
          _eventController.add(event);
        }
      }
    } else {
      buffer.writeln(line);
    }
  }

  ServerSentEvent? _parseEvent(String text) {
    String? id;
    String? event;
    final dataLines = <String>[];
    int? retry;

    for (final line in text.split('\n')) {
      if (line.isEmpty) continue;

      if (line.startsWith(':')) {
        // Comment, ignore
        continue;
      }

      final colonIndex = line.indexOf(':');
      String field;
      String value;

      if (colonIndex == -1) {
        field = line;
        value = '';
      } else {
        field = line.substring(0, colonIndex);
        value = line.substring(colonIndex + 1);
        if (value.startsWith(' ')) {
          value = value.substring(1);
        }
      }

      switch (field) {
        case 'id':
          id = value;
          break;
        case 'event':
          event = value;
          break;
        case 'data':
          dataLines.add(value);
          break;
        case 'retry':
          final retryValue = int.tryParse(value);
          if (retryValue != null) {
            retry = retryValue;
            _currentReconnectDelay = Duration(milliseconds: retryValue);
          }
          break;
      }
    }

    if (id == null && event == null && dataLines.isEmpty) {
      return null;
    }

    return ServerSentEvent(
      id: id,
      event: event,
      data: dataLines.isEmpty ? null : dataLines.join('\n'),
      retry: retry,
    );
  }

  void _handleDisconnection() {
    _subscription?.cancel();
    _subscription = null;

    if (_state == SSEConnectionState.closed) {
      return;
    }

    if (_config.reconnect && _reconnectAttempts < _config.maxReconnectAttempts) {
      _scheduleReconnect();
    } else {
      _setState(SSEConnectionState.disconnected);
    }
  }

  void _handleError(Object error) {
    _subscription?.cancel();
    _subscription = null;

    if (_state == SSEConnectionState.closed) {
      return;
    }

    if (_config.reconnect && _reconnectAttempts < _config.maxReconnectAttempts) {
      _scheduleReconnect();
    } else {
      _setState(SSEConnectionState.disconnected);
      _eventController.addError(
        error is SSEException ? error : SSEException('Connection error: $error'),
      );
    }
  }

  void _scheduleReconnect() {
    _setState(SSEConnectionState.reconnecting);
    _reconnectAttempts++;

    Future.delayed(_currentReconnectDelay, () {
      if (_state == SSEConnectionState.reconnecting) {
        // Exponential backoff
        _currentReconnectDelay = Duration(
          milliseconds: (_currentReconnectDelay.inMilliseconds *
                  _config.reconnectDelayMultiplier)
              .round(),
        );

        if (_currentReconnectDelay > _config.maxReconnectDelay) {
          _currentReconnectDelay = _config.maxReconnectDelay;
        }

        _doConnect();
      }
    });
  }

  /// Closes the connection.
  void close() {
    _setState(SSEConnectionState.closed);
    _subscription?.cancel();
    _subscription = null;
  }

  /// Disposes the client and releases resources.
  void dispose() {
    close();
    _eventController.close();
    _stateController.close();
  }
}

/// Exception thrown by SSE client.
class SSEException implements Exception {
  /// Creates a new [SSEException].
  const SSEException(this.message, {this.statusCode});

  /// Error message.
  final String message;

  /// HTTP status code if available.
  final int? statusCode;

  @override
  String toString() => 'SSEException: $message';
}

/// Builder for creating SSE subscriptions with typed event handlers.
class SSESubscription {
  /// Creates a new [SSESubscription].
  SSESubscription(this._client);

  final SSEClient _client;
  final Map<String, void Function(ServerSentEvent)> _handlers = {};
  void Function(ServerSentEvent)? _defaultHandler;
  StreamSubscription<ServerSentEvent>? _subscription;

  /// Registers a handler for a specific event type.
  SSESubscription on(String eventType, void Function(ServerSentEvent) handler) {
    _handlers[eventType] = handler;
    return this;
  }

  /// Registers a handler for 'message' events (default SSE event type).
  SSESubscription onMessage(void Function(ServerSentEvent) handler) {
    return on('message', handler);
  }

  /// Registers a default handler for unhandled event types.
  SSESubscription onDefault(void Function(ServerSentEvent) handler) {
    _defaultHandler = handler;
    return this;
  }

  /// Starts listening to events.
  void listen() {
    _subscription = _client.events.listen((event) {
      final eventType = event.event ?? 'message';
      final handler = _handlers[eventType] ?? _defaultHandler;
      handler?.call(event);
    });
  }

  /// Cancels the subscription.
  void cancel() {
    _subscription?.cancel();
    _subscription = null;
  }
}

/// Extension for convenient SSE subscriptions.
extension SSEClientSubscription on SSEClient {
  /// Creates a subscription builder.
  SSESubscription subscribe() => SSESubscription(this);

  /// Listens for events of a specific type.
  StreamSubscription<ServerSentEvent> onEvent(
    String eventType,
    void Function(ServerSentEvent) handler,
  ) {
    return events
        .where((e) => e.event == eventType || (e.event == null && eventType == 'message'))
        .listen(handler);
  }
}
