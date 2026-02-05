# FlutterNetworkKit

<div align="center">

[![pub package](https://img.shields.io/pub/v/flutter_network_kit.svg)](https://pub.dev/packages/flutter_network_kit)
[![Dart SDK](https://img.shields.io/badge/Dart-3.0+-blue.svg)](https://dart.dev)
[![Flutter](https://img.shields.io/badge/Flutter-3.10+-blue.svg)](https://flutter.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![codecov](https://codecov.io/gh/muhittincamdali/FlutterNetworkKit/branch/main/graph/badge.svg)](https://codecov.io/gh/muhittincamdali/FlutterNetworkKit)

**Enterprise-grade networking toolkit for Flutter applications**

*Everything you need to build robust, scalable network layers*

[Features](#-features) · [Installation](#-installation) · [Quick Start](#-quick-start) · [Documentation](#-documentation) · [Examples](#-examples)

</div>

---

## 🎯 Why FlutterNetworkKit?

| Feature | Dio | http | Retrofit | **FlutterNetworkKit** |
|---------|-----|------|----------|----------------------|
| Type-safe client | ✅ | ❌ | ✅ | ✅ |
| Interceptors | ✅ | ❌ | ✅ | ✅ |
| Auto retry | ❌ | ❌ | ❌ | ✅ |
| Offline queue | ❌ | ❌ | ❌ | ✅ |
| Request batching | ❌ | ❌ | ❌ | ✅ |
| Inspector UI | ❌ | ❌ | ❌ | ✅ |
| GraphQL support | ❌ | ❌ | ❌ | ✅ |
| SSE support | ❌ | ❌ | ❌ | ✅ |
| Code generation | ❌ | ❌ | ✅ | ✅ |
| Certificate pinning | ✅ | ❌ | ❌ | ✅ |

**FlutterNetworkKit** is the most comprehensive networking solution for Flutter, providing everything from basic HTTP requests to advanced features like offline queuing, request batching, and a visual network inspector.

---

## ✨ Features

### Core Features
- 🔌 **Dio-powered HTTP client** with type-safe request/response handling
- 🔗 **Interceptor chain** for request/response transformation
- 🔐 **Authentication interceptor** with automatic token refresh
- 📝 **Logging interceptor** with customizable output
- 🔄 **Retry interceptor** with exponential backoff
- 💾 **Response caching** with memory and disk storage
- 🎭 **Mock interceptor** for testing

### Advanced Features
- 📴 **Offline queue** - Automatically queue requests when offline and sync when back online
- 📦 **Request batching** - Execute multiple requests with dependency management
- 📤 **File upload** - Upload files with progress tracking
- 📥 **File download** - Download files with resume support and checksum validation
- 🔒 **SSL certificate pinning** - Enhanced security for your API calls
- 📡 **WebSocket client** - Real-time communication with auto-reconnection
- 📊 **Server-Sent Events** - Stream server events with typed handlers
- 🔍 **Network inspector UI** - Debug network requests visually

### Developer Experience
- 📱 **GraphQL client** - Execute queries and mutations with type safety
- 🛠️ **Code generation** - Generate API clients and models from specifications
- 📈 **Performance metrics** - Track request timing and success rates
- 🧪 **Testing utilities** - Mock adapters and response factories

---

## 📦 Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_network_kit: ^1.0.0
```

Then run:

```bash
flutter pub get
```

---

## 🚀 Quick Start

### Basic HTTP Client

```dart
import 'package:flutter_network_kit/flutter_network_kit.dart';

// Create client
final client = NetworkClient(
  configuration: NetworkConfiguration(
    baseUrl: 'https://api.example.com',
    timeout: Duration(seconds: 30),
  ),
);

// GET request
final users = await client.get<List<dynamic>>('/users');

// POST request
final newUser = await client.post<Map<String, dynamic>>(
  '/users',
  body: {'name': 'John', 'email': 'john@example.com'},
);

// With type-safe decoder
final user = await client.get<User>(
  '/users/1',
  decoder: (json) => User.fromJson(json),
);
```

### With Interceptors

```dart
final client = NetworkClient(
  configuration: NetworkConfiguration(
    baseUrl: 'https://api.example.com',
  ),
  interceptors: [
    // Logging
    LoggingInterceptor(
      requestBody: true,
      responseBody: true,
    ),
    
    // Authentication
    AuthInterceptor(
      tokenProvider: () async => await storage.getToken(),
      onTokenExpired: () async => await authService.refreshToken(),
    ),
    
    // Retry on failure
    RetryInterceptor(
      maxRetries: 3,
      retryDelay: Duration(seconds: 1),
    ),
    
    // Caching
    CacheInterceptor(
      cacheManager: cacheManager,
      defaultPolicy: CachePolicy.cacheFirst,
    ),
  ],
);
```

---

## 📖 Documentation

### 📴 Offline Queue

Queue requests when offline and automatically execute them when connectivity is restored:

```dart
final queue = OfflineQueue(
  executor: (request) => client.execute(request),
  config: OfflineQueueConfig(
    maxQueueSize: 100,
    processOnReconnect: true,
    persistQueue: true,
  ),
);

await queue.initialize();

// Queue a request (will execute immediately if online, or queue if offline)
final requestId = await queue.enqueue(
  NetworkRequest.post('/orders', body: orderData),
  priority: 1,
  maxRetries: 5,
);

// Listen for results
queue.resultStream.listen((result) {
  switch (result.result) {
    case QueueExecutionSuccess(response: var response):
      print('Order submitted: ${response.data}');
    case QueueExecutionFailure(error: var error):
      print('Order failed: $error');
    case QueueExecutionSkipped(reason: var reason):
      print('Order skipped: $reason');
  }
});
```

### 📦 Request Batching

Execute multiple requests efficiently with dependency support:

```dart
final batch = RequestBatch(
  executor: (request) => client.execute(request),
  config: BatchConfig(
    maxConcurrent: 5,
    stopOnError: false,
  ),
);

// Add requests with dependencies
batch.add(BatchRequest(
  request: NetworkRequest.get('/user'),
  id: 'user',
));

batch.add(BatchRequest(
  request: NetworkRequest.get('/user/orders'),
  id: 'orders',
  dependsOn: ['user'], // Only runs after 'user' succeeds
));

batch.add(BatchRequest(
  request: NetworkRequest.get('/user/preferences'),
  id: 'preferences',
  dependsOn: ['user'],
));

// Execute all
final results = await batch.execute();

// Or use the builder
final results = await BatchBuilder(executor: client.execute)
  .get('/users', id: 'users')
  .get('/posts', id: 'posts')
  .get('/comments', id: 'comments')
  .config(BatchConfig(maxConcurrent: 3))
  .execute();
```

### 📤 File Upload

Upload files with progress tracking:

```dart
final uploader = FileUploader(
  dio: client.dio,
  defaultConfig: UploadConfig(
    timeout: Duration(minutes: 10),
  ),
);

final task = await uploader.upload(
  file: File('photo.jpg'),
  uploadUrl: 'https://api.example.com/upload',
  fieldName: 'image',
  additionalFields: {
    'description': 'Profile photo',
  },
);

// Track progress
task.progressStream.listen((progress) {
  print('Upload: ${progress.formattedProgress} at ${progress.formattedSpeed}');
  print('ETA: ${progress.estimatedTimeRemaining}');
});

// Wait for completion
final response = await task.wait();
print('Upload complete: ${response.data}');
```

### 📥 File Download

Download files with resume support:

```dart
final downloader = FileDownloader(
  dio: client.dio,
  defaultConfig: DownloadConfig(
    enableResume: true,
    validateChecksum: true,
    checksumType: ChecksumType.sha256,
  ),
);

final task = await downloader.download(
  url: 'https://example.com/largefile.zip',
  savePath: '/downloads/largefile.zip',
  config: DownloadConfig(
    expectedChecksum: 'abc123...',
  ),
);

// Track progress
task.progressStream.listen((progress) {
  print('Download: ${progress.formattedProgress}');
  print('Speed: ${progress.formattedSpeed}');
});

// Pause/Resume
downloader.pause(task.id);
await Future.delayed(Duration(seconds: 5));
await downloader.resume(task.id);

// Wait for completion
final file = await task.wait();
print('Downloaded to: ${file.path}');
```

### 📊 Server-Sent Events

Handle real-time server events:

```dart
final sse = SSEClient(
  url: 'https://api.example.com/events',
  config: SSEConfig(
    reconnect: true,
    maxReconnectAttempts: 5,
  ),
);

// Subscribe to events
sse.subscribe()
  .on('message', (event) => print('Message: ${event.data}'))
  .on('notification', (event) => print('Notification: ${event.jsonData}'))
  .on('update', (event) => handleUpdate(event))
  .onDefault((event) => print('Unknown: ${event.event}'))
  .listen();

// Connect
await sse.connect();

// Monitor connection state
sse.stateStream.listen((state) {
  print('SSE state: $state');
});
```

### 🔍 Network Inspector

Debug network requests visually:

```dart
final inspector = NetworkInspector(
  config: InspectorConfig(
    maxRequests: 500,
    recordRequestBodies: true,
    recordResponseBodies: true,
  ),
);

final client = NetworkClient(
  configuration: config,
  interceptors: [
    InspectorInterceptor(inspector),
  ],
);

// Show inspector UI anywhere in your app
FloatingActionButton(
  onPressed: () => NetworkInspectorOverlay.show(context, inspector),
  child: Icon(Icons.bug_report),
)

// Export recorded requests
final json = inspector.exportAsJson();

// Get statistics
final stats = inspector.stats;
print('Success rate: ${stats.successRate}%');
print('Avg duration: ${stats.averageDuration.inMilliseconds}ms');
```

### 📱 GraphQL Client

Execute GraphQL operations:

```dart
final graphql = GraphQLClient(
  endpoint: 'https://api.example.com/graphql',
  dio: client.dio,
);

// Query
final result = await graphql.query(
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
);

print('User: ${result.data['user']}');

// Mutation
final mutation = await graphql.mutate(
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
      'input': {'name': 'John', 'email': 'john@example.com'},
    },
  ),
);
```

### 🔒 SSL Certificate Pinning

Enhanced security for API calls:

```dart
final client = NetworkClient(
  configuration: NetworkConfiguration(
    baseUrl: 'https://api.example.com',
    sslConfig: SSLConfiguration(
      certificates: [
        SSLCertificate.fromAsset('assets/certificates/api.pem'),
        SSLCertificate.fromHash(
          'sha256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
        ),
      ],
      allowSelfSigned: false,
    ),
  ),
);
```

### 📡 WebSocket Client

Real-time bidirectional communication:

```dart
final ws = WebSocketClient(
  url: 'wss://api.example.com/ws',
  reconnectionStrategy: ExponentialBackoff(
    initialDelay: Duration(seconds: 1),
    maxDelay: Duration(seconds: 30),
    maxAttempts: 10,
  ),
);

// Connect
await ws.connect();

// Send messages
ws.send(WebSocketMessage.text('Hello'));
ws.send(WebSocketMessage.json({'type': 'subscribe', 'channel': 'updates'}));

// Receive messages
ws.messages.listen((message) {
  switch (message) {
    case TextMessage(text: var text):
      print('Text: $text');
    case JsonMessage(data: var data):
      print('JSON: $data');
    case BinaryMessage(bytes: var bytes):
      print('Binary: ${bytes.length} bytes');
  }
});

// Monitor connection
ws.stateStream.listen((state) {
  print('WebSocket: $state');
});
```

---

## 🎨 Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      NetworkClient                          │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────────────────────────────────────────────┐   │
│  │                 Interceptor Chain                     │   │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐ │   │
│  │  │  Auth   │→│  Cache  │→│  Retry  │→│   Log   │ │   │
│  │  └─────────┘  └─────────┘  └─────────┘  └─────────┘ │   │
│  └──────────────────────────────────────────────────────┘   │
├─────────────────────────────────────────────────────────────┤
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐   │
│  │ Offline Queue │  │ Request Batch │  │   Inspector   │   │
│  └───────────────┘  └───────────────┘  └───────────────┘   │
├─────────────────────────────────────────────────────────────┤
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐   │
│  │  File Upload  │  │ File Download │  │     Cache     │   │
│  └───────────────┘  └───────────────┘  └───────────────┘   │
├─────────────────────────────────────────────────────────────┤
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐   │
│  │   WebSocket   │  │      SSE      │  │    GraphQL    │   │
│  └───────────────┘  └───────────────┘  └───────────────┘   │
├─────────────────────────────────────────────────────────────┤
│                        Dio Client                           │
└─────────────────────────────────────────────────────────────┘
```

---

## 🧪 Testing

FlutterNetworkKit provides comprehensive testing utilities:

```dart
// Mock interceptor for testing
final mockInterceptor = MockInterceptor()
  ..when('/users').thenReturn({'users': []})
  ..when('/users/1').thenReturn({'id': 1, 'name': 'John'})
  ..when('/error').thenError(statusCode: 500, message: 'Server error');

final client = NetworkClient(
  configuration: config,
  interceptors: [mockInterceptor],
);

// Verify requests
expect(mockInterceptor.requestCount, 3);
expect(mockInterceptor.lastRequest?.path, '/users');
```

---

## 📱 Example App

Check out the [example](example/) directory for a complete sample application demonstrating all features.

```bash
cd example
flutter run
```

---

## 🤝 Contributing

Contributions are welcome! Please read our [Contributing Guide](CONTRIBUTING.md) for details.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

Built with ❤️ using:
- [Dio](https://pub.dev/packages/dio) - HTTP client
- [Hive](https://pub.dev/packages/hive) - Disk cache
- [connectivity_plus](https://pub.dev/packages/connectivity_plus) - Network monitoring

---

<div align="center">

**[⬆ Back to Top](#flutternetworkkit)**

Made with ❤️ by [Muhittin Camdali](https://github.com/muhittincamdali)

</div>
