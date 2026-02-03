import 'dart:async';

import '../request/request.dart';
import '../response/response.dart';
import '../response/api_error.dart';
import '../cache/cache_manager.dart';
import '../cache/cache_policy.dart';
import '../client/base_client.dart';
import 'interceptor.dart';

/// Interceptor that caches responses for GET requests.
///
/// This interceptor checks the cache before making a request and
/// stores responses in the cache after successful requests.
///
/// Example:
/// ```dart
/// final cacheInterceptor = CacheInterceptor(
///   cacheManager: MemoryCacheManager(),
///   policy: CachePolicy(
///     maxAge: Duration(minutes: 5),
///     staleWhileRevalidate: Duration(minutes: 1),
///   ),
/// );
/// ```
class CacheInterceptor extends NetworkInterceptor {
  /// Creates a new [CacheInterceptor].
  CacheInterceptor({
    required this.cacheManager,
    CachePolicy? defaultPolicy,
    this.onCacheHit,
    this.onCacheMiss,
    this.onCacheStore,
    this.forceFresh = false,
    this.cacheableStatusCodes = const [200, 203, 204, 206, 300, 301, 404, 405, 410, 414, 501],
    this.cacheableMethods = const [HttpMethod.get, HttpMethod.head],
  }) : _defaultPolicy = defaultPolicy ?? CachePolicy.standard();

  /// The cache manager to use for storing responses.
  final CacheManager cacheManager;

  final CachePolicy _defaultPolicy;

  /// Called when a cached response is found.
  final void Function(String key, NetworkResponse<dynamic> response)? onCacheHit;

  /// Called when no cached response is found.
  final void Function(String key)? onCacheMiss;

  /// Called when a response is stored in the cache.
  final void Function(String key, NetworkResponse<dynamic> response)? onCacheStore;

  /// If true, always fetch fresh data and ignore cache.
  final bool forceFresh;

  /// HTTP status codes that are eligible for caching.
  final List<int> cacheableStatusCodes;

  /// HTTP methods that are eligible for caching.
  final List<HttpMethod> cacheableMethods;

  @override
  int get priority => 20;

  @override
  String get name => 'CacheInterceptor';

  @override
  Future<InterceptorResult<NetworkRequest>> onRequest(
    NetworkRequest request,
  ) async {
    // Only cache GET and HEAD requests
    if (!_isCacheable(request)) {
      return InterceptorResult.next(request);
    }

    // Skip cache if force fresh is enabled
    if (forceFresh || _shouldBypassCache(request)) {
      return InterceptorResult.next(request);
    }

    // Generate cache key
    final cacheKey = _generateCacheKey(request);

    // Check cache
    final cachedEntry = await cacheManager.getEntry(cacheKey);

    if (cachedEntry == null) {
      onCacheMiss?.call(cacheKey);
      return InterceptorResult.next(
        request.copyWith(extra: {...?request.extra, '_cacheKey': cacheKey}),
      );
    }

    // Check if cached entry is still fresh
    final policy = _getPolicyForRequest(request);

    if (cachedEntry.isFresh(policy.maxAge)) {
      // Return cached response
      final response = NetworkResponse<dynamic>(
        data: cachedEntry.data,
        statusCode: cachedEntry.statusCode,
        headers: cachedEntry.headers,
        fromCache: true,
      );
      onCacheHit?.call(cacheKey, response);
      return InterceptorResult.resolve(response);
    }

    // Check for stale-while-revalidate
    if (policy.staleWhileRevalidate != null &&
        cachedEntry.isStaleButUsable(policy.maxAge, policy.staleWhileRevalidate!)) {
      // Return stale response and trigger background revalidation
      final response = NetworkResponse<dynamic>(
        data: cachedEntry.data,
        statusCode: cachedEntry.statusCode,
        headers: cachedEntry.headers,
        fromCache: true,
        extra: {'_stale': true},
      );

      // Mark request for background revalidation
      _triggerBackgroundRevalidation(request, cacheKey);

      onCacheHit?.call(cacheKey, response);
      return InterceptorResult.resolve(response);
    }

    // Cache is stale, fetch fresh data
    onCacheMiss?.call(cacheKey);
    return InterceptorResult.next(
      request.copyWith(
        extra: {...?request.extra, '_cacheKey': cacheKey, '_staleData': cachedEntry.data},
      ),
    );
  }

  @override
  Future<ResponseInterceptorResult<NetworkResponse<dynamic>>> onResponse(
    NetworkResponse<dynamic> response,
  ) async {
    // Get cache key from request
    final cacheKey = response.extra?['_cacheKey'] as String?;

    if (cacheKey == null) {
      return ResponseInterceptorResult.next(response);
    }

    // Only cache successful responses
    if (!cacheableStatusCodes.contains(response.statusCode)) {
      return ResponseInterceptorResult.next(response);
    }

    // Check cache control headers
    if (_shouldNotCache(response)) {
      return ResponseInterceptorResult.next(response);
    }

    // Store in cache
    final entry = CacheEntry(
      key: cacheKey,
      data: response.data,
      statusCode: response.statusCode,
      headers: response.headers,
      createdAt: DateTime.now(),
      etag: response.etag,
      lastModified: response.lastModified,
    );

    await cacheManager.setEntry(cacheKey, entry);
    onCacheStore?.call(cacheKey, response);

    return ResponseInterceptorResult.next(response);
  }

  @override
  Future<ErrorInterceptorResult<ApiError>> onError(ApiError error) async {
    // On error, try to return stale cached data if available
    final staleData = error.details?['_staleData'];

    if (staleData != null) {
      // Return stale cached response instead of error
      return ErrorInterceptorResult.resolve(
        NetworkResponse<dynamic>(
          data: staleData,
          statusCode: 200,
          fromCache: true,
          extra: {'_staleOnError': true},
        ),
      );
    }

    return ErrorInterceptorResult.next(error);
  }

  bool _isCacheable(NetworkRequest request) {
    return cacheableMethods.contains(request.method);
  }

  bool _shouldBypassCache(NetworkRequest request) {
    // Check for no-cache header
    final cacheControl = request.headers?['Cache-Control'];
    if (cacheControl != null) {
      if (cacheControl.contains('no-cache') ||
          cacheControl.contains('no-store')) {
        return true;
      }
    }

    // Check for bypass flag in extra
    return request.extra?['_bypassCache'] == true;
  }

  bool _shouldNotCache(NetworkResponse response) {
    final cacheControl = response.cacheControl;
    if (cacheControl != null) {
      if (cacheControl.contains('no-store') ||
          cacheControl.contains('private')) {
        return true;
      }
    }
    return false;
  }

  String _generateCacheKey(NetworkRequest request) {
    final buffer = StringBuffer();
    buffer.write(request.method.value);
    buffer.write(':');
    buffer.write(request.baseUrl ?? '');
    buffer.write(request.path);

    if (request.queryParameters != null && request.queryParameters!.isNotEmpty) {
      final sortedParams = Map.fromEntries(
        request.queryParameters!.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key)),
      );
      buffer.write('?');
      buffer.write(sortedParams.entries
          .map((e) => '${e.key}=${e.value}')
          .join('&'));
    }

    return buffer.toString();
  }

  CachePolicy _getPolicyForRequest(NetworkRequest request) {
    // Check for request-specific policy
    final requestPolicy = request.extra?['_cachePolicy'] as CachePolicy?;
    return requestPolicy ?? _defaultPolicy;
  }

  void _triggerBackgroundRevalidation(NetworkRequest request, String cacheKey) {
    // In a real implementation, this would trigger a background fetch
    // to update the cache without blocking the response
    Future.microtask(() async {
      // This is a placeholder for background revalidation logic
    });
  }

  /// Clears all cached responses.
  Future<void> clearCache() async {
    await cacheManager.clear();
  }

  /// Removes a specific entry from the cache.
  Future<void> invalidate(String key) async {
    await cacheManager.remove(key);
  }

  /// Invalidates cache entries matching a pattern.
  Future<void> invalidatePattern(String pattern) async {
    await cacheManager.removeWhere((key) => key.contains(pattern));
  }
}

/// A cache entry that stores response data with metadata.
class CacheEntry {
  /// Creates a new [CacheEntry].
  const CacheEntry({
    required this.key,
    required this.data,
    required this.statusCode,
    this.headers,
    required this.createdAt,
    this.etag,
    this.lastModified,
  });

  /// The cache key.
  final String key;

  /// The cached response data.
  final dynamic data;

  /// The HTTP status code.
  final int statusCode;

  /// The response headers.
  final Map<String, List<String>>? headers;

  /// When this entry was created.
  final DateTime createdAt;

  /// The ETag header value.
  final String? etag;

  /// The Last-Modified header value.
  final String? lastModified;

  /// Returns true if this entry is still fresh.
  bool isFresh(Duration maxAge) {
    return DateTime.now().difference(createdAt) < maxAge;
  }

  /// Returns true if this entry is stale but usable for stale-while-revalidate.
  bool isStaleButUsable(Duration maxAge, Duration staleWindow) {
    final age = DateTime.now().difference(createdAt);
    return age >= maxAge && age < maxAge + staleWindow;
  }

  /// Returns the age of this cache entry.
  Duration get age => DateTime.now().difference(createdAt);

  /// Converts to JSON for persistence.
  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'data': data,
      'statusCode': statusCode,
      'headers': headers,
      'createdAt': createdAt.toIso8601String(),
      'etag': etag,
      'lastModified': lastModified,
    };
  }

  /// Creates from JSON.
  factory CacheEntry.fromJson(Map<String, dynamic> json) {
    return CacheEntry(
      key: json['key'] as String,
      data: json['data'],
      statusCode: json['statusCode'] as int,
      headers: (json['headers'] as Map<String, dynamic>?)?.map(
        (k, v) => MapEntry(k, (v as List).cast<String>()),
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      etag: json['etag'] as String?,
      lastModified: json['lastModified'] as String?,
    );
  }
}
