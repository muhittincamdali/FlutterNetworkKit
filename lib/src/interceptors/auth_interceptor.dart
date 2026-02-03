import 'dart:async';

import '../request/request.dart';
import '../response/response.dart';
import '../response/api_error.dart';
import 'interceptor.dart';

/// Callback for providing authentication tokens.
typedef TokenProvider = Future<String?> Function();

/// Callback for refreshing expired tokens.
typedef TokenRefresher = Future<String?> Function(String? currentToken);

/// Callback for handling authentication failures.
typedef AuthFailureHandler = Future<void> Function(ApiError error);

/// Interceptor that handles authentication and token refresh.
///
/// This interceptor automatically adds authentication headers to requests
/// and can refresh expired tokens when receiving 401 responses.
///
/// Example:
/// ```dart
/// final authInterceptor = AuthInterceptor(
///   tokenProvider: () async => await storage.getToken(),
///   tokenRefresher: (token) async {
///     final newToken = await authService.refresh(token);
///     await storage.saveToken(newToken);
///     return newToken;
///   },
/// );
/// ```
class AuthInterceptor extends NetworkInterceptor {
  /// Creates a new [AuthInterceptor].
  AuthInterceptor({
    required this.tokenProvider,
    this.tokenRefresher,
    this.authFailureHandler,
    this.headerName = 'Authorization',
    this.tokenPrefix = 'Bearer',
    this.excludePaths = const [],
    this.maxRetries = 1,
  });

  /// Provides the current authentication token.
  final TokenProvider tokenProvider;

  /// Refreshes an expired token.
  final TokenRefresher? tokenRefresher;

  /// Called when authentication fails and cannot be recovered.
  final AuthFailureHandler? authFailureHandler;

  /// The name of the authorization header.
  final String headerName;

  /// The prefix for the token (e.g., 'Bearer').
  final String tokenPrefix;

  /// Paths that should not have authentication headers added.
  final List<String> excludePaths;

  /// Maximum number of refresh retries.
  final int maxRetries;

  bool _isRefreshing = false;
  final _refreshCompleter = <Completer<String?>>[];
  int _retryCount = 0;

  @override
  int get priority => 10;

  @override
  String get name => 'AuthInterceptor';

  @override
  Future<InterceptorResult<NetworkRequest>> onRequest(
    NetworkRequest request,
  ) async {
    // Skip authentication for excluded paths
    if (_shouldExclude(request.path)) {
      return InterceptorResult.next(request);
    }

    // Get the current token
    final token = await tokenProvider();

    if (token == null || token.isEmpty) {
      return InterceptorResult.next(request);
    }

    // Add the authorization header
    final headers = Map<String, String>.from(request.headers ?? {});
    headers[headerName] = '$tokenPrefix $token';

    return InterceptorResult.next(request.copyWith(headers: headers));
  }

  @override
  Future<ErrorInterceptorResult<ApiError>> onError(ApiError error) async {
    // Only handle 401 Unauthorized errors
    if (!error.isUnauthorized) {
      return ErrorInterceptorResult.next(error);
    }

    // Check if we should try to refresh the token
    if (tokenRefresher == null) {
      await authFailureHandler?.call(error);
      return ErrorInterceptorResult.next(error);
    }

    // Check retry limit
    if (_retryCount >= maxRetries) {
      _retryCount = 0;
      await authFailureHandler?.call(error);
      return ErrorInterceptorResult.next(error);
    }

    try {
      // Try to refresh the token
      final newToken = await _refreshToken();

      if (newToken == null) {
        await authFailureHandler?.call(error);
        return ErrorInterceptorResult.next(error);
      }

      _retryCount++;

      // Create a new request with the refreshed token
      // Note: The actual retry should be handled by the client
      // This is a signal that the token was refreshed
      return ErrorInterceptorResult.next(
        ApiError(
          statusCode: error.statusCode,
          message: 'Token refreshed, retry request',
          errorCode: 'TOKEN_REFRESHED',
          details: {'newToken': newToken},
        ),
      );
    } catch (e) {
      await authFailureHandler?.call(error);
      return ErrorInterceptorResult.next(error);
    }
  }

  Future<String?> _refreshToken() async {
    // If already refreshing, wait for the result
    if (_isRefreshing) {
      final completer = Completer<String?>();
      _refreshCompleter.add(completer);
      return completer.future;
    }

    _isRefreshing = true;

    try {
      final currentToken = await tokenProvider();
      final newToken = await tokenRefresher!(currentToken);

      // Complete all waiting requests
      for (final completer in _refreshCompleter) {
        completer.complete(newToken);
      }
      _refreshCompleter.clear();

      return newToken;
    } catch (e) {
      // Complete all waiting requests with error
      for (final completer in _refreshCompleter) {
        completer.completeError(e);
      }
      _refreshCompleter.clear();
      rethrow;
    } finally {
      _isRefreshing = false;
    }
  }

  bool _shouldExclude(String path) {
    for (final excludePath in excludePaths) {
      if (path.contains(excludePath)) {
        return true;
      }
    }
    return false;
  }

  /// Resets the retry count.
  void resetRetryCount() {
    _retryCount = 0;
  }
}

/// Interceptor for Basic authentication.
class BasicAuthInterceptor extends NetworkInterceptor {
  /// Creates a new [BasicAuthInterceptor].
  BasicAuthInterceptor({
    required this.username,
    required this.password,
    this.excludePaths = const [],
  });

  /// The username for Basic auth.
  final String username;

  /// The password for Basic auth.
  final String password;

  /// Paths that should not have authentication headers added.
  final List<String> excludePaths;

  @override
  int get priority => 10;

  @override
  String get name => 'BasicAuthInterceptor';

  @override
  Future<InterceptorResult<NetworkRequest>> onRequest(
    NetworkRequest request,
  ) async {
    // Skip authentication for excluded paths
    for (final excludePath in excludePaths) {
      if (request.path.contains(excludePath)) {
        return InterceptorResult.next(request);
      }
    }

    // Create Basic auth header
    final credentials = '$username:$password';
    final encoded = Uri.encodeFull(credentials);

    final headers = Map<String, String>.from(request.headers ?? {});
    headers['Authorization'] = 'Basic $encoded';

    return InterceptorResult.next(request.copyWith(headers: headers));
  }
}

/// Interceptor for API key authentication.
class ApiKeyInterceptor extends NetworkInterceptor {
  /// Creates a new [ApiKeyInterceptor].
  ApiKeyInterceptor({
    required this.apiKey,
    this.headerName = 'X-API-Key',
    this.queryParamName,
    this.excludePaths = const [],
  });

  /// The API key value.
  final String apiKey;

  /// The header name for the API key.
  final String headerName;

  /// If set, adds the API key as a query parameter instead.
  final String? queryParamName;

  /// Paths that should not have authentication added.
  final List<String> excludePaths;

  @override
  int get priority => 10;

  @override
  String get name => 'ApiKeyInterceptor';

  @override
  Future<InterceptorResult<NetworkRequest>> onRequest(
    NetworkRequest request,
  ) async {
    // Skip authentication for excluded paths
    for (final excludePath in excludePaths) {
      if (request.path.contains(excludePath)) {
        return InterceptorResult.next(request);
      }
    }

    if (queryParamName != null) {
      // Add as query parameter
      final params = Map<String, dynamic>.from(request.queryParameters ?? {});
      params[queryParamName!] = apiKey;
      return InterceptorResult.next(request.copyWith(queryParameters: params));
    } else {
      // Add as header
      final headers = Map<String, String>.from(request.headers ?? {});
      headers[headerName] = apiKey;
      return InterceptorResult.next(request.copyWith(headers: headers));
    }
  }
}
