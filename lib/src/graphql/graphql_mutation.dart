import 'graphql_client.dart';

/// Represents a GraphQL mutation operation.
///
/// Example:
/// ```dart
/// final mutation = GraphQLMutation(
///   mutation: '''
///     mutation CreateUser(\$input: CreateUserInput!) {
///       createUser(input: \$input) {
///         id
///         name
///         email
///       }
///     }
///   ''',
///   variables: {
///     'input': {
///       'name': 'John Doe',
///       'email': 'john@example.com',
///     },
///   },
/// );
/// ```
class GraphQLMutation implements GraphQLOperation {
  /// Creates a new [GraphQLMutation].
  const GraphQLMutation({
    required this.mutation,
    this.variables,
    this.operationName,
  });

  /// Creates a mutation from a document string.
  factory GraphQLMutation.document(String document, {
    Map<String, Object?>? variables,
  }) {
    final operationName = _extractOperationName(document);
    return GraphQLMutation(
      mutation: document,
      variables: variables,
      operationName: operationName,
    );
  }

  /// The GraphQL mutation string.
  final String mutation;

  /// Variables for the mutation.
  final Map<String, Object?>? variables;

  /// The operation name (for documents with multiple operations).
  final String? operationName;

  @override
  Map<String, Object?> toRequestBody() {
    return {
      'query': mutation,
      if (variables != null && variables!.isNotEmpty) 'variables': variables,
      if (operationName != null) 'operationName': operationName,
    };
  }

  /// Creates a copy with updated variables.
  GraphQLMutation withVariables(Map<String, Object?> variables) {
    return GraphQLMutation(
      mutation: mutation,
      variables: {...?this.variables, ...variables},
      operationName: operationName,
    );
  }

  /// Creates a copy with a specific variable set.
  GraphQLMutation setVariable(String name, Object? value) {
    return GraphQLMutation(
      mutation: mutation,
      variables: {...?variables, name: value},
      operationName: operationName,
    );
  }

  /// Creates a copy with input data.
  GraphQLMutation withInput(Map<String, Object?> input) {
    return setVariable('input', input);
  }

  @override
  String toString() {
    return 'GraphQLMutation('
        'operationName: $operationName, '
        'variables: $variables'
        ')';
  }

  static String? _extractOperationName(String document) {
    final regex = RegExp(r'mutation\s+(\w+)');
    final match = regex.firstMatch(document);
    return match?.group(1);
  }
}

/// Builder for creating GraphQL mutations.
class GraphQLMutationBuilder {
  String? _mutation;
  String? _operationName;
  final Map<String, Object?> _variables = {};
  final List<String> _returnFields = [];

  /// Sets the mutation string.
  GraphQLMutationBuilder mutation(String mutation) {
    _mutation = mutation;
    return this;
  }

  /// Sets the operation name.
  GraphQLMutationBuilder operationName(String name) {
    _operationName = name;
    return this;
  }

  /// Adds a variable.
  GraphQLMutationBuilder variable(String name, Object? value) {
    _variables[name] = value;
    return this;
  }

  /// Adds multiple variables.
  GraphQLMutationBuilder variables(Map<String, Object?> variables) {
    _variables.addAll(variables);
    return this;
  }

  /// Sets the input variable.
  GraphQLMutationBuilder input(Map<String, Object?> input) {
    _variables['input'] = input;
    return this;
  }

  /// Adds a field to return.
  GraphQLMutationBuilder returnField(String name) {
    _returnFields.add(name);
    return this;
  }

  /// Adds multiple fields to return.
  GraphQLMutationBuilder returnFields(List<String> names) {
    _returnFields.addAll(names);
    return this;
  }

  /// Builds the mutation.
  GraphQLMutation build() {
    if (_mutation == null) {
      throw StateError('Mutation string must be set');
    }

    return GraphQLMutation(
      mutation: _mutation!,
      variables: _variables.isNotEmpty ? _variables : null,
      operationName: _operationName,
    );
  }
}

/// Common GraphQL mutation templates.
class GraphQLMutationTemplates {
  GraphQLMutationTemplates._();

  /// Creates a create mutation template.
  static GraphQLMutation create(
    String typeName, {
    required Map<String, Object?> input,
    List<String> returnFields = const ['id'],
  }) {
    final fieldStr = returnFields.join('\n        ');
    return GraphQLMutation(
      mutation: '''
        mutation Create$typeName(\$input: Create${typeName}Input!) {
          create$typeName(input: \$input) {
            $fieldStr
          }
        }
      ''',
      variables: {'input': input},
      operationName: 'Create$typeName',
    );
  }

  /// Creates an update mutation template.
  static GraphQLMutation update(
    String typeName, {
    required String id,
    required Map<String, Object?> input,
    List<String> returnFields = const ['id'],
  }) {
    final fieldStr = returnFields.join('\n        ');
    return GraphQLMutation(
      mutation: '''
        mutation Update$typeName(\$id: ID!, \$input: Update${typeName}Input!) {
          update$typeName(id: \$id, input: \$input) {
            $fieldStr
          }
        }
      ''',
      variables: {'id': id, 'input': input},
      operationName: 'Update$typeName',
    );
  }

  /// Creates a delete mutation template.
  static GraphQLMutation delete(
    String typeName, {
    required String id,
  }) {
    return GraphQLMutation(
      mutation: '''
        mutation Delete$typeName(\$id: ID!) {
          delete$typeName(id: \$id) {
            success
            message
          }
        }
      ''',
      variables: {'id': id},
      operationName: 'Delete$typeName',
    );
  }

  /// Creates a batch create mutation template.
  static GraphQLMutation batchCreate(
    String typeName, {
    required List<Map<String, Object?>> inputs,
    List<String> returnFields = const ['id'],
  }) {
    final fieldStr = returnFields.join('\n        ');
    return GraphQLMutation(
      mutation: '''
        mutation BatchCreate$typeName(\$inputs: [Create${typeName}Input!]!) {
          batchCreate${typeName}s(inputs: \$inputs) {
            $fieldStr
          }
        }
      ''',
      variables: {'inputs': inputs},
      operationName: 'BatchCreate$typeName',
    );
  }

  /// Creates a batch delete mutation template.
  static GraphQLMutation batchDelete(
    String typeName, {
    required List<String> ids,
  }) {
    return GraphQLMutation(
      mutation: '''
        mutation BatchDelete$typeName(\$ids: [ID!]!) {
          batchDelete${typeName}s(ids: \$ids) {
            success
            deletedCount
          }
        }
      ''',
      variables: {'ids': ids},
      operationName: 'BatchDelete$typeName',
    );
  }
}

/// Extension methods for mutations.
extension GraphQLMutationExtension on GraphQLMutation {
  /// Adds optimistic response data.
  GraphQLMutation withOptimisticResponse(Map<String, Object?> response) {
    return GraphQLMutation(
      mutation: mutation,
      variables: {
        ...?variables,
        '__optimistic': response,
      },
      operationName: operationName,
    );
  }

  /// Adds a refetch query after mutation.
  GraphQLMutation withRefetchQueries(List<String> queryNames) {
    return GraphQLMutation(
      mutation: mutation,
      variables: {
        ...?variables,
        '__refetchQueries': queryNames,
      },
      operationName: operationName,
    );
  }
}
