/// Configuration for cache behavior.
///
/// This class defines how long responses should be cached and
/// under what conditions stale data can be served.
///
/// Example:
/// ```dart
/// final policy = CachePolicy(
///   maxAge: Duration(minutes: 5),
///   staleWhileRevalidate: Duration(minutes: 1),
///   staleIfError: Duration(hours: 1),
/// );
/// ```
class CachePolicy {
  /// Creates a new [CachePolicy].
  const CachePolicy({
    required this.maxAge,
    this.staleWhileRevalidate,
    this.staleIfError,
    this.mustRevalidate = false,
    this.noCache = false,
    this.noStore = false,
    this.private = false,
    this.maxStale,
    this.minFresh,
  });

  /// Creates a standard cache policy with sensible defaults.
  factory CachePolicy.standard({
    Duration maxAge = const Duration(minutes: 5),
  }) {
    return CachePolicy(
      maxAge: maxAge,
      staleWhileRevalidate: const Duration(minutes: 1),
      staleIfError: const Duration(hours: 1),
    );
  }

  /// Creates a policy for short-lived data.
  factory CachePolicy.shortLived() {
    return const CachePolicy(
      maxAge: Duration(minutes: 1),
      staleWhileRevalidate: Duration(seconds: 30),
    );
  }

  /// Creates a policy for long-lived, rarely changing data.
  factory CachePolicy.longLived() {
    return const CachePolicy(
      maxAge: Duration(days: 1),
      staleWhileRevalidate: Duration(hours: 1),
      staleIfError: Duration(days: 7),
    );
  }

  /// Creates a policy that doesn't cache anything.
  factory CachePolicy.noCache() {
    return const CachePolicy(
      maxAge: Duration.zero,
      noCache: true,
    );
  }

  /// Creates a policy from HTTP Cache-Control header.
  factory CachePolicy.fromHeader(String cacheControl) {
    final directives = _parseCacheControl(cacheControl);

    Duration? maxAge;
    Duration? staleWhileRevalidate;
    Duration? maxStale;
    Duration? minFresh;
    var mustRevalidate = false;
    var noCache = false;
    var noStore = false;
    var private = false;

    for (final directive in directives) {
      final parts = directive.split('=');
      final name = parts[0].trim().toLowerCase();
      final value = parts.length > 1 ? parts[1].trim() : null;

      switch (name) {
        case 'max-age':
          if (value != null) {
            maxAge = Duration(seconds: int.parse(value));
          }
          break;
        case 'stale-while-revalidate':
          if (value != null) {
            staleWhileRevalidate = Duration(seconds: int.parse(value));
          }
          break;
        case 'max-stale':
          if (value != null) {
            maxStale = Duration(seconds: int.parse(value));
          }
          break;
        case 'min-fresh':
          if (value != null) {
            minFresh = Duration(seconds: int.parse(value));
          }
          break;
        case 'must-revalidate':
          mustRevalidate = true;
          break;
        case 'no-cache':
          noCache = true;
          break;
        case 'no-store':
          noStore = true;
          break;
        case 'private':
          private = true;
          break;
      }
    }

    return CachePolicy(
      maxAge: maxAge ?? Duration.zero,
      staleWhileRevalidate: staleWhileRevalidate,
      maxStale: maxStale,
      minFresh: minFresh,
      mustRevalidate: mustRevalidate,
      noCache: noCache,
      noStore: noStore,
      private: private,
    );
  }

  /// How long a response is considered fresh.
  final Duration maxAge;

  /// Window during which stale responses can be served
  /// while revalidating in the background.
  final Duration? staleWhileRevalidate;

  /// Window during which stale responses can be served
  /// if the origin server is unavailable.
  final Duration? staleIfError;

  /// If true, the cache must revalidate with the origin server
  /// after the response becomes stale.
  final bool mustRevalidate;

  /// If true, forces revalidation before using cached response.
  final bool noCache;

  /// If true, prevents any caching.
  final bool noStore;

  /// If true, the response is only cacheable by browser caches,
  /// not shared caches.
  final bool private;

  /// Maximum staleness the client is willing to accept.
  final Duration? maxStale;

  /// Minimum freshness required by the client.
  final Duration? minFresh;

  /// Returns true if caching is allowed.
  bool get canCache => !noStore;

  /// Returns true if the response can be served from cache.
  bool canServeFromCache(Duration age) {
    if (noCache || noStore) return false;
    if (age < maxAge) return true;
    if (staleWhileRevalidate != null && age < maxAge + staleWhileRevalidate!) {
      return true;
    }
    if (maxStale != null && age < maxAge + maxStale!) {
      return true;
    }
    return false;
  }

  /// Returns true if background revalidation should be triggered.
  bool shouldRevalidate(Duration age) {
    if (noCache) return true;
    if (mustRevalidate && age >= maxAge) return true;
    if (staleWhileRevalidate != null &&
        age >= maxAge &&
        age < maxAge + staleWhileRevalidate!) {
      return true;
    }
    return false;
  }

  /// Converts to Cache-Control header value.
  String toHeader() {
    final parts = <String>[];

    parts.add('max-age=${maxAge.inSeconds}');

    if (staleWhileRevalidate != null) {
      parts.add('stale-while-revalidate=${staleWhileRevalidate!.inSeconds}');
    }
    if (mustRevalidate) {
      parts.add('must-revalidate');
    }
    if (noCache) {
      parts.add('no-cache');
    }
    if (noStore) {
      parts.add('no-store');
    }
    if (private) {
      parts.add('private');
    }

    return parts.join(', ');
  }

  /// Creates a copy with the specified overrides.
  CachePolicy copyWith({
    Duration? maxAge,
    Duration? staleWhileRevalidate,
    Duration? staleIfError,
    bool? mustRevalidate,
    bool? noCache,
    bool? noStore,
    bool? private,
    Duration? maxStale,
    Duration? minFresh,
  }) {
    return CachePolicy(
      maxAge: maxAge ?? this.maxAge,
      staleWhileRevalidate: staleWhileRevalidate ?? this.staleWhileRevalidate,
      staleIfError: staleIfError ?? this.staleIfError,
      mustRevalidate: mustRevalidate ?? this.mustRevalidate,
      noCache: noCache ?? this.noCache,
      noStore: noStore ?? this.noStore,
      private: private ?? this.private,
      maxStale: maxStale ?? this.maxStale,
      minFresh: minFresh ?? this.minFresh,
    );
  }

  @override
  String toString() => 'CachePolicy(${toHeader()})';

  static List<String> _parseCacheControl(String header) {
    return header.split(',').map((e) => e.trim()).toList();
  }
}

/// Extension methods for working with cache policies.
extension CachePolicyExtension on CachePolicy {
  /// Calculates the remaining freshness time.
  Duration remainingFreshness(DateTime createdAt) {
    final age = DateTime.now().difference(createdAt);
    if (age >= maxAge) return Duration.zero;
    return maxAge - age;
  }

  /// Returns true if the entry is stale.
  bool isStale(DateTime createdAt) {
    return DateTime.now().difference(createdAt) >= maxAge;
  }

  /// Returns true if the entry is usable (fresh or within stale window).
  bool isUsable(DateTime createdAt) {
    return canServeFromCache(DateTime.now().difference(createdAt));
  }
}
