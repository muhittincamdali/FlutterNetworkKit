import 'dart:convert';

import 'package:logging/logging.dart';

import '../client/network_configuration.dart';
import '../request/request.dart';
import '../response/response.dart';
import '../response/api_error.dart';
import 'interceptor.dart';

/// Interceptor that logs request and response information.
///
/// The level of detail can be configured using [LogLevel].
///
/// Example:
/// ```dart
/// final loggingInterceptor = LoggingInterceptor(
///   level: LogLevel.body,
///   logger: (message) => print(message),
/// );
/// ```
class LoggingInterceptor extends NetworkInterceptor {
  /// Creates a new [LoggingInterceptor].
  LoggingInterceptor({
    this.level = LogLevel.basic,
    this.logger,
    this.logHeaders = true,
    this.logBody = true,
    this.maxBodyLength = 10000,
    this.sensitiveHeaders = const ['Authorization', 'Cookie', 'Set-Cookie'],
    this.maskSensitive = true,
    this.prettyPrint = true,
    this.includeTimestamp = true,
  }) : _logger = logger ?? _defaultLogger;

  /// The level of detail for logging.
  final LogLevel level;

  /// Custom logger function.
  final void Function(String message)? logger;

  /// Whether to log request/response headers.
  final bool logHeaders;

  /// Whether to log request/response body.
  final bool logBody;

  /// Maximum body length to log.
  final int maxBodyLength;

  /// Headers that should be masked in logs.
  final List<String> sensitiveHeaders;

  /// Whether to mask sensitive header values.
  final bool maskSensitive;

  /// Whether to pretty print JSON bodies.
  final bool prettyPrint;

  /// Whether to include timestamps in logs.
  final bool includeTimestamp;

  final void Function(String message) _logger;
  final Map<String, DateTime> _requestStartTimes = {};

  static void _defaultLogger(String message) {
    Logger('NetworkKit').info(message);
  }

  @override
  int get priority => 999;

  @override
  String get name => 'LoggingInterceptor';

  @override
  Future<InterceptorResult<NetworkRequest>> onRequest(
    NetworkRequest request,
  ) async {
    if (level == LogLevel.none) {
      return InterceptorResult.next(request);
    }

    final requestId = _generateRequestId();
    _requestStartTimes[requestId] = DateTime.now();

    final buffer = StringBuffer();

    // Add timestamp
    if (includeTimestamp) {
      buffer.writeln('───────────────────────────────────────');
      buffer.writeln('📤 REQUEST [${DateTime.now().toIso8601String()}]');
    } else {
      buffer.writeln('───────────────────────────────────────');
      buffer.writeln('📤 REQUEST');
    }

    // Basic info
    buffer.writeln('${request.method.value} ${request.fullUrl}');

    // Headers
    if (_shouldLogHeaders && request.headers != null) {
      buffer.writeln('Headers:');
      for (final entry in request.headers!.entries) {
        final value = _maskHeaderIfSensitive(entry.key, entry.value);
        buffer.writeln('  ${entry.key}: $value');
      }
    }

    // Body
    if (_shouldLogBody && request.body != null) {
      buffer.writeln('Body:');
      buffer.writeln(_formatBody(request.body));
    }

    buffer.writeln('───────────────────────────────────────');

    _logger(buffer.toString());

    // Store request ID for matching response
    final modifiedRequest = request.copyWith(
      extra: {...?request.extra, '_requestId': requestId},
    );

    return InterceptorResult.next(modifiedRequest);
  }

  @override
  Future<ResponseInterceptorResult<NetworkResponse<dynamic>>> onResponse(
    NetworkResponse<dynamic> response,
  ) async {
    if (level == LogLevel.none) {
      return ResponseInterceptorResult.next(response);
    }

    final requestId = response.extra?['_requestId'] as String?;
    final startTime = requestId != null ? _requestStartTimes.remove(requestId) : null;
    final duration = startTime != null
        ? DateTime.now().difference(startTime)
        : response.requestTime;

    final buffer = StringBuffer();

    // Add timestamp
    if (includeTimestamp) {
      buffer.writeln('───────────────────────────────────────');
      buffer.writeln('📥 RESPONSE [${DateTime.now().toIso8601String()}]');
    } else {
      buffer.writeln('───────────────────────────────────────');
      buffer.writeln('📥 RESPONSE');
    }

    // Status
    final statusEmoji = response.isSuccess ? '✅' : '❌';
    buffer.writeln('$statusEmoji Status: ${response.statusCode}');

    // Duration
    if (duration != null) {
      buffer.writeln('⏱️ Duration: ${duration.inMilliseconds}ms');
    }

    // From cache
    if (response.fromCache) {
      buffer.writeln('💾 From Cache: true');
    }

    // Headers
    if (_shouldLogHeaders && response.headers != null) {
      buffer.writeln('Headers:');
      for (final entry in response.headers!.entries) {
        final values = entry.value.join(', ');
        final maskedValue = _maskHeaderIfSensitive(entry.key, values);
        buffer.writeln('  ${entry.key}: $maskedValue');
      }
    }

    // Body
    if (_shouldLogBody && response.data != null) {
      buffer.writeln('Body:');
      buffer.writeln(_formatBody(response.data));
    }

    buffer.writeln('───────────────────────────────────────');

    _logger(buffer.toString());

    return ResponseInterceptorResult.next(response);
  }

  @override
  Future<ErrorInterceptorResult<ApiError>> onError(ApiError error) async {
    if (level == LogLevel.none) {
      return ErrorInterceptorResult.next(error);
    }

    final buffer = StringBuffer();

    // Add timestamp
    if (includeTimestamp) {
      buffer.writeln('═══════════════════════════════════════');
      buffer.writeln('❌ ERROR [${DateTime.now().toIso8601String()}]');
    } else {
      buffer.writeln('═══════════════════════════════════════');
      buffer.writeln('❌ ERROR');
    }

    // Error info
    buffer.writeln('Status: ${error.statusCode}');
    buffer.writeln('Message: ${error.message}');

    if (error.errorCode != null) {
      buffer.writeln('Code: ${error.errorCode}');
    }

    if (error.requestPath != null) {
      buffer.writeln('Path: ${error.requestMethod} ${error.requestPath}');
    }

    // Validation errors
    if (error.hasValidationErrors) {
      buffer.writeln('Validation Errors:');
      for (final entry in error.validationErrors!.entries) {
        buffer.writeln('  ${entry.key}: ${entry.value.join(", ")}');
      }
    }

    // Details
    if (error.details != null && _shouldLogBody) {
      buffer.writeln('Details:');
      buffer.writeln(_formatBody(error.details));
    }

    buffer.writeln('═══════════════════════════════════════');

    _logger(buffer.toString());

    return ErrorInterceptorResult.next(error);
  }

  bool get _shouldLogHeaders {
    return logHeaders && (level == LogLevel.headers ||
        level == LogLevel.body ||
        level == LogLevel.verbose);
  }

  bool get _shouldLogBody {
    return logBody && (level == LogLevel.body || level == LogLevel.verbose);
  }

  String _maskHeaderIfSensitive(String name, String value) {
    if (!maskSensitive) return value;

    for (final sensitive in sensitiveHeaders) {
      if (name.toLowerCase() == sensitive.toLowerCase()) {
        if (value.length > 10) {
          return '${value.substring(0, 5)}...${value.substring(value.length - 3)}';
        }
        return '***';
      }
    }
    return value;
  }

  String _formatBody(dynamic body) {
    if (body == null) return 'null';

    String formatted;
    if (body is String) {
      formatted = body;
    } else if (body is Map || body is List) {
      try {
        if (prettyPrint) {
          formatted = const JsonEncoder.withIndent('  ').convert(body);
        } else {
          formatted = json.encode(body);
        }
      } catch (_) {
        formatted = body.toString();
      }
    } else {
      try {
        final jsonData = (body as dynamic).toJson();
        if (prettyPrint) {
          formatted = const JsonEncoder.withIndent('  ').convert(jsonData);
        } else {
          formatted = json.encode(jsonData);
        }
      } catch (_) {
        formatted = body.toString();
      }
    }

    if (formatted.length > maxBodyLength) {
      return '${formatted.substring(0, maxBodyLength)}...[truncated]';
    }

    return formatted;
  }

  String _generateRequestId() {
    return DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  }
}

/// A simple console logger for debugging.
class ConsoleLoggingInterceptor extends LoggingInterceptor {
  /// Creates a console logger with verbose output.
  ConsoleLoggingInterceptor()
      : super(
          level: LogLevel.verbose,
          logger: print,
          prettyPrint: true,
        );
}

/// A minimal logger that only logs errors.
class ErrorLoggingInterceptor extends LoggingInterceptor {
  /// Creates an error-only logger.
  ErrorLoggingInterceptor({void Function(String)? logger})
      : super(
          level: LogLevel.basic,
          logger: logger,
        );

  @override
  Future<InterceptorResult<NetworkRequest>> onRequest(
    NetworkRequest request,
  ) async {
    return InterceptorResult.next(request);
  }

  @override
  Future<ResponseInterceptorResult<NetworkResponse<dynamic>>> onResponse(
    NetworkResponse<dynamic> response,
  ) async {
    return ResponseInterceptorResult.next(response);
  }
}
