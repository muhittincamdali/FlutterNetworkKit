import 'dart:convert';

/// Utilities for working with JSON data.
///
/// Provides safe parsing, deep access, and transformation utilities.
///
/// Example:
/// ```dart
/// final json = {'user': {'name': 'John', 'age': 30}};
///
/// final name = JsonUtils.getPath<String>(json, 'user.name');
/// print(name); // John
///
/// final age = JsonUtils.getPath<int>(json, 'user.age');
/// print(age); // 30
/// ```
class JsonUtils {
  JsonUtils._();

  /// Safely parses a JSON string.
  static Map<String, Object?>? tryParse(String source) {
    try {
      final result = json.decode(source);
      if (result is Map<String, Object?>) {
        return result;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Parses a JSON string to a list.
  static List<Object?>? tryParseList(String source) {
    try {
      final result = json.decode(source);
      if (result is List) {
        return result;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Gets a value from a nested path using dot notation.
  static T? getPath<T>(Map<String, Object?> json, String path) {
    final keys = path.split('.');
    Object? current = json;

    for (final key in keys) {
      if (current is Map<String, Object?>) {
        current = current[key];
      } else if (current is List) {
        final index = int.tryParse(key);
        if (index != null && index >= 0 && index < current.length) {
          current = current[index];
        } else {
          return null;
        }
      } else {
        return null;
      }
    }

    return current as T?;
  }

  /// Sets a value at a nested path.
  static void setPath(
    Map<String, Object?> json,
    String path,
    Object? value,
  ) {
    final keys = path.split('.');
    Object? current = json;

    for (var i = 0; i < keys.length - 1; i++) {
      final key = keys[i];

      if (current is Map<String, Object?>) {
        if (!current.containsKey(key)) {
          current[key] = <String, Object?>{};
        }
        current = current[key];
      } else {
        return;
      }
    }

    if (current is Map<String, Object?>) {
      current[keys.last] = value;
    }
  }

  /// Removes a value at a nested path.
  static bool removePath(Map<String, Object?> json, String path) {
    final keys = path.split('.');
    Object? current = json;

    for (var i = 0; i < keys.length - 1; i++) {
      final key = keys[i];
      if (current is Map<String, Object?>) {
        current = current[key];
      } else {
        return false;
      }
    }

    if (current is Map<String, Object?>) {
      return current.remove(keys.last) != null;
    }
    return false;
  }

  /// Deeply merges two JSON objects.
  static Map<String, Object?> merge(
    Map<String, Object?> base,
    Map<String, Object?> override,
  ) {
    final result = Map<String, Object?>.from(base);

    for (final entry in override.entries) {
      if (result.containsKey(entry.key) &&
          result[entry.key] is Map<String, Object?> &&
          entry.value is Map<String, Object?>) {
        result[entry.key] = merge(
          result[entry.key] as Map<String, Object?>,
          entry.value as Map<String, Object?>,
        );
      } else {
        result[entry.key] = entry.value;
      }
    }

    return result;
  }

  /// Flattens a nested JSON object into dot-notation keys.
  static Map<String, Object?> flatten(
    Map<String, Object?> json, {
    String prefix = '',
  }) {
    final result = <String, Object?>{};

    for (final entry in json.entries) {
      final key = prefix.isEmpty ? entry.key : '$prefix.${entry.key}';

      if (entry.value is Map<String, Object?>) {
        result.addAll(flatten(
          entry.value as Map<String, Object?>,
          prefix: key,
        ));
      } else if (entry.value is List) {
        for (var i = 0; i < (entry.value as List).length; i++) {
          final item = (entry.value as List)[i];
          if (item is Map<String, Object?>) {
            result.addAll(flatten(item, prefix: '$key.$i'));
          } else {
            result['$key.$i'] = item;
          }
        }
      } else {
        result[key] = entry.value;
      }
    }

    return result;
  }

  /// Unflattens a dot-notation map back to nested structure.
  static Map<String, Object?> unflatten(Map<String, Object?> flat) {
    final result = <String, Object?>{};

    for (final entry in flat.entries) {
      setPath(result, entry.key, entry.value);
    }

    return result;
  }

  /// Converts all keys to camelCase.
  static Map<String, Object?> keysToCamelCase(Map<String, Object?> json) {
    return json.map((key, value) {
      final camelKey = _toCamelCase(key);
      final newValue = value is Map<String, Object?>
          ? keysToCamelCase(value)
          : value is List
              ? value.map((e) => e is Map<String, Object?> ? keysToCamelCase(e) : e).toList()
              : value;
      return MapEntry(camelKey, newValue);
    });
  }

  /// Converts all keys to snake_case.
  static Map<String, Object?> keysToSnakeCase(Map<String, Object?> json) {
    return json.map((key, value) {
      final snakeKey = _toSnakeCase(key);
      final newValue = value is Map<String, Object?>
          ? keysToSnakeCase(value)
          : value is List
              ? value.map((e) => e is Map<String, Object?> ? keysToSnakeCase(e) : e).toList()
              : value;
      return MapEntry(snakeKey, newValue);
    });
  }

  /// Removes null values from a map.
  static Map<String, Object?> removeNulls(Map<String, Object?> json) {
    final result = <String, Object?>{};

    for (final entry in json.entries) {
      if (entry.value != null) {
        if (entry.value is Map<String, Object?>) {
          result[entry.key] = removeNulls(entry.value as Map<String, Object?>);
        } else {
          result[entry.key] = entry.value;
        }
      }
    }

    return result;
  }

  /// Filters a map to only include specified keys.
  static Map<String, Object?> pick(
    Map<String, Object?> json,
    List<String> keys,
  ) {
    return Map.fromEntries(
      json.entries.where((e) => keys.contains(e.key)),
    );
  }

  /// Filters a map to exclude specified keys.
  static Map<String, Object?> omit(
    Map<String, Object?> json,
    List<String> keys,
  ) {
    return Map.fromEntries(
      json.entries.where((e) => !keys.contains(e.key)),
    );
  }

  /// Deep clones a JSON object.
  static Map<String, Object?> deepClone(Map<String, Object?> json) {
    return json.decode(json.encode(json)) as Map<String, Object?>;
  }

  static String _toCamelCase(String input) {
    return input.replaceAllMapped(
      RegExp(r'[_-](\w)'),
      (m) => m.group(1)!.toUpperCase(),
    );
  }

  static String _toSnakeCase(String input) {
    return input
        .replaceAllMapped(
          RegExp(r'[A-Z]'),
          (m) => '_${m.group(0)!.toLowerCase()}',
        )
        .replaceFirst('_', '');
  }
}

/// Extension methods for JSON maps.
extension JsonMapExtension on Map<String, Object?> {
  /// Gets a value at a nested path.
  T? getPath<T>(String path) => JsonUtils.getPath<T>(this, path);

  /// Sets a value at a nested path.
  void setPath(String path, Object? value) => JsonUtils.setPath(this, path, value);

  /// Merges with another map.
  Map<String, Object?> merge(Map<String, Object?> other) =>
      JsonUtils.merge(this, other);

  /// Flattens to dot-notation keys.
  Map<String, Object?> flatten() => JsonUtils.flatten(this);

  /// Converts keys to camelCase.
  Map<String, Object?> keysToCamelCase() => JsonUtils.keysToCamelCase(this);

  /// Converts keys to snake_case.
  Map<String, Object?> keysToSnakeCase() => JsonUtils.keysToSnakeCase(this);

  /// Removes null values.
  Map<String, Object?> removeNulls() => JsonUtils.removeNulls(this);

  /// Picks specified keys.
  Map<String, Object?> pick(List<String> keys) => JsonUtils.pick(this, keys);

  /// Omits specified keys.
  Map<String, Object?> omit(List<String> keys) => JsonUtils.omit(this, keys);

  /// Safely gets a string value.
  String? getString(String key) => this[key] as String?;

  /// Safely gets an int value.
  int? getInt(String key) => this[key] as int?;

  /// Safely gets a double value.
  double? getDouble(String key) => this[key] as double?;

  /// Safely gets a bool value.
  bool? getBool(String key) => this[key] as bool?;

  /// Safely gets a list value.
  List<T>? getList<T>(String key) => (this[key] as List?)?.cast<T>();

  /// Safely gets a map value.
  Map<String, Object?>? getMap(String key) =>
      this[key] as Map<String, Object?>?;

  /// Pretty prints the JSON.
  String toPrettyString() {
    return const JsonEncoder.withIndent('  ').convert(this);
  }
}
