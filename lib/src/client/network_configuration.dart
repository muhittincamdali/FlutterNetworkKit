import 'dart:io';

import '../ssl/ssl_configuration.dart';
import '../cache/cache_policy.dart';
import '../retry/retry_policy.dart';

/// Configuration options for the network client.
///
/// This class encapsulates all configuration settings for the [NetworkClient],
/// including timeouts, headers, SSL settings, and more.
///
/// Example:
/// ```dart
/// final config = NetworkConfiguration(
///   baseUrl: 'https://api.example.com',
///   timeout: Duration(seconds: 30),
///   headers: {'Authorization': 'Bearer token'},
/// );
/// ```
class NetworkConfiguration {
  /// Creates a new [NetworkConfiguration].
  const NetworkConfiguration({
    required this.baseUrl,
    this.connectTimeout = const Duration(seconds: 30),
    this.receiveTimeout = const Duration(seconds: 30),
    this.sendTimeout = const Duration(seconds: 30),
    this.defaultHeaders = const {},
    this.validateStatus,
    this.followRedirects = true,
    this.maxRedirects = 5,
    this.sslConfiguration,
    this.cachePolicy,
    this.retryPolicy,
    this.enableLogging = false,
    this.logLevel = LogLevel.basic,
    this.userAgent,
    this.contentType = 'application/json',
    this.acceptType = 'application/json',
    this.acceptEncoding = 'gzip, deflate',
    this.persistentConnection = true,
    this.idleTimeout = const Duration(seconds: 15),
    this.maxConnectionsPerHost,
    this.proxy,
    this.bypassProxy = const [],
  });

  /// The base URL for all requests.
  ///
  /// All relative paths will be appended to this URL.
  final String baseUrl;

  /// The timeout for establishing a connection.
  final Duration connectTimeout;

  /// The timeout for receiving data.
  final Duration receiveTimeout;

  /// The timeout for sending data.
  final Duration sendTimeout;

  /// Default headers to include in all requests.
  ///
  /// These headers can be overridden on a per-request basis.
  final Map<String, String> defaultHeaders;

  /// A function to validate the HTTP status code.
  ///
  /// Returns `true` if the status code is valid, `false` otherwise.
  /// If not provided, status codes 200-299 are considered valid.
  final bool Function(int?)? validateStatus;

  /// Whether to follow redirects automatically.
  final bool followRedirects;

  /// The maximum number of redirects to follow.
  final int maxRedirects;

  /// SSL/TLS configuration including certificate pinning.
  final SSLConfiguration? sslConfiguration;

  /// The default cache policy for GET requests.
  final CachePolicy? cachePolicy;

  /// The default retry policy for failed requests.
  final RetryPolicy? retryPolicy;

  /// Whether to enable request/response logging.
  final bool enableLogging;

  /// The level of detail for logging.
  final LogLevel logLevel;

  /// Custom User-Agent header value.
  final String? userAgent;

  /// The default Content-Type header value.
  final String contentType;

  /// The default Accept header value.
  final String acceptType;

  /// The default Accept-Encoding header value.
  final String acceptEncoding;

  /// Whether to use persistent (keep-alive) connections.
  final bool persistentConnection;

  /// The idle timeout for persistent connections.
  final Duration idleTimeout;

  /// Maximum number of concurrent connections per host.
  final int? maxConnectionsPerHost;

  /// Proxy configuration for all requests.
  final ProxyConfiguration? proxy;

  /// List of hosts that should bypass the proxy.
  final List<String> bypassProxy;

  /// Returns the merged headers with defaults.
  Map<String, String> get mergedHeaders {
    final headers = <String, String>{
      HttpHeaders.contentTypeHeader: contentType,
      HttpHeaders.acceptHeader: acceptType,
      HttpHeaders.acceptEncodingHeader: acceptEncoding,
      ...defaultHeaders,
    };

    if (userAgent != null) {
      headers[HttpHeaders.userAgentHeader] = userAgent!;
    }

    return headers;
  }

  /// Creates a copy of this configuration with the specified overrides.
  NetworkConfiguration copyWith({
    String? baseUrl,
    Duration? connectTimeout,
    Duration? receiveTimeout,
    Duration? sendTimeout,
    Map<String, String>? defaultHeaders,
    bool Function(int?)? validateStatus,
    bool? followRedirects,
    int? maxRedirects,
    SSLConfiguration? sslConfiguration,
    CachePolicy? cachePolicy,
    RetryPolicy? retryPolicy,
    bool? enableLogging,
    LogLevel? logLevel,
    String? userAgent,
    String? contentType,
    String? acceptType,
    String? acceptEncoding,
    bool? persistentConnection,
    Duration? idleTimeout,
    int? maxConnectionsPerHost,
    ProxyConfiguration? proxy,
    List<String>? bypassProxy,
  }) {
    return NetworkConfiguration(
      baseUrl: baseUrl ?? this.baseUrl,
      connectTimeout: connectTimeout ?? this.connectTimeout,
      receiveTimeout: receiveTimeout ?? this.receiveTimeout,
      sendTimeout: sendTimeout ?? this.sendTimeout,
      defaultHeaders: defaultHeaders ?? this.defaultHeaders,
      validateStatus: validateStatus ?? this.validateStatus,
      followRedirects: followRedirects ?? this.followRedirects,
      maxRedirects: maxRedirects ?? this.maxRedirects,
      sslConfiguration: sslConfiguration ?? this.sslConfiguration,
      cachePolicy: cachePolicy ?? this.cachePolicy,
      retryPolicy: retryPolicy ?? this.retryPolicy,
      enableLogging: enableLogging ?? this.enableLogging,
      logLevel: logLevel ?? this.logLevel,
      userAgent: userAgent ?? this.userAgent,
      contentType: contentType ?? this.contentType,
      acceptType: acceptType ?? this.acceptType,
      acceptEncoding: acceptEncoding ?? this.acceptEncoding,
      persistentConnection: persistentConnection ?? this.persistentConnection,
      idleTimeout: idleTimeout ?? this.idleTimeout,
      maxConnectionsPerHost: maxConnectionsPerHost ?? this.maxConnectionsPerHost,
      proxy: proxy ?? this.proxy,
      bypassProxy: bypassProxy ?? this.bypassProxy,
    );
  }

  @override
  String toString() {
    return 'NetworkConfiguration('
        'baseUrl: $baseUrl, '
        'connectTimeout: $connectTimeout, '
        'receiveTimeout: $receiveTimeout, '
        'sendTimeout: $sendTimeout, '
        'enableLogging: $enableLogging'
        ')';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NetworkConfiguration &&
        other.baseUrl == baseUrl &&
        other.connectTimeout == connectTimeout &&
        other.receiveTimeout == receiveTimeout &&
        other.sendTimeout == sendTimeout &&
        other.followRedirects == followRedirects &&
        other.maxRedirects == maxRedirects &&
        other.enableLogging == enableLogging &&
        other.logLevel == logLevel;
  }

  @override
  int get hashCode {
    return Object.hash(
      baseUrl,
      connectTimeout,
      receiveTimeout,
      sendTimeout,
      followRedirects,
      maxRedirects,
      enableLogging,
      logLevel,
    );
  }
}

/// Log level for network requests.
enum LogLevel {
  /// No logging.
  none,

  /// Log only request method and URL.
  basic,

  /// Log request and response headers.
  headers,

  /// Log request and response body.
  body,

  /// Log everything including timing information.
  verbose,
}

/// Proxy configuration for network requests.
class ProxyConfiguration {
  /// Creates a new [ProxyConfiguration].
  const ProxyConfiguration({
    required this.host,
    required this.port,
    this.username,
    this.password,
    this.type = ProxyType.http,
  });

  /// The proxy server host.
  final String host;

  /// The proxy server port.
  final int port;

  /// Optional username for proxy authentication.
  final String? username;

  /// Optional password for proxy authentication.
  final String? password;

  /// The type of proxy.
  final ProxyType type;

  /// Returns the proxy URL string.
  String get url {
    final auth = username != null && password != null
        ? '$username:$password@'
        : '';
    return '${type.name}://$auth$host:$port';
  }

  /// Whether this proxy requires authentication.
  bool get requiresAuth => username != null && password != null;

  @override
  String toString() => 'ProxyConfiguration(host: $host, port: $port, type: $type)';
}

/// The type of proxy server.
enum ProxyType {
  /// HTTP proxy.
  http,

  /// HTTPS proxy.
  https,

  /// SOCKS4 proxy.
  socks4,

  /// SOCKS5 proxy.
  socks5,
}
