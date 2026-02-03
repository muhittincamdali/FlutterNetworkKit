import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../interceptors/cache_interceptor.dart';
import 'cache_manager.dart';

/// A disk-based cache manager for persistent storage.
///
/// This implementation stores cached data on disk for persistence
/// across app restarts. It uses hashed filenames to store entries.
///
/// Example:
/// ```dart
/// final cacheDir = await getTemporaryDirectory();
/// final cache = DiskCacheManager(
///   directory: Directory('${cacheDir.path}/network_cache'),
///   maxSizeBytes: 50 * 1024 * 1024, // 50 MB
/// );
///
/// await cache.set('key', data);
/// final cached = await cache.get<MyData>('key');
/// ```
class DiskCacheManager implements CacheManager {
  /// Creates a new [DiskCacheManager].
  DiskCacheManager({
    this.directory,
    this.maxSizeBytes = 50 * 1024 * 1024, // 50 MB default
    this.maxEntries = 1000,
    this.defaultTTL,
    this.fileExtension = '.cache',
  });

  /// The directory to store cache files.
  final Directory? directory;

  /// Maximum size of the cache in bytes.
  final int maxSizeBytes;

  /// Maximum number of entries in the cache.
  final int maxEntries;

  /// Default TTL for cache entries.
  final Duration? defaultTTL;

  /// File extension for cache files.
  final String fileExtension;

  Directory? _cacheDir;
  bool _initialized = false;

  Future<Directory> _getCacheDirectory() async {
    if (_cacheDir != null) return _cacheDir!;

    if (directory != null) {
      _cacheDir = directory;
    } else {
      final appDir = await getTemporaryDirectory();
      _cacheDir = Directory('${appDir.path}/network_kit_cache');
    }

    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }

    _initialized = true;
    return _cacheDir!;
  }

  String _hashKey(String key) {
    final bytes = utf8.encode(key);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  File _getFile(Directory dir, String key) {
    final hashedKey = _hashKey(key);
    return File('${dir.path}/$hashedKey$fileExtension');
  }

  File _getMetaFile(Directory dir, String key) {
    final hashedKey = _hashKey(key);
    return File('${dir.path}/$hashedKey.meta');
  }

  @override
  Future<T?> get<T>(String key) async {
    final entry = await getEntry(key);
    return entry?.data as T?;
  }

  @override
  Future<CacheEntry?> getEntry(String key) async {
    try {
      final dir = await _getCacheDirectory();
      final file = _getFile(dir, key);
      final metaFile = _getMetaFile(dir, key);

      if (!await file.exists() || !await metaFile.exists()) {
        return null;
      }

      // Read metadata
      final metaContent = await metaFile.readAsString();
      final meta = json.decode(metaContent) as Map<String, dynamic>;

      // Check if expired
      final expiresAt = meta['expiresAt'] != null
          ? DateTime.parse(meta['expiresAt'] as String)
          : null;

      if (expiresAt != null && DateTime.now().isAfter(expiresAt)) {
        await remove(key);
        return null;
      }

      // Read data
      final content = await file.readAsString();
      final data = json.decode(content);

      return CacheEntry(
        key: key,
        data: data,
        statusCode: meta['statusCode'] as int? ?? 200,
        headers: (meta['headers'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, (v as List).cast<String>()),
        ),
        createdAt: DateTime.parse(meta['createdAt'] as String),
        etag: meta['etag'] as String?,
        lastModified: meta['lastModified'] as String?,
      );
    } catch (e) {
      // If any error occurs reading the cache, return null
      return null;
    }
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
    try {
      final dir = await _getCacheDirectory();

      // Evict if necessary
      await _evictIfNeeded();

      final file = _getFile(dir, key);
      final metaFile = _getMetaFile(dir, key);

      final effectiveTTL = ttl ?? defaultTTL;
      final expiresAt = effectiveTTL != null
          ? DateTime.now().add(effectiveTTL)
          : null;

      // Write data
      final dataContent = json.encode(entry.data);
      await file.writeAsString(dataContent);

      // Write metadata
      final meta = {
        'key': key,
        'statusCode': entry.statusCode,
        'createdAt': entry.createdAt.toIso8601String(),
        if (expiresAt != null) 'expiresAt': expiresAt.toIso8601String(),
        if (entry.headers != null) 'headers': entry.headers,
        if (entry.etag != null) 'etag': entry.etag,
        if (entry.lastModified != null) 'lastModified': entry.lastModified,
      };
      await metaFile.writeAsString(json.encode(meta));
    } catch (e) {
      // Silently fail on write errors
    }
  }

  @override
  Future<void> remove(String key) async {
    try {
      final dir = await _getCacheDirectory();
      final file = _getFile(dir, key);
      final metaFile = _getMetaFile(dir, key);

      if (await file.exists()) {
        await file.delete();
      }
      if (await metaFile.exists()) {
        await metaFile.delete();
      }
    } catch (e) {
      // Silently fail on delete errors
    }
  }

  @override
  Future<void> removeWhere(bool Function(String key) predicate) async {
    final allKeys = await keys;
    for (final key in allKeys) {
      if (predicate(key)) {
        await remove(key);
      }
    }
  }

  @override
  Future<void> clear() async {
    try {
      final dir = await _getCacheDirectory();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        await dir.create();
      }
    } catch (e) {
      // Silently fail
    }
  }

  @override
  Future<bool> contains(String key) async {
    final dir = await _getCacheDirectory();
    final file = _getFile(dir, key);
    return file.exists();
  }

  @override
  Future<int> get count async {
    try {
      final dir = await _getCacheDirectory();
      final files = await dir
          .list()
          .where((f) => f is File && f.path.endsWith(fileExtension))
          .length;
      return files;
    } catch (e) {
      return 0;
    }
  }

  @override
  Future<int?> get sizeInBytes async {
    try {
      final dir = await _getCacheDirectory();
      var totalSize = 0;

      await for (final file in dir.list()) {
        if (file is File) {
          totalSize += await file.length();
        }
      }

      return totalSize;
    } catch (e) {
      return null;
    }
  }

  @override
  Future<List<String>> get keys async {
    try {
      final dir = await _getCacheDirectory();
      final keys = <String>[];

      await for (final file in dir.list()) {
        if (file is File && file.path.endsWith('.meta')) {
          try {
            final content = await file.readAsString();
            final meta = json.decode(content) as Map<String, dynamic>;
            final key = meta['key'] as String?;
            if (key != null) {
              keys.add(key);
            }
          } catch (_) {
            // Skip invalid meta files
          }
        }
      }

      return keys;
    } catch (e) {
      return [];
    }
  }

  @override
  Future<void> dispose() async {
    // Nothing to dispose for disk cache
  }

  /// Evicts all stale entries older than the given duration.
  Future<int> evictStale(Duration maxAge) async {
    var evicted = 0;
    final allKeys = await keys;
    final now = DateTime.now();

    for (final key in allKeys) {
      final entry = await getEntry(key);
      if (entry != null && now.difference(entry.createdAt) > maxAge) {
        await remove(key);
        evicted++;
      }
    }

    return evicted;
  }

  Future<void> _evictIfNeeded() async {
    final currentCount = await count;
    final currentSize = await sizeInBytes ?? 0;

    // Evict by count
    if (currentCount >= maxEntries) {
      await _evictOldest((currentCount - maxEntries + 1).clamp(1, 100));
    }

    // Evict by size
    if (currentSize > maxSizeBytes) {
      final targetSize = (maxSizeBytes * 0.8).toInt(); // Reduce to 80%
      await _evictUntilSize(targetSize);
    }
  }

  Future<void> _evictOldest(int count) async {
    try {
      final dir = await _getCacheDirectory();
      final entries = <_DiskCacheFileInfo>[];

      await for (final file in dir.list()) {
        if (file is File && file.path.endsWith('.meta')) {
          try {
            final stat = await file.stat();
            final content = await file.readAsString();
            final meta = json.decode(content) as Map<String, dynamic>;
            entries.add(_DiskCacheFileInfo(
              key: meta['key'] as String,
              modified: stat.modified,
              size: await file.length(),
            ));
          } catch (_) {
            // Skip invalid files
          }
        }
      }

      // Sort by modification time (oldest first)
      entries.sort((a, b) => a.modified.compareTo(b.modified));

      // Remove oldest entries
      for (var i = 0; i < count && i < entries.length; i++) {
        await remove(entries[i].key);
      }
    } catch (e) {
      // Silently fail
    }
  }

  Future<void> _evictUntilSize(int targetSize) async {
    try {
      final dir = await _getCacheDirectory();
      final entries = <_DiskCacheFileInfo>[];

      await for (final file in dir.list()) {
        if (file is File && file.path.endsWith('.meta')) {
          try {
            final stat = await file.stat();
            final content = await file.readAsString();
            final meta = json.decode(content) as Map<String, dynamic>;
            final dataFile = _getFile(dir, meta['key'] as String);
            final dataSize = await dataFile.exists() ? await dataFile.length() : 0;
            entries.add(_DiskCacheFileInfo(
              key: meta['key'] as String,
              modified: stat.modified,
              size: dataSize + await file.length(),
            ));
          } catch (_) {
            // Skip invalid files
          }
        }
      }

      // Sort by modification time (oldest first)
      entries.sort((a, b) => a.modified.compareTo(b.modified));

      var currentSize = entries.fold(0, (sum, e) => sum + e.size);

      for (final entry in entries) {
        if (currentSize <= targetSize) break;
        await remove(entry.key);
        currentSize -= entry.size;
      }
    } catch (e) {
      // Silently fail
    }
  }

  /// Returns statistics about the disk cache.
  Future<DiskCacheStats> getStats() async {
    return DiskCacheStats(
      entries: await count,
      maxEntries: maxEntries,
      sizeBytes: await sizeInBytes ?? 0,
      maxSizeBytes: maxSizeBytes,
    );
  }
}

class _DiskCacheFileInfo {
  const _DiskCacheFileInfo({
    required this.key,
    required this.modified,
    required this.size,
  });

  final String key;
  final DateTime modified;
  final int size;
}

/// Statistics about the disk cache.
class DiskCacheStats {
  const DiskCacheStats({
    required this.entries,
    required this.maxEntries,
    required this.sizeBytes,
    required this.maxSizeBytes,
  });

  final int entries;
  final int maxEntries;
  final int sizeBytes;
  final int maxSizeBytes;

  double get fillRatio => entries / maxEntries;
  double get sizeFillRatio => sizeBytes / maxSizeBytes;

  @override
  String toString() {
    return 'DiskCacheStats('
        'entries: $entries/$maxEntries, '
        'size: ${(sizeBytes / 1024 / 1024).toStringAsFixed(2)} MB / ${(maxSizeBytes / 1024 / 1024).toStringAsFixed(2)} MB'
        ')';
  }
}
