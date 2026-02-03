import 'dart:async';

import '../client/network_client.dart';
import '../response/response.dart';
import '../response/api_error.dart';
import 'graphql_query.dart';
import 'graphql_mutation.dart';

/// A GraphQL client built on top of NetworkClient.
///
/// This client provides a convenient way to execute GraphQL queries
/// and mutations with proper type handling and error handling.
///
/// Example:
/// ```dart
/// final client = GraphQLClient(
///   networkClient: networkClient,
///   endpoint: '/graphql',
/// );
///
/// final result = await client.query<User>(
///   GraphQLQuery(
///     query: '''
///       query GetUser(\$id: ID!) {
///         user(id: \$id) {
///           id
///           name
///           email
///         }
///       }
///     ''',
///     variables: {'id': '123'},
///   ),
///   decoder: (data) => User.fromJson(data['user']),
/// );
/// ```
class GraphQLClient {
  /// Creates a new [GraphQLClient].
  GraphQLClient({
    required this.networkClient,
    this.endpoint = '/graphql',
    this.defaultHeaders,
    this.onError,
  });

  /// The underlying network client.
  final NetworkClient networkClient;

  /// The GraphQL endpoint path.
  final String endpoint;

  /// Default headers for all GraphQL requests.
  final Map<String, String>? defaultHeaders;

  /// Called when an error occurs.
  final void Function(GraphQLError error)? onError;

  /// Executes a GraphQL query.
  ///
  /// [T] is the expected return type.
  /// [query] is the GraphQL query to execute.
  /// [decoder] is a function to parse the response data.
  Future<GraphQLResult<T>> query<T>(
    GraphQLQuery query, {
    T Function(Map<String, dynamic>)? decoder,
    Map<String, String>? headers,
  }) async {
    return _execute<T>(
      query.query,
      query.variables,
      query.operationName,
      decoder: decoder,
      headers: headers,
    );
  }

  /// Executes a GraphQL mutation.
  ///
  /// [T] is the expected return type.
  /// [mutation] is the GraphQL mutation to execute.
  /// [decoder] is a function to parse the response data.
  Future<GraphQLResult<T>> mutate<T>(
    GraphQLMutation mutation, {
    T Function(Map<String, dynamic>)? decoder,
    Map<String, String>? headers,
  }) async {
    return _execute<T>(
      mutation.mutation,
      mutation.variables,
      mutation.operationName,
      decoder: decoder,
      headers: headers,
    );
  }

  /// Executes a raw GraphQL operation.
  Future<GraphQLResult<T>> execute<T>(
    String document, {
    Map<String, dynamic>? variables,
    String? operationName,
    T Function(Map<String, dynamic>)? decoder,
    Map<String, String>? headers,
  }) async {
    return _execute<T>(
      document,
      variables,
      operationName,
      decoder: decoder,
      headers: headers,
    );
  }

  Future<GraphQLResult<T>> _execute<T>(
    String document,
    Map<String, dynamic>? variables,
    String? operationName, {
    T Function(Map<String, dynamic>)? decoder,
    Map<String, String>? headers,
  }) async {
    final body = <String, dynamic>{
      'query': document,
      if (variables != null && variables.isNotEmpty) 'variables': variables,
      if (operationName != null) 'operationName': operationName,
    };

    final mergedHeaders = <String, String>{
      'Content-Type': 'application/json',
      ...?defaultHeaders,
      ...?headers,
    };

    try {
      final response = await networkClient.post<Map<String, dynamic>>(
        endpoint,
        body: body,
        headers: mergedHeaders,
      );

      return _parseResponse<T>(response, decoder);
    } on ApiError catch (e) {
      final error = GraphQLError.fromApiError(e);
      onError?.call(error);
      return GraphQLResult<T>.error(error);
    }
  }

  GraphQLResult<T> _parseResponse<T>(
    NetworkResponse<Map<String, dynamic>> response,
    T Function(Map<String, dynamic>)? decoder,
  ) {
    final data = response.data;

    // Check for GraphQL errors
    if (data.containsKey('errors')) {
      final errors = (data['errors'] as List)
          .map((e) => GraphQLError.fromJson(e as Map<String, dynamic>))
          .toList();

      // If there's data alongside errors, return both
      if (data.containsKey('data') && data['data'] != null) {
        final resultData = data['data'] as Map<String, dynamic>;
        final parsedData = decoder != null ? decoder(resultData) : resultData as T;
        return GraphQLResult<T>.partial(parsedData, errors);
      }

      onError?.call(errors.first);
      return GraphQLResult<T>.errors(errors);
    }

    // Success case
    if (data.containsKey('data')) {
      final resultData = data['data'] as Map<String, dynamic>;
      final parsedData = decoder != null ? decoder(resultData) : resultData as T;
      return GraphQLResult<T>.success(parsedData);
    }

    // Unexpected response format
    return GraphQLResult<T>.error(
      GraphQLError(message: 'Invalid GraphQL response format'),
    );
  }

  /// Executes multiple queries in a single request.
  Future<List<GraphQLResult<dynamic>>> batch(
    List<GraphQLOperation> operations,
  ) async {
    final bodies = operations.map((op) => op.toRequestBody()).toList();

    try {
      final response = await networkClient.post<List<dynamic>>(
        endpoint,
        body: bodies,
        headers: {
          'Content-Type': 'application/json',
          ...?defaultHeaders,
        },
      );

      return response.data.map((item) {
        final data = item as Map<String, dynamic>;
        return _parseResponse<dynamic>(
          NetworkResponse(data: data, statusCode: response.statusCode),
          null,
        );
      }).toList();
    } on ApiError catch (e) {
      final error = GraphQLError.fromApiError(e);
      onError?.call(error);
      return operations.map((_) => GraphQLResult<dynamic>.error(error)).toList();
    }
  }

  /// Creates a query builder.
  GraphQLQueryBuilder queryBuilder() => GraphQLQueryBuilder();

  /// Creates a mutation builder.
  GraphQLMutationBuilder mutationBuilder() => GraphQLMutationBuilder();
}

/// Result of a GraphQL operation.
class GraphQLResult<T> {
  const GraphQLResult._({
    this.data,
    this.errors,
    required this.hasErrors,
  });

  /// Creates a successful result.
  factory GraphQLResult.success(T data) {
    return GraphQLResult._(data: data, hasErrors: false);
  }

  /// Creates an error result.
  factory GraphQLResult.error(GraphQLError error) {
    return GraphQLResult._(errors: [error], hasErrors: true);
  }

  /// Creates a result with multiple errors.
  factory GraphQLResult.errors(List<GraphQLError> errors) {
    return GraphQLResult._(errors: errors, hasErrors: true);
  }

  /// Creates a partial result with both data and errors.
  factory GraphQLResult.partial(T data, List<GraphQLError> errors) {
    return GraphQLResult._(data: data, errors: errors, hasErrors: true);
  }

  /// The response data.
  final T? data;

  /// The GraphQL errors.
  final List<GraphQLError>? errors;

  /// Whether the response contains errors.
  final bool hasErrors;

  /// Whether the operation was successful.
  bool get isSuccess => !hasErrors;

  /// Whether the response contains data.
  bool get hasData => data != null;

  /// Returns the data or throws if there's an error.
  T get dataOrThrow {
    if (data != null) return data!;
    if (errors != null && errors!.isNotEmpty) {
      throw errors!.first;
    }
    throw GraphQLError(message: 'No data available');
  }

  /// Returns the data or a default value.
  T dataOrElse(T defaultValue) => data ?? defaultValue;

  /// Maps the data to a new type.
  GraphQLResult<R> map<R>(R Function(T data) mapper) {
    if (data == null) {
      return GraphQLResult<R>._(
        errors: errors,
        hasErrors: hasErrors,
      );
    }
    return GraphQLResult<R>._(
      data: mapper(data!),
      errors: errors,
      hasErrors: hasErrors,
    );
  }

  @override
  String toString() {
    if (hasErrors) {
      return 'GraphQLResult.error(${errors?.map((e) => e.message).join(", ")})';
    }
    return 'GraphQLResult.success($data)';
  }
}

/// A GraphQL error.
class GraphQLError implements Exception {
  /// Creates a new [GraphQLError].
  const GraphQLError({
    required this.message,
    this.locations,
    this.path,
    this.extensions,
  });

  /// Creates a [GraphQLError] from JSON.
  factory GraphQLError.fromJson(Map<String, dynamic> json) {
    return GraphQLError(
      message: json['message'] as String? ?? 'Unknown error',
      locations: (json['locations'] as List?)
          ?.map((e) => GraphQLErrorLocation.fromJson(e as Map<String, dynamic>))
          .toList(),
      path: (json['path'] as List?)?.cast<String>(),
      extensions: json['extensions'] as Map<String, dynamic>?,
    );
  }

  /// Creates a [GraphQLError] from an [ApiError].
  factory GraphQLError.fromApiError(ApiError error) {
    return GraphQLError(
      message: error.message,
      extensions: {
        'statusCode': error.statusCode,
        if (error.errorCode != null) 'code': error.errorCode,
      },
    );
  }

  /// The error message.
  final String message;

  /// The source locations of the error.
  final List<GraphQLErrorLocation>? locations;

  /// The path to the errored field.
  final List<String>? path;

  /// Additional error metadata.
  final Map<String, dynamic>? extensions;

  /// Returns the error code if available.
  String? get code => extensions?['code'] as String?;

  @override
  String toString() => 'GraphQLError: $message';
}

/// A location in a GraphQL document.
class GraphQLErrorLocation {
  /// Creates a new [GraphQLErrorLocation].
  const GraphQLErrorLocation({
    required this.line,
    required this.column,
  });

  /// Creates from JSON.
  factory GraphQLErrorLocation.fromJson(Map<String, dynamic> json) {
    return GraphQLErrorLocation(
      line: json['line'] as int,
      column: json['column'] as int,
    );
  }

  /// The line number (1-indexed).
  final int line;

  /// The column number (1-indexed).
  final int column;

  @override
  String toString() => 'line: $line, column: $column';
}

/// Base class for GraphQL operations.
abstract class GraphQLOperation {
  /// Converts this operation to a request body.
  Map<String, dynamic> toRequestBody();
}
