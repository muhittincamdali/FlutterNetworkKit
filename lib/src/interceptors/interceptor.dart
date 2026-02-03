import '../request/request.dart';
import '../response/response.dart';
import '../response/api_error.dart';

/// Base class for network interceptors.
///
/// Interceptors can modify requests before they are sent, responses before
/// they are returned, and handle errors during the request lifecycle.
///
/// Example:
/// ```dart
/// class LoggingInterceptor extends NetworkInterceptor {
///   @override
///   Future<InterceptorResult<NetworkRequest>> onRequest(
///     NetworkRequest request,
///   ) async {
///     print('Request: ${request.method} ${request.path}');
///     return InterceptorResult.next(request);
///   }
/// }
/// ```
abstract class NetworkInterceptor {
  /// Creates a new [NetworkInterceptor].
  const NetworkInterceptor();

  /// Called before a request is sent.
  ///
  /// Return [InterceptorResult.next] to continue with the request,
  /// [InterceptorResult.reject] to abort with an error,
  /// or [InterceptorResult.resolve] to short-circuit with a response.
  Future<InterceptorResult<NetworkRequest>> onRequest(NetworkRequest request) {
    return Future.value(InterceptorResult.next(request));
  }

  /// Called when a response is received.
  ///
  /// Return [InterceptorResult.next] to continue with the response,
  /// or [InterceptorResult.reject] to convert to an error.
  Future<ResponseInterceptorResult<NetworkResponse<dynamic>>> onResponse(
    NetworkResponse<dynamic> response,
  ) {
    return Future.value(ResponseInterceptorResult.next(response));
  }

  /// Called when an error occurs.
  ///
  /// Return [ErrorInterceptorResult.next] to propagate the error,
  /// or [ErrorInterceptorResult.resolve] to recover with a response.
  Future<ErrorInterceptorResult<ApiError>> onError(ApiError error) {
    return Future.value(ErrorInterceptorResult.next(error));
  }

  /// The priority of this interceptor.
  ///
  /// Lower values run first. Default is 100.
  int get priority => 100;

  /// A name for this interceptor (used for logging).
  String get name => runtimeType.toString();
}

/// Result type for request interceptors.
sealed class InterceptorResult<T> {
  const InterceptorResult._();

  /// Continue with the request/response.
  const factory InterceptorResult.next(T value) = InterceptorNext<T>;

  /// Reject with an error.
  const factory InterceptorResult.reject(ApiError error) = InterceptorReject<T>;

  /// Resolve with a response (short-circuit).
  const factory InterceptorResult.resolve(NetworkResponse<dynamic> response) =
      InterceptorResolve<T>;

  /// Pattern match on the result.
  R when<R>({
    required R Function(T value) next,
    required R Function(ApiError error) reject,
    required R Function(NetworkResponse<dynamic> response) resolve,
  }) {
    final self = this;
    if (self is InterceptorNext<T>) {
      return next(self.value);
    } else if (self is InterceptorReject<T>) {
      return reject(self.error);
    } else if (self is InterceptorResolve<T>) {
      return resolve(self.response);
    }
    throw StateError('Unknown InterceptorResult type');
  }
}

/// Continue with the modified request/response.
final class InterceptorNext<T> extends InterceptorResult<T> {
  const InterceptorNext(this.value) : super._();
  final T value;
}

/// Reject with an error.
final class InterceptorReject<T> extends InterceptorResult<T> {
  const InterceptorReject(this.error) : super._();
  final ApiError error;
}

/// Resolve immediately with a response.
final class InterceptorResolve<T> extends InterceptorResult<T> {
  const InterceptorResolve(this.response) : super._();
  final NetworkResponse<dynamic> response;
}

/// Result type for response interceptors.
sealed class ResponseInterceptorResult<T> {
  const ResponseInterceptorResult._();

  /// Continue with the response.
  const factory ResponseInterceptorResult.next(T value) =
      ResponseInterceptorNext<T>;

  /// Reject with an error.
  const factory ResponseInterceptorResult.reject(ApiError error) =
      ResponseInterceptorReject<T>;

  /// Pattern match on the result.
  R when<R>({
    required R Function(T value) next,
    required R Function(ApiError error) reject,
  }) {
    final self = this;
    if (self is ResponseInterceptorNext<T>) {
      return next(self.value);
    } else if (self is ResponseInterceptorReject<T>) {
      return reject(self.error);
    }
    throw StateError('Unknown ResponseInterceptorResult type');
  }
}

/// Continue with the response.
final class ResponseInterceptorNext<T> extends ResponseInterceptorResult<T> {
  const ResponseInterceptorNext(this.value) : super._();
  final T value;
}

/// Reject with an error.
final class ResponseInterceptorReject<T> extends ResponseInterceptorResult<T> {
  const ResponseInterceptorReject(this.error) : super._();
  final ApiError error;
}

/// Result type for error interceptors.
sealed class ErrorInterceptorResult<T> {
  const ErrorInterceptorResult._();

  /// Continue with the error.
  const factory ErrorInterceptorResult.next(T error) = ErrorInterceptorNext<T>;

  /// Resolve with a response (recover from error).
  const factory ErrorInterceptorResult.resolve(
      NetworkResponse<dynamic> response) = ErrorInterceptorResolve<T>;

  /// Pattern match on the result.
  R when<R>({
    required R Function(T error) next,
    required R Function(NetworkResponse<dynamic> response) resolve,
  }) {
    final self = this;
    if (self is ErrorInterceptorNext<T>) {
      return next(self.error);
    } else if (self is ErrorInterceptorResolve<T>) {
      return resolve(self.response);
    }
    throw StateError('Unknown ErrorInterceptorResult type');
  }
}

/// Continue with the error.
final class ErrorInterceptorNext<T> extends ErrorInterceptorResult<T> {
  const ErrorInterceptorNext(this.error) : super._();
  final T error;
}

/// Resolve with a response.
final class ErrorInterceptorResolve<T> extends ErrorInterceptorResult<T> {
  const ErrorInterceptorResolve(this.response) : super._();
  final NetworkResponse<dynamic> response;
}

/// Manages a chain of interceptors.
class InterceptorChain {
  /// Creates a new [InterceptorChain].
  InterceptorChain([List<NetworkInterceptor>? interceptors])
      : _interceptors = interceptors ?? [] {
    _sortInterceptors();
  }

  final List<NetworkInterceptor> _interceptors;

  /// The list of interceptors in the chain.
  List<NetworkInterceptor> get interceptors => List.unmodifiable(_interceptors);

  /// Adds an interceptor to the chain.
  void add(NetworkInterceptor interceptor) {
    _interceptors.add(interceptor);
    _sortInterceptors();
  }

  /// Removes an interceptor from the chain.
  void remove(NetworkInterceptor interceptor) {
    _interceptors.remove(interceptor);
  }

  /// Clears all interceptors from the chain.
  void clear() {
    _interceptors.clear();
  }

  void _sortInterceptors() {
    _interceptors.sort((a, b) => a.priority.compareTo(b.priority));
  }

  /// Processes a request through all interceptors.
  Future<InterceptorResult<NetworkRequest>> processRequest(
    NetworkRequest request,
  ) async {
    var currentRequest = request;

    for (final interceptor in _interceptors) {
      final result = await interceptor.onRequest(currentRequest);

      if (result is InterceptorNext<NetworkRequest>) {
        currentRequest = result.value;
      } else {
        return result;
      }
    }

    return InterceptorResult.next(currentRequest);
  }

  /// Processes a response through all interceptors.
  Future<ResponseInterceptorResult<NetworkResponse<dynamic>>> processResponse(
    NetworkResponse<dynamic> response,
  ) async {
    var currentResponse = response;

    for (final interceptor in _interceptors.reversed) {
      final result = await interceptor.onResponse(currentResponse);

      if (result is ResponseInterceptorNext<NetworkResponse<dynamic>>) {
        currentResponse = result.value;
      } else {
        return result;
      }
    }

    return ResponseInterceptorResult.next(currentResponse);
  }

  /// Processes an error through all interceptors.
  Future<ErrorInterceptorResult<ApiError>> processError(ApiError error) async {
    var currentError = error;

    for (final interceptor in _interceptors.reversed) {
      final result = await interceptor.onError(currentError);

      if (result is ErrorInterceptorNext<ApiError>) {
        currentError = result.error;
      } else {
        return result;
      }
    }

    return ErrorInterceptorResult.next(currentError);
  }
}
