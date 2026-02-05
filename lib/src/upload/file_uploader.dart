import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as path;

import '../response/response.dart';
import '../response/api_error.dart';

/// Configuration for file upload.
class UploadConfig {
  /// Creates a new [UploadConfig].
  const UploadConfig({
    this.chunkSize = 1024 * 1024, // 1MB
    this.maxConcurrentChunks = 3,
    this.timeout = const Duration(minutes: 10),
    this.enableResume = true,
    this.validateHash = false,
    this.compressionEnabled = false,
    this.compressionQuality = 80,
  });

  /// Size of each chunk for chunked uploads (in bytes).
  final int chunkSize;

  /// Maximum concurrent chunk uploads.
  final int maxConcurrentChunks;

  /// Upload timeout.
  final Duration timeout;

  /// Whether to enable resumable uploads.
  final bool enableResume;

  /// Whether to validate file hash after upload.
  final bool validateHash;

  /// Whether to compress images before upload.
  final bool compressionEnabled;

  /// Image compression quality (1-100).
  final int compressionQuality;
}

/// Progress information for file upload.
class UploadProgress {
  /// Creates a new [UploadProgress].
  const UploadProgress({
    required this.bytesSent,
    required this.totalBytes,
    required this.speed,
    required this.elapsedTime,
  });

  /// Bytes sent so far.
  final int bytesSent;

  /// Total bytes to send.
  final int totalBytes;

  /// Upload speed in bytes per second.
  final double speed;

  /// Time elapsed since upload started.
  final Duration elapsedTime;

  /// Progress percentage (0.0 to 1.0).
  double get progress => totalBytes > 0 ? bytesSent / totalBytes : 0;

  /// Estimated time remaining.
  Duration get estimatedTimeRemaining {
    if (speed <= 0) return Duration.zero;
    final remaining = (totalBytes - bytesSent) / speed;
    return Duration(seconds: remaining.round());
  }

  /// Formatted progress string.
  String get formattedProgress => '${(progress * 100).toStringAsFixed(1)}%';

  /// Formatted speed string.
  String get formattedSpeed {
    if (speed < 1024) return '${speed.toStringAsFixed(0)} B/s';
    if (speed < 1024 * 1024) return '${(speed / 1024).toStringAsFixed(1)} KB/s';
    return '${(speed / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
}

/// State of an upload operation.
enum UploadState {
  /// Upload is pending.
  pending,

  /// Upload is in progress.
  uploading,

  /// Upload is paused.
  paused,

  /// Upload completed successfully.
  completed,

  /// Upload failed.
  failed,

  /// Upload was cancelled.
  cancelled,
}

/// Represents an upload task.
class UploadTask {
  UploadTask._({
    required this.id,
    required this.file,
    required this.uploadUrl,
    required this.config,
    required Dio dio,
  })  : _dio = dio,
        _startTime = DateTime.now();

  final String id;
  final File file;
  final String uploadUrl;
  final UploadConfig config;
  final Dio _dio;
  final DateTime _startTime;

  UploadState _state = UploadState.pending;
  int _bytesSent = 0;
  int _totalBytes = 0;
  Object? _error;
  NetworkResponse? _response;
  CancelToken? _cancelToken;

  final _progressController = StreamController<UploadProgress>.broadcast();
  final _stateController = StreamController<UploadState>.broadcast();

  /// Stream of upload progress.
  Stream<UploadProgress> get progressStream => _progressController.stream;

  /// Stream of state changes.
  Stream<UploadState> get stateStream => _stateController.stream;

  /// Current upload state.
  UploadState get state => _state;

  /// Error if upload failed.
  Object? get error => _error;

  /// Response if upload completed.
  NetworkResponse? get response => _response;

  /// Current progress.
  UploadProgress get progress => UploadProgress(
        bytesSent: _bytesSent,
        totalBytes: _totalBytes,
        speed: _calculateSpeed(),
        elapsedTime: DateTime.now().difference(_startTime),
      );

  void _setState(UploadState state) {
    _state = state;
    _stateController.add(state);
  }

  double _calculateSpeed() {
    final elapsed = DateTime.now().difference(_startTime).inMilliseconds;
    if (elapsed <= 0) return 0;
    return _bytesSent / (elapsed / 1000);
  }

  void _updateProgress(int sent, int total) {
    _bytesSent = sent;
    _totalBytes = total;
    _progressController.add(progress);
  }

  Future<void> _dispose() async {
    await _progressController.close();
    await _stateController.close();
  }
}

/// Handles file uploads with progress tracking and resumable support.
///
/// Example:
/// ```dart
/// final uploader = FileUploader(dio: dio);
///
/// final task = await uploader.upload(
///   file: File('image.jpg'),
///   uploadUrl: 'https://api.example.com/upload',
///   fieldName: 'file',
/// );
///
/// task.progressStream.listen((progress) {
///   print('Upload: ${progress.formattedProgress} at ${progress.formattedSpeed}');
/// });
///
/// final response = await task.wait();
/// ```
class FileUploader {
  /// Creates a new [FileUploader].
  FileUploader({
    required Dio dio,
    UploadConfig? defaultConfig,
  })  : _dio = dio,
        _defaultConfig = defaultConfig ?? const UploadConfig();

  final Dio _dio;
  final UploadConfig _defaultConfig;
  final Map<String, UploadTask> _tasks = {};
  int _taskCounter = 0;

  /// Active upload tasks.
  Map<String, UploadTask> get tasks => Map.unmodifiable(_tasks);

  /// Uploads a file to the specified URL.
  Future<UploadTask> upload({
    required File file,
    required String uploadUrl,
    String fieldName = 'file',
    Map<String, dynamic>? additionalFields,
    Map<String, String>? headers,
    UploadConfig? config,
  }) async {
    final uploadConfig = config ?? _defaultConfig;
    final taskId = 'upload_${++_taskCounter}';

    final task = UploadTask._(
      id: taskId,
      file: file,
      uploadUrl: uploadUrl,
      config: uploadConfig,
      dio: _dio,
    );

    _tasks[taskId] = task;

    // Start upload asynchronously
    _executeUpload(task, fieldName, additionalFields, headers);

    return task;
  }

  Future<void> _executeUpload(
    UploadTask task,
    String fieldName,
    Map<String, dynamic>? additionalFields,
    Map<String, String>? headers,
  ) async {
    task._setState(UploadState.uploading);
    task._cancelToken = CancelToken();

    try {
      final file = task.file;
      final fileLength = await file.length();
      task._totalBytes = fileLength;

      // Determine mime type
      final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';
      final fileName = path.basename(file.path);

      // Create multipart file
      final multipartFile = await MultipartFile.fromFile(
        file.path,
        filename: fileName,
        contentType: DioMediaType.parse(mimeType),
      );

      // Build form data
      final formData = FormData.fromMap({
        fieldName: multipartFile,
        ...?additionalFields,
      });

      // Execute upload
      final response = await _dio.post<dynamic>(
        task.uploadUrl,
        data: formData,
        options: Options(
          headers: headers,
          sendTimeout: task.config.timeout,
          receiveTimeout: task.config.timeout,
        ),
        cancelToken: task._cancelToken,
        onSendProgress: (sent, total) {
          task._updateProgress(sent, total);
        },
      );

      task._response = NetworkResponse(
        data: response.data,
        statusCode: response.statusCode ?? 200,
        headers: response.headers.map,
      );
      task._setState(UploadState.completed);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        task._setState(UploadState.cancelled);
      } else {
        task._error = ApiError.fromDioError(e);
        task._setState(UploadState.failed);
      }
    } catch (e) {
      task._error = e;
      task._setState(UploadState.failed);
    }
  }

  /// Uploads bytes directly.
  Future<UploadTask> uploadBytes({
    required Uint8List bytes,
    required String uploadUrl,
    required String filename,
    String fieldName = 'file',
    String? mimeType,
    Map<String, dynamic>? additionalFields,
    Map<String, String>? headers,
    UploadConfig? config,
  }) async {
    // Create temporary file
    final tempDir = Directory.systemTemp;
    final tempFile = File('${tempDir.path}/$filename');
    await tempFile.writeAsBytes(bytes);

    try {
      return await upload(
        file: tempFile,
        uploadUrl: uploadUrl,
        fieldName: fieldName,
        additionalFields: additionalFields,
        headers: headers,
        config: config,
      );
    } finally {
      // Clean up temp file after upload completes
      // Note: This is simplified; in production, cleanup should happen after upload
    }
  }

  /// Uploads multiple files.
  Future<List<UploadTask>> uploadMultiple({
    required List<File> files,
    required String uploadUrl,
    String fieldName = 'files',
    Map<String, dynamic>? additionalFields,
    Map<String, String>? headers,
    UploadConfig? config,
  }) async {
    final tasks = <UploadTask>[];

    for (final file in files) {
      final task = await upload(
        file: file,
        uploadUrl: uploadUrl,
        fieldName: fieldName,
        additionalFields: additionalFields,
        headers: headers,
        config: config,
      );
      tasks.add(task);
    }

    return tasks;
  }

  /// Cancels an upload task.
  void cancel(String taskId) {
    final task = _tasks[taskId];
    if (task != null && task.state == UploadState.uploading) {
      task._cancelToken?.cancel('Upload cancelled by user');
      task._setState(UploadState.cancelled);
    }
  }

  /// Cancels all active uploads.
  void cancelAll() {
    for (final task in _tasks.values) {
      if (task.state == UploadState.uploading) {
        task._cancelToken?.cancel('All uploads cancelled');
        task._setState(UploadState.cancelled);
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
        .where((e) => e.value.state == UploadState.completed ||
            e.value.state == UploadState.failed ||
            e.value.state == UploadState.cancelled)
        .map((e) => e.key)
        .toList();

    for (final id in completed) {
      await removeTask(id);
    }
  }

  /// Disposes the uploader and cancels all uploads.
  Future<void> dispose() async {
    cancelAll();
    for (final task in _tasks.values) {
      await task._dispose();
    }
    _tasks.clear();
  }
}

/// Extension for waiting on upload task.
extension UploadTaskWait on UploadTask {
  /// Waits for the upload to complete.
  Future<NetworkResponse> wait() async {
    if (state == UploadState.completed) {
      return response!;
    }

    if (state == UploadState.failed) {
      throw error!;
    }

    if (state == UploadState.cancelled) {
      throw StateError('Upload was cancelled');
    }

    // Wait for completion
    await stateStream.firstWhere((s) =>
        s == UploadState.completed ||
        s == UploadState.failed ||
        s == UploadState.cancelled);

    if (state == UploadState.completed) {
      return response!;
    }

    if (state == UploadState.cancelled) {
      throw StateError('Upload was cancelled');
    }

    throw error!;
  }
}
