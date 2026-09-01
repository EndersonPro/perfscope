/// Shared deterministic box-drawing plumbing for pretty-style output.
///
/// Layout contract (used by [PrettyRenderer] and [PerformanceLogger]):
/// * Inner box width is 58 characters between the two vertical borders.
/// * Every content line is `'│ ' + content padded to 56 + ' │'`, so all
///   lines have identical length.
/// * Key/value rows use a left-aligned label column (14 chars by default);
///   numeric millisecond values are right-aligned in a narrow field.
/// * All functions are pure string math — no IO, no clock access.
library;

/// Characters between the two vertical borders of a pretty box.
const int kBoxInnerWidth = 58;

/// Default width of the left-aligned key column in key/value rows.
const int kBoxLabelWidth = 14;

/// Field width used to right-align `'X.XXX ms'` values after the label.
const int kBoxMsFieldWidth = 9;

/// Top border line (without trailing newline).
String boxTop() => '╭${'─' * kBoxInnerWidth}╮';

/// Header separator line (without trailing newline).
String boxSeparator() => '├${'─' * kBoxInnerWidth}┤';

/// Bottom border line (without trailing newline).
String boxBottom() => '╰${'─' * kBoxInnerWidth}╯';

/// One content line: `'│ ' + content padded to 56 + ' │'`.
String boxRow(String content) =>
    '│ ${padRightTo(content, kBoxInnerWidth - 2)} │';

/// Left-aligned label followed by a plain text value.
String kvText(String label, String value, {int labelWidth = kBoxLabelWidth}) =>
    '${padRightTo(label, labelWidth)}$value';

/// Left-aligned label followed by an ms value right-aligned in
/// [fieldWidth] characters as `'X.XXX ms'`.
String kvMs(
  String label,
  Duration duration, {
  int labelWidth = kBoxLabelWidth,
  int fieldWidth = kBoxMsFieldWidth,
}) =>
    '${padRightTo(label, labelWidth)}'
    '${'${msFixed3(duration)} ms'.padLeft(fieldWidth)}';

/// Milliseconds formatted with exactly 3 decimal places.
String msFixed3(Duration duration) =>
    (duration.inMicroseconds / Duration.microsecondsPerMillisecond)
        .toStringAsFixed(3);

/// Milliseconds formatted with exactly 1 decimal place.
String msFixed1(Duration duration) =>
    (duration.inMicroseconds / Duration.microsecondsPerMillisecond)
        .toStringAsFixed(1);

/// Right-pads [value] with spaces to exactly [width] characters.
String padRightTo(String value, int width) =>
    value.length >= width ? value : value.padRight(width);

/// Joins [lines] into a newline-terminated block without a trailing
/// newline on the final line.
String joinLines(List<String> lines) => lines.join('\n');
