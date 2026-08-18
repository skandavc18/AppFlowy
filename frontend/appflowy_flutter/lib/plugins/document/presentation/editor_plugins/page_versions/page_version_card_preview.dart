import 'package:appflowy/workspace/application/page_versions/page_versions.dart';
import 'package:appflowy/workspace/application/view/view_preview_mode.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/icon.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A remembered page, drawn by the preview the folder gallery already uses.
///
/// A version is a snapshot, so the widget is fed a made-up view and a preview
/// built from what was stored rather than from the backend — but it is the
/// same preview a folder card, a search result and an embed all show, so a
/// remembered table reads as a table and a remembered file as its own file.
class PageVersionCardPreview extends StatelessWidget {
  const PageVersionCardPreview({
    super.key,
    required this.payload,
    this.filePath,
  });

  final PageVersionPayload payload;

  /// Where the stored copy of a file landed, so pictures and PDFs can show
  /// themselves rather than a sheet of ruled lines.
  final String? filePath;

  @override
  Widget build(BuildContext context) {
    final view = pageVersionPreviewView(payload, filePath: filePath);
    final item = WorkspaceExplorerItem.fromView(view);
    final preview = pageVersionGalleryPreview(
      payload,
      view: view,
      item: item,
    );
    return LayoutBuilder(
      builder: (context, constraints) => FolderGalleryPreviewThumbnail(
        item: item,
        view: view,
        preview: SynchronousFuture(preview),
        userProfile: null,
        height: constraints.maxHeight.isFinite ? constraints.maxHeight : 160,
        borderRadius: BorderRadius.zero,
        compact: true,
        // ⚠️ A view with no preference asks for its COVER, which a version has
        // no signed-in reader to fetch — that is a blank thumbnail. What was
        // in it is the point here anyway.
        previewMode: ViewPreviewMode.content,
      ),
    );
  }
}

/// The view a remembered page would have had.
ViewPB pageVersionPreviewView(
  PageVersionPayload payload, {
  String? filePath,
}) {
  final settings = payload.settings;
  final file = payload.file;
  // ⚠️ Dressing a file or folder as a workspace item is what routes it to the
  // same preview the folder gallery draws, and keeps anything from asking the
  // backend for a page that may be gone.
  final metadata = switch (payload.shape) {
    PageVersionShape.file => WorkspaceItemMetadata.file(
        contentKind: WorkspaceFileContentKind.binary,
        storageUrl: filePath,
        size: file?.bytes ?? 0,
      ),
    PageVersionShape.container => const WorkspaceItemMetadata.folder(),
    _ => null,
  };
  return ViewPB(
    name: payload.shape == PageVersionShape.file &&
            (file?.name.isNotEmpty ?? false)
        ? file!.name
        : settings.name,
    layout: ViewLayoutPB.valueOf(settings.layout) ?? ViewLayoutPB.Document,
    extra: metadata?.mergeIntoExtra(settings.extra) ?? settings.extra,
    icon: settings.iconValue.isEmpty
        ? null
        : ViewIconPB(
            ty: ViewIconTypePB.valueOf(settings.iconType) ??
                ViewIconTypePB.Emoji,
            value: settings.iconValue,
          ),
  );
}

/// What the gallery should draw for a remembered page.
FolderGalleryPreview pageVersionGalleryPreview(
  PageVersionPayload payload, {
  required ViewPB view,
  required WorkspaceExplorerItem item,
}) {
  if (payload.shape == PageVersionShape.database) {
    return FolderGalleryPreview(
      kind: FolderGalleryPreviewKind.database,
      blocks: const [],
      wordCount: 0,
      readingMinutes: 0,
      tags: const [],
      fileTypeLabel: 'TABLE',
      database: pageVersionDatabaseSnapshot(payload.table),
    );
  }
  return FolderGalleryPreviewParser.withoutDocument(view: view, item: item) ??
      FolderGalleryPreviewParser.unavailable(view: view, item: item);
}

/// A stored table, cut down to what a preview card shows.
FolderGalleryDatabaseSnapshot? pageVersionDatabaseSnapshot(
  PageVersionTable? table,
) {
  if (table == null || table.columns.isEmpty) {
    return null;
  }
  final columns = table.columns
      .take(FolderGalleryDatabasePreviewLoader.maximumColumns)
      .toList(growable: false);
  return FolderGalleryDatabaseSnapshot(
    columns: List.unmodifiable(
      columns.map(
        (column) => column.name.trim().isEmpty ? 'Untitled' : column.name,
      ),
    ),
    rows: List.unmodifiable(
      table.rows.take(FolderGalleryDatabasePreviewLoader.maximumRows).map(
            (row) => List<String>.unmodifiable(
              columns.map((column) => row.cells[column.id] ?? ''),
            ),
          ),
    ),
    totalRowCount: table.rows.length,
  );
}
