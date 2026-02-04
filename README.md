<p align="center">
  <img src="assets/logo.png" alt="FlutterNetworkKit" width="200"/>
</p>

<h1 align="center">FlutterNetworkKit</h1>

<p align="center">
  <strong>🌐 Enterprise networking layer for Flutter with interceptors, caching & code generation</strong>
</p>

<p align="center">
  <a href="https://github.com/muhittincamdali/FlutterNetworkKit/actions/workflows/ci.yml">
    <img src="https://github.com/muhittincamdali/FlutterNetworkKit/actions/workflows/ci.yml/badge.svg" alt="CI"/>
  </a>
  <a href="https://pub.dev/packages/flutter_network_kit">
    <img src="https://img.shields.io/badge/pub.dev-flutter__network__kit-blue?style=flat-square&logo=dart" alt="pub.dev"/>
  </a>
  <img src="https://img.shields.io/badge/Flutter-3.24-02569B?style=flat-square&logo=flutter&logoColor=white" alt="Flutter 3.24"/>
  <img src="https://img.shields.io/badge/Dart-3.5-0175C2?style=flat-square&logo=dart&logoColor=white" alt="Dart 3.5"/>
  <img src="https://img.shields.io/badge/Platform-iOS%20%7C%20Android%20%7C%20Web-lightgrey?style=flat-square" alt="Platform"/>
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="License"/>
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#installation">Installation</a> •
  <a href="#quick-start">Quick Start</a> •
  <a href="#documentation">Documentation</a> •
  <a href="#contributing">Contributing</a>
</p>

---

## 📋 Table of Contents

- [Why FlutterNetworkKit?](#why-flutternetworkkit)
- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Documentation](#documentation)
  - [Interceptors](#interceptors)
  - [Response Caching](#response-caching)
  - [Code Generation](#code-generation)
  - [Error Handling](#error-handling)
  - [Testing](#testing)
- [Contributing](#contributing)
- [License](#license)
- [Star History](#-star-history)

---

## Why FlutterNetworkKit?

Dio is great but requires lots of setup. Retrofit needs build_runner. **FlutterNetworkKit** provides a complete networking solution with sensible defaults and powerful customization out of the box.

```dart
// Define your API with type-safe annotations
@Api(baseUrl: 'https://api.example.com')
abstract class UserApi {
  @GET('/users/{id}')
  Future<User> getUser(@Path() String id);
  
  @POST('/users')
  Future<User> createUser(@Body() CreateUserRequest request);
}

// Use it with dependency injection
final api = UserApi();
final user = await api.getUser('123');
```

## Features

| Feature | Description |
|---------|-------------|
| 🔄 **Interceptors** | Request/response middleware pipeline |
| 💾 **Caching** | Automatic response caching with TTL |
| 🔐 **Auth** | Token refresh, OAuth2 support |
| 📊 **Logging** | Request/response logging |
| 🔄 **Retry** | Configurable retry with backoff |
| 📝 **Code Gen** | Type-safe API generation |
| 🧪 **Mock** | Easy testing with mock client |
| ⚡ **Performance** | Connection pooling & compression |

## Requirements

| Requirement | Version |
|-------------|---------|
| Flutter | 3.24+ |
| Dart | 3.5+ |
| iOS | 12.0+ |
| Android | API 21+ |

## Installation

### pub.dev

```yaml
dependencies:
  flutter_network_kit: ^1.0.0

dev_dependencies:
  build_runner: ^2.4.0
  flutter_network_kit_generator: ^1.0.0
```

Then run:

```bash
flutter pub get
```

### Git

```yaml
dependencies:
  flutter_network_kit:
    git:
      url: https://github.com/muhittincamdali/FlutterNetworkKit.git
      ref: main
```

## Quick Start

```dart
import 'package:flutter_network_kit/flutter_network_kit.dart';

// Configure the client
final client = NetworkClient(
  baseUrl: 'https://api.example.com',
  interceptors: [
    AuthInterceptor(tokenProvider: () => getToken()),
    LoggingInterceptor(),
    CacheInterceptor(),
  ],
);

// Make type-safe requests
final users = await client.get<List<User>>('/users');
final user = await client.post<User>('/users', body: newUser);
```

## Documentation

### Interceptors

Create custom interceptors for cross-cutting concerns:

```dart
class AuthInterceptor extends Interceptor {
  final Future<String> Function() tokenProvider;
  
  AuthInterceptor({required this.tokenProvider});
  
  @override
  Future<RequestOptions> onRequest(RequestOptions options) async {
    final token = await tokenProvider();
    options.headers['Authorization'] = 'Bearer $token';
    return options;
  }
  
  @override
  Future<Response> onError(DioException error) async {
    if (error.response?.statusCode == 401) {
      await refreshToken();
      return retry(error.requestOptions);
    }
    throw error;
  }
}
```

### Response Caching

Automatic caching with configurable TTL:

```dart
final client = NetworkClient(
  cache: CacheConfig(
    maxAge: Duration(minutes: 5),
    maxSize: 50 * 1024 * 1024, // 50MB
    storage: HiveCacheStorage(),
  ),
);

// Cached automatically based on HTTP headers
final data = await client.get('/data');

// Force cache
final cachedData = await client.get('/data', options: Options(
  extra: {'cache': true, 'maxAge': Duration(hours: 1)},
));
```

### Code Generation

Define type-safe API interfaces:

```dart
@Api(baseUrl: 'https://api.example.com')
abstract class ProductApi {
  @GET('/products')
  Future<List<Product>> getProducts(@Query('category') String? category);
  
  @GET('/products/{id}')
  Future<Product> getProduct(@Path() String id);
  
  @POST('/products')
  Future<Product> createProduct(@Body() CreateProductRequest request);
  
  @PUT('/products/{id}')
  Future<Product> updateProduct(
    @Path() String id,
    @Body() Product product,
  );
  
  @DELETE('/products/{id}')
  Future<void> deleteProduct(@Path() String id);
  
  @Multipart()
  @POST('/products/{id}/image')
  Future<void> uploadImage(
    @Path() String id,
    @Part() File image,
  );
}

// Generate implementation
// flutter pub run build_runner build
```

### Error Handling

Structured error handling:

```dart
try {
  final user = await api.getUser('123');
} on NetworkException catch (e) {
  switch (e.type) {
    case NetworkExceptionType.unauthorized:
      // Handle 401 - redirect to login
      break;
    case NetworkExceptionType.notFound:
      // Handle 404 - show not found UI
      break;
    case NetworkExceptionType.serverError:
      // Handle 5xx - show error message
      break;
    case NetworkExceptionType.noConnection:
      // Handle offline - show cached data
      break;
    case NetworkExceptionType.timeout:
      // Handle timeout - retry
      break;
  }
}
```

### Testing

Mock client for unit tests:

```dart
void main() {
  late MockNetworkClient mockClient;
  late UserRepository repository;

  setUp(() {
    mockClient = MockNetworkClient();
    repository = UserRepository(client: mockClient);
  });

  test('getUser returns user from API', () async {
    mockClient
      .when('/users/1')
      .thenReturn(User(id: '1', name: 'John'));

    final user = await repository.getUser('1');

    expect(user.name, 'John');
    mockClient.verify('/users/1').called(1);
  });
}
```

## Contributing

Contributions are welcome! Please read our [Contributing Guide](CONTRIBUTING.md) for details.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'feat: add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

FlutterNetworkKit is released under the MIT License. See [LICENSE](LICENSE) for details.

---

## 📈 Star History

<a href="https://star-history.com/#muhittincamdali/FlutterNetworkKit&Date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=muhittincamdali/FlutterNetworkKit&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=muhittincamdali/FlutterNetworkKit&type=Date" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=muhittincamdali/FlutterNetworkKit&type=Date" />
 </picture>
</a>

---

<p align="center">
  Made with ❤️ by <a href="https://github.com/muhittincamdali">Muhittin Camdali</a>
</p>
