/// Builder for constructing URLs with path parameters and query strings.
///
/// Example:
/// ```dart
/// final url = UrlBuilder('https://api.example.com')
///     .path('/users')
///     .pathParam('id', '123')
///     .query('include', 'profile')
///     .query('sort', 'name')
///     .build();
///
/// // Result: https://api.example.com/users/123?include=profile&sort=name
/// ```
class UrlBuilder {
  /// Creates a new [UrlBuilder] with the given base URL.
  UrlBuilder([this._baseUrl = '']);

  String _baseUrl;
  final List<String> _pathSegments = [];
  final Map<String, List<String>> _queryParams = {};
  String? _fragment;

  /// Sets the base URL.
  UrlBuilder baseUrl(String url) {
    _baseUrl = url;
    return this;
  }

  /// Appends a path segment.
  UrlBuilder path(String segment) {
    if (segment.startsWith('/')) {
      segment = segment.substring(1);
    }
    if (segment.endsWith('/')) {
      segment = segment.substring(0, segment.length - 1);
    }
    _pathSegments.add(segment);
    return this;
  }

  /// Appends a path parameter (replaces {param} placeholders).
  UrlBuilder pathParam(String name, String value) {
    // Store for later substitution
    _pathSegments.add('{$name:$value}');
    return this;
  }

  /// Appends multiple path segments.
  UrlBuilder paths(List<String> segments) {
    for (final segment in segments) {
      path(segment);
    }
    return this;
  }

  /// Adds a query parameter.
  UrlBuilder query(String name, dynamic value) {
    if (value != null) {
      _queryParams.putIfAbsent(name, () => []).add(value.toString());
    }
    return this;
  }

  /// Adds multiple values for a query parameter.
  UrlBuilder queryAll(String name, List<dynamic> values) {
    for (final value in values) {
      query(name, value);
    }
    return this;
  }

  /// Adds multiple query parameters from a map.
  UrlBuilder queryMap(Map<String, dynamic> params) {
    params.forEach((key, value) {
      if (value is List) {
        queryAll(key, value);
      } else {
        query(key, value);
      }
    });
    return this;
  }

  /// Adds a query parameter only if the condition is true.
  UrlBuilder queryIf(bool condition, String name, dynamic value) {
    if (condition) {
      query(name, value);
    }
    return this;
  }

  /// Adds a query parameter only if the value is not null.
  UrlBuilder queryIfNotNull(String name, dynamic value) {
    return queryIf(value != null, name, value);
  }

  /// Sets the URL fragment (hash).
  UrlBuilder fragment(String fragment) {
    _fragment = fragment;
    return this;
  }

  /// Builds the complete URL string.
  String build() {
    final buffer = StringBuffer(_baseUrl);

    // Build path
    if (_pathSegments.isNotEmpty) {
      if (!_baseUrl.endsWith('/')) {
        buffer.write('/');
      }

      final resolvedSegments = _pathSegments.map((segment) {
        // Handle path parameters
        if (segment.startsWith('{') && segment.contains(':')) {
          final value = segment.substring(
            segment.indexOf(':') + 1,
            segment.length - 1,
          );
          return Uri.encodeComponent(value);
        }
        return segment;
      });

      buffer.write(resolvedSegments.join('/'));
    }

    // Build query string
    if (_queryParams.isNotEmpty) {
      buffer.write('?');
      final queryParts = <String>[];

      for (final entry in _queryParams.entries) {
        for (final value in entry.value) {
          queryParts.add(
            '${Uri.encodeQueryComponent(entry.key)}='
            '${Uri.encodeQueryComponent(value)}',
          );
        }
      }

      buffer.write(queryParts.join('&'));
    }

    // Add fragment
    if (_fragment != null) {
      buffer.write('#$_fragment');
    }

    return buffer.toString();
  }

  /// Resets the builder to its initial state.
  UrlBuilder reset() {
    _baseUrl = '';
    _pathSegments.clear();
    _queryParams.clear();
    _fragment = null;
    return this;
  }

  /// Creates a copy of this builder.
  UrlBuilder copy() {
    final copy = UrlBuilder(_baseUrl);
    copy._pathSegments.addAll(_pathSegments);
    _queryParams.forEach((key, values) {
      copy._queryParams[key] = List.from(values);
    });
    copy._fragment = _fragment;
    return copy;
  }

  @override
  String toString() => build();
}

/// Extension for parsing URLs.
extension UrlParsing on String {
  /// Parses this string as a URL and returns its components.
  UrlComponents parseUrl() {
    final uri = Uri.parse(this);
    return UrlComponents(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.port,
      path: uri.path,
      queryParameters: uri.queryParametersAll,
      fragment: uri.fragment.isEmpty ? null : uri.fragment,
    );
  }

  /// Creates a UrlBuilder from this URL string.
  UrlBuilder toUrlBuilder() {
    final uri = Uri.parse(this);
    final builder = UrlBuilder('${uri.scheme}://${uri.host}')
        .path(uri.path);

    uri.queryParametersAll.forEach((key, values) {
      builder.queryAll(key, values);
    });

    if (uri.fragment.isNotEmpty) {
      builder.fragment(uri.fragment);
    }

    return builder;
  }
}

/// Parsed URL components.
class UrlComponents {
  /// Creates new [UrlComponents].
  const UrlComponents({
    this.scheme,
    this.host,
    this.port,
    this.path,
    this.queryParameters,
    this.fragment,
  });

  /// The URL scheme (http, https, etc.).
  final String? scheme;

  /// The host name.
  final String? host;

  /// The port number.
  final int? port;

  /// The URL path.
  final String? path;

  /// Query parameters.
  final Map<String, List<String>>? queryParameters;

  /// The URL fragment.
  final String? fragment;

  /// Returns the base URL (scheme + host + port).
  String? get baseUrl {
    if (scheme == null || host == null) return null;
    final portPart = port != null && port != 80 && port != 443
        ? ':$port'
        : '';
    return '$scheme://$host$portPart';
  }

  /// Returns a single query parameter value.
  String? getQueryParam(String name) {
    return queryParameters?[name]?.firstOrNull;
  }

  /// Returns all values for a query parameter.
  List<String>? getQueryParams(String name) {
    return queryParameters?[name];
  }

  @override
  String toString() {
    return 'UrlComponents('
        'scheme: $scheme, '
        'host: $host, '
        'path: $path'
        ')';
  }
}

/// Template for URL paths with placeholders.
class UrlTemplate {
  /// Creates a new [UrlTemplate].
  const UrlTemplate(this.template);

  /// The template string with {param} placeholders.
  final String template;

  /// Substitutes parameters in the template.
  String substitute(Map<String, dynamic> params) {
    var result = template;
    for (final entry in params.entries) {
      result = result.replaceAll(
        '{${entry.key}}',
        Uri.encodeComponent(entry.value.toString()),
      );
    }
    return result;
  }

  /// Extracts parameter names from the template.
  List<String> get parameterNames {
    final regex = RegExp(r'\{(\w+)\}');
    return regex.allMatches(template).map((m) => m.group(1)!).toList();
  }

  /// Returns true if all parameters are provided.
  bool hasAllParameters(Map<String, dynamic> params) {
    return parameterNames.every((name) => params.containsKey(name));
  }

  @override
  String toString() => 'UrlTemplate($template)';
}
