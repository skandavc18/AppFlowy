import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/foundation.dart';

/// The name a table is given before it is renamed.
const untitledTableName = 'Untitled table';

/// The layouts a table can be shown in.
///
/// These are AppFlowy's own database layouts, so a table in a collection is an
/// ordinary database view and every existing tool works on it unchanged.
const databaseTableLayouts = [
  ViewLayoutPB.Grid,
  ViewLayoutPB.Board,
  ViewLayoutPB.Calendar,
];

/// Whether [view] is a database rather than a page, a file or a folder.
bool isDatabaseTable(ViewPB view) => databaseTableLayouts.contains(view.layout);

/// One table in a database collection.
@immutable
class DatabaseTable {
  const DatabaseTable({required this.view});

  final ViewPB view;

  String get id => view.id;

  String get name => view.name.isNotEmpty ? view.name : untitledTableName;

  ViewLayoutPB get layout => view.layout;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DatabaseTable &&
          other.view.id == view.id &&
          other.view.name == view.name &&
          other.view.layout == view.layout;

  @override
  int get hashCode => Object.hash(view.id, view.name, view.layout);
}

/// The tables among a collection's children, in the order the folder holds
/// them. Anything that is not a database is left to the contents views.
List<DatabaseTable> databaseTablesFrom(List<ViewPB> views) => [
      for (final view in views)
        if (isDatabaseTable(view)) DatabaseTable(view: view),
    ];
