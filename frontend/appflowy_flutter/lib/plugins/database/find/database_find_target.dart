import 'package:flutter/foundation.dart';

/// Stable identities, never a row number, column label, or another view's ID.
@immutable
class DatabaseFindTarget {
  const DatabaseFindTarget.title(this.viewId)
      : rowId = null,
        fieldId = null;

  const DatabaseFindTarget.field(this.viewId, this.fieldId) : rowId = null;

  const DatabaseFindTarget.cell(this.viewId, this.rowId, this.fieldId);

  /// A real card/row boundary, used only when that layout omits a property.
  const DatabaseFindTarget.row(this.viewId, this.rowId) : fieldId = null;

  final String viewId;
  final String? rowId;
  final String? fieldId;

  bool get isTitle => rowId == null && fieldId == null;
  bool get isRow => rowId != null && fieldId == null;

  static DatabaseFindTarget? parse(String viewId, String partId) {
    if (viewId.isEmpty) return null;
    if (partId == 'title') return DatabaseFindTarget.title(viewId);
    final parts = partId.split(':');
    if (parts.length == 2 && parts[0] == 'field' && parts[1].isNotEmpty) {
      return DatabaseFindTarget.field(viewId, parts[1]);
    }
    if (parts.length == 3 &&
        parts[0] == 'row' &&
        parts[1].isNotEmpty &&
        parts[2].isNotEmpty) {
      return DatabaseFindTarget.cell(viewId, parts[1], parts[2]);
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is DatabaseFindTarget &&
      viewId == other.viewId &&
      rowId == other.rowId &&
      fieldId == other.fieldId;

  @override
  int get hashCode => Object.hash(viewId, rowId, fieldId);
}

/// The current renderer's membership/order, captured BEFORE reading cells.
/// Native GetFields alone does not describe hidden columns. A null snapshot
/// means the layout cannot attest membership; it must not invent a row order.
@immutable
class DatabaseFindViewSnapshot {
  DatabaseFindViewSnapshot({
    required this.viewId,
    required Iterable<String> rowIds,
    required Iterable<String> fieldIds,
    this.revision,
  })  : rowIds = List.unmodifiable(rowIds),
        fieldIds = List.unmodifiable(fieldIds);

  final String viewId;
  final List<String> rowIds;
  final List<String> fieldIds;
  final Object? revision;

  bool contains(DatabaseFindTarget target) =>
      target.viewId == viewId &&
      (target.rowId == null || rowIds.contains(target.rowId)) &&
      (target.fieldId == null || fieldIds.contains(target.fieldId));

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DatabaseFindViewSnapshot &&
          viewId == other.viewId &&
          revision == other.revision &&
          listEquals(rowIds, other.rowIds) &&
          listEquals(fieldIds, other.fieldIds));

  @override
  int get hashCode => Object.hash(
        viewId,
        revision,
        Object.hashAll(rowIds),
        Object.hashAll(fieldIds),
      );
}
