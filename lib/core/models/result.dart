/// A simple Result type to replace `dartz` Either.
///
/// Usage:
/// ```dart
/// Result<int> result = Success(42);
/// result.when(success: (v) => print(v), failure: (f) => print(f));
/// ```
sealed class Result<T> {
  const Result();
}

/// Success variant of [Result].
final class Success<T> extends Result<T> {
  final T value;
  const Success(this.value);
}

/// Failure variant of [Result].
final class Failure<T> extends Result<T> {
  final String message;
  final Object? error;
  final StackTrace? stackTrace;

  const Failure(this.message, {this.error, this.stackTrace});

  @override
  String toString() => 'Failure($message)';
}

/// Extension to make working with [Result] more ergonomic.
extension ResultExtension<T> on Result<T> {
  /// Execute [onSuccess] if this is a [Success], or [onFailure] if this is a [Failure].
  R when<R>({
    required R Function(T value) onSuccess,
    required R Function(String message) onFailure,
  }) {
    if (this is Success<T>) {
      return onSuccess((this as Success<T>).value);
    } else {
      return onFailure((this as Failure<T>).message);
    }
  }

  /// Get the value if Success, or null if Failure.
  T? get valueOrNull => this is Success<T> ? (this as Success<T>).value : null;

  /// Get the error message if Failure, or null if Success.
  String? get errorMessage =>
      this is Failure<T> ? (this as Failure<T>).message : null;

  /// Returns true if this is a [Success].
  bool get isSuccess => this is Success<T>;

  /// Returns true if this is a [Failure].
  bool get isFailure => this is Failure<T>;
}
