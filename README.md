<div align="center">

# 🌐 FlutterNetworkKit

**Enterprise networking layer for Flutter with interceptors, caching & code generation**

[![Dart](https://img.shields.io/badge/Dart-3.0+-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
[![Flutter](https://img.shields.io/badge/Flutter-3.16+-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![pub.dev](https://img.shields.io/badge/pub.dev-Package-blue?style=for-the-badge)](https://pub.dev)
[![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)](LICENSE)

</div>

---

## ✨ Features

- 🚀 **Type-Safe** — Generated API clients
- 🔄 **Interceptors** — Auth, logging, retry
- 💾 **Caching** — Automatic response cache
- 📊 **Offline** — Request queue for offline
- 🔧 **Code Gen** — From OpenAPI spec

---

## 🚀 Quick Start

```dart
import 'package:flutter_network_kit/flutter_network_kit.dart';

final client = NetworkClient(
  baseUrl: 'https://api.example.com',
  interceptors: [
    AuthInterceptor(token: () => getToken()),
    LoggingInterceptor(),
    RetryInterceptor(maxRetries: 3),
  ],
);

// GET
final users = await client.get<List<User>>('/users');

// POST
final newUser = await client.post<User>('/users', body: userData);
```

---

## 📄 License

MIT • [@muhittincamdali](https://github.com/muhittincamdali)
