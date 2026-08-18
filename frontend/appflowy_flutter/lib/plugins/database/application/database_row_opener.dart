import 'package:flutter/foundation.dart';

/// How a host wants a row opened.
///
/// A table normally opens a row in a dialog of its own. A version preview is
/// already a dialog, and the row it shows is a record rather than something to
/// edit, so it takes the row over itself instead.
@immutable
class DatabaseRowOpener {
  const DatabaseRowOpener(this.open);

  final void Function(String rowId) open;
}
