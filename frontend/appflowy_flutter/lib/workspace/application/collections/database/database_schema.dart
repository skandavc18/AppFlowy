import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:flutter/foundation.dart';

/// One column of a table, as far as a collection needs to know about it.
@immutable
class DatabaseFieldSummary {
  const DatabaseFieldSummary({
    required this.id,
    required this.name,
    required this.type,
    required this.isPrimary,
    this.relatedDatabaseId,
  });

  final String id;
  final String name;
  final FieldType type;
  final bool isPrimary;

  /// The database a relation column points at, when this is one.
  final String? relatedDatabaseId;

  bool get isRelation => type == FieldType.Relation;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DatabaseFieldSummary &&
          other.id == id &&
          other.name == name &&
          other.type == type &&
          other.isPrimary == isPrimary &&
          other.relatedDatabaseId == relatedDatabaseId;

  @override
  int get hashCode => Object.hash(id, name, type, isPrimary, relatedDatabaseId);
}

/// What a table holds: its columns, how many rows, and which database it is.
@immutable
class DatabaseTableSummary {
  const DatabaseTableSummary({
    required this.viewId,
    required this.databaseId,
    required this.fields,
    required this.rowCount,
  });

  static const empty = DatabaseTableSummary(
    viewId: '',
    databaseId: '',
    fields: [],
    rowCount: 0,
  );

  final String viewId;
  final String databaseId;
  final List<DatabaseFieldSummary> fields;
  final int rowCount;

  bool get isEmpty => viewId.isEmpty;

  DatabaseFieldSummary? get primaryField {
    for (final field in fields) {
      if (field.isPrimary) {
        return field;
      }
    }
    return fields.isEmpty ? null : fields.first;
  }

  Iterable<DatabaseFieldSummary> get relations =>
      fields.where((field) => field.isRelation);
}

/// A column in one table that points at another.
@immutable
class DatabaseRelation {
  const DatabaseRelation({
    required this.fromViewId,
    required this.fieldName,
    required this.toDatabaseId,
    this.toViewId,
  });

  final String fromViewId;
  final String fieldName;
  final String toDatabaseId;

  /// The table in this collection the relation lands on, when it is one of
  /// them. A relation may point outside the collection, and that is reported
  /// rather than hidden.
  final String? toViewId;

  bool get isInternal => toViewId != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DatabaseRelation &&
          other.fromViewId == fromViewId &&
          other.fieldName == fieldName &&
          other.toDatabaseId == toDatabaseId &&
          other.toViewId == toViewId;

  @override
  int get hashCode =>
      Object.hash(fromViewId, fieldName, toDatabaseId, toViewId);
}

/// Resolves every relation column in [summaries] to the table it points at.
///
/// Pure, so the whole join is testable without a backend.
List<DatabaseRelation> buildDatabaseRelations(
  List<DatabaseTableSummary> summaries,
) {
  final byDatabaseId = <String, String>{
    for (final summary in summaries)
      if (summary.databaseId.isNotEmpty) summary.databaseId: summary.viewId,
  };
  return [
    for (final summary in summaries)
      for (final field in summary.relations)
        if (field.relatedDatabaseId?.isNotEmpty ?? false)
          DatabaseRelation(
            fromViewId: summary.viewId,
            fieldName: field.name,
            toDatabaseId: field.relatedDatabaseId!,
            toViewId: byDatabaseId[field.relatedDatabaseId],
          ),
  ];
}
