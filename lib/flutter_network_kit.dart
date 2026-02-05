/// Flutter Network Kit - Enterprise networking toolkit for Flutter
///
/// A comprehensive, production-ready networking layer that provides:
/// - Type-safe HTTP client with interceptor chains
/// - Automatic token refresh and authentication handling
/// - Response caching with configurable policies
/// - Retry mechanisms with exponential backoff
/// - WebSocket support with auto-reconnection
/// - GraphQL client integration
/// - SSL certificate pinning
/// - Network monitoring and metrics
/// - Offline queue with automatic sync
/// - Request batching with dependency support
/// - File upload/download with progress tracking
/// - Server-Sent Events (SSE) support
/// - Network inspector UI for debugging
///
/// Example usage:
/// ```dart
/// final client = NetworkClient(
///   configuration: NetworkConfiguration(
///     baseUrl: 'https://api.example.com',
///     timeout: Duration(seconds: 30),
///   ),
/// );
///
/// final response = await client.get<User>('/users/1');
/// ```
library flutter_network_kit;

// Client exports
export 'src/client/network_client.dart';
export 'src/client/network_configuration.dart';
export 'src/client/base_client.dart';

// Request exports
export 'src/request/request.dart';
export 'src/request/request_builder.dart';
export 'src/request/multipart_request.dart';
export 'src/request/form_data.dart';

// Response exports
export 'src/response/response.dart';
export 'src/response/response_parser.dart';
export 'src/response/api_error.dart';

// Interceptor exports
export 'src/interceptors/interceptor.dart';
export 'src/interceptors/auth_interceptor.dart';
export 'src/interceptors/logging_interceptor.dart';
export 'src/interceptors/retry_interceptor.dart';
export 'src/interceptors/cache_interceptor.dart';
export 'src/interceptors/mock_interceptor.dart';
export 'src/interceptors/inspector_interceptor.dart';

// Cache exports
export 'src/cache/cache_manager.dart';
export 'src/cache/cache_policy.dart';
export 'src/cache/memory_cache.dart';
export 'src/cache/disk_cache.dart';

// Retry exports
export 'src/retry/retry_policy.dart';
export 'src/retry/exponential_backoff.dart';

// SSL exports
export 'src/ssl/certificate_pinning.dart';
export 'src/ssl/ssl_configuration.dart';

// WebSocket exports
export 'src/websocket/websocket_client.dart';
export 'src/websocket/websocket_message.dart';
export 'src/websocket/reconnection_strategy.dart';

// GraphQL exports
export 'src/graphql/graphql_client.dart';
export 'src/graphql/graphql_query.dart';
export 'src/graphql/graphql_mutation.dart';

// Code generation exports
export 'src/codegen/api_generator.dart';
export 'src/codegen/model_generator.dart';

// Monitoring exports
export 'src/monitoring/network_monitor.dart';
export 'src/monitoring/request_metrics.dart';

// Utility exports
export 'src/utils/url_builder.dart';
export 'src/utils/json_utils.dart';

// Offline queue exports
export 'src/offline/offline_queue.dart';

// Batch exports
export 'src/batch/request_batch.dart';

// Upload exports
export 'src/upload/file_uploader.dart';

// Download exports
export 'src/download/file_downloader.dart';

// SSE exports
export 'src/sse/sse_client.dart';

// Inspector exports
export 'src/inspector/network_inspector.dart';
