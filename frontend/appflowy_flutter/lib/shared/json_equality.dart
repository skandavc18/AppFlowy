/// Whether two decoded JSON values hold the same thing.
///
/// Maps and lists compare by identity, so a document read back from storage
/// never `==` the one that was written — and anything that decides "did this
/// change?" with `==` then mistakes every echo of its own write for news.
/// Shared sub-trees are recognised by identity first, so comparing a value
/// with a lightly edited copy of itself costs only the part that differs.
bool jsonValuesEqual(Object? a, Object? b) {
  if (identical(a, b)) {
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) {
      return false;
    }
    for (final entry in a.entries) {
      final other = b[entry.key];
      if (other == null && !b.containsKey(entry.key)) {
        return false;
      }
      if (!jsonValuesEqual(entry.value, other)) {
        return false;
      }
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) {
      return false;
    }
    for (var index = 0; index < a.length; index++) {
      if (!jsonValuesEqual(a[index], b[index])) {
        return false;
      }
    }
    return true;
  }
  return a == b;
}
