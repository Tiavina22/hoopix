/// Base failure type surfaced by domain-layer operations. Kept intentionally
/// small — a human-readable [message] and an optional lower-level [cause]
/// (e.g. a `ProcessFailure`) — so presentation code can decide how much
/// detail to show without depending on data-layer types directly.
class Failure {
  const Failure(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => cause == null ? message : '$message ($cause)';
}
