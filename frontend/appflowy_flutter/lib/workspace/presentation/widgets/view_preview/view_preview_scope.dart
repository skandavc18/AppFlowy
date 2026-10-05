import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy_backend/protobuf/flowy-document/entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/widgets.dart';

/// The reads behind one surface's page previews, such as the search palette.
/// The surface owns them: documents come through its own reader, and a table
/// already drawn is kept only while the surface is open.
class ViewPreviewReads {
  ViewPreviewReads({
    required Future<DocumentDataPB?> Function(String viewId) readDocument,
    FolderGalleryDatabasePreviewLoader tables =
        const FolderGalleryDatabasePreviewLoader(
      columnLimit: largeColumnLimit,
      rowLimit: largeRowLimit,
    ),
  })  : _readDocument = readDocument,
        _tables = tables;

  factory ViewPreviewReads.native() => ViewPreviewReads(
        readDocument: (id) async =>
            (await DocumentService().getDocument(documentId: id))
                .fold((document) => document, (_) => null),
      );

  /// A preview pane is larger than a gallery card, so it reads more of a table.
  static const largeColumnLimit = 6;
  static const largeRowLimit = 16;

  final Future<DocumentDataPB?> Function(String viewId) _readDocument;
  final FolderGalleryDatabasePreviewLoader _tables;
  final _drawnTables = <String, (String, Future<FolderGalleryPreview>)>{};
  bool _disposed = false;

  Future<DocumentDataPB?> document(String viewId) => _readDocument(viewId);

  /// One read per table revision while the surface is open. [reload] reads
  /// again, after a failure say.
  Future<FolderGalleryPreview> table(ViewPB view, {bool reload = false}) {
    final stamp = '${view.layout.value}:${view.lastEdited}';
    final drawn = _drawnTables[view.id];
    if (!reload && drawn != null && drawn.$1 == stamp) return drawn.$2;
    final table = _tables.load(view: view);
    if (!_disposed) _drawnTables[view.id] = (stamp, table);
    return table;
  }

  void dispose() {
    _disposed = true;
    _drawnTables.clear();
  }
}

class ViewPreviewScope extends InheritedWidget {
  const ViewPreviewScope({
    super.key,
    required this.reads,
    required super.child,
  });

  final ViewPreviewReads reads;

  static ViewPreviewReads? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ViewPreviewScope>()?.reads;

  @override
  bool updateShouldNotify(ViewPreviewScope oldWidget) =>
      !identical(reads, oldWidget.reads);
}
