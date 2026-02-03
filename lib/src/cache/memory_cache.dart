import 'dart:async';
import 'dart:convert';

import '../interceptors/cache_interceptor.dart';
import 'cache_manager.dart';

/// An in-memory cache manager with LRU eviction.
///
/// This implementation stores cached data in memory for fast access.
/// It uses an LRU (Least Recently Used) eviction policy when the
/// maximum size is reached.
///
/// Example:
/// ```dart
/// final cache = MemoryCacheManager(
///   maxSize: 100,
///   defaultTTL: Duration(minutes: 5),
/// );
///
/// await cache.set('key', data);
/// final cached = await cache.get<MyData>('key');
/// ```
class MemoryCacheManager implements CacheManager {
  /// Creates a new [MemoryCacheManager].
  MemoryCacheManager({
    this.maxSize = 100,
    this.maxSizeBytes,
    this.defaultTTL,
    this.onEvict,
  });

  /// Maximum number of entries in the cache.
  final int maxSize;

  /// Maximum size of the cache in bytes.
  final int? maxSizeBytes;

  /// Default TTL for cache entries.
  final Duration? defaultTTL;

  /// Called when an entry is evicted from the cache.
  final void Function(String key, CacheEntry entry)? onEvict;

  final Map<String, _MemoryCacheEntry> _cache = {};
  final List<String> _accessOrder = [];
  int _currentSizeBytes = 0;

  @override
  Future<T?> get<T>(String key) async {
    final entry = _cache[key];
    if (entry == null) return null;

    // Check if expired
    if (entry.isExpired) {
      await remove(key);
      return null;
    }

    // Update access order for LRU
    _updateAccessOrder(key);

    return entry.entry.data as T?;
  }

  @override
  Future<CacheEntry?> getEntry(String key) async {
    final entry = _cache[key];
    if (entry == null) return null;

    // Check if expired
    if (entry.isExpired) {
      await remove(key);
      return null;
    }

    // Update access order for LRU
    _updateAccessOrder(key);

    return entry.entry;
  }

  @override
  Future<void> set<T>(String key, T value, {Duration? ttl}) async {
    final effectiveTTL = ttl ?? defaultTTL;
    final entry = CacheEntry(
      key: key,
      data: value,
      statusCode: 200,
      createdAt: DateTime.now(),
    );
    await setEntry(key, entry, ttl: effectiveTTL);
  }

  @override
  Future<void> setEntry(String key, CacheEntry entry, {Duration? ttl}) async {
    // Calculate size
    final size = _calculateSize(entry.data);

    // Evict if necessary
    await _evictIfNeeded(size);

    // Remove existing entry if present
    if (_cache.containsKey(key)) {
      await remove(key);
    }

    // Add new entry
    final effectiveTTL = ttl ?? defaultTTL;
    final expiresAt = effectiveTTL != null
        ? DateTime.now().add(effectiveTTL)
        : null;

    _cache[key] = _MemoryCacheEntry(
      entry: entry,
      size: size,
      expiresAt: expiresAt,
    );
    _accessOrder.add(key);
    _currentSizeBytes += size;
  }

  @override
  Future<void> remove(String key) async {
    final entry = _cache.remove(key);
    if (entry != null) {
      _accessOrder.remove(key);
      _currentSizeBytes -= entry.size;
      onEvict?.call(key, entry.entry);
    }
  }

  @override
  Future<void> removeWhere(bool Function(String key) predicate) async {
    final keysToRemove = _cache.keys.where(predicate).toList();
    for (final key in keysToRemove) {
      await remove(key);
    }
  }

  @override
  Future<void> clear() async {
    _cache.clear();
    _accessOrder.clear();
    _currentSizeBytes = 0;
  }

  @override
  Future<bool> contains(String key) async {
    final entry = _cache[key];
    if (entry == null) return false;

    if (entry.isExpired) {
      await remove(key);
      return false;
    }

    return true;
  }

  @override
  Future<int> get count async => _cache.length;

  @override
  Future<int?> get sizeInBytes async => _currentSizeBytes;

  @override
  Future<List<String>> get keys async => List.from(_cache.keys);

  @override
  Future<void> dispose() async {
    await clear();
  }

  /// Evicts all stale entries older than the given duration.
  Future<int> evictStale(Duration maxAge) async {
    var evicted = 0;
    final now = DateTime.now();
    final keysToRemove = <String>[];

    for (final entry in _cache.entries) {
      if (entry.value.isExpired ||
          now.difference(entry.value.entry.createdAt) > maxAge) {
        keysToRemove.add(entry.key);
      }
    }

    for (final key in keysToRemove) {
      await remove(key);
      evicted++;
    }

    return evicted;
  }

  /// Trims the cache to the specified number of entries.
  Future<int> trimTo(int targetSize) async {
    var evicted = 0;

    while (_cache.length > targetSize && _accessOrder.isNotEmpty) {
      final oldestKey = _accessOrder.first;
      await remove(oldestKey);
      evicted++;
    }

    return evicted;
  }

  /// Returns statistics about the cache.
  MemoryCacheStats getStats() {
    return MemoryCacheStats(
      entries: _cache.length,
      maxEntries: maxSize,
      sizeBytes: _currentSizeBytes,
      maxSizeBytes: maxSizeBytes,
    );
  }

  void _updateAccessOrder(String key) {
    _accessOrder.remove(key);
    _accessOrder.add(key);
  }

  Future<void> _evictIfNeeded(int newEntrySize) async {
    // Evict expired entries first
    final expiredKeys = _cache.entries
        .where((e) => e.value.isExpired)
        .map((e) => e.key)
        .toList();

    for (final key in expiredKeys) {
      await remove(key);
    }

    // Evict by count if needed
    while (_cache.length >= maxSize && _accessOrder.isNotEmpty) {
      final oldestKey = _accessOrder.first;
      await remove(oldestKey);
    }

    // Evict by size if needed
    if (maxSizeBytes != null) {
      while (_currentSizeBytes + newEntrySize > maxSizeBytes! &&
          _accessOrder.isNotEmpty) {
        final oldestKey = _accessOrder.first;
        await remove(oldestKey);
      }
    }
  }

  int _calculateSize(dynamic data) {
    if (data == null) return 0;
    if (data is String) return data.length * 2; // UTF-16
    if (data is List<int>) return data.length;
    try {
      final jsonStr = json.encode(data);
      return jsonStr.length * 2;
    } catch (_) {
      return 1000; // Estimate for complex objects
    }
  }
}

/// Internal cache entry with metadata.
class _MemoryCacheEntry {
  const _MemoryCacheEntry({
    required this.entry,
    required this.size,
    this.expiresAt,
  });

  final CacheEntry entry;
  final int size;
  final DateTime? expiresAt;

  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }
}

/// Statistics about the memory cache.
class MemoryCacheStats {
  const MemoryCacheStats({
    required this.entries,
    required this.maxEntries,
    required this.sizeBytes,
    this.maxSizeBytes,
  });

  final int entries;
  final int maxEntries;
  final int sizeBytes;
  final int? maxSizeBytes;

  double get fillRatio => entries / maxEntries;

  double? get sizeFillRatio {
    if (maxSizeBytes == null) return null;
    return sizeBytes / maxSizeBytes!;
  }

  @override
  String toString() {
    return 'MemoryCacheStats('
        'entries: $entries/$maxEntries, '
        'size: ${(sizeBytes / 1024).toStringAsFixed(2)} KB'
        ')';
  }
}
