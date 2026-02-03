import 'dart:math';

/// Strategy for automatic WebSocket reconnection.
///
/// Implementations define how long to wait between reconnection attempts
/// and when to stop trying to reconnect.
abstract class ReconnectionStrategy {
  /// Returns the delay before the next reconnection attempt.
  ///
  /// Returns null if no more attempts should be made.
  Duration? getDelay(int attempt);

  /// Resets the strategy state.
  void reset();
}

/// Exponential backoff reconnection strategy.
///
/// The delay increases exponentially with each attempt.
///
/// Example:
/// ```dart
/// final strategy = ExponentialReconnection(
///   initialDelay: Duration(seconds: 1),
///   maxDelay: Duration(seconds: 30),
///   maxAttempts: 10,
/// );
/// ```
class ExponentialReconnection implements ReconnectionStrategy {
  /// Creates a new [ExponentialReconnection].
  const ExponentialReconnection({
    this.initialDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
    this.maxAttempts,
    this.multiplier = 2.0,
  });

  /// The initial delay before the first reconnection.
  final Duration initialDelay;

  /// The maximum delay between attempts.
  final Duration maxDelay;

  /// Maximum number of reconnection attempts (null for unlimited).
  final int? maxAttempts;

  /// The multiplier for each subsequent attempt.
  final double multiplier;

  @override
  Duration? getDelay(int attempt) {
    if (maxAttempts != null && attempt >= maxAttempts!) {
      return null;
    }

    final delayMs = initialDelay.inMilliseconds * pow(multiplier, attempt);
    final clampedMs = delayMs.clamp(0, maxDelay.inMilliseconds);
    return Duration(milliseconds: clampedMs.toInt());
  }

  @override
  void reset() {
    // Stateless, nothing to reset
  }

  @override
  String toString() {
    return 'ExponentialReconnection('
        'initial: $initialDelay, '
        'max: $maxDelay, '
        'maxAttempts: $maxAttempts'
        ')';
  }
}

/// Fixed delay reconnection strategy.
///
/// Uses the same delay for all reconnection attempts.
class FixedReconnection implements ReconnectionStrategy {
  /// Creates a new [FixedReconnection].
  const FixedReconnection({
    this.delay = const Duration(seconds: 5),
    this.maxAttempts,
  });

  /// The delay between reconnection attempts.
  final Duration delay;

  /// Maximum number of reconnection attempts (null for unlimited).
  final int? maxAttempts;

  @override
  Duration? getDelay(int attempt) {
    if (maxAttempts != null && attempt >= maxAttempts!) {
      return null;
    }
    return delay;
  }

  @override
  void reset() {}

  @override
  String toString() {
    return 'FixedReconnection(delay: $delay, maxAttempts: $maxAttempts)';
  }
}

/// Linear backoff reconnection strategy.
///
/// The delay increases linearly with each attempt.
class LinearReconnection implements ReconnectionStrategy {
  /// Creates a new [LinearReconnection].
  const LinearReconnection({
    this.initialDelay = const Duration(seconds: 1),
    this.increment = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
    this.maxAttempts,
  });

  /// The initial delay before the first reconnection.
  final Duration initialDelay;

  /// The amount to increase the delay for each attempt.
  final Duration increment;

  /// The maximum delay between attempts.
  final Duration maxDelay;

  /// Maximum number of reconnection attempts (null for unlimited).
  final int? maxAttempts;

  @override
  Duration? getDelay(int attempt) {
    if (maxAttempts != null && attempt >= maxAttempts!) {
      return null;
    }

    final delayMs = initialDelay.inMilliseconds +
        (increment.inMilliseconds * attempt);
    final clampedMs = delayMs.clamp(0, maxDelay.inMilliseconds);
    return Duration(milliseconds: clampedMs);
  }

  @override
  void reset() {}

  @override
  String toString() {
    return 'LinearReconnection('
        'initial: $initialDelay, '
        'increment: $increment, '
        'max: $maxDelay'
        ')';
  }
}

/// Reconnection strategy with random jitter.
///
/// Adds randomness to prevent thundering herd problems.
class JitteredReconnection implements ReconnectionStrategy {
  /// Creates a new [JitteredReconnection].
  JitteredReconnection({
    this.baseDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
    this.maxAttempts,
    this.jitterFactor = 0.5,
    this.multiplier = 2.0,
  }) : _random = Random();

  /// The base delay for calculations.
  final Duration baseDelay;

  /// The maximum delay between attempts.
  final Duration maxDelay;

  /// Maximum number of reconnection attempts (null for unlimited).
  final int? maxAttempts;

  /// The jitter factor (0.0 to 1.0).
  final double jitterFactor;

  /// The multiplier for exponential backoff.
  final double multiplier;

  final Random _random;

  @override
  Duration? getDelay(int attempt) {
    if (maxAttempts != null && attempt >= maxAttempts!) {
      return null;
    }

    final baseMs = baseDelay.inMilliseconds * pow(multiplier, attempt);
    final jitter = baseMs * jitterFactor * (_random.nextDouble() * 2 - 1);
    final totalMs = (baseMs + jitter).round();
    final clampedMs = totalMs.clamp(0, maxDelay.inMilliseconds);
    return Duration(milliseconds: clampedMs);
  }

  @override
  void reset() {}

  @override
  String toString() {
    return 'JitteredReconnection('
        'base: $baseDelay, '
        'max: $maxDelay, '
        'jitter: $jitterFactor'
        ')';
  }
}

/// No reconnection strategy.
///
/// Never attempts to reconnect.
class NoReconnection implements ReconnectionStrategy {
  /// Creates a new [NoReconnection].
  const NoReconnection();

  @override
  Duration? getDelay(int attempt) => null;

  @override
  void reset() {}

  @override
  String toString() => 'NoReconnection()';
}

/// Custom reconnection strategy with a callback.
class CustomReconnection implements ReconnectionStrategy {
  /// Creates a new [CustomReconnection].
  const CustomReconnection({
    required this.delayProvider,
  });

  /// Function that provides the delay for each attempt.
  final Duration? Function(int attempt) delayProvider;

  @override
  Duration? getDelay(int attempt) => delayProvider(attempt);

  @override
  void reset() {}
}

/// Extension methods for reconnection strategies.
extension ReconnectionStrategyExtension on ReconnectionStrategy {
  /// Returns the total time that would be spent on reconnection attempts.
  Duration totalTime(int attempts) {
    var total = Duration.zero;
    for (var i = 0; i < attempts; i++) {
      final delay = getDelay(i);
      if (delay == null) break;
      total += delay;
    }
    return total;
  }

  /// Returns a list of delays for a sequence of attempts.
  List<Duration> delaySequence(int maxAttempts) {
    final delays = <Duration>[];
    for (var i = 0; i < maxAttempts; i++) {
      final delay = getDelay(i);
      if (delay == null) break;
      delays.add(delay);
    }
    return delays;
  }
}
