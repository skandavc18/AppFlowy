import 'dart:convert';

/// Decoded view extras, remembered for the few that are large.
///
/// A canvas or a dashboard keeps its whole document in its view's extra, and
/// a sidebar row, a tab, a breadcrumb and the page itself each ask the same
/// view a dozen questions — is it a chart? a map? a canvas? what is its
/// cover? — every one of which used to decode the entire extra again. A canvas
/// holding drawings turned each of those questions into megabytes of JSON.
///
/// ⚠️ Callers get their own top-level map, but nested maps and lists are
/// SHARED with the cache. Copy a nested value before changing it.
abstract final class ViewExtraCache {
  /// Extras shorter than this are decoded every time; they are cheap, and
  /// keeping them would only churn the cache.
  static const int threshold = 16 * 1024;
  static const int capacity = 8;

  static final List<(String, Map<String, dynamic>)> _entries = [];

  /// The JSON object [extra] holds, or null when it holds something else.
  ///
  /// Throws a [FormatException] when [extra] is not JSON at all.
  static Map<String, dynamic>? decode(String extra) {
    final remember = extra.length >= threshold;
    if (remember) {
      for (var index = 0; index < _entries.length; index++) {
        final (source, decoded) = _entries[index];
        if (identical(source, extra) ||
            (source.length == extra.length && source == extra)) {
          if (index > 0) {
            _entries
              ..removeAt(index)
              ..insert(0, (source, decoded));
          }
          return Map<String, dynamic>.of(decoded);
        }
      }
    }
    final value = jsonDecode(extra);
    if (value is! Map) {
      return null;
    }
    final decoded = Map<String, dynamic>.from(value);
    if (remember) {
      _entries.insert(0, (extra, Map<String, dynamic>.of(decoded)));
      if (_entries.length > capacity) {
        _entries.removeLast();
      }
    }
    return decoded;
  }

  static void clear() => _entries.clear();
}
