/// Fixed-capacity FIFO ring buffer that overwrites the oldest entries.
///
/// Adding to a full buffer replaces the oldest slot in O(1); elements are
/// never shifted, so no `removeAt(0)` copying ever happens.
class RingBuffer<T> {
  /// Creates a buffer holding at most [capacity] elements.
  RingBuffer(int capacity)
      : assert(capacity > 0, 'capacity must be positive'),
        _slots = List<T?>.filled(capacity, null);

  final List<T?> _slots;

  /// Index of the oldest element currently stored.
  int _head = 0;

  /// Number of valid elements (<= capacity).
  int _count = 0;

  /// Maximum number of elements this buffer can hold.
  int get capacity => _slots.length;

  /// Current number of stored elements.
  int get length => _count;

  /// Whether the buffer holds no elements.
  bool get isEmpty => _count == 0;

  /// Whether the buffer holds [capacity] elements.
  bool get isFull => _count == capacity;

  /// Adds [value], overwriting the oldest element once full.
  void add(T value) {
    if (_count < capacity) {
      _slots[(_head + _count) % capacity] = value;
      _count++;
      return;
    }
    _slots[_head] = value;
    _head = (_head + 1) % capacity;
  }

  /// Returns the element [index] positions from the oldest entry
  /// (0-based, chronological). Bounds are asserted in debug mode.
  T operator [](int index) {
    assert(index >= 0 && index < _count, 'Index out of range: $index');
    return _slots[(_head + index) % capacity] as T;
  }

  /// Returns a chronological list copy of the buffered elements.
  List<T> toList() => List<T>.generate(_count, (i) => this[i]);

  /// Visits every stored element in chronological order.
  void forEach(void Function(T element) action) {
    for (var i = 0; i < _count; i++) {
      action(this[i]);
    }
  }

  /// The most recently added element, or null when empty.
  T? get last => isEmpty ? null : this[_count - 1];

  /// Removes all elements without deallocating the backing storage.
  void clear() {
    _slots.fillRange(0, capacity, null);
    _head = 0;
    _count = 0;
  }
}
