import 'graphql_client.dart';

/// Represents a GraphQL query operation.
///
/// Example:
/// ```dart
/// final query = GraphQLQuery(
///   query: '''
///     query GetUsers(\$limit: Int) {
///       users(limit: \$limit) {
///         id
///         name
///         email
///       }
///     }
///   ''',
///   variables: {'limit': 10},
///   operationName: 'GetUsers',
/// );
/// ```
class GraphQLQuery implements GraphQLOperation {
  /// Creates a new [GraphQLQuery].
  const GraphQLQuery({
    required this.query,
    this.variables,
    this.operationName,
  });

  /// Creates a query from a document string.
  factory GraphQLQuery.document(String document, {
    Map<String, dynamic>? variables,
  }) {
    final operationName = _extractOperationName(document);
    return GraphQLQuery(
      query: document,
      variables: variables,
      operationName: operationName,
    );
  }

  /// The GraphQL query string.
  final String query;

  /// Variables for the query.
  final Map<String, dynamic>? variables;

  /// The operation name (for documents with multiple operations).
  final String? operationName;

  @override
  Map<String, dynamic> toRequestBody() {
    return {
      'query': query,
      if (variables != null && variables!.isNotEmpty) 'variables': variables,
      if (operationName != null) 'operationName': operationName,
    };
  }

  /// Creates a copy with updated variables.
  GraphQLQuery withVariables(Map<String, dynamic> variables) {
    return GraphQLQuery(
      query: query,
      variables: {...?this.variables, ...variables},
      operationName: operationName,
    );
  }

  /// Creates a copy with a specific variable set.
  GraphQLQuery setVariable(String name, dynamic value) {
    return GraphQLQuery(
      query: query,
      variables: {...?variables, name: value},
      operationName: operationName,
    );
  }

  @override
  String toString() {
    return 'GraphQLQuery('
        'operationName: $operationName, '
        'variables: $variables'
        ')';
  }

  static String? _extractOperationName(String document) {
    final regex = RegExp(r'query\s+(\w+)');
    final match = regex.firstMatch(document);
    return match?.group(1);
  }
}

/// Builder for creating GraphQL queries.
class GraphQLQueryBuilder {
  String? _query;
  String? _operationName;
  final Map<String, dynamic> _variables = {};
  final List<String> _fields = [];
  String? _alias;

  /// Sets the query string.
  GraphQLQueryBuilder query(String query) {
    _query = query;
    return this;
  }

  /// Sets the operation name.
  GraphQLQueryBuilder operationName(String name) {
    _operationName = name;
    return this;
  }

  /// Adds a variable.
  GraphQLQueryBuilder variable(String name, dynamic value) {
    _variables[name] = value;
    return this;
  }

  /// Adds multiple variables.
  GraphQLQueryBuilder variables(Map<String, dynamic> variables) {
    _variables.addAll(variables);
    return this;
  }

  /// Sets an alias for the query.
  GraphQLQueryBuilder alias(String alias) {
    _alias = alias;
    return this;
  }

  /// Adds a field to select.
  GraphQLQueryBuilder field(String name) {
    _fields.add(name);
    return this;
  }

  /// Adds multiple fields to select.
  GraphQLQueryBuilder fields(List<String> names) {
    _fields.addAll(names);
    return this;
  }

  /// Builds the query.
  GraphQLQuery build() {
    if (_query == null) {
      throw StateError('Query string must be set');
    }

    return GraphQLQuery(
      query: _query!,
      variables: _variables.isNotEmpty ? _variables : null,
      operationName: _operationName,
    );
  }
}

/// Predefined GraphQL query fragments.
class GraphQLFragments {
  GraphQLFragments._();

  /// Creates a pagination fragment.
  static String pagination({
    List<String> nodeFields = const ['id'],
    bool includePageInfo = true,
  }) {
    final nodeFieldsStr = nodeFields.join('\n        ');
    return '''
      edges {
        cursor
        node {
          $nodeFieldsStr
        }
      }
      ${includePageInfo ? 'pageInfo { hasNextPage hasPreviousPage startCursor endCursor }' : ''}
    ''';
  }

  /// Creates a user fragment.
  static const String user = '''
    fragment UserFields on User {
      id
      username
      email
      createdAt
      updatedAt
    }
  ''';

  /// Creates a timestamp fragment.
  static const String timestamps = '''
    fragment Timestamps on Node {
      createdAt
      updatedAt
    }
  ''';
}

/// Extension methods for queries.
extension GraphQLQueryExtension on GraphQLQuery {
  /// Adds pagination variables.
  GraphQLQuery withPagination({
    int? first,
    int? last,
    String? after,
    String? before,
  }) {
    return withVariables({
      if (first != null) 'first': first,
      if (last != null) 'last': last,
      if (after != null) 'after': after,
      if (before != null) 'before': before,
    });
  }

  /// Adds a filter variable.
  GraphQLQuery withFilter(Map<String, dynamic> filter) {
    return setVariable('filter', filter);
  }

  /// Adds a sort variable.
  GraphQLQuery withSort(String field, {bool descending = false}) {
    return setVariable('sort', {
      'field': field,
      'direction': descending ? 'DESC' : 'ASC',
    });
  }
}

/// Common GraphQL query templates.
class GraphQLQueryTemplates {
  GraphQLQueryTemplates._();

  /// Creates a list query template.
  static GraphQLQuery list(
    String typeName, {
    List<String> fields = const ['id'],
    int? limit,
    int? offset,
  }) {
    final fieldStr = fields.join('\n      ');
    return GraphQLQuery(
      query: '''
        query List$typeName(\$limit: Int, \$offset: Int) {
          ${typeName.toLowerCase()}s(limit: \$limit, offset: \$offset) {
            $fieldStr
          }
        }
      ''',
      variables: {
        if (limit != null) 'limit': limit,
        if (offset != null) 'offset': offset,
      },
      operationName: 'List$typeName',
    );
  }

  /// Creates a get-by-ID query template.
  static GraphQLQuery getById(
    String typeName, {
    required String id,
    List<String> fields = const ['id'],
  }) {
    final fieldStr = fields.join('\n      ');
    return GraphQLQuery(
      query: '''
        query Get$typeName(\$id: ID!) {
          ${typeName.toLowerCase()}(id: \$id) {
            $fieldStr
          }
        }
      ''',
      variables: {'id': id},
      operationName: 'Get$typeName',
    );
  }

  /// Creates a search query template.
  static GraphQLQuery search(
    String typeName, {
    required String searchTerm,
    List<String> fields = const ['id'],
    int? limit,
  }) {
    final fieldStr = fields.join('\n      ');
    return GraphQLQuery(
      query: '''
        query Search$typeName(\$query: String!, \$limit: Int) {
          search${typeName}s(query: \$query, limit: \$limit) {
            $fieldStr
          }
        }
      ''',
      variables: {
        'query': searchTerm,
        if (limit != null) 'limit': limit,
      },
      operationName: 'Search$typeName',
    );
  }
}
