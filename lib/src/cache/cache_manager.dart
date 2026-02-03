import 'dart:async';
import 'dart:convert';

import '../interceptors/cache_interceptor.dart';
import 'cache_policy.dart';
import 'memory_cache.dart';
import 'disk_cache.dart';

/// Abstract interface for cache management.
///
/// Implementations of this interface provide storage and retrieval
/// of cached responses with optional expiration.
///
/// Example:
/// ```dart
/// final cacheManager = MemoryCacheManager(
///   maxSize: 100,
///   defaultTTL: Duration(minutes: 5),
/// );
///
/// await cacheManager.set('key', data);
/// final cached = await cacheManager.get<MyData>('key');
/// ```
abstract class CacheManager {
  /// Retrieves a cached value by key.
  Future<T?> get<T>(String key);

  /// Retrieves a cache entry with metadata by key.
  Future<CacheEntry?> getEntry(String key);

  /// Stores a value in the cache.
  Future<void> set<T>(String key, T value, {Duration? ttl});

  /// Stores a cache entry with metadata.
  Future<void> setEntry(String key, CacheEntry entry);

  /// Removes a cached value by key.
  Future<void> remove(String key);

  /// Removes all entries matching a predicate.
  Future<void> removeWhere(bool Function(String key) predicate);

  /// Clears all cached values.
  Future<void> clear();

  /// Returns true if the key exists in the cache.
  Future<bool> contains(String key);

  /// Returns the number of cached entries.
  Future<int> get count;

  /// Returns the total size of cached data in bytes (if available).
  Future<int?> get sizeInBytes;

  /// Returns all cache keys.
  Future<List<String>> get keys;

  /// Disposes the cache manager and releases resources.
  Future<void> dispose();
}

/// A cache manager that combines memory and disk caching.
///
/// This implementation uses a two-tier caching strategy where hot data
/// is kept in memory for fast access, while less frequently accessed
/// data is stored on disk.
///
/// Example:
/// ```dart
/// final cacheManager = TieredCacheManager(
///   memoryCache: MemoryCacheManager(maxSize: 50),
///   diskCache: DiskCacheManager(directory: cacheDir),
/// );
/// ```
class TieredCacheManager implements CacheManager {
  /// Creates a new [TieredCacheManager].
  TieredCacheManager({
    required MemoryCacheManager memoryCache,
    required DiskCacheManager diskCache,
    this.promoteToDisk = true,
    this.defaultTTL = const Duration(hours: 1),
  })  : _memoryCache = memoryCache,
        _diskCache = diskCache;

  final MemoryCacheManager _memoryCache;
  final DiskCacheManager _diskCache;

  /// Whether to promote memory cache entries to disk.
  final bool promoteToDisk;

  /// Default TTL for cache entries.
  final Duration defaultTTL;

  @override
  Future<T?> get<T>(String key) async {
    // Check memory cache first
    var value = await _memoryCache.get<T>(key);
    if (value != null) {
      return value;
    }

    // Check disk cache
    value = await _diskCache.get<T>(key);
    if (value != null) {
      // Promote to memory cache
      await _memoryCache.set(key, value);
      return value;
    }

    return null;
  }

  @override
  Future<CacheEntry?> getEntry(String key) async {
    // Check memory cache first
    var entry = await _memoryCache.getEntry(key);
    if (entry != null) {
      return entry;
    }

    // Check disk cache
    entry = await _diskCache.getEntry(key);
    if (entry != null) {
      // Promote to memory cache
      await _memoryCache.setEntry(key, entry);
      return entry;
    }

    return null;
  }

  @override
  Future<void> set<T>(String key, T value, {Duration? ttl}) async {
    // Always store in memory
    await _memoryCache.set(key, value, ttl: ttl);

    // Optionally promote to disk
    if (promoteToDisk) {
      await _diskCache.set(key, value, ttl: ttl);
    }
  }

  @override
  Future<void> setEntry(String key, CacheEntry entry) async {
    await _memoryCache.setEntry(key, entry);

    if (promoteToDisk) {
      await _diskCache.setEntry(key, entry);
    }
  }

  @override
  Future<void> remove(String key) async {
    await Future.wait([
      _memoryCache.remove(key),
      _diskCache.remove(key),
    ]);
  }

  @override
  Future<void> removeWhere(bool Function(String key) predicate) async {
    await Future.wait([
      _memoryCache.removeWhere(predicate),
      _diskCache.removeWhere(predicate),
    ]);
  }

  @override
  Future<void> clear() async {
    await Future.wait([
      _memoryCache.clear(),
      _diskCache.clear(),
    ]);
  }

  @override
  Future<bool> contains(String key) async {
    return await _memoryCache.contains(key) ||
        await _diskCache.contains(key);
  }

  @override
  Future<int> get count async {
    // Return unique count from both caches
    final memoryKeys = await _memoryCache.keys;
    final diskKeys = await _diskCache.keys;
    return {...memoryKeys, ...diskKeys}.length;
  }

  @override
  Future<int?> get sizeInBytes async {
    final memorySize = await _memoryCache.sizeInBytes ?? 0;
    final diskSize = await _diskCache.sizeInBytes ?? 0;
    return memorySize + diskSize;
  }

  @override
  Future<List<String>> get keys async {
    final memoryKeys = await _memoryCache.keys;
    final diskKeys = await _diskCache.keys;
    return {...memoryKeys, ...diskKeys}.toList();
  }

  @override
  Future<void> dispose() async {
    await Future.wait([
      _memoryCache.dispose(),
      _diskCache.dispose(),
    ]);
  }

  /// Returns statistics about the cache.
  Future<CacheStats> getStats() async {
    return CacheStats(
      memoryEntries: await _memoryCache.count,
      diskEntries: await _diskCache.count,
      memorySize: await _memoryCache.sizeInBytes ?? 0,
      diskSize: await _diskCache.sizeInBytes ?? 0,
    );
  }

  /// Evicts stale entries from both caches.
  Future<int> evictStale(CachePolicy policy) async {
    var evicted = 0;
    evicted += await _memoryCache.evictStale(policy.maxAge);
    evicted += await _diskCache.evictStale(policy.maxAge);
    return evicted;
  }
}

/// Statistics about cache usage.
class CacheStats {
  /// Creates new [CacheStats].
  const CacheStats({
    required this.memoryEntries,
    required this.diskEntries,
    required this.memorySize,
    required this.diskSize,
  });

  /// Number of entries in memory cache.
  final int memoryEntries;

  /// Number of entries in disk cache.
  final int diskEntries;

  /// Size of memory cache in bytes.
  final int memorySize;

  /// Size of disk cache in bytes.
  final int diskSize;

  /// Total number of entries.
  int get totalEntries => memoryEntries + diskEntries;

  /// Total size in bytes.
  int get totalSize => memorySize + diskSize;

  @override
  String toString() {
    return 'CacheStats('
        'entries: $totalEntries (memory: $memoryEntries, disk: $diskEntries), '
        'size: ${(totalSize / 1024).toStringAsFixed(2)} KB'
        ')';
  }
}

/// Extension methods for cache management.
extension CacheManagerExtension on CacheManager {
  /// Gets a value or computes it if not cached.
  Future<T> getOrCompute<T>(
    String key,
    Future<T> Function() compute, {
    Duration? ttl,
  }) async {
    final cached = await get<T>(key);
    if (cached != null) {
      return cached;
    }

    final value = await compute();
    await set(key, value, ttl: ttl);
    return value;
  }

  /// Gets multiple values at once.
  Future<Map<String, T?>> getMany<T>(List<String> keys) async {
    final results = <String, T?>{};
    for (final key in keys) {
      results[key] = await get<T>(key);
    }
    return results;
  }

  /// Sets multiple values at once.
  Future<void> setMany<T>(Map<String, T> entries, {Duration? ttl}) async {
    for (final entry in entries.entries) {
      await set(entry.key, entry.value, ttl: ttl);
    }
  }

  /// Removes multiple entries at once.
  Future<void> removeMany(List<String> keys) async {
    for (final key in keys) {
      await remove(key);
    }
  }
}

/// A no-op cache manager that doesn't cache anything.
class NoOpCacheManager implements CacheManager {
  /// Creates a new [NoOpCacheManager].
  const NoOpCacheManager();

  @override
  Future<T?> get<T>(String key) async => null;

  @override
  Future<CacheEntry?> getEntry(String key) async => null;

  @override
  Future<void> set<T>(String key, T value, {Duration? ttl}) async {}

  @override
  Future<void> setEntry(String key, CacheEntry entry) async {}

  @override
  Future<void> remove(String key) async {}

  @override
  Future<void> removeWhere(bool Function(String key) predicate) async {}

  @override
  Future<void> clear() async {}

  @override
  Future<bool> contains(String key) async => false;

  @override
  Future<int> get count async => 0;

  @override
  Future<int?> get sizeInBytes async => 0;

  @override
  Future<List<String>> get keys async => [];

  @override
  Future<void> dispose() async {}
}
