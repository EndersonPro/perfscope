/// Generates sequential local correlation identifiers such as `ses_1`.
///
/// These identifiers exist to correlate records produced within a single
/// PerfScope session (frames, events, traces). They are **not**
/// cryptographically secure and are **not** globally unique across
/// processes; never use them as security tokens or database keys.
final class IdGenerator {
  /// Creates a generator that emits identifiers prefixed with [prefix].
  ///
  /// Example: `IdGenerator('ses')` yields `ses_1`, `ses_2`, ...
  IdGenerator(this._prefix) : _counter = 0;

  final String _prefix;

  int _counter;

  /// Returns the next identifier in the `<prefix>_<n>` sequence,
  /// incrementing from 1.
  String next() => '${_prefix}_${++_counter}';
}

/// Generates sequential integer identifiers starting at 1.
///
/// Used by records that store numeric identifiers (e.g. `FrameSample.id`).
/// Like [IdGenerator], values are only unique within a single PerfScope
/// session and carry no global guarantees.
final class IntIdGenerator {
  /// Creates a generator whose counter starts at zero.
  ///
  /// The first identifier returned by [next] is `1`.
  IntIdGenerator() : _counter = 0;

  int _counter;

  /// Returns the next integer identifier, incrementing from 1.
  int next() => ++_counter;
}
