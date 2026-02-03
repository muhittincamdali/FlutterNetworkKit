import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

import 'websocket_message.dart';
import 'reconnection_strategy.dart';

/// A WebSocket client with automatic reconnection and message handling.
///
/// This client provides a robust WebSocket implementation with features
/// like automatic reconnection, heartbeat, and message serialization.
///
/// Example:
/// ```dart
/// final client = WebSocketClient(
///   url: 'wss://api.example.com/ws',
///   reconnectionStrategy: ExponentialReconnection(),
/// );
///
/// await client.connect();
///
/// client.messages.listen((message) {
///   print('Received: ${message.data}');
/// });
///
/// client.send(WebSocketMessage.text('Hello'));
/// ```
class WebSocketClient {
  /// Creates a new [WebSocketClient].
  WebSocketClient({
    required this.url,
    this.protocols,
    this.headers,
    this.reconnectionStrategy,
    this.heartbeatInterval,
    this.heartbeatMessage,
    this.connectionTimeout = const Duration(seconds: 30),
    this.onConnect,
    this.onDisconnect,
    this.onError,
    this.onReconnecting,
  });

  /// The WebSocket URL to connect to.
  final String url;

  /// Subprotocols to use.
  final Iterable<String>? protocols;

  /// Headers to send with the connection request.
  final Map<String, String>? headers;

  /// Strategy for automatic reconnection.
  final ReconnectionStrategy? reconnectionStrategy;

  /// Interval for sending heartbeat messages.
  final Duration? heartbeatInterval;

  /// The message to send as heartbeat.
  final WebSocketMessage? heartbeatMessage;

  /// Timeout for connection attempts.
  final Duration connectionTimeout;

  /// Called when connection is established.
  final void Function()? onConnect;

  /// Called when connection is closed.
  final void Function(int? code, String? reason)? onDisconnect;

  /// Called when an error occurs.
  final void Function(Object error)? onError;

  /// Called when reconnection is attempted.
  final void Function(int attempt)? onReconnecting;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  bool _isConnecting = false;
  bool _shouldReconnect = true;

  final _messageController = StreamController<WebSocketMessage>.broadcast();
  final _connectionStateController = StreamController<ConnectionState>.broadcast();

  /// Stream of incoming messages.
  Stream<WebSocketMessage> get messages => _messageController.stream;

  /// Stream of connection state changes.
  Stream<ConnectionState> get connectionState => _connectionStateController.stream;

  /// The current connection state.
  ConnectionState _state = ConnectionState.disconnected;
  ConnectionState get state => _state;

  /// Returns true if connected.
  bool get isConnected => _state == ConnectionState.connected;

  /// Connects to the WebSocket server.
  Future<void> connect() async {
    if (_isConnecting || isConnected) return;

    _isConnecting = true;
    _shouldReconnect = true;
    _updateState(ConnectionState.connecting);

    try {
      _channel = IOWebSocketChannel.connect(
        Uri.parse(url),
        protocols: protocols,
        headers: headers,
      );

      // Wait for connection or timeout
      await _channel!.ready.timeout(connectionTimeout);

      _subscription = _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleClose,
      );

      _reconnectAttempt = 0;
      _isConnecting = false;
      _updateState(ConnectionState.connected);
      _startHeartbeat();
      onConnect?.call();
    } catch (e) {
      _isConnecting = false;
      _updateState(ConnectionState.error);
      onError?.call(e);
      _scheduleReconnect();
    }
  }

  /// Disconnects from the WebSocket server.
  Future<void> disconnect({int? code, String? reason}) async {
    _shouldReconnect = false;
    _stopHeartbeat();
    _cancelReconnect();

    await _subscription?.cancel();
    await _channel?.sink.close(code ?? 1000, reason);

    _channel = null;
    _subscription = null;
    _updateState(ConnectionState.disconnected);
    onDisconnect?.call(code, reason);
  }

  /// Sends a message to the server.
  void send(WebSocketMessage message) {
    if (!isConnected) {
      throw StateError('WebSocket is not connected');
    }

    switch (message.type) {
      case MessageType.text:
        _channel!.sink.add(message.data);
        break;
      case MessageType.binary:
        _channel!.sink.add(message.binaryData);
        break;
      case MessageType.json:
        _channel!.sink.add(json.encode(message.data));
        break;
    }
  }

  /// Sends a text message.
  void sendText(String text) {
    send(WebSocketMessage.text(text));
  }

  /// Sends a JSON message.
  void sendJson(Map<String, dynamic> data) {
    send(WebSocketMessage.json(data));
  }

  /// Sends binary data.
  void sendBinary(List<int> data) {
    send(WebSocketMessage.binary(data));
  }

  void _handleMessage(dynamic data) {
    WebSocketMessage message;

    if (data is String) {
      // Try to parse as JSON
      try {
        final jsonData = json.decode(data);
        message = WebSocketMessage.json(jsonData);
      } catch (_) {
        message = WebSocketMessage.text(data);
      }
    } else if (data is List<int>) {
      message = WebSocketMessage.binary(data);
    } else {
      message = WebSocketMessage.text(data.toString());
    }

    _messageController.add(message);
  }

  void _handleError(Object error) {
    _updateState(ConnectionState.error);
    onError?.call(error);
    _scheduleReconnect();
  }

  void _handleClose() {
    _stopHeartbeat();
    _updateState(ConnectionState.disconnected);
    onDisconnect?.call(null, null);
    _scheduleReconnect();
  }

  void _updateState(ConnectionState newState) {
    if (_state != newState) {
      _state = newState;
      _connectionStateController.add(newState);
    }
  }

  void _startHeartbeat() {
    if (heartbeatInterval == null) return;

    _heartbeatTimer = Timer.periodic(heartbeatInterval!, (_) {
      if (isConnected) {
        final message = heartbeatMessage ?? WebSocketMessage.text('ping');
        try {
          send(message);
        } catch (_) {
          // Ignore send errors during heartbeat
        }
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _scheduleReconnect() {
    if (!_shouldReconnect || reconnectionStrategy == null) return;

    _cancelReconnect();
    _updateState(ConnectionState.reconnecting);

    final delay = reconnectionStrategy!.getDelay(_reconnectAttempt);
    if (delay == null) {
      // No more reconnection attempts
      _updateState(ConnectionState.disconnected);
      return;
    }

    _reconnectAttempt++;
    onReconnecting?.call(_reconnectAttempt);

    _reconnectTimer = Timer(delay, () {
      connect();
    });
  }

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  /// Disposes the client and releases resources.
  Future<void> dispose() async {
    await disconnect();
    await _messageController.close();
    await _connectionStateController.close();
  }
}

/// Connection state of the WebSocket client.
enum ConnectionState {
  /// Not connected.
  disconnected,

  /// Attempting to connect.
  connecting,

  /// Connected and ready.
  connected,

  /// Attempting to reconnect after disconnection.
  reconnecting,

  /// An error occurred.
  error,
}

/// Extension methods for WebSocket client.
extension WebSocketClientExtension on WebSocketClient {
  /// Sends a message and waits for a response.
  Future<WebSocketMessage> sendAndWait(
    WebSocketMessage message, {
    Duration timeout = const Duration(seconds: 30),
    bool Function(WebSocketMessage)? matcher,
  }) async {
    final completer = Completer<WebSocketMessage>();

    final subscription = messages.listen((response) {
      if (matcher == null || matcher(response)) {
        completer.complete(response);
      }
    });

    try {
      send(message);
      return await completer.future.timeout(timeout);
    } finally {
      await subscription.cancel();
    }
  }

  /// Filters messages by a predicate.
  Stream<WebSocketMessage> where(bool Function(WebSocketMessage) test) {
    return messages.where(test);
  }

  /// Maps messages to a different type.
  Stream<T> mapMessages<T>(T Function(WebSocketMessage) mapper) {
    return messages.map(mapper);
  }

  /// Filters and maps JSON messages.
  Stream<Map<String, dynamic>> get jsonMessages {
    return messages
        .where((m) => m.type == MessageType.json)
        .map((m) => m.data as Map<String, dynamic>);
  }
}
