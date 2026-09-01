import 'metadata_validator.dart';

/// Bounded, type-safe store for contextual metadata attached to PerfScope
/// records (screens, interactions, sessions).
///
/// Values are validated against a small allow-list so the store stays
/// trivially serializable and cheap to copy — see [MetadataValidator] for
/// the single source of truth of those rules:
/// * `null`, `bool`, `int`, `double`, `String` (length-capped);
/// * `List` of those primitives (size-capped, no nested collections);
/// * `Map<String, ...>` of the same primitives (size-capped, no nesting).
///
/// Anything outside the allow-list — or over any limit — fails fast with
/// an [ArgumentError] naming the offending key and runtime type.
final class MetadataStore {
  /// Maximum number of stored keys. Setting a *new* key beyond the limit
  /// throws; replacing an existing key is always allowed.
  static const int maxEntries = 64;

  /// Maximum number of items inside a List/Map value.
  static const int maxItemsPerCollection =
      MetadataValidator.maxItemsPerCollection;

  /// Maximum length of a single String value.
  static const int maxStringLength = MetadataValidator.maxStringLength;

  final Map<String, Object?> _values = <String, Object?>{};

  /// Whether [key] currently has a value.
  bool containsKey(String key) => _values.containsKey(key);

  /// Validates and stores [value] under [key], replacing any previous one.
  ///
  /// Throws [ArgumentError] when [value] violates the allow-list or any
  /// limit, or when storing a new key would exceed [maxEntries].
  void set(String key, Object? value) {
    MetadataValidator.validate(key, value);
    if (!_values.containsKey(key) && _values.length >= maxEntries) {
      throw ArgumentError(
        'Metadata limit reached: maxEntries=$maxEntries, '
        'cannot add key "$key"',
        key,
      );
    }
    _values[key] = MetadataValidator.defensiveCopy(value);
  }

  /// Removes [key] and returns its previous value (null when absent).
  Object? remove(String key) => _values.remove(key);

  /// Removes every entry.
  void clear() => _values.clear();

  /// Defensive snapshot: a fresh map whose collection values are copied
  /// too, so later mutations of the store or of caller-held collections
  /// never leak in either direction.
  Map<String, Object?> snapshot() {
    final copy = <String, Object?>{};
    _values.forEach((key, value) {
      copy[key] = MetadataValidator.defensiveCopy(value);
    });
    return copy;
  }
}
