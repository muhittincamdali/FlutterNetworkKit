import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;
import 'package:crypto/crypto.dart';
import 'dart:convert';

import '../response/api_error.dart';

/// Configuration for file download.
class DownloadConfig {
  /// Creates a new [DownloadConfig].
  const DownloadConfig({
    this.timeout = const Duration(minutes: 30),
    this.enableResume = true,
    this.validateChecksum = false,
    this.expectedChecksum,
    this.checksumType = ChecksumType.sha256,
    this.deleteOnError = true,
    this.createDirectory = true,
    this.overwrite = false,
  });

  /// Download timeout.
  final Duration timeout;

  /// Whether to enable resumable downloads.
  final bool enableResume;

  /// Whether to validate file checksum.
  final bool validateChecksum;

  /// Expected checksum for validation.
  final String? expectedChecksum;

  /// Type of checksum to use.
  final ChecksumType checksumType;

  /// Whether to delete partial file on error.
  final bool deleteOnError;

  /// Whether to create parent directories.
  final bool createDirectory;

  /// Whether to overwrite existing files.
  final bool overwrite;
}

/// Type of checksum for validation.
enum ChecksumType { md5, sha1, sha256 }

/// Progress information for file download.
class DownloadProgress {
  /// Creates a new [DownloadProgress].
  const DownloadProgress({
    required this.bytesReceived,
    required this.totalBytes,
    required this.speed,
    required this.elapsedTime,
  });

  /// Bytes received so far.
  final int bytesReceived;

  /// Total bytes to receive (-1 if unknown).
  final int totalBytes;

  /// Download speed in bytes per second.
  final double speed;

  /// Time elapsed since download started.
  final Duration elapsedTime;

  /// Progress percentage (0.0 to 1.0), or -1 if unknown.
  double get progress => totalBytes > 0 ? bytesReceived / totalBytes : -1;

  /// Whether total size is known.
  bool get isSizeKnown => totalBytes > 0;

  /// Estimated time remaining.
  Duration get estimatedTimeRemaining {
    if (speed <= 0 || !isSizeKnown) return Duration.zero;
    final remaining = (totalBytes - bytesReceived) / speed;
    return Duration(seconds: remaining.round());
  }

  /// Formatted progress string.
  String get formattedProgress {
    if (!isSizeKnown) return _formatBytes(bytesReceived);
    return '${(progress * 100).toStringAsFixed(1)}%';
  }

  /// Formatted speed string.
  String get formattedSpeed {
    if (speed < 1024) return '${speed.toStringAsFixed(0)} B/s';
    if (speed < 1024 * 1024) return '${(speed / 1024).toStringAsFixed(1)} KB/s';
    return '${(speed / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// State of a download operation.
enum DownloadState {
  /// Download is pending.
  pending,

  /// Download is in progress.
  downloading,

  /// Download is paused.
  paused,

  /// Download completed successfully.
  completed,

  /// Download failed.
  failed,

  /// Download was cancelled.
  cancelled,
}

/// Represents a download task.
class DownloadTask {
  DownloadTask._({
    required this.id,
    required this.url,
    required this.savePath,
    required this.config,
    required Dio dio,
  })  : _dio = dio,
        _startTime = DateTime.now();

  final String id;
  final String url;
  final String savePath;
  final DownloadConfig config;
  final Dio _dio;
  final DateTime _startTime;

  DownloadState _state = DownloadState.pending;
  int _bytesReceived = 0;
  int _totalBytes = -1;
  int _resumeOffset = 0;
  Object? _error;
  File? _file;
  CancelToken? _cancelToken;

  final _progressController = StreamController<DownloadProgress>.broadcast();
  final _stateController = StreamController<DownloadState>.broadcast();

  /// Stream of download progress.
  Stream<DownloadProgress> get progressStream => _progressController.stream;

  /// Stream of state changes.
  Stream<DownloadState> get stateStream => _stateController.stream;

  /// Current download state.
  DownloadState get state => _state;

  /// Error if download failed.
  Object? get error => _error;

  /// Downloaded file if completed.
  File? get file => _file;

  /// Current progress.
  DownloadProgress get progress => DownloadProgress(
        bytesReceived: _bytesReceived,
        totalBytes: _totalBytes,
        speed: _calculateSpeed(),
        elapsedTime: DateTime.now().difference(_startTime),
      );

  void _setState(DownloadState state) {
    _state = state;
    _stateController.add(state);
  }

  double _calculateSpeed() {
    final elapsed = DateTime.now().difference(_startTime).inMilliseconds;
    if (elapsed <= 0) return 0;
    return (_bytesReceived - _resumeOffset) / (elapsed / 1000);
  }

  void _updateProgress(int received, int total) {
    _bytesReceived = received + _resumeOffset;
    if (total > 0) _totalBytes = total + _resumeOffset;
    _progressController.add(progress);
  }

  Future<void> _dispose() async {
    await _progressController.close();
    await _stateController.close();
  }
}

/// Handles file downloads with progress tracking and resumable support.
///
/// Example:
/// ```dart
/// final downloader = FileDownloader(dio: dio);
///
/// final task = await downloader.download(
///   url: 'https://example.com/file.zip',
///   savePath: '/path/to/file.zip',
/// );
///
/// task.progressStream.listen((progress) {
///   print('Download: ${progress.formattedProgress} at ${progress.formattedSpeed}');
/// });
///
/// final file = await task.wait();
/// ```
class FileDownloader {
  /// Creates a new [FileDownloader].
  FileDownloader({
    required Dio dio,
    DownloadConfig? defaultConfig,
  })  : _dio = dio,
        _defaultConfig = defaultConfig ?? const DownloadConfig();

  final Dio _dio;
  final DownloadConfig _defaultConfig;
  final Map<String, DownloadTask> _tasks = {};
  int _taskCounter = 0;

  /// Active download tasks.
  Map<String, DownloadTask> get tasks => Map.unmodifiable(_tasks);

  /// Downloads a file from the specified URL.
  Future<DownloadTask> download({
    required String url,
    required String savePath,
    Map<String, String>? headers,
    DownloadConfig? config,
  }) async {
    final downloadConfig = config ?? _defaultConfig;
    final taskId = 'download_${++_taskCounter}';

    final task = DownloadTask._(
      id: taskId,
      url: url,
      savePath: savePath,
      config: downloadConfig,
      dio: _dio,
    );

    _tasks[taskId] = task;

    // Start download asynchronously
    _executeDownload(task, headers);

    return task;
  }

  Future<void> _executeDownload(
    DownloadTask task,
    Map<String, String>? headers,
  ) async {
    task._setState(DownloadState.downloading);
    task._cancelToken = CancelToken();

    try {
      final file = File(task.savePath);
      final config = task.config;

      // Create directory if needed
      if (config.createDirectory) {
        await file.parent.create(recursive: true);
      }

      // Check for existing partial download
      int resumeOffset = 0;
      if (config.enableResume && await file.exists()) {
        if (config.overwrite) {
          await file.delete();
        } else {
          resumeOffset = await file.length();
          task._resumeOffset = resumeOffset;
        }
      }

      // Build headers
      final requestHeaders = <String, dynamic>{
        ...?headers,
      };

      if (resumeOffset > 0) {
        requestHeaders['Range'] = 'bytes=$resumeOffset-';
      }

      // Execute download
      await _dio.download(
        task.url,
        task.savePath,
        options: Options(
          headers: requestHeaders,
          receiveTimeout: config.timeout,
        ),
        cancelToken: task._cancelToken,
        deleteOnError: config.deleteOnError,
        onReceiveProgress: (received, total) {
          task._updateProgress(received, total);
        },
      );

      // Validate checksum if required
      if (config.validateChecksum && config.expectedChecksum != null) {
        final isValid = await _validateChecksum(
          file,
          config.expectedChecksum!,
          config.checksumType,
        );

        if (!isValid) {
          if (config.deleteOnError) {
            await file.delete();
          }
          throw DownloadChecksumException(
            expected: config.expectedChecksum!,
            actual: await _calculateChecksum(file, config.checksumType),
          );
        }
      }

      task._file = file;
      task._setState(DownloadState.completed);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        task._setState(DownloadState.cancelled);
      } else {
        task._error = ApiError.fromDioError(e);
        task._setState(DownloadState.failed);
      }
    } catch (e) {
      task._error = e;
      task._setState(DownloadState.failed);
    }
  }

  Future<bool> _validateChecksum(
    File file,
    String expected,
    ChecksumType type,
  ) async {
    final actual = await _calculateChecksum(file, type);
    return actual.toLowerCase() == expected.toLowerCase();
  }

  Future<String> _calculateChecksum(File file, ChecksumType type) async {
    final bytes = await file.readAsBytes();

    switch (type) {
      case ChecksumType.md5:
        return md5.convert(bytes).toString();
      case ChecksumType.sha1:
        return sha1.convert(bytes).toString();
      case ChecksumType.sha256:
        return sha256.convert(bytes).toString();
    }
  }

  /// Downloads a file and returns its bytes.
  Future<List<int>> downloadBytes({
    required String url,
    Map<String, String>? headers,
    void Function(DownloadProgress)? onProgress,
  }) async {
    final tempPath = '${Directory.systemTemp.path}/${DateTime.now().millisecondsSinceEpoch}';

    final task = await download(
      url: url,
      savePath: tempPath,
      headers: headers,
    );

    if (onProgress != null) {
      task.progressStream.listen(onProgress);
    }

    final file = await task.wait();
    final bytes = await file.readAsBytes();

    // Clean up temp file
    await file.delete();

    return bytes;
  }

  /// Downloads multiple files.
  Future<List<DownloadTask>> downloadMultiple({
    required List<DownloadRequest> requests,
    int maxConcurrent = 3,
  }) async {
    final tasks = <DownloadTask>[];
    final semaphore = _Semaphore(maxConcurrent);

    await Future.wait(
      requests.map((request) async {
        await semaphore.acquire();
        try {
          final task = await download(
            url: request.url,
            savePath: request.savePath,
            headers: request.headers,
            config: request.config,
          );
          tasks.add(task);
        } finally {
          semaphore.release();
        }
      }),
    );

    return tasks;
  }

  /// Cancels a download task.
  void cancel(String taskId) {
    final task = _tasks[taskId];
    if (task != null && task.state == DownloadState.downloading) {
      task._cancelToken?.cancel('Download cancelled by user');
      task._setState(DownloadState.cancelled);
    }
  }

  /// Pauses a download task (for resumable downloads).
  void pause(String taskId) {
    final task = _tasks[taskId];
    if (task != null && task.state == DownloadState.downloading) {
      task._cancelToken?.cancel('Download paused');
      task._setState(DownloadState.paused);
    }
  }

  /// Resumes a paused download.
  Future<void> resume(String taskId) async {
    final task = _tasks[taskId];
    if (task != null && task.state == DownloadState.paused) {
      _executeDownload(task, null);
    }
  }

  /// Cancels all active downloads.
  void cancelAll() {
    for (final task in _tasks.values) {
      if (task.state == DownloadState.downloading) {
        task._cancelToken?.cancel('All downloads cancelled');
        task._setState(DownloadState.cancelled);
      }
    }
  }

  /// Removes a completed/failed/cancelled task.
  Future<void> removeTask(String taskId) async {
    final task = _tasks.remove(taskId);
    await task?._dispose();
  }

  /// Clears all completed tasks.
  Future<void> clearCompleted() async {
    final completed = _tasks.entries
        .where((e) =>
            e.value.state == DownloadState.completed ||
            e.value.state == DownloadState.failed ||
            e.value.state == DownloadState.cancelled)
        .map((e) => e.key)
        .toList();

    for (final id in completed) {
      await removeTask(id);
    }
  }

  /// Disposes the downloader and cancels all downloads.
  Future<void> dispose() async {
    cancelAll();
    for (final task in _tasks.values) {
      await task._dispose();
    }
    _tasks.clear();
  }
}

/// Request for batch download.
class DownloadRequest {
  /// Creates a new [DownloadRequest].
  const DownloadRequest({
    required this.url,
    required this.savePath,
    this.headers,
    this.config,
  });

  /// URL to download from.
  final String url;

  /// Path to save the file.
  final String savePath;

  /// Optional headers.
  final Map<String, String>? headers;

  /// Optional config override.
  final DownloadConfig? config;
}

/// Extension for waiting on download task.
extension DownloadTaskWait on DownloadTask {
  /// Waits for the download to complete.
  Future<File> wait() async {
    if (state == DownloadState.completed) {
      return file!;
    }

    if (state == DownloadState.failed) {
      throw error!;
    }

    if (state == DownloadState.cancelled) {
      throw StateError('Download was cancelled');
    }

    // Wait for completion
    await stateStream.firstWhere((s) =>
        s == DownloadState.completed ||
        s == DownloadState.failed ||
        s == DownloadState.cancelled);

    if (state == DownloadState.completed) {
      return file!;
    }

    if (state == DownloadState.cancelled) {
      throw StateError('Download was cancelled');
    }

    throw error!;
  }
}

/// Exception thrown when checksum validation fails.
class DownloadChecksumException implements Exception {
  /// Creates a new [DownloadChecksumException].
  const DownloadChecksumException({
    required this.expected,
    required this.actual,
  });

  /// Expected checksum.
  final String expected;

  /// Actual checksum.
  final String actual;

  @override
  String toString() =>
      'DownloadChecksumException: Checksum mismatch (expected: $expected, actual: $actual)';
}

/// Simple semaphore for limiting concurrency.
class _Semaphore {
  _Semaphore(this.maxConcurrent);

  final int maxConcurrent;
  int _current = 0;
  final _queue = <Completer<void>>[];

  Future<void> acquire() async {
    if (_current < maxConcurrent) {
      _current++;
      return;
    }

    final completer = Completer<void>();
    _queue.add(completer);
    await completer.future;
  }

  void release() {
    if (_queue.isNotEmpty) {
      final completer = _queue.removeAt(0);
      completer.complete();
    } else {
      _current--;
    }
  }
}
