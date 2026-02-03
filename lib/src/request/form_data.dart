import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Represents form data for HTTP requests.
///
/// This class provides utilities for creating URL-encoded form data
/// and working with form fields.
///
/// Example:
/// ```dart
/// final form = NetworkFormData()
///   ..append('username', 'john_doe')
///   ..append('email', 'john@example.com')
///   ..appendAll({'role': 'admin', 'active': 'true'});
///
/// final encoded = form.encode();
/// ```
class NetworkFormData {
  /// Creates a new [NetworkFormData].
  NetworkFormData();

  /// Creates [NetworkFormData] from a map.
  factory NetworkFormData.fromMap(Map<String, dynamic> map) {
    final formData = NetworkFormData();
    map.forEach((key, value) {
      if (value is List) {
        for (final item in value) {
          formData.append(key, item.toString());
        }
      } else {
        formData.append(key, value.toString());
      }
    });
    return formData;
  }

  final List<MapEntry<String, String>> _entries = [];

  /// Returns all entries in this form data.
  List<MapEntry<String, String>> get entries => List.unmodifiable(_entries);

  /// Appends a field to the form data.
  void append(String name, String value) {
    _entries.add(MapEntry(name, value));
  }

  /// Appends multiple fields to the form data.
  void appendAll(Map<String, String> fields) {
    fields.forEach((name, value) => append(name, value));
  }

  /// Appends a field if the value is not null.
  void appendIfNotNull(String name, String? value) {
    if (value != null) {
      append(name, value);
    }
  }

  /// Appends a boolean field.
  void appendBool(String name, bool value) {
    append(name, value.toString());
  }

  /// Appends an integer field.
  void appendInt(String name, int value) {
    append(name, value.toString());
  }

  /// Appends a double field.
  void appendDouble(String name, double value) {
    append(name, value.toString());
  }

  /// Appends a list field with indexed keys.
  void appendList(String name, List<dynamic> values) {
    for (var i = 0; i < values.length; i++) {
      append('$name[$i]', values[i].toString());
    }
  }

  /// Appends a list field with repeated keys.
  void appendRepeated(String name, List<dynamic> values) {
    for (final value in values) {
      append(name, value.toString());
    }
  }

  /// Appends a nested object with dot notation keys.
  void appendNested(String prefix, Map<String, dynamic> map) {
    map.forEach((key, value) {
      final fullKey = '$prefix.$key';
      if (value is Map<String, dynamic>) {
        appendNested(fullKey, value);
      } else if (value is List) {
        appendList(fullKey, value);
      } else {
        append(fullKey, value.toString());
      }
    });
  }

  /// Removes a field by name.
  void remove(String name) {
    _entries.removeWhere((entry) => entry.key == name);
  }

  /// Returns the first value for a field.
  String? get(String name) {
    for (final entry in _entries) {
      if (entry.key == name) {
        return entry.value;
      }
    }
    return null;
  }

  /// Returns all values for a field.
  List<String> getAll(String name) {
    return _entries
        .where((entry) => entry.key == name)
        .map((entry) => entry.value)
        .toList();
  }

  /// Returns true if the field exists.
  bool has(String name) {
    return _entries.any((entry) => entry.key == name);
  }

  /// Clears all fields.
  void clear() {
    _entries.clear();
  }

  /// Returns the number of fields.
  int get length => _entries.length;

  /// Returns true if the form data is empty.
  bool get isEmpty => _entries.isEmpty;

  /// Returns true if the form data is not empty.
  bool get isNotEmpty => _entries.isNotEmpty;

  /// Encodes the form data as a URL-encoded string.
  String encode() {
    return _entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
  }

  /// Converts to a map (last value wins for duplicate keys).
  Map<String, String> toMap() {
    final map = <String, String>{};
    for (final entry in _entries) {
      map[entry.key] = entry.value;
    }
    return map;
  }

  /// Converts to a map with lists for duplicate keys.
  Map<String, List<String>> toMultiMap() {
    final map = <String, List<String>>{};
    for (final entry in _entries) {
      map.putIfAbsent(entry.key, () => []).add(entry.value);
    }
    return map;
  }

  /// Returns the content type header value.
  String get contentType => 'application/x-www-form-urlencoded';

  /// Returns the encoded content as bytes.
  Uint8List toBytes() {
    return Uint8List.fromList(utf8.encode(encode()));
  }

  @override
  String toString() => encode();
}

/// Extension for parsing form data from strings.
extension FormDataParsing on String {
  /// Parses URL-encoded form data from this string.
  NetworkFormData parseFormData() {
    final formData = NetworkFormData();
    final pairs = split('&');

    for (final pair in pairs) {
      final parts = pair.split('=');
      if (parts.length == 2) {
        formData.append(
          Uri.decodeQueryComponent(parts[0]),
          Uri.decodeQueryComponent(parts[1]),
        );
      }
    }

    return formData;
  }
}

/// Extension for converting maps to form data.
extension MapToFormData on Map<String, dynamic> {
  /// Converts this map to form data.
  NetworkFormData toFormData() {
    return NetworkFormData.fromMap(this);
  }
}
