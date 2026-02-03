import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';

/// Represents a multipart form data request for file uploads.
///
/// This class provides a convenient way to build multipart requests
/// with files, fields, and streams.
///
/// Example:
/// ```dart
/// final request = MultipartRequest()
///   ..addFile('avatar', File('path/to/image.jpg'))
///   ..addField('username', 'john_doe')
///   ..addField('email', 'john@example.com');
///
/// final response = await client.upload('/profile', request);
/// ```
class MultipartRequest {
  /// Creates a new [MultipartRequest].
  MultipartRequest();

  final List<MultipartFile> _files = [];
  final Map<String, dynamic> _fields = {};

  /// The list of files to upload.
  List<MultipartFile> get files => List.unmodifiable(_files);

  /// The form fields to include.
  Map<String, dynamic> get fields => Map.unmodifiable(_fields);

  /// Adds a file from the filesystem.
  ///
  /// [fieldName] is the form field name for this file.
  /// [file] is the file to upload.
  /// [filename] is an optional custom filename (defaults to file basename).
  /// [contentType] is an optional custom content type.
  Future<void> addFile(
    String fieldName,
    File file, {
    String? filename,
    MediaType? contentType,
  }) async {
    final fileName = filename ?? file.uri.pathSegments.last;
    final mimeType = contentType ?? _getMimeType(fileName);

    _files.add(
      await MultipartFile.fromFile(
        file.path,
        filename: fileName,
        contentType: mimeType,
      ),
    );
  }

  /// Adds a file from bytes.
  ///
  /// [fieldName] is the form field name for this file.
  /// [bytes] is the file content.
  /// [filename] is the filename to use.
  /// [contentType] is an optional custom content type.
  void addBytes(
    String fieldName,
    Uint8List bytes, {
    required String filename,
    MediaType? contentType,
  }) {
    final mimeType = contentType ?? _getMimeType(filename);

    _files.add(
      MultipartFile.fromBytes(
        bytes,
        filename: filename,
        contentType: mimeType,
      ),
    );
  }

  /// Adds a file from a stream.
  ///
  /// [fieldName] is the form field name for this file.
  /// [stream] is the file content stream.
  /// [length] is the content length in bytes.
  /// [filename] is the filename to use.
  /// [contentType] is an optional custom content type.
  void addStream(
    String fieldName,
    Stream<List<int>> stream, {
    required int length,
    required String filename,
    MediaType? contentType,
  }) {
    final mimeType = contentType ?? _getMimeType(filename);

    _files.add(
      MultipartFile.fromStream(
        () => stream,
        length,
        filename: filename,
        contentType: mimeType,
      ),
    );
  }

  /// Adds a text field to the request.
  void addField(String name, String value) {
    _fields[name] = value;
  }

  /// Adds multiple text fields to the request.
  void addFields(Map<String, String> fields) {
    _fields.addAll(fields);
  }

  /// Adds a JSON field to the request.
  void addJsonField(String name, dynamic value) {
    _fields[name] = value;
  }

  /// Removes a file at the specified index.
  void removeFileAt(int index) {
    if (index >= 0 && index < _files.length) {
      _files.removeAt(index);
    }
  }

  /// Removes a field by name.
  void removeField(String name) {
    _fields.remove(name);
  }

  /// Clears all files and fields.
  void clear() {
    _files.clear();
    _fields.clear();
  }

  /// Converts this request to Dio [FormData].
  Future<FormData> toFormData() async {
    final formData = FormData();

    // Add fields
    for (final entry in _fields.entries) {
      formData.fields.add(MapEntry(entry.key, entry.value.toString()));
    }

    // Add files
    for (final file in _files) {
      formData.files.add(MapEntry('file', file));
    }

    return formData;
  }

  /// Returns the total size of all files in bytes.
  int get totalSize {
    return _files.fold(0, (sum, file) => sum + file.length);
  }

  /// Returns true if this request has files.
  bool get hasFiles => _files.isNotEmpty;

  /// Returns true if this request has fields.
  bool get hasFields => _fields.isNotEmpty;

  /// Returns true if this request is empty.
  bool get isEmpty => _files.isEmpty && _fields.isEmpty;

  MediaType _getMimeType(String filename) {
    final mimeType = lookupMimeType(filename);
    if (mimeType != null) {
      final parts = mimeType.split('/');
      return MediaType(parts[0], parts.length > 1 ? parts[1] : 'octet-stream');
    }
    return MediaType('application', 'octet-stream');
  }

  @override
  String toString() {
    return 'MultipartRequest('
        'files: ${_files.length}, '
        'fields: ${_fields.length}, '
        'totalSize: $totalSize bytes'
        ')';
  }
}

/// Extension for creating multipart requests from files.
extension FileMultipartExtension on File {
  /// Creates a multipart file from this file.
  Future<MultipartFile> toMultipartFile({
    String? filename,
    MediaType? contentType,
  }) async {
    final fileName = filename ?? uri.pathSegments.last;
    final mimeType = contentType ?? _getMimeType(fileName);

    return MultipartFile.fromFile(
      path,
      filename: fileName,
      contentType: mimeType,
    );
  }

  MediaType _getMimeType(String filename) {
    final mimeType = lookupMimeType(filename);
    if (mimeType != null) {
      final parts = mimeType.split('/');
      return MediaType(parts[0], parts.length > 1 ? parts[1] : 'octet-stream');
    }
    return MediaType('application', 'octet-stream');
  }
}

/// Builder for creating multipart requests with a fluent API.
class MultipartRequestBuilder {
  final MultipartRequest _request = MultipartRequest();

  /// Adds a file from the filesystem.
  MultipartRequestBuilder file(
    String fieldName,
    File file, {
    String? filename,
    MediaType? contentType,
  }) {
    _request.addFile(fieldName, file, filename: filename, contentType: contentType);
    return this;
  }

  /// Adds a file from bytes.
  MultipartRequestBuilder bytes(
    String fieldName,
    Uint8List bytes, {
    required String filename,
    MediaType? contentType,
  }) {
    _request.addBytes(fieldName, bytes, filename: filename, contentType: contentType);
    return this;
  }

  /// Adds a text field.
  MultipartRequestBuilder field(String name, String value) {
    _request.addField(name, value);
    return this;
  }

  /// Adds multiple text fields.
  MultipartRequestBuilder fields(Map<String, String> fields) {
    _request.addFields(fields);
    return this;
  }

  /// Builds the multipart request.
  MultipartRequest build() => _request;
}
