/// Shared validation rules for contextual metadata attached to PerfScope
/// records (screens, interactions, traces, sessions).
///
/// Values are validated against a small allow-list so every record stays
/// trivially serializable and cheap to copy:
/// * `null`, `bool`, `int`, `double`, `String` (length-capped);
/// * `List` of those primitives (size-capped, no nested collections);
/// * `Map<String, ...>` of the same primitives (size-capped, no nesting).
///
/// Anything outside the allow-list — or over any limit — fails fast with
/// an [ArgumentError] naming the offending key and runtime type.
///
/// Both [MetadataStore] and inline trace metadata validation funnel through
/// this single implementation so the rules can never drift apart.
final class MetadataValidator {
  /// Maximum number of items inside a List/Map value.
  static const int maxItemsPerCollection = 32;

  /// Maximum length of a single String value.
  static const int maxStringLength = 512;

  const MetadataValidator._();

  /// Throws [ArgumentError] when [value] violates the allow-list or any
  /// limit; returns normally otherwise.
  static void validate(String key, Object? value) {
    if (value == null || value is bool || value is int || value is double) {
      return;
    }
    if (value is String) {
      if (value.length > maxStringLength) {
        throw ArgumentError(
          'Metadata string for "$key" exceeds maxStringLength='
          '$maxStringLength (got ${value.length})',
          key,
        );
      }
      return;
    }
    if (value is List<Object?>) {
      _validateCollection(key, value.length);
      for (final item in value) {
        _validateItem(key, item);
      }
      return;
    }
    if (value is Map<dynamic, dynamic>) {
      if (value.keys.any((k) => k is! String)) {
        throw ArgumentError.value(
          value.runtimeType,
          key,
          'Metadata map for "$key" must have String keys',
        );
      }
      _validateCollection(key, value.length);
      for (final item in value.values) {
        _validateItem(key, item);
      }
      return;
    }
    throw ArgumentError.value(
      value.runtimeType,
      key,
      'Unsupported metadata type for key "$key": ${value.runtimeType}',
    );
  }

  static void _validateCollection(String key, int length) {
    if (length > maxItemsPerCollection) {
      throw ArgumentError(
        'Metadata collection for "$key" exceeds maxItemsPerCollection='
        '$maxItemsPerCollection (got $length)',
        key,
      );
    }
  }

  static void _validateItem(String key, Object? item) {
    if (_isPrimitive(item)) {
      return;
    }
    throw ArgumentError.value(
      item.runtimeType,
      key,
      'Metadata collection for "$key" may only contain primitives '
      '(null, bool, int, double, String); got ${item.runtimeType} '
      '(nesting depth 1)',
    );
  }

  static bool _isPrimitive(Object? value) =>
      value == null ||
      value is bool ||
      value is int ||
      value is double ||
      value is String;

  /// Defensive snapshot helper: a fresh copy of collection values so later
  /// mutations of caller-held collections never leak into stored records
  /// (primitives are immutable and safe to share).
  static Object? defensiveCopy(Object? value) {
    if (value is List<Object?>) {
      return List<Object?>.of(value);
    }
    if (value is Map<String, Object?>) {
      return Map<String, Object?>.of(value);
    }
    // Primitives are immutable — safe to share.
    return value;
  }

  /// Returns a fully defensive copy of [metadata] after validating every
  /// entry. Used by callers that attach a caller-supplied map to a record
  /// in one step (e.g. manual traces).
  static Map<String, Object?> validatedCopy(Map<String, Object?> metadata) {
    final copy = <String, Object?>{};
    metadata.forEach((key, value) {
      validate(key, value);
      copy[key] = defensiveCopy(value);
    });
    return copy;
  }
}
