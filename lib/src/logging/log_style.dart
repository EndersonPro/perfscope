/// Re-export of [PerfScopeLogStyle] so the logging layer can depend on a
/// single, focused import surface.
///
/// The enum itself stays declared in `core/perfscope_config.dart`: config
/// equality, `copyWith`, and defaults reference it directly, and moving the
/// declaration would churn every existing import for no behavioral gain.
library;

export '../core/perfscope_config.dart' show PerfScopeLogStyle;
