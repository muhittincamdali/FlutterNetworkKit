# Flutter Network Kit

[![pub package](https://img.shields.io/pub/v/flutter_network_kit.svg)](https://pub.dev/packages/flutter_network_kit)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Flutter](https://img.shields.io/badge/Flutter-3.10+-blue.svg)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.0+-blue.svg)](https://dart.dev)

Enterprise-grade networking toolkit for Flutter applications. A comprehensive, production-ready networking layer with interceptors, caching, retry logic, WebSocket support, GraphQL integration, and more.

## Features

- **🔗 Type-safe HTTP Client** - Strongly typed requests and responses with Dio
- **🔄 Interceptor Chain** - Modular request/response processing pipeline
- **🔐 Authentication** - Bearer token, Basic auth, API key interceptors with auto-refresh
- **💾 Response Caching** - Memory and disk caching with configurable policies
- **🔁 Retry Mechanism** - Exponential backoff, jitter, and custom strategies
- **📡 WebSocket Support** - Auto-reconnection and message handling
- **📊 GraphQL Client** - Queries, mutations, and batch operations
- **🔒 SSL Pinning** - Certificate validation and mutual TLS
- **📈 Monitoring** - Request metrics and performance tracking
- **🛠 Code Generation** - Generate API clients from specifications

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_network_kit: ^1.0.0
```

## Quick Start

### Basic HTTP Client

```dart
import 'package:flutter_network_kit/flutter_network_kit.dart';

// Create client with configuration
final client = NetworkClient(
  configuration: NetworkConfiguration(
    baseUrl: 'https://api.example.com',
    connectTimeout: Duration(seconds: 30),
    defaultHeaders: {
      'X-API-Version': '1.0',
    },
  ),
);

// GET request
final users = await client.get<List<dynamic>>('/users');
print('Users: ${users.data}');

// POST request with body
final newUser = await client.post<Map<String, dynamic>>(
  '/users',
  body: {'name': 'John', 'email': 'john@example.com'},
);

// Type-safe response parsing
final response = await client.get<User>(
  '/users/1',
  decoder: (data) => User.fromJson(data),
);
```

### Using Request Builder

```dart
final response = await client.request()
    .get()
    .path('/users')
    .queryParam('page', 1)
    .queryParam('limit', 10)
    .header('X-Custom', 'value')
    .authorization('token123')
    .timeout(Duration(seconds: 60))
    .execute<List<User>>(
      decoder: (data) => (data as List).map((e) => User.fromJson(e)).toList(),
    );
```

## Interceptors

### Authentication Interceptor

```dart
final authInterceptor = AuthInterceptor(
  tokenProvider: () async => await storage.getToken(),
  tokenRefresher: (currentToken) async {
    final newToken = await authService.refresh(currentToken);
    await storage.saveToken(newToken);
    return newToken;
  },
  authFailureHandler: (error) async {
    // Navigate to login
    navigator.pushReplacementNamed('/login');
  },
  excludePaths: ['/auth/login', '/auth/register'],
);

client.addInterceptor(authInterceptor);
```

### Logging Interceptor

```dart
final loggingInterceptor = LoggingInterceptor(
  level: LogLevel.body,
  logger: (message) => debugPrint(message),
  sensitiveHeaders: ['Authorization', 'Cookie'],
  maskSensitive: true,
  prettyPrint: true,
);

client.addInterceptor(loggingInterceptor);
```

### Retry Interceptor

```dart
final retryInterceptor = RetryInterceptor(
  policy: RetryPolicy(
    maxRetries: 3,
    retryStatusCodes: [500, 502, 503, 504],
    retryOnNetworkError: true,
    retryOnTimeout: true,
  ),
  backoff: ExponentialBackoff(
    initialDelay: Duration(seconds: 1),
    maxDelay: Duration(seconds: 30),
    multiplier: 2.0,
  ),
  onRetry: (attempt, error) {
    print('Retry attempt $attempt after error: ${error.message}');
  },
);

client.addInterceptor(retryInterceptor);
```

### Cache Interceptor

```dart
final cacheManager = TieredCacheManager(
  memoryCache: MemoryCacheManager(maxSize: 100),
  diskCache: DiskCacheManager(
    directory: cacheDir,
    maxSizeBytes: 50 * 1024 * 1024,
  ),
);

final cacheInterceptor = CacheInterceptor(
  cacheManager: cacheManager,
  defaultPolicy: CachePolicy(
    maxAge: Duration(minutes: 5),
    staleWhileRevalidate: Duration(minutes: 1),
  ),
  onCacheHit: (key, response) => print('Cache hit: $key'),
);

client.addInterceptor(cacheInterceptor);
```

### Mock Interceptor (Testing)

```dart
final mockInterceptor = MockInterceptor()
  ..addMock(
    method: HttpMethod.get,
    path: '/users',
    response: MockResponse(
      data: [{'id': 1, 'name': 'John'}],
      statusCode: 200,
      delay: Duration(milliseconds: 100),
    ),
  )
  ..addDynamicMock(
    method: HttpMethod.get,
    path: '/users/*',
    handler: (request) => MockResponse(
      data: {'id': request.path.split('/').last},
    ),
  );
```

## Response Caching

### Cache Policies

```dart
// Standard caching
final standardPolicy = CachePolicy.standard(
  maxAge: Duration(minutes: 5),
);

// Long-lived data
final longLivedPolicy = CachePolicy.longLived();

// No caching
final noCachePolicy = CachePolicy.noCache();

// Custom policy from Cache-Control header
final policy = CachePolicy.fromHeader('max-age=300, stale-while-revalidate=60');
```

### Manual Cache Control

```dart
// Bypass cache for specific request
final fresh = await client.get('/users', useCache: false);

// Clear all cache
await client.clearCache();

// Clear specific entry
await cacheManager.remove('/users');

// Clear matching pattern
await cacheManager.removeWhere((key) => key.contains('/users'));
```

## WebSocket Support

```dart
final wsClient = WebSocketClient(
  url: 'wss://api.example.com/ws',
  reconnectionStrategy: ExponentialReconnection(
    initialDelay: Duration(seconds: 1),
    maxDelay: Duration(seconds: 30),
    maxAttempts: 10,
  ),
  heartbeatInterval: Duration(seconds: 30),
  onConnect: () => print('Connected'),
  onDisconnect: (code, reason) => print('Disconnected: $code'),
);

await wsClient.connect();

// Listen to messages
wsClient.messages.listen((message) {
  if (message.isJson) {
    final data = message.jsonData;
    print('Received: $data');
  }
});

// Send messages
wsClient.sendText('Hello');
wsClient.sendJson({'type': 'subscribe', 'channel': 'updates'});

// Connection state
wsClient.connectionState.listen((state) {
  print('Connection state: $state');
});
```

## GraphQL Client

```dart
final graphql = GraphQLClient(
  networkClient: client,
  endpoint: '/graphql',
);

// Query
final result = await graphql.query<User>(
  GraphQLQuery(
    query: '''
      query GetUser(\$id: ID!) {
        user(id: \$id) {
          id
          name
          email
        }
      }
    ''',
    variables: {'id': '123'},
  ),
  decoder: (data) => User.fromJson(data['user']),
);

if (result.isSuccess) {
  print('User: ${result.data}');
}

// Mutation
final createResult = await graphql.mutate<User>(
  GraphQLMutation(
    mutation: '''
      mutation CreateUser(\$input: CreateUserInput!) {
        createUser(input: \$input) {
          id
          name
        }
      }
    ''',
    variables: {
      'input': {'name': 'Jane', 'email': 'jane@example.com'},
    },
  ),
  decoder: (data) => User.fromJson(data['createUser']),
);
```

## SSL Certificate Pinning

```dart
final sslConfig = SSLConfiguration(
  certificatePinning: CertificatePinning(
    pins: [
      CertificatePin(
        host: 'api.example.com',
        sha256Hashes: [
          'sha256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
          'sha256/BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=',
        ],
      ),
    ],
    includeSubdomains: true,
  ),
  verifyHostname: true,
);

final secureClient = NetworkClient(
  configuration: NetworkConfiguration(
    baseUrl: 'https://api.example.com',
    sslConfiguration: sslConfig,
  ),
);
```

## Network Monitoring

```dart
final monitor = NetworkMonitor(
  historyLimit: 100,
  slowRequestThreshold: Duration(seconds: 3),
  onSlowRequest: (metrics) {
    analytics.track('slow_request', {
      'path': metrics.path,
      'duration': metrics.duration?.inMilliseconds,
    });
  },
  onError: (metrics) {
    crashlytics.recordError(
      'Network error: ${metrics.error}',
      {'path': metrics.path, 'status': metrics.statusCode},
    );
  },
);

final client = NetworkClient(
  configuration: config,
  monitor: monitor,
);

// Get statistics
print('Average response time: ${monitor.averageResponseTime}');
print('Success rate: ${(monitor.successRate * 100).toStringAsFixed(1)}%');
print('Error rate: ${(monitor.errorRate * 100).toStringAsFixed(1)}%');

// Generate report
print(monitor.generateReport());
```

## File Upload

```dart
final request = MultipartRequest()
  ..addFile('avatar', File('path/to/image.jpg'))
  ..addField('username', 'john_doe')
  ..addField('bio', 'Hello world');

final response = await client.upload<UploadResult>(
  '/profile/avatar',
  request,
  onProgress: (progress) {
    print('Upload progress: ${(progress * 100).toStringAsFixed(0)}%');
  },
);
```

## File Download

```dart
final filePath = await client.download(
  '/files/document.pdf',
  '/path/to/save/document.pdf',
  onProgress: (progress) {
    print('Download progress: ${(progress * 100).toStringAsFixed(0)}%');
  },
);
```

## Error Handling

```dart
try {
  final response = await client.get('/users');
} on ApiError catch (e) {
  if (e.isUnauthorized) {
    // Handle auth error
  } else if (e.isNetworkError) {
    // Handle connectivity issue
  } else if (e.hasValidationErrors) {
    // Handle validation errors
    for (final field in e.validationErrors!.keys) {
      print('$field: ${e.getValidationError(field)}');
    }
  } else {
    // Handle other errors
    print('Error ${e.statusCode}: ${e.userMessage}');
  }
}
```

## URL Building

```dart
final url = UrlBuilder('https://api.example.com')
    .path('/users')
    .pathParam('id', userId)
    .query('include', 'profile')
    .queryAll('fields', ['name', 'email', 'avatar'])
    .queryIfNotNull('filter', filterValue)
    .build();
```

## JSON Utilities

```dart
// Deep path access
final name = JsonUtils.getPath<String>(json, 'user.profile.name');

// Merge objects
final merged = JsonUtils.merge(defaults, overrides);

// Flatten nested structure
final flat = JsonUtils.flatten(nestedJson);

// Transform keys
final camelCase = JsonUtils.keysToCamelCase(snakeCaseJson);

// Remove nulls
final cleaned = JsonUtils.removeNulls(jsonWithNulls);
```

## Testing

The library includes a mock interceptor for testing:

```dart
void main() {
  late NetworkClient client;
  late MockInterceptor mockInterceptor;

  setUp(() {
    mockInterceptor = MockInterceptor(passthrough: false);
    client = NetworkClient(
      configuration: NetworkConfiguration(baseUrl: 'https://test.com'),
      interceptors: [mockInterceptor],
    );
  });

  test('fetches users', () async {
    mockInterceptor.addMock(
      method: HttpMethod.get,
      path: '/users',
      response: MockResponse(data: [{'id': 1, 'name': 'Test'}]),
    );

    final response = await client.get('/users');
    expect(response.data, isNotEmpty);
  });
}
```

## Requirements

- Flutter 3.10+
- Dart 3.0+

## Dependencies

- `dio` - HTTP client
- `http` - Additional HTTP utilities
- `connectivity_plus` - Network connectivity
- `hive` - Disk caching
- `web_socket_channel` - WebSocket support
- `crypto` - SSL hashing

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome! Please read our [Contributing Guide](CONTRIBUTING.md) for details.

## Author

**Muhittin Camdali**
- GitHub: [@muhittincamdali](https://github.com/muhittincamdali)

---

Made with ❤️ for the Flutter community
