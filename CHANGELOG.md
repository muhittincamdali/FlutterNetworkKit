# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-01-15

### Added

- **NetworkClient** - Full-featured Dio wrapper with interceptor chain management
- **AuthInterceptor** - Automatic token refresh with configurable refresh logic
- **CacheInterceptor** - In-memory and persistent response caching with TTL support
- **LoggingInterceptor** - Structured request/response logging with filtering
- **RetryInterceptor** - Exponential backoff retry with configurable attempts and delays
- **ConnectivityInterceptor** - Offline request queue with automatic replay on reconnect
- **GraphQLClient** - Full GraphQL query, mutation, and subscription support
- **WebSocketClient** - WebSocket connections with automatic reconnection and heartbeat
- **SSEClient** - Server-Sent Events streaming with typed event parsing
- **MockClient** - Request/response mocking for unit and integration tests
- **ResponseCache** - LRU cache with size limits and expiration policies
- **UploadManager** - Multipart file uploads with progress tracking and cancellation
- **DownloadManager** - File downloads with resume capability and progress callbacks
- **ApiResponse** - Freezed model for type-safe API response handling
- **Pagination** - Cursor and offset-based pagination helpers
- **ApiGenerator** - Code generation helpers for REST endpoint boilerplate
- **NetworkConfig** - Centralized configuration with environment support
- **NetworkError** - Typed error hierarchy with DioException mapping

### Performance

- Connection pooling enabled by default
- Response compression with gzip/deflate support
- Efficient memory management for large file transfers
- Background isolate support for heavy JSON parsing

## [0.9.0] - 2025-12-20

### Added

- Initial beta release with core networking features
- Basic interceptor chain support
- WebSocket client with manual reconnect

### Changed

- Migrated from http package to Dio for better interceptor support

### Fixed

- Memory leak in WebSocket reconnection loop
- Cache invalidation not respecting TTL headers

## [0.8.0] - 2025-11-10

### Added

- Alpha release for internal testing
- NetworkClient with basic GET/POST/PUT/DELETE
- Simple retry logic without exponential backoff
- Basic logging interceptor

### Known Issues

- Token refresh not thread-safe (fixed in 0.9.0)
- Cache does not persist across app restarts (fixed in 1.0.0)
