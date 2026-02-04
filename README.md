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
  <img src="https://img.shields.io/badge/Flutter-3.24-blue.svg" alt="Flutter 3.24"/>
  <img src="https://img.shields.io/badge/Dart-3.5-blue.svg" alt="Dart 3.5"/>
</p>

---

## Why FlutterNetworkKit?

Dio is great but requires lots of setup. Retrofit needs build_runner. **FlutterNetworkKit** provides a complete networking solution with sensible defaults and powerful customization.

```dart
// Define your API
@Api(baseUrl: 'https://api.example.com')
abstract class UserApi {
  @GET('/users/{id}')
  Future<User> getUser(@Path() String id);
  
  @POST('/users')
  Future<User> createUser(@Body() CreateUserRequest request);
}

// Use it
final api = UserApi();
final user = await api.getUser('123');
```

## Features

| Feature | Description |
|---------|-------------|
| 🔄 **Interceptors** | Request/response middleware |
| 💾 **Caching** | Automatic response caching |
| 🔐 **Auth** | Token refresh, OAuth |
| 📊 **Logging** | Request/response logging |
| 🔄 **Retry** | Configurable retry logic |
| 📝 **Code Gen** | Type-safe API generation |
| 🧪 **Mock** | Easy testing support |

## Quick Start

```dart
import 'package:flutter_network_kit/flutter_network_kit.dart';

// Configure
final client = NetworkClient(
  baseUrl: 'https://api.example.com',
  interceptors: [
    AuthInterceptor(tokenProvider: () => getToken()),
    LoggingInterceptor(),
    CacheInterceptor(),
  ],
);

// Make requests
final users = await client.get<List<User>>('/users');
final user = await client.post<User>('/users', body: newUser);
```

## Interceptors

```dart
class AuthInterceptor extends Interceptor {
  @override
  Future<RequestOptions> onRequest(RequestOptions options) async {
    options.headers['Authorization'] = 'Bearer ${await getToken()}';
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

## Response Caching

```dart
final client = NetworkClient(
  cache: CacheConfig(
    maxAge: Duration(minutes: 5),
    maxSize: 50 * 1024 * 1024, // 50MB
  ),
);

// Cached automatically
final data = await client.get('/data', cache: true);
```

## Code Generation

```dart
// Define API interface
@Api(baseUrl: 'https://api.example.com')
abstract class ProductApi {
  @GET('/products')
  Future<List<Product>> getProducts(@Query('category') String? category);
  
  @GET('/products/{id}')
  Future<Product> getProduct(@Path() String id);
  
  @POST('/products')
  Future<Product> createProduct(@Body() CreateProductRequest request);
  
  @PUT('/products/{id}')
  Future<Product> updateProduct(@Path() String id, @Body() Product product);
  
  @DELETE('/products/{id}')
  Future<void> deleteProduct(@Path() String id);
}

// Run build_runner
// flutter pub run build_runner build
```

## Error Handling

```dart
try {
  final user = await api.getUser('123');
} on NetworkException catch (e) {
  switch (e.type) {
    case NetworkExceptionType.unauthorized:
      // Handle 401
      break;
    case NetworkExceptionType.notFound:
      // Handle 404
      break;
    case NetworkExceptionType.noConnection:
      // Offline
      break;
  }
}
```

## Testing

```dart
final mockClient = MockNetworkClient();
mockClient.when('/users').thenReturn([User(id: '1', name: 'Test')]);

// Inject mockClient in tests
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT License
