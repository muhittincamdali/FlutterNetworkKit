import 'dart:convert';

/// Parses HTTP response data into typed objects.
///
/// The [ResponseParser] provides utilities for parsing JSON responses
/// into domain models with error handling.
///
/// Example:
/// ```dart
/// final parser = ResponseParser<User>(
///   decoder: (json) => User.fromJson(json as Map<String, dynamic>),
/// );
///
/// final user = parser.parse(responseData);
/// ```
class ResponseParser<T> {
  /// Creates a new [ResponseParser] with the given decoder.
  const ResponseParser({
    required this.decoder,
    this.listDecoder,
  });

  /// The function to decode a single object.
  final T Function(dynamic json) decoder;

  /// The function to decode a list of objects.
  final List<T> Function(dynamic json)? listDecoder;

  /// Parses the data into type T.
  T parse(dynamic data) {
    if (data is String) {
      data = json.decode(data);
    }
    return decoder(data);
  }

  /// Parses the data into type T, returning null on error.
  T? tryParse(dynamic data) {
    try {
      return parse(data);
    } catch (_) {
      return null;
    }
  }

  /// Parses the data into a list of type T.
  List<T> parseList(dynamic data) {
    if (data is String) {
      data = json.decode(data);
    }

    if (listDecoder != null) {
      return listDecoder!(data);
    }

    if (data is List) {
      return data.map((item) => decoder(item)).toList();
    }

    throw FormatException('Expected list but got ${data.runtimeType}');
  }

  /// Parses the data into a list of type T, returning empty list on error.
  List<T> tryParseList(dynamic data) {
    try {
      return parseList(data);
    } catch (_) {
      return [];
    }
  }

  /// Parses paginated response data.
  PaginatedResponse<T> parsePaginated(
    dynamic data, {
    String dataKey = 'data',
    String totalKey = 'total',
    String pageKey = 'page',
    String perPageKey = 'per_page',
  }) {
    if (data is String) {
      data = json.decode(data);
    }

    if (data is! Map<String, dynamic>) {
      throw FormatException('Expected map but got ${data.runtimeType}');
    }

    final items = parseList(data[dataKey]);
    final total = data[totalKey] as int? ?? items.length;
    final page = data[pageKey] as int? ?? 1;
    final perPage = data[perPageKey] as int? ?? items.length;

    return PaginatedResponse<T>(
      items: items,
      total: total,
      page: page,
      perPage: perPage,
    );
  }
}

/// A paginated response containing a list of items.
class PaginatedResponse<T> {
  /// Creates a new [PaginatedResponse].
  const PaginatedResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.perPage,
  });

  /// The list of items in this page.
  final List<T> items;

  /// The total number of items across all pages.
  final int total;

  /// The current page number.
  final int page;

  /// The number of items per page.
  final int perPage;

  /// The total number of pages.
  int get totalPages => (total / perPage).ceil();

  /// Whether there are more pages.
  bool get hasMore => page < totalPages;

  /// Whether this is the first page.
  bool get isFirst => page == 1;

  /// Whether this is the last page.
  bool get isLast => page >= totalPages;

  /// Maps the items to a new type.
  PaginatedResponse<R> map<R>(R Function(T item) mapper) {
    return PaginatedResponse<R>(
      items: items.map(mapper).toList(),
      total: total,
      page: page,
      perPage: perPage,
    );
  }

  @override
  String toString() {
    return 'PaginatedResponse('
        'items: ${items.length}, '
        'total: $total, '
        'page: $page/$totalPages'
        ')';
  }
}

/// Factory class for creating response parsers.
class ResponseParserFactory {
  const ResponseParserFactory._();

  /// Creates a parser for a single object.
  static ResponseParser<T> object<T>(T Function(dynamic) decoder) {
    return ResponseParser<T>(decoder: decoder);
  }

  /// Creates a parser for JSON maps.
  static ResponseParser<Map<String, dynamic>> jsonMap() {
    return ResponseParser<Map<String, dynamic>>(
      decoder: (data) => data as Map<String, dynamic>,
    );
  }

  /// Creates a parser for JSON lists.
  static ResponseParser<List<dynamic>> jsonList() {
    return ResponseParser<List<dynamic>>(
      decoder: (data) => data as List<dynamic>,
    );
  }

  /// Creates a parser for strings.
  static ResponseParser<String> string() {
    return ResponseParser<String>(
      decoder: (data) => data.toString(),
    );
  }

  /// Creates a parser for integers.
  static ResponseParser<int> integer() {
    return ResponseParser<int>(
      decoder: (data) => data is int ? data : int.parse(data.toString()),
    );
  }

  /// Creates a parser for doubles.
  static ResponseParser<double> decimal() {
    return ResponseParser<double>(
      decoder: (data) => data is double ? data : double.parse(data.toString()),
    );
  }

  /// Creates a parser for booleans.
  static ResponseParser<bool> boolean() {
    return ResponseParser<bool>(
      decoder: (data) {
        if (data is bool) return data;
        if (data is int) return data != 0;
        if (data is String) {
          return data.toLowerCase() == 'true' || data == '1';
        }
        return false;
      },
    );
  }
}

/// Extension for parsing responses with common types.
extension ResponseDataParsing on dynamic {
  /// Parses as a map.
  Map<String, dynamic> asMap() {
    if (this is String) {
      return json.decode(this as String) as Map<String, dynamic>;
    }
    return this as Map<String, dynamic>;
  }

  /// Parses as a list.
  List<dynamic> asList() {
    if (this is String) {
      return json.decode(this as String) as List<dynamic>;
    }
    return this as List<dynamic>;
  }

  /// Parses as a typed list.
  List<T> asTypedList<T>(T Function(dynamic) decoder) {
    final list = asList();
    return list.map(decoder).toList();
  }

  /// Safely gets a value from a map.
  T? getValue<T>(String key) {
    if (this is Map<String, dynamic>) {
      return (this as Map<String, dynamic>)[key] as T?;
    }
    return null;
  }

  /// Gets a nested value using dot notation.
  T? getNestedValue<T>(String path) {
    final keys = path.split('.');
    dynamic current = this;

    for (final key in keys) {
      if (current is Map<String, dynamic>) {
        current = current[key];
      } else {
        return null;
      }
    }

    return current as T?;
  }
}
