import 'dart:math';

/// Strategy for calculating delay between retry attempts.
abstract class BackoffStrategy {
  /// Calculates the delay before the next retry attempt.
  Duration getDelay(int attempt);

  /// Resets the backoff state.
  void reset();
}

/// Exponential backoff strategy for retry delays.
///
/// The delay increases exponentially with each retry attempt.
/// delay = initialDelay * (multiplier ^ attempt)
///
/// Example:
/// ```dart
/// final backoff = ExponentialBackoff(
///   initialDelay: Duration(seconds: 1),
///   maxDelay: Duration(seconds: 30),
///   multiplier: 2.0,
/// );
///
/// // Attempt 0: 1s
/// // Attempt 1: 2s
/// // Attempt 2: 4s
/// // Attempt 3: 8s
/// // ...up to maxDelay
/// ```
class ExponentialBackoff implements BackoffStrategy {
  /// Creates a new [ExponentialBackoff].
  const ExponentialBackoff({
    this.initialDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
    this.multiplier = 2.0,
  }) : assert(multiplier >= 1.0, 'Multiplier must be >= 1.0');

  /// The initial delay before the first retry.
  final Duration initialDelay;

  /// The maximum delay between retries.
  final Duration maxDelay;

  /// The multiplier for each subsequent retry.
  final double multiplier;

  @override
  Duration getDelay(int attempt) {
    final delayMs = initialDelay.inMilliseconds * pow(multiplier, attempt);
    final clampedMs = delayMs.clamp(0, maxDelay.inMilliseconds);
    return Duration(milliseconds: clampedMs.toInt());
  }

  @override
  void reset() {
    // Stateless, nothing to reset
  }

  /// Returns the delay for the next attempt as a string.
  String getDelayString(int attempt) {
    final delay = getDelay(attempt);
    if (delay.inSeconds > 0) {
      return '${delay.inSeconds}s';
    }
    return '${delay.inMilliseconds}ms';
  }

  @override
  String toString() {
    return 'ExponentialBackoff('
        'initial: $initialDelay, '
        'max: $maxDelay, '
        'multiplier: $multiplier'
        ')';
  }
}

/// Fixed delay backoff strategy.
///
/// Uses the same delay for all retry attempts.
class FixedBackoff implements BackoffStrategy {
  /// Creates a new [FixedBackoff].
  const FixedBackoff({
    this.delay = const Duration(seconds: 1),
  });

  /// The fixed delay between retries.
  final Duration delay;

  @override
  Duration getDelay(int attempt) => delay;

  @override
  void reset() {}

  @override
  String toString() => 'FixedBackoff(delay: $delay)';
}

/// Incremental backoff strategy.
///
/// The delay increases linearly with each retry attempt.
/// delay = initialDelay + (increment * attempt)
class IncrementalBackoff implements BackoffStrategy {
  /// Creates a new [IncrementalBackoff].
  const IncrementalBackoff({
    this.initialDelay = const Duration(seconds: 1),
    this.increment = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
  });

  /// The initial delay before the first retry.
  final Duration initialDelay;

  /// The amount to increase the delay for each attempt.
  final Duration increment;

  /// The maximum delay between retries.
  final Duration maxDelay;

  @override
  Duration getDelay(int attempt) {
    final delayMs = initialDelay.inMilliseconds +
        (increment.inMilliseconds * attempt);
    final clampedMs = delayMs.clamp(0, maxDelay.inMilliseconds);
    return Duration(milliseconds: clampedMs);
  }

  @override
  void reset() {}

  @override
  String toString() {
    return 'IncrementalBackoff('
        'initial: $initialDelay, '
        'increment: $increment, '
        'max: $maxDelay'
        ')';
  }
}

/// Fibonacci backoff strategy.
///
/// The delay follows the Fibonacci sequence.
class FibonacciBackoff implements BackoffStrategy {
  /// Creates a new [FibonacciBackoff].
  FibonacciBackoff({
    this.baseUnit = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
  }) : _fibCache = [0, 1];

  /// The base unit for the Fibonacci sequence.
  final Duration baseUnit;

  /// The maximum delay between retries.
  final Duration maxDelay;

  final List<int> _fibCache;

  @override
  Duration getDelay(int attempt) {
    final fibValue = _fibonacci(attempt + 1);
    final delayMs = baseUnit.inMilliseconds * fibValue;
    final clampedMs = delayMs.clamp(0, maxDelay.inMilliseconds);
    return Duration(milliseconds: clampedMs);
  }

  int _fibonacci(int n) {
    while (_fibCache.length <= n) {
      _fibCache.add(_fibCache[_fibCache.length - 1] + _fibCache[_fibCache.length - 2]);
    }
    return _fibCache[n];
  }

  @override
  void reset() {
    _fibCache.clear();
    _fibCache.addAll([0, 1]);
  }

  @override
  String toString() {
    return 'FibonacciBackoff('
        'baseUnit: $baseUnit, '
        'max: $maxDelay'
        ')';
  }
}

/// Decorrelated jitter backoff strategy.
///
/// This strategy adds randomness to prevent thundering herd problems.
/// delay = random(base, previous_delay * 3)
class DecorrelatedJitterBackoff implements BackoffStrategy {
  /// Creates a new [DecorrelatedJitterBackoff].
  DecorrelatedJitterBackoff({
    this.baseDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
  }) : _random = Random();

  /// The base delay.
  final Duration baseDelay;

  /// The maximum delay.
  final Duration maxDelay;

  final Random _random;
  Duration _previousDelay = Duration.zero;

  @override
  Duration getDelay(int attempt) {
    if (attempt == 0) {
      _previousDelay = baseDelay;
      return baseDelay;
    }

    final minDelay = baseDelay.inMilliseconds;
    final maxPrevious = _previousDelay.inMilliseconds * 3;

    final delayMs = minDelay + _random.nextInt(maxPrevious - minDelay + 1);
    final clampedMs = delayMs.clamp(0, maxDelay.inMilliseconds);

    _previousDelay = Duration(milliseconds: clampedMs);
    return _previousDelay;
  }

  @override
  void reset() {
    _previousDelay = Duration.zero;
  }

  @override
  String toString() {
    return 'DecorrelatedJitterBackoff('
        'base: $baseDelay, '
        'max: $maxDelay'
        ')';
  }
}

/// A composite backoff that switches strategies based on attempt count.
class CompositeBackoff implements BackoffStrategy {
  /// Creates a new [CompositeBackoff].
  CompositeBackoff({
    required this.strategies,
  }) : assert(strategies.isNotEmpty, 'Must provide at least one strategy');

  /// List of (threshold, strategy) pairs.
  /// Uses the strategy where attempt < threshold.
  final List<(int, BackoffStrategy)> strategies;

  @override
  Duration getDelay(int attempt) {
    for (final (threshold, strategy) in strategies) {
      if (attempt < threshold) {
        return strategy.getDelay(attempt);
      }
    }
    return strategies.last.$2.getDelay(attempt);
  }

  @override
  void reset() {
    for (final (_, strategy) in strategies) {
      strategy.reset();
    }
  }
}

/// Extension methods for backoff strategies.
extension BackoffStrategyExtension on BackoffStrategy {
  /// Returns the total delay for a sequence of retries.
  Duration totalDelay(int attempts) {
    var total = Duration.zero;
    for (var i = 0; i < attempts; i++) {
      total += getDelay(i);
    }
    return total;
  }

  /// Returns a list of delays for a sequence of retries.
  List<Duration> delaySequence(int attempts) {
    return List.generate(attempts, getDelay);
  }
}
