import 'dart:convert';

/// Generator for creating Dart model classes from JSON samples.
///
/// This generator analyzes JSON data and generates corresponding
/// Dart model classes with type-safe fields.
///
/// Example:
/// ```dart
/// final generator = ModelGenerator();
///
/// final json = {'id': 1, 'name': 'John', 'email': 'john@example.com'};
/// final code = generator.generate('User', json);
/// print(code);
/// ```
class ModelGenerator {
  /// Creates a new [ModelGenerator].
  ModelGenerator({
    this.nullSafety = true,
    this.useJsonSerializable = true,
    this.useFinalFields = true,
    this.generateCopyWith = true,
    this.generateToString = true,
    this.generateEquality = true,
    this.dateTimeFormat = 'DateTime',
  });

  /// Whether to generate null-safe code.
  final bool nullSafety;

  /// Whether to use json_serializable annotations.
  final bool useJsonSerializable;

  /// Whether to use final fields.
  final bool useFinalFields;

  /// Whether to generate copyWith method.
  final bool generateCopyWith;

  /// Whether to generate toString method.
  final bool generateToString;

  /// Whether to generate equality operators.
  final bool generateEquality;

  /// The type to use for date/time fields.
  final String dateTimeFormat;

  final Set<String> _generatedClasses = {};
  final List<String> _nestedClasses = [];

  /// Generates a Dart class from a JSON sample.
  String generate(String className, dynamic json) {
    _generatedClasses.clear();
    _nestedClasses.clear();

    final mainClass = _generateClass(className, json as Map<String, dynamic>);

    final buffer = StringBuffer();

    // File header
    buffer.writeln('// Generated model class');
    buffer.writeln('// Source: JSON sample');
    buffer.writeln();

    // Imports
    if (useJsonSerializable) {
      buffer.writeln("import 'package:json_annotation/json_annotation.dart';");
      buffer.writeln();
      buffer.writeln("part '${_toSnakeCase(className)}.g.dart';");
      buffer.writeln();
    }

    // Main class
    buffer.writeln(mainClass);

    // Nested classes
    for (final nested in _nestedClasses) {
      buffer.writeln();
      buffer.writeln(nested);
    }

    return buffer.toString();
  }

  /// Generates multiple classes from a JSON object with multiple types.
  Map<String, String> generateMultiple(Map<String, dynamic> schemas) {
    final results = <String, String>{};

    for (final entry in schemas.entries) {
      _generatedClasses.clear();
      _nestedClasses.clear();

      final code = generate(entry.key, entry.value);
      results[entry.key] = code;
    }

    return results;
  }

  String _generateClass(String className, Map<String, dynamic> json) {
    if (_generatedClasses.contains(className)) {
      return '';
    }
    _generatedClasses.add(className);

    final buffer = StringBuffer();
    final fields = <_FieldInfo>[];

    // Analyze fields
    for (final entry in json.entries) {
      final fieldInfo = _analyzeField(entry.key, entry.value, className);
      fields.add(fieldInfo);
    }

    // Class annotation
    if (useJsonSerializable) {
      buffer.writeln('@JsonSerializable()');
    }

    // Class declaration
    buffer.writeln('class $className {');

    // Constructor
    buffer.writeln('  /// Creates a new [$className].');
    buffer.write('  const $className({');
    for (final field in fields) {
      if (field.required) {
        buffer.write('required this.${field.dartName}, ');
      } else {
        buffer.write('this.${field.dartName}, ');
      }
    }
    buffer.writeln('});');
    buffer.writeln();

    // fromJson factory
    if (useJsonSerializable) {
      buffer.writeln('  /// Creates a [$className] from JSON.');
      buffer.writeln('  factory $className.fromJson(Map<String, dynamic> json) =>');
      buffer.writeln('      _\$${className}FromJson(json);');
      buffer.writeln();
    } else {
      _generateManualFromJson(buffer, className, fields);
    }

    // Fields
    for (final field in fields) {
      if (field.jsonName != field.dartName && useJsonSerializable) {
        buffer.writeln("  @JsonKey(name: '${field.jsonName}')");
      }
      final modifier = useFinalFields ? 'final ' : '';
      final nullableSuffix = !field.required && nullSafety ? '?' : '';
      buffer.writeln('  $modifier${field.dartType}$nullableSuffix ${field.dartName};');
      buffer.writeln();
    }

    // toJson method
    if (useJsonSerializable) {
      buffer.writeln('  /// Converts this [$className] to JSON.');
      buffer.writeln('  Map<String, dynamic> toJson() => _\$${className}ToJson(this);');
    } else {
      _generateManualToJson(buffer, className, fields);
    }

    // copyWith method
    if (generateCopyWith) {
      buffer.writeln();
      _generateCopyWith(buffer, className, fields);
    }

    // toString method
    if (generateToString) {
      buffer.writeln();
      _generateToString(buffer, className, fields);
    }

    // Equality operators
    if (generateEquality) {
      buffer.writeln();
      _generateEquality(buffer, className, fields);
    }

    buffer.writeln('}');

    return buffer.toString();
  }

  _FieldInfo _analyzeField(String key, dynamic value, String parentClass) {
    final dartName = _toDartName(key);
    final dartType = _inferType(value, parentClass, key);

    return _FieldInfo(
      jsonName: key,
      dartName: dartName,
      dartType: dartType,
      required: value != null,
      isNested: value is Map,
      isList: value is List,
    );
  }

  String _inferType(dynamic value, String parentClass, String fieldName) {
    if (value == null) {
      return 'dynamic';
    }

    if (value is bool) {
      return 'bool';
    }

    if (value is int) {
      return 'int';
    }

    if (value is double) {
      return 'double';
    }

    if (value is String) {
      // Check for common date patterns
      if (_isDateTimeString(value)) {
        return dateTimeFormat;
      }
      return 'String';
    }

    if (value is List) {
      if (value.isEmpty) {
        return 'List<dynamic>';
      }
      final itemType = _inferType(value.first, parentClass, fieldName);
      return 'List<$itemType>';
    }

    if (value is Map<String, dynamic>) {
      // Generate nested class
      final nestedClassName = _toClassName(fieldName);
      final nestedClass = _generateClass(nestedClassName, value);
      if (nestedClass.isNotEmpty) {
        _nestedClasses.add(nestedClass);
      }
      return nestedClassName;
    }

    return 'dynamic';
  }

  bool _isDateTimeString(String value) {
    // Check for ISO 8601 format
    final iso8601 = RegExp(r'^\d{4}-\d{2}-\d{2}');
    return iso8601.hasMatch(value);
  }

  void _generateManualFromJson(
    StringBuffer buffer,
    String className,
    List<_FieldInfo> fields,
  ) {
    buffer.writeln('  /// Creates a [$className] from JSON.');
    buffer.writeln('  factory $className.fromJson(Map<String, dynamic> json) {');
    buffer.writeln('    return $className(');
    for (final field in fields) {
      if (field.isNested) {
        buffer.writeln("      ${field.dartName}: ${field.dartType}.fromJson(json['${field.jsonName}'] as Map<String, dynamic>),");
      } else if (field.isList && !field.dartType.contains('dynamic')) {
        final itemType = field.dartType.replaceAll('List<', '').replaceAll('>', '');
        if (_isPrimitive(itemType)) {
          buffer.writeln("      ${field.dartName}: (json['${field.jsonName}'] as List).cast<$itemType>(),");
        } else {
          buffer.writeln("      ${field.dartName}: (json['${field.jsonName}'] as List).map((e) => $itemType.fromJson(e as Map<String, dynamic>)).toList(),");
        }
      } else {
        buffer.writeln("      ${field.dartName}: json['${field.jsonName}'] as ${field.dartType}${field.required ? '' : '?'},");
      }
    }
    buffer.writeln('    );');
    buffer.writeln('  }');
    buffer.writeln();
  }

  void _generateManualToJson(
    StringBuffer buffer,
    String className,
    List<_FieldInfo> fields,
  ) {
    buffer.writeln();
    buffer.writeln('  /// Converts this [$className] to JSON.');
    buffer.writeln('  Map<String, dynamic> toJson() {');
    buffer.writeln('    return {');
    for (final field in fields) {
      if (field.isNested) {
        buffer.writeln("      '${field.jsonName}': ${field.dartName}${field.required ? '' : '?'}.toJson(),");
      } else if (field.isList && !field.dartType.contains('dynamic') && !_isPrimitive(_getListItemType(field.dartType))) {
        buffer.writeln("      '${field.jsonName}': ${field.dartName}${field.required ? '' : '?'}.map((e) => e.toJson()).toList(),");
      } else {
        buffer.writeln("      '${field.jsonName}': ${field.dartName},");
      }
    }
    buffer.writeln('    };');
    buffer.writeln('  }');
  }

  void _generateCopyWith(
    StringBuffer buffer,
    String className,
    List<_FieldInfo> fields,
  ) {
    buffer.writeln('  /// Creates a copy with the specified overrides.');
    buffer.write('  $className copyWith({');
    for (final field in fields) {
      buffer.write('${field.dartType}? ${field.dartName}, ');
    }
    buffer.writeln('}) {');
    buffer.write('    return $className(');
    for (final field in fields) {
      buffer.write('${field.dartName}: ${field.dartName} ?? this.${field.dartName}, ');
    }
    buffer.writeln(');');
    buffer.writeln('  }');
  }

  void _generateToString(
    StringBuffer buffer,
    String className,
    List<_FieldInfo> fields,
  ) {
    buffer.writeln('  @override');
    buffer.write("  String toString() => '$className(");
    for (var i = 0; i < fields.length; i++) {
      final field = fields[i];
      buffer.write('${field.dartName}: \$${field.dartName}');
      if (i < fields.length - 1) buffer.write(', ');
    }
    buffer.writeln(")';");
  }

  void _generateEquality(
    StringBuffer buffer,
    String className,
    List<_FieldInfo> fields,
  ) {
    buffer.writeln('  @override');
    buffer.writeln('  bool operator ==(Object other) {');
    buffer.writeln('    if (identical(this, other)) return true;');
    buffer.writeln('    return other is $className &&');
    for (var i = 0; i < fields.length; i++) {
      final field = fields[i];
      buffer.write('        other.${field.dartName} == ${field.dartName}');
      if (i < fields.length - 1) {
        buffer.writeln(' &&');
      } else {
        buffer.writeln(';');
      }
    }
    buffer.writeln('  }');
    buffer.writeln();
    buffer.writeln('  @override');
    buffer.write('  int get hashCode => Object.hash(');
    buffer.write(fields.map((f) => f.dartName).join(', '));
    buffer.writeln(');');
  }

  String _toDartName(String jsonKey) {
    // Convert snake_case or kebab-case to camelCase
    return jsonKey
        .replaceAllMapped(
          RegExp(r'[_-](\w)'),
          (m) => m.group(1)!.toUpperCase(),
        );
  }

  String _toClassName(String fieldName) {
    final name = _toDartName(fieldName);
    return name[0].toUpperCase() + name.substring(1);
  }

  String _toSnakeCase(String input) {
    return input
        .replaceAllMapped(RegExp(r'[A-Z]'), (m) => '_${m.group(0)!.toLowerCase()}')
        .replaceFirst('_', '');
  }

  bool _isPrimitive(String type) {
    return ['String', 'int', 'double', 'bool', 'num', 'dynamic'].contains(type);
  }

  String _getListItemType(String listType) {
    return listType.replaceAll('List<', '').replaceAll('>', '');
  }
}

class _FieldInfo {
  const _FieldInfo({
    required this.jsonName,
    required this.dartName,
    required this.dartType,
    required this.required,
    required this.isNested,
    required this.isList,
  });

  final String jsonName;
  final String dartName;
  final String dartType;
  final bool required;
  final bool isNested;
  final bool isList;
}
