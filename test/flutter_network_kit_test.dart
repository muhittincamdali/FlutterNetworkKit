import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_network_kit/flutter_network_kit.dart';

void main() {
  group('NetworkConfiguration', () {
    test('creates with default values', () {
      final config = NetworkConfiguration(baseUrl: 'https://api.example.com');

      expect(config.baseUrl, 'https://api.example.com');
      expect(config.connectTimeout, const Duration(seconds: 30));
      expect(config.receiveTimeout, const Duration(seconds: 30));
      expect(config.sendTimeout, const Duration(seconds: 30));
      expect(config.followRedirects, true);
      expect(config.maxRedirects, 5);
    });

    test('copyWith creates new instance with overrides', () {
      final original = NetworkConfiguration(
        baseUrl: 'https://api.example.com',
        connectTimeout: const Duration(seconds: 10),
      );

      final copy = original.copyWith(
        connectTimeout: const Duration(seconds: 20),
      );

      expect(copy.baseUrl, 'https://api.example.com');
      expect(copy.connectTimeout, const Duration(seconds: 20));
      expect(original.connectTimeout, const Duration(seconds: 10));
    });

    test('mergedHeaders includes content type and accept', () {
      final config = NetworkConfiguration(
        baseUrl: 'https://api.example.com',
        defaultHeaders: {'X-Custom': 'value'},
      );

      final headers = config.mergedHeaders;

      expect(headers['Content-Type'], 'application/json');
      expect(headers['Accept'], 'application/json');
      expect(headers['X-Custom'], 'value');
    });
  });

  group('NetworkRequest', () {
    test('creates GET request', () {
      final request = NetworkRequest.get(
        '/users',
        queryParameters: {'page': 1},
      );

      expect(request.method, HttpMethod.get);
      expect(request.path, '/users');
      expect(request.queryParameters?['page'], 1);
      expect(request.isGet, true);
    });

    test('creates POST request with body', () {
      final request = NetworkRequest.post(
        '/users',
        body: {'name': 'John'},
      );

      expect(request.method, HttpMethod.post);
      expect(request.path, '/users');
      expect(request.body, {'name': 'John'});
      expect(request.isPost, true);
      expect(request.hasBody, true);
    });

    test('withAuthorization adds bearer token', () {
      final request = NetworkRequest.get('/users')
          .withAuthorization('test-token');

      expect(request.headers?['Authorization'], 'Bearer test-token');
    });

    test('addQueryParameter appends parameter', () {
      final request = NetworkRequest.get('/users')
          .addQueryParameter('page', 1)
          .addQueryParameter('limit', 10);

      expect(request.queryParameters?['page'], 1);
      expect(request.queryParameters?['limit'], 10);
    });
  });

  group('NetworkResponse', () {
    test('isSuccess returns true for 2xx status codes', () {
      expect(NetworkResponse(data: null, statusCode: 200).isSuccess, true);
      expect(NetworkResponse(data: null, statusCode: 201).isSuccess, true);
      expect(NetworkResponse(data: null, statusCode: 299).isSuccess, true);
      expect(NetworkResponse(data: null, statusCode: 300).isSuccess, false);
      expect(NetworkResponse(data: null, statusCode: 400).isSuccess, false);
    });

    test('isClientError returns true for 4xx status codes', () {
      expect(NetworkResponse(data: null, statusCode: 400).isClientError, true);
      expect(NetworkResponse(data: null, statusCode: 404).isClientError, true);
      expect(NetworkResponse(data: null, statusCode: 500).isClientError, false);
    });

    test('isServerError returns true for 5xx status codes', () {
      expect(NetworkResponse(data: null, statusCode: 500).isServerError, true);
      expect(NetworkResponse(data: null, statusCode: 503).isServerError, true);
      expect(NetworkResponse(data: null, statusCode: 400).isServerError, false);
    });

    test('map transforms data', () {
      final response = NetworkResponse<int>(data: 42, statusCode: 200);
      final mapped = response.map((data) => data.toString());

      expect(mapped.data, '42');
      expect(mapped.statusCode, 200);
    });
  });

  group('ApiError', () {
    test('creates network error', () {
      final error = ApiError.network();

      expect(error.statusCode, 0);
      expect(error.isNetworkError, true);
      expect(error.errorCode, 'NETWORK_ERROR');
    });

    test('creates timeout error', () {
      final error = ApiError.timeout();

      expect(error.statusCode, 408);
      expect(error.isTimeout, true);
      expect(error.errorCode, 'TIMEOUT_ERROR');
    });

    test('creates unauthorized error', () {
      final error = ApiError.unauthorized();

      expect(error.statusCode, 401);
      expect(error.isUnauthorized, true);
      expect(error.errorCode, 'UNAUTHORIZED');
    });

    test('shouldRetry returns true for retriable errors', () {
      expect(ApiError.network().shouldRetry, true);
      expect(ApiError.timeout().shouldRetry, true);
      expect(ApiError.serverError().shouldRetry, true);
      expect(ApiError.unauthorized().shouldRetry, false);
      expect(ApiError.notFound().shouldRetry, false);
    });
  });

  group('CachePolicy', () {
    test('standard creates sensible defaults', () {
      final policy = CachePolicy.standard();

      expect(policy.maxAge, const Duration(minutes: 5));
      expect(policy.staleWhileRevalidate, const Duration(minutes: 1));
      expect(policy.noCache, false);
      expect(policy.noStore, false);
    });

    test('noCache creates non-caching policy', () {
      final policy = CachePolicy.noCache();

      expect(policy.maxAge, Duration.zero);
      expect(policy.noCache, true);
      expect(policy.canCache, false);
    });

    test('canServeFromCache respects maxAge', () {
      final policy = CachePolicy(maxAge: const Duration(minutes: 5));

      expect(policy.canServeFromCache(const Duration(minutes: 3)), true);
      expect(policy.canServeFromCache(const Duration(minutes: 6)), false);
    });

    test('toHeader generates valid Cache-Control', () {
      final policy = CachePolicy(
        maxAge: const Duration(minutes: 5),
        mustRevalidate: true,
      );

      final header = policy.toHeader();

      expect(header.contains('max-age=300'), true);
      expect(header.contains('must-revalidate'), true);
    });
  });

  group('RetryPolicy', () {
    test('standard creates sensible defaults', () {
      final policy = RetryPolicy.standard();

      expect(policy.maxRetries, 3);
      expect(policy.retryOnNetworkError, true);
      expect(policy.retryOnTimeout, true);
      expect(policy.retryStatusCodes.contains(500), true);
    });

    test('shouldRetry respects maxRetries', () {
      final policy = RetryPolicy(maxRetries: 3);

      expect(policy.shouldRetry(attempt: 0, isNetworkError: true), true);
      expect(policy.shouldRetry(attempt: 2, isNetworkError: true), true);
      expect(policy.shouldRetry(attempt: 3, isNetworkError: true), false);
    });

    test('shouldRetryStatus checks status codes', () {
      final policy = RetryPolicy(retryStatusCodes: [500, 503]);

      expect(policy.shouldRetryStatus(500), true);
      expect(policy.shouldRetryStatus(503), true);
      expect(policy.shouldRetryStatus(400), false);
      expect(policy.shouldRetryStatus(404), false);
    });
  });

  group('ExponentialBackoff', () {
    test('calculates delay correctly', () {
      final backoff = ExponentialBackoff(
        initialDelay: const Duration(seconds: 1),
        multiplier: 2.0,
        maxDelay: const Duration(seconds: 30),
      );

      expect(backoff.getDelay(0), const Duration(seconds: 1));
      expect(backoff.getDelay(1), const Duration(seconds: 2));
      expect(backoff.getDelay(2), const Duration(seconds: 4));
      expect(backoff.getDelay(3), const Duration(seconds: 8));
    });

    test('respects maxDelay', () {
      final backoff = ExponentialBackoff(
        initialDelay: const Duration(seconds: 10),
        multiplier: 2.0,
        maxDelay: const Duration(seconds: 30),
      );

      expect(backoff.getDelay(5), const Duration(seconds: 30));
    });
  });

  group('UrlBuilder', () {
    test('builds simple URL', () {
      final url = UrlBuilder('https://api.example.com')
          .path('/users')
          .build();

      expect(url, 'https://api.example.com/users');
    });

    test('adds query parameters', () {
      final url = UrlBuilder('https://api.example.com')
          .path('/users')
          .query('page', 1)
          .query('limit', 10)
          .build();

      expect(url, 'https://api.example.com/users?page=1&limit=10');
    });

    test('handles path parameters', () {
      final url = UrlBuilder('https://api.example.com')
          .path('/users')
          .pathParam('id', '123')
          .build();

      expect(url.contains('123'), true);
    });

    test('queryIfNotNull only adds non-null values', () {
      final url = UrlBuilder('https://api.example.com')
          .path('/users')
          .queryIfNotNull('page', 1)
          .queryIfNotNull('filter', null)
          .build();

      expect(url.contains('page=1'), true);
      expect(url.contains('filter'), false);
    });
  });

  group('JsonUtils', () {
    test('getPath retrieves nested values', () {
      final json = {
        'user': {
          'profile': {
            'name': 'John',
          },
        },
      };

      expect(JsonUtils.getPath<String>(json, 'user.profile.name'), 'John');
    });

    test('setPath sets nested values', () {
      final json = <String, dynamic>{};
      JsonUtils.setPath(json, 'user.profile.name', 'John');

      expect(json['user']['profile']['name'], 'John');
    });

    test('merge combines objects deeply', () {
      final base = {'a': 1, 'b': {'c': 2}};
      final override = {'b': {'d': 3}};

      final result = JsonUtils.merge(base, override);

      expect(result['a'], 1);
      expect(result['b']['c'], 2);
      expect(result['b']['d'], 3);
    });

    test('flatten converts to dot notation', () {
      final json = {
        'user': {
          'name': 'John',
          'age': 30,
        },
      };

      final flat = JsonUtils.flatten(json);

      expect(flat['user.name'], 'John');
      expect(flat['user.age'], 30);
    });

    test('removeNulls removes null values', () {
      final json = {
        'name': 'John',
        'email': null,
        'age': 30,
      };

      final cleaned = JsonUtils.removeNulls(json);

      expect(cleaned['name'], 'John');
      expect(cleaned['age'], 30);
      expect(cleaned.containsKey('email'), false);
    });
  });

  group('RequestMetrics', () {
    test('tracks request timing', () {
      final metrics = RequestMetrics.start(HttpMethod.get, '/users');

      // Simulate some delay
      metrics.complete(statusCode: 200, responseSize: 1024);

      expect(metrics.isCompleted, true);
      expect(metrics.isSuccess, true);
      expect(metrics.statusCode, 200);
      expect(metrics.responseSize, 1024);
      expect(metrics.duration, isNotNull);
    });

    test('tracks failed requests', () {
      final metrics = RequestMetrics.start(HttpMethod.get, '/users');
      metrics.complete(statusCode: 500, error: 'Server error');

      expect(metrics.isSuccess, false);
      expect(metrics.isServerError, true);
      expect(metrics.error, 'Server error');
    });
  });

  group('WebSocketMessage', () {
    test('creates text message', () {
      final message = WebSocketMessage.text('Hello');

      expect(message.type, MessageType.text);
      expect(message.data, 'Hello');
      expect(message.isText, true);
    });

    test('creates JSON message', () {
      final message = WebSocketMessage.json({'type': 'ping'});

      expect(message.type, MessageType.json);
      expect(message.data, {'type': 'ping'});
      expect(message.isJson, true);
    });

    test('creates binary message', () {
      final message = WebSocketMessage.binary([1, 2, 3, 4]);

      expect(message.type, MessageType.binary);
      expect(message.binaryData?.length, 4);
      expect(message.isBinary, true);
    });

    test('getValue extracts from JSON', () {
      final message = WebSocketMessage.json({'type': 'chat', 'text': 'Hello'});

      expect(message.getValue<String>('type'), 'chat');
      expect(message.getValue<String>('text'), 'Hello');
    });
  });

  group('GraphQLQuery', () {
    test('creates query with variables', () {
      final query = GraphQLQuery(
        query: 'query GetUser(\$id: ID!) { user(id: \$id) { name } }',
        variables: {'id': '123'},
        operationName: 'GetUser',
      );

      expect(query.operationName, 'GetUser');
      expect(query.variables?['id'], '123');
    });

    test('withVariables creates new query', () {
      final original = GraphQLQuery(
        query: 'query { users { name } }',
        variables: {'page': 1},
      );

      final updated = original.withVariables({'limit': 10});

      expect(updated.variables?['page'], 1);
      expect(updated.variables?['limit'], 10);
      expect(original.variables?.containsKey('limit'), false);
    });

    test('toRequestBody formats correctly', () {
      final query = GraphQLQuery(
        query: 'query { users { name } }',
        variables: {'page': 1},
        operationName: 'GetUsers',
      );

      final body = query.toRequestBody();

      expect(body['query'], 'query { users { name } }');
      expect(body['variables'], {'page': 1});
      expect(body['operationName'], 'GetUsers');
    });
  });

  group('GraphQLMutation', () {
    test('creates mutation with input', () {
      final mutation = GraphQLMutation(
        mutation: 'mutation CreateUser(\$input: CreateUserInput!) { createUser(input: \$input) { id } }',
        variables: {'input': {'name': 'John'}},
        operationName: 'CreateUser',
      );

      expect(mutation.operationName, 'CreateUser');
      expect((mutation.variables?['input'] as Map)['name'], 'John');
    });

    test('withInput sets input variable', () {
      final mutation = GraphQLMutation(
        mutation: 'mutation { createUser(input: \$input) { id } }',
      );

      final updated = mutation.withInput({'name': 'Jane'});

      expect((updated.variables?['input'] as Map)['name'], 'Jane');
    });
  });

  group('ReconnectionStrategy', () {
    test('ExponentialReconnection calculates delays', () {
      final strategy = ExponentialReconnection(
        initialDelay: const Duration(seconds: 1),
        maxDelay: const Duration(seconds: 30),
        maxAttempts: 5,
      );

      expect(strategy.getDelay(0), const Duration(seconds: 1));
      expect(strategy.getDelay(1), const Duration(seconds: 2));
      expect(strategy.getDelay(5), null); // Exceeded max attempts
    });

    test('FixedReconnection uses constant delay', () {
      final strategy = FixedReconnection(
        delay: const Duration(seconds: 5),
        maxAttempts: 3,
      );

      expect(strategy.getDelay(0), const Duration(seconds: 5));
      expect(strategy.getDelay(1), const Duration(seconds: 5));
      expect(strategy.getDelay(2), const Duration(seconds: 5));
      expect(strategy.getDelay(3), null);
    });

    test('NoReconnection always returns null', () {
      const strategy = NoReconnection();

      expect(strategy.getDelay(0), null);
      expect(strategy.getDelay(1), null);
    });
  });

  group('Result', () {
    test('Success contains data', () {
      const result = Result<int>.success(42);

      expect(result.isSuccess, true);
      expect(result.isFailure, false);
      expect(result.data, 42);
    });

    test('Failure contains error', () {
      final error = Exception('Test error');
      final result = Result<int>.failure(error);

      expect(result.isSuccess, false);
      expect(result.isFailure, true);
      expect(result.error, error);
    });

    test('fold handles both cases', () {
      const success = Result<int>.success(42);
      final failure = Result<int>.failure(Exception('error'));

      expect(
        success.fold(
          onSuccess: (data) => 'Success: $data',
          onFailure: (error) => 'Failure',
        ),
        'Success: 42',
      );

      expect(
        failure.fold(
          onSuccess: (data) => 'Success: $data',
          onFailure: (error) => 'Failure',
        ),
        'Failure',
      );
    });

    test('map transforms success', () {
      const result = Result<int>.success(42);
      final mapped = result.map((data) => data.toString());

      expect(mapped.isSuccess, true);
      expect(mapped.data, '42');
    });

    test('getOrElse returns default on failure', () {
      final result = Result<int>.failure(Exception('error'));

      expect(result.getOrElse(0), 0);
    });
  });
}
