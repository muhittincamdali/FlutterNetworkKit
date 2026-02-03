import 'dart:convert';
import 'dart:typed_data';

/// Type of WebSocket message.
enum MessageType {
  /// Plain text message.
  text,

  /// Binary data message.
  binary,

  /// JSON-encoded message.
  json,
}

/// Represents a WebSocket message.
///
/// Messages can be text, binary, or JSON-encoded.
///
/// Example:
/// ```dart
/// // Text message
/// final textMsg = WebSocketMessage.text('Hello');
///
/// // JSON message
/// final jsonMsg = WebSocketMessage.json({'type': 'chat', 'text': 'Hi'});
///
/// // Binary message
/// final binaryMsg = WebSocketMessage.binary([0x00, 0x01, 0x02]);
/// ```
class WebSocketMessage {
  /// Creates a new [WebSocketMessage].
  const WebSocketMessage._({
    required this.type,
    required this.data,
    this.binaryData,
    this.timestamp,
    this.metadata,
  });

  /// Creates a text message.
  factory WebSocketMessage.text(String text) {
    return WebSocketMessage._(
      type: MessageType.text,
      data: text,
      timestamp: DateTime.now(),
    );
  }

  /// Creates a binary message.
  factory WebSocketMessage.binary(List<int> data) {
    return WebSocketMessage._(
      type: MessageType.binary,
      data: null,
      binaryData: Uint8List.fromList(data),
      timestamp: DateTime.now(),
    );
  }

  /// Creates a JSON message.
  factory WebSocketMessage.json(dynamic data) {
    return WebSocketMessage._(
      type: MessageType.json,
      data: data,
      timestamp: DateTime.now(),
    );
  }

  /// Creates a message from raw data.
  factory WebSocketMessage.fromRaw(dynamic rawData) {
    if (rawData is String) {
      try {
        final jsonData = json.decode(rawData);
        return WebSocketMessage.json(jsonData);
      } catch (_) {
        return WebSocketMessage.text(rawData);
      }
    } else if (rawData is List<int>) {
      return WebSocketMessage.binary(rawData);
    }
    return WebSocketMessage.text(rawData.toString());
  }

  /// The type of this message.
  final MessageType type;

  /// The message data.
  final dynamic data;

  /// Binary data for binary messages.
  final Uint8List? binaryData;

  /// When this message was created.
  final DateTime? timestamp;

  /// Additional metadata associated with this message.
  final Map<String, dynamic>? metadata;

  /// Returns true if this is a text message.
  bool get isText => type == MessageType.text;

  /// Returns true if this is a binary message.
  bool get isBinary => type == MessageType.binary;

  /// Returns true if this is a JSON message.
  bool get isJson => type == MessageType.json;

  /// Returns the text content of this message.
  String? get text {
    if (type == MessageType.text) return data as String;
    if (type == MessageType.json) return json.encode(data);
    return null;
  }

  /// Returns the JSON content of this message.
  Map<String, dynamic>? get jsonData {
    if (type == MessageType.json && data is Map<String, dynamic>) {
      return data as Map<String, dynamic>;
    }
    if (type == MessageType.text) {
      try {
        return json.decode(data as String) as Map<String, dynamic>;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Returns a value from the JSON data.
  T? getValue<T>(String key) {
    final jsonMap = jsonData;
    if (jsonMap == null) return null;
    return jsonMap[key] as T?;
  }

  /// Returns the message size in bytes.
  int get size {
    if (type == MessageType.binary) {
      return binaryData?.length ?? 0;
    }
    final textData = text;
    return textData?.length ?? 0;
  }

  /// Creates a copy with metadata added.
  WebSocketMessage withMetadata(Map<String, dynamic> metadata) {
    return WebSocketMessage._(
      type: type,
      data: data,
      binaryData: binaryData,
      timestamp: timestamp,
      metadata: {...?this.metadata, ...metadata},
    );
  }

  @override
  String toString() {
    switch (type) {
      case MessageType.text:
        return 'WebSocketMessage.text("${_truncate(data as String, 50)}")';
      case MessageType.binary:
        return 'WebSocketMessage.binary(${binaryData?.length} bytes)';
      case MessageType.json:
        return 'WebSocketMessage.json(${_truncate(json.encode(data), 50)})';
    }
  }

  String _truncate(String s, int maxLength) {
    if (s.length <= maxLength) return s;
    return '${s.substring(0, maxLength)}...';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WebSocketMessage &&
        other.type == type &&
        other.data == data;
  }

  @override
  int get hashCode => Object.hash(type, data);
}

/// Builder for creating WebSocket messages.
class WebSocketMessageBuilder {
  MessageType _type = MessageType.text;
  dynamic _data;
  Map<String, dynamic>? _metadata;

  /// Sets the message type to text.
  WebSocketMessageBuilder text(String text) {
    _type = MessageType.text;
    _data = text;
    return this;
  }

  /// Sets the message type to binary.
  WebSocketMessageBuilder binary(List<int> data) {
    _type = MessageType.binary;
    _data = data;
    return this;
  }

  /// Sets the message type to JSON.
  WebSocketMessageBuilder json(Map<String, dynamic> data) {
    _type = MessageType.json;
    _data = data;
    return this;
  }

  /// Adds metadata to the message.
  WebSocketMessageBuilder meta(String key, dynamic value) {
    _metadata ??= {};
    _metadata![key] = value;
    return this;
  }

  /// Builds the message.
  WebSocketMessage build() {
    switch (_type) {
      case MessageType.text:
        final msg = WebSocketMessage.text(_data as String);
        return _metadata != null ? msg.withMetadata(_metadata!) : msg;
      case MessageType.binary:
        final msg = WebSocketMessage.binary(_data as List<int>);
        return _metadata != null ? msg.withMetadata(_metadata!) : msg;
      case MessageType.json:
        final msg = WebSocketMessage.json(_data);
        return _metadata != null ? msg.withMetadata(_metadata!) : msg;
    }
  }
}

/// Common WebSocket message types for chat-like protocols.
class WebSocketMessageTypes {
  WebSocketMessageTypes._();

  /// Creates a ping message.
  static WebSocketMessage ping() {
    return WebSocketMessage.json({'type': 'ping'});
  }

  /// Creates a pong message.
  static WebSocketMessage pong() {
    return WebSocketMessage.json({'type': 'pong'});
  }

  /// Creates a subscribe message.
  static WebSocketMessage subscribe(String channel) {
    return WebSocketMessage.json({
      'type': 'subscribe',
      'channel': channel,
    });
  }

  /// Creates an unsubscribe message.
  static WebSocketMessage unsubscribe(String channel) {
    return WebSocketMessage.json({
      'type': 'unsubscribe',
      'channel': channel,
    });
  }

  /// Creates an authenticate message.
  static WebSocketMessage authenticate(String token) {
    return WebSocketMessage.json({
      'type': 'auth',
      'token': token,
    });
  }
}
