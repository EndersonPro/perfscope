import '../core/ids.dart';

/// Maximum number of simultaneously active interaction spans.
///
/// Deliberately config-independent: runaway interaction nesting is almost
/// always a caller bug (start without end), so the guard exists to keep
/// memory and event volume bounded, not to be tuned.
const int maxInteractionDepth = 16;

/// Sentinel returned by [InteractionTracker.activeInteractionId] when no
/// interaction span is active. Mapped back to `null` at frame enrichment.
const String noActiveInteractionId = '';

/// Handle for one started interaction span.
///
/// Created exclusively by [InteractionTracker.start]; [end] may be called
/// at most once (further calls are safe no-ops) and works even if inner
/// spans ended first — out-of-order endings are supported.
final class InteractionHandle {
  InteractionHandle._({
    required this.id,
    required this.name,
    required this.parentInteractionId,
    required DateTime startedAt,
    required bool hasEnded,
    void Function(InteractionHandle handle)? onEnd,
  })  : _startedAt = startedAt,
        _hasEnded = hasEnded,
        _onEnd = onEnd;

  /// Local correlation identifier unique within this PerfScope session.
  final String id;

  /// Caller-provided label for the interaction.
  final String name;

  /// Id of the span that was innermost-active when this one started, or
  /// null at the root of the interaction stack.
  final String? parentInteractionId;

  final DateTime _startedAt;

  /// Wall-clock time at which the span started. Internal detail consumed
  /// by the engine to compute end-event durations; not part of the public
  /// contract.
  DateTime get startedAt => _startedAt;

  bool _hasEnded;
  final void Function(InteractionHandle handle)? _onEnd;

  /// Marks the span as ended and detaches it from the tracker stack,
  /// wherever it currently sits. Repeated calls are safe no-ops.
  void end() {
    if (_hasEnded) {
      return;
    }
    _hasEnded = true;
    _onEnd?.call(this);
  }

  /// Whether [end] has already been called on this handle.
  bool get hasEnded => _hasEnded;

  /// Inert, already-ended handle used when a start request must be ignored
  /// (depth guard exceeded). Its empty [id] lets callers detect the case.
  static InteractionHandle inert(String name) {
    return InteractionHandle._(
      id: '',
      name: name,
      parentInteractionId: null,
      startedAt: DateTime.fromMicrosecondsSinceEpoch(0),
      hasEnded: true,
    );
  }
}

/// Tracks user interaction spans with a stack discipline.
///
/// * [start] pushes a span; [InteractionHandle.end] removes it from wherever
///   it sits in the stack, so out-of-order endings are allowed and
///   [activeInteractionId] always reflects the innermost still-active span.
/// * Quick markers ([markOnce]) are one-shot attributions for the next
///   observed frame, independent of any active span.
///
/// The tracker emits nothing itself; the engine subscribes via [onSpanEnded]
/// to produce events.
final class InteractionTracker {
  /// Creates a tracker. [onWarning] receives a `[PerfScope]`-prefixed
  /// diagnostic line at most once per process when the depth guard fires.
  InteractionTracker({void Function(String message)? onWarning})
      : _onWarning = onWarning;

  final void Function(String message)? _onWarning;
  final IdGenerator _ids = IdGenerator('iax');
  final List<InteractionHandle> _stack = <InteractionHandle>[];

  /// Invoked by the tracker whenever an active span ends, carrying the
  /// handle so listeners can compute durations from its `startedAt`.
  void Function(InteractionHandle handle)? onSpanEnded;

  bool _depthWarningWritten = false;
  String? _pendingMarkerId;

  /// Id of the innermost still-active span, or [noActiveInteractionId].
  String get activeInteractionId =>
      _stack.isEmpty ? noActiveInteractionId : _stack.last.id;

  /// Number of currently active spans.
  int get depth => _stack.length;

  /// Starts a new interaction span nested inside the current innermost one.
  ///
  /// When [maxInteractionDepth] is already reached the span is ignored:
  /// an inert (already-ended, empty-id) handle is returned and a single
  /// warning is emitted through the injected callback for the whole
  /// process lifetime.
  InteractionHandle start(String name, DateTime now) {
    if (_stack.length >= maxInteractionDepth) {
      _warnDepthOnce();
      return InteractionHandle.inert(name);
    }
    final parent = _stack.isEmpty ? null : _stack.last.id;
    final handle = InteractionHandle._(
      id: _ids.next(),
      name: name,
      parentInteractionId: parent,
      startedAt: now,
      hasEnded: false,
      onEnd: _onSpanEnded,
    );
    _stack.add(handle);
    return handle;
  }

  /// Sets a one-shot quick marker attributed to the very next observed
  /// frame. Calling it again before consumption replaces the marker
  /// (last mark wins). Returns the marker's interaction id.
  String markOnce(String name, DateTime now) {
    return _pendingMarkerId = _ids.next();
  }

  /// Returns the pending marker's interaction id exactly once, then clears
  /// it. Returns null when no unconsumed marker exists.
  String? consumePendingMarker() {
    final id = _pendingMarkerId;
    _pendingMarkerId = null;
    return id;
  }

  void _onSpanEnded(InteractionHandle handle) {
    // Out-of-order ends: detach from wherever the span sits in the stack.
    _stack.removeWhere((active) => identical(active, handle));
    onSpanEnded?.call(handle);
  }

  void _warnDepthOnce() {
    if (_depthWarningWritten) {
      return;
    }
    _depthWarningWritten = true;
    _onWarning?.call('[PerfScope] maxInteractionDepth ($maxInteractionDepth) '
        'reached: ignoring further interaction starts until active ones end');
  }
}
