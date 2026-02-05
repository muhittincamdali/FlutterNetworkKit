# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2025-02-05

### Added
- **Offline Queue**: Automatically queue requests when offline and sync when back online
  - Priority-based queue processing
  - Persistent queue storage with Hive
  - Configurable max retries and expiration
  - Event streams for queue changes and results
  
- **Request Batching**: Execute multiple requests efficiently
  - Dependency support between requests
  - Priority-based execution
  - Concurrent request limiting
  - Progress tracking
  - Fluent builder API
  
- **File Uploader**: Enhanced file upload with progress tracking
  - Progress stream with speed and ETA
  - Multi-file upload support
  - Cancellation support
  - State management (pending, uploading, completed, failed)
  
- **File Downloader**: Robust file download with resume support
  - Resume interrupted downloads
  - Checksum validation (MD5, SHA1, SHA256)
  - Progress tracking with speed calculation
  - Pause/resume functionality
  - Batch download support
  
- **Server-Sent Events (SSE)**: Real-time server event streaming
  - Automatic reconnection with exponential backoff
  - Event type filtering
  - Typed subscription handlers
  - Connection state monitoring
  
- **Network Inspector UI**: Visual debugging tool
  - Request/response inspection
  - Filter by method and URL
  - Statistics dashboard
  - Export to JSON
  - Request details view with headers and body

- **Inspector Interceptor**: Connect network inspector to client

### Changed
- Updated library exports to include all new modules
- Improved documentation with comprehensive examples

### Fixed
- Various minor bug fixes and improvements

## [1.0.0] - 2025-02-03

### Added
- Initial release
- NetworkClient with Dio integration
- Interceptor chain support
- AuthInterceptor with automatic token refresh
- LoggingInterceptor with customizable output
- RetryInterceptor with exponential backoff
- CacheInterceptor with memory and disk storage
- MockInterceptor for testing
- Response caching with configurable policies
- SSL certificate pinning
- WebSocket client with auto-reconnection
- GraphQL client integration
- API and model code generation
- Network monitoring and metrics
- Comprehensive request/response types
