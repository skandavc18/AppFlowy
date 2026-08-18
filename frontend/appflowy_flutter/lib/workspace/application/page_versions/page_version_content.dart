import 'dart:convert';
import 'dart:io';

import 'package:appflowy/plugins/database/application/row/row_service.dart';
import 'package:appflowy/plugins/database/domain/field_service.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_util.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/workspace/application/canvas/canvas_metadata.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_metadata.dart';
import 'package:appflowy/workspace/application/page_versions/page_version.dart';
import 'package:appflowy/workspace/application/providers/collection_source.dart';
import 'package:appflowy/workspace/application/providers/provider_controller.dart';
import 'package:appflowy/workspace/application/settings/share/import_service.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart' show Document;
import 'package:appflowy_result/appflowy_result.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// What a remembered state of an object actually holds.
///
/// A page, a table, a folder and a file are all "views" to the sidebar but are
/// nothing alike underneath, so a version says which shape it is and every
/// reader switches on that rather than guessing from the layout.
enum PageVersionShape {
  /// A written page — its blocks are kept.
  document,

  /// A workspace file — its bytes are kept beside the record.
  file,

  /// A folder or collection — what it held is kept.
  container,

  /// A table and every reading built on one — its columns and rows are kept.
  database,

  /// A canvas or a dashboard — its whole arrangement lives in `extra`.
  board,

  /// One row of a table: the cells it showed, and the page behind it.
  row,

  /// Everything else. Only what the view says about itself is kept.
  settings;

  static PageVersionShape fromName(Object? value) => PageVersionShape.values
      .firstWhere((shape) => shape.name == value, orElse: () => settings);
}

/// The shape a view's history takes.
///
/// ⚠️ Order matters. A chart, a map and a slide deck are Grid views wearing a
/// mark, so the layout tests below catch them — but a canvas and a dashboard
/// are Documents whose blocks are EMPTY: everything they hold is in `extra`,
/// so they have to be caught before the document test or a version of one
/// records nothing at all.
PageVersionShape pageVersionShapeOf(ViewPB view) {
  if (view.isWorkspaceFile) {
    return PageVersionShape.file;
  }
  if (view.isCollection || view.isWorkspaceFolder) {
    return PageVersionShape.container;
  }
  if (view.isCanvas || view.isDashboard) {
    return PageVersionShape.board;
  }
  return switch (view.layout) {
    ViewLayoutPB.Grid ||
    ViewLayoutPB.Board ||
    ViewLayoutPB.Calendar =>
      PageVersionShape.database,
    ViewLayoutPB.Document => PageVersionShape.document,
    _ => PageVersionShape.settings,
  };
}

/// Which row of which table a page belongs to.
///
/// A row's page is an ordinary view, so nothing about it says it is a row.
/// Told where it sits, a version of it keeps the row's cells as well as its
/// writing — which is what makes the history reached from the row page and
/// the history reached from the table agree.
@immutable
class PageVersionRowContext {
  const PageVersionRowContext({required this.tableViewId, required this.rowId});

  final String tableViewId;
  final String rowId;

  bool get isEmpty => tableViewId.isEmpty || rowId.isEmpty;
}

/// What a view says about itself, kept for every shape.
///
/// `extra` is the important one: the cover, the icon choice, and every
/// envelope the application writes there — chart, map, slide, dashboard,
/// canvas, collection, table view, property styles — all live in that string,
/// so putting it back restores an arrangement no other payload could.
@immutable
class PageVersionViewSettings {
  const PageVersionViewSettings({
    required this.name,
    required this.extra,
    this.layout = 0,
    this.iconType = 0,
    this.iconValue = '',
  });

  factory PageVersionViewSettings.fromView(ViewPB view) =>
      PageVersionViewSettings(
        name: view.name,
        extra: view.extra,
        layout: view.layout.value,
        iconType: view.hasIcon() ? view.icon.ty.value : 0,
        iconValue: view.hasIcon() ? view.icon.value : '',
      );

  factory PageVersionViewSettings.fromJson(Map<String, Object?> values) =>
      PageVersionViewSettings(
        name: values['name'] as String? ?? '',
        extra: values['extra'] as String? ?? '',
        layout: values['layout'] is int ? values['layout']! as int : 0,
        iconType: values['icon_ty'] is int ? values['icon_ty']! as int : 0,
        iconValue: values['icon_value'] as String? ?? '',
      );

  final String name;
  final String extra;
  final int layout;
  final int iconType;
  final String iconValue;

  bool get hasIcon => iconValue.isNotEmpty;

  Map<String, Object?> toJson() => {
        'name': name,
        'extra': extra,
        'layout': layout,
        if (iconValue.isNotEmpty) ...{
          'icon_ty': iconType,
          'icon_value': iconValue,
        },
      };
}

/// One thing a folder or collection held.
@immutable
class PageVersionChild {
  const PageVersionChild({
    required this.id,
    required this.name,
    required this.layout,
    this.icon = '',
    this.isFolder = false,
  });

  factory PageVersionChild.fromView(ViewPB view) => PageVersionChild(
        id: view.id,
        name: view.name,
        layout: view.layout.value,
        icon: view.hasIcon() ? view.icon.value : '',
        isFolder: view.isWorkspaceFolder || view.isCollection,
      );

  factory PageVersionChild.fromJson(Map<String, Object?> values) =>
      PageVersionChild(
        id: values['id'] as String? ?? '',
        name: values['name'] as String? ?? '',
        layout: values['layout'] is int ? values['layout']! as int : 0,
        icon: values['icon'] as String? ?? '',
        isFolder: values['folder'] == true,
      );

  final String id;
  final String name;
  final int layout;
  final String icon;
  final bool isFolder;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'layout': layout,
        if (icon.isNotEmpty) 'icon': icon,
        if (isFolder) 'folder': true,
      };
}

/// A table as it stood: its columns, and every row as text.
@immutable
class PageVersionTable {
  const PageVersionTable({required this.columns, required this.rows});

  factory PageVersionTable.fromJson(Map<String, Object?> values) {
    final columns = <PageVersionColumn>[];
    final rawColumns = values['columns'];
    if (rawColumns is List) {
      for (final column in rawColumns) {
        if (column is Map) {
          columns.add(
            PageVersionColumn(
              id: column['id'] as String? ?? '',
              name: column['name'] as String? ?? '',
              fieldType: column['type'] is int ? column['type']! as int : 0,
              isPrimary: column['primary'] == true,
            ),
          );
        }
      }
    }
    final rows = <PageVersionRow>[];
    final rawRows = values['rows'];
    if (rawRows is List) {
      for (final row in rawRows) {
        if (row is Map) {
          rows.add(PageVersionRow.fromJson(Map<String, Object?>.from(row)));
        }
      }
    }
    return PageVersionTable(columns: columns, rows: rows);
  }

  final List<PageVersionColumn> columns;
  final List<PageVersionRow> rows;

  bool get isEmpty => rows.isEmpty;

  /// The table as delimited text, which is how it is put back — the importer
  /// reads the column names off the first line.
  String toCsv() {
    String escape(String value) {
      if (value.contains(',') || value.contains('"') || value.contains('\n')) {
        return '"${value.replaceAll('"', '""')}"';
      }
      return value;
    }

    final lines = <String>[
      columns.map((column) => escape(column.name)).join(','),
      for (final row in rows)
        columns.map((column) => escape(row.cells[column.id] ?? '')).join(','),
    ];
    return lines.join('\n');
  }

  Map<String, Object?> toJson() => {
        'columns': [
          for (final column in columns)
            {
              'id': column.id,
              'name': column.name,
              'type': column.fieldType,
              if (column.isPrimary) 'primary': true,
            },
        ],
        'rows': [
          for (final row in rows) row.toJson(),
        ],
      };
}

@immutable
class PageVersionColumn {
  const PageVersionColumn({
    required this.id,
    required this.name,
    this.fieldType = 0,
    this.isPrimary = false,
  });

  final String id;
  final String name;

  /// The `FieldType` value, so a stored cell is classified the way the live
  /// table classifies it — a checkbox draws as a checkbox, a select as tags.
  final int fieldType;

  final bool isPrimary;
}

/// One row as it stood: the cells it showed, and the page behind it.
///
/// A table is a collection of rows and a row is a page of its own, so a
/// version of a table has to carry both or opening a remembered row shows an
/// empty page.
@immutable
class PageVersionRow {
  const PageVersionRow({
    required this.id,
    required this.cells,
    this.documentId = '',
    this.document,
  });

  factory PageVersionRow.fromJson(Map<String, Object?> values) =>
      PageVersionRow(
        id: values['id'] as String? ?? '',
        cells: values['cells'] is Map
            ? Map<String, String>.from(values['cells']! as Map)
            : const {},
        documentId: values['document_id'] as String? ?? '',
        document: values['document'] is Map
            ? Map<String, Object?>.from(values['document']! as Map)
            : null,
      );

  final String id;
  final Map<String, String> cells;

  /// The page behind the row, which is a view of its own.
  final String documentId;

  /// That page's blocks, when it had any.
  final Map<String, Object?>? document;

  Map<String, Object?> toJson() => {
        'id': id,
        'cells': cells,
        if (documentId.isNotEmpty) 'document_id': documentId,
        if (document != null) 'document': document,
      };
}

/// What a workspace file was, and where its bytes were kept.
@immutable
class PageVersionFile {
  const PageVersionFile({
    required this.name,
    required this.extension,
    required this.bytes,
    this.stored = true,
  });

  factory PageVersionFile.fromJson(Map<String, Object?> values) =>
      PageVersionFile(
        name: values['name'] as String? ?? '',
        extension: values['extension'] as String? ?? '',
        bytes: values['bytes'] is int ? values['bytes']! as int : 0,
        stored: values['stored'] != false,
      );

  final String name;
  final String extension;
  final int bytes;

  /// Whether a copy of the bytes was kept, or only the record of the file.
  final bool stored;

  Map<String, Object?> toJson() => {
        'name': name,
        'extension': extension,
        'bytes': bytes,
        if (!stored) 'stored': false,
      };
}

/// Where a collection's contents actually live, when it is not this side.
@immutable
class PageVersionLink {
  const PageVersionLink({
    required this.service,
    this.name = '',
    this.url = '',
    this.readOnly = false,
    this.listed = false,
  });

  factory PageVersionLink.fromJson(Map<String, Object?> values) =>
      PageVersionLink(
        service: values['service'] as String? ?? '',
        name: values['name'] as String? ?? '',
        url: values['url'] as String? ?? '',
        readOnly: values['read_only'] == true,
        listed: values['listed'] == true,
      );

  final String service;
  final String name;
  final String url;
  final bool readOnly;

  /// Whether the service was actually asked what it held at the time.
  final bool listed;

  Map<String, Object?> toJson() => {
        'service': service,
        if (name.isNotEmpty) 'name': name,
        if (url.isNotEmpty) 'url': url,
        if (readOnly) 'read_only': true,
        if (listed) 'listed': true,
      };
}

/// The writing a stored page holds, or null when there is none to read.
Document? pageVersionDocumentOf(Map<String, Object?>? stored) {
  if (stored == null) {
    return null;
  }
  try {
    return Document.fromJson(Map<String, dynamic>.from(stored));
  } on Object catch (error) {
    Log.warn('A stored page could not be read as a document: $error');
    return null;
  }
}

/// Everything one version holds.
@immutable
class PageVersionPayload {
  const PageVersionPayload({
    required this.shape,
    required this.settings,
    this.document,
    this.file,
    this.children,
    this.table,
    this.link,
  });

  factory PageVersionPayload.fromJson(Map<String, Object?> values) {
    if (!values.containsKey('shape')) {
      // Written before anything but a page was remembered: the whole file was
      // the document.
      return PageVersionPayload(
        shape: PageVersionShape.document,
        settings: const PageVersionViewSettings(name: '', extra: ''),
        document: values,
      );
    }

    final settings = values['settings'];
    final children = values['children'];
    final table = values['table'];
    final file = values['file'];
    final link = values['link'];
    return PageVersionPayload(
      shape: PageVersionShape.fromName(values['shape']),
      settings: settings is Map
          ? PageVersionViewSettings.fromJson(
              Map<String, Object?>.from(settings),
            )
          : const PageVersionViewSettings(name: '', extra: ''),
      document: values['document'] is Map
          ? Map<String, Object?>.from(values['document']! as Map)
          : null,
      file: file is Map
          ? PageVersionFile.fromJson(Map<String, Object?>.from(file))
          : null,
      link: link is Map
          ? PageVersionLink.fromJson(Map<String, Object?>.from(link))
          : null,
      children: children is List
          ? [
              for (final child in children)
                if (child is Map)
                  PageVersionChild.fromJson(Map<String, Object?>.from(child)),
            ]
          : null,
      table: table is Map
          ? PageVersionTable.fromJson(Map<String, Object?>.from(table))
          : null,
    );
  }

  final PageVersionShape shape;
  final PageVersionViewSettings settings;

  /// The editor document, in the form `Document.fromJson` reads.
  final Map<String, Object?>? document;

  final PageVersionFile? file;
  final List<PageVersionChild>? children;
  final PageVersionTable? table;

  /// Set when the collection's contents live in another service.
  final PageVersionLink? link;

  Document? get editorDocument => pageVersionDocumentOf(document);

  Map<String, Object?> toJson() => {
        'shape': shape.name,
        'settings': settings.toJson(),
        if (document != null) 'document': document,
        if (file != null) 'file': file!.toJson(),
        if (link != null) 'link': link!.toJson(),
        if (children != null)
          'children': [for (final child in children!) child.toJson()],
        if (table != null) 'table': table!.toJson(),
      };
}

/// A version as it was just read, before it is written down.
@immutable
class CapturedPage {
  const CapturedPage({
    required this.payload,
    this.fileBytes,
  });

  final PageVersionPayload payload;

  /// A workspace file's own bytes, kept beside the record rather than inside
  /// it — a JSON string holding a base64 photograph is nobody's friend.
  final Uint8List? fileBytes;
}

/// Reads whatever a view is holding right now.
///
/// Every shape goes through here, so a version is captured the same way
/// wherever it was asked for — a page being closed, a rail being opened, or a
/// sweep of the workspace.
abstract final class PageVersionReader {
  static Future<CapturedPage?> read(
    ViewPB view, {
    Document? openDocument,
    int maximumFileBytes = PageVersionPolicy.defaultMaximumFileBytes,
    bool readLinkedCollections = false,
    PageVersionRowContext? row,
  }) async {
    final settings = PageVersionViewSettings.fromView(view);
    final shape = pageVersionShapeOf(view);

    // A row's page is a document like any other; what makes it a row is the
    // table it belongs to, which only the caller knows.
    if (row != null && !row.isEmpty) {
      final document = openDocument ?? await _readDocument(view.id);
      return CapturedPage(
        payload: PageVersionPayload(
          shape: PageVersionShape.row,
          settings: settings,
          document: document?.toJson(),
          table: await readRow(row),
        ),
      );
    }

    switch (shape) {
      case PageVersionShape.document:
        final document = openDocument ?? await _readDocument(view.id);
        return CapturedPage(
          payload: PageVersionPayload(
            shape: shape,
            settings: settings,
            document: document?.toJson(),
          ),
        );

      case PageVersionShape.file:
        return _readFile(view, settings, maximumFileBytes);

      case PageVersionShape.container:
        final source = view.source;
        if (source.isRemote) {
          return _readLinkedCollection(
            view,
            settings,
            source,
            readLinkedCollections,
          );
        }
        final children = await ViewBackendService.getChildViews(
          viewId: view.id,
        ).fold<List<ViewPB>>((views) => views, (_) => const []);
        return CapturedPage(
          payload: PageVersionPayload(
            shape: shape,
            settings: settings,
            children: [
              for (final child in children) PageVersionChild.fromView(child),
            ],
          ),
        );

      case PageVersionShape.database:
        final table = await readTable(view.id);
        return CapturedPage(
          payload: PageVersionPayload(
            shape: shape,
            settings: settings,
            table: table,
          ),
        );

      case PageVersionShape.board:
        // A canvas and a dashboard keep everything in `extra`, which every
        // shape stores already.
        return CapturedPage(
          payload: PageVersionPayload(shape: shape, settings: settings),
        );

      case PageVersionShape.row:
      case PageVersionShape.settings:
        return CapturedPage(
          payload: PageVersionPayload(shape: shape, settings: settings),
        );
    }
  }

  /// The cells of one row, with the columns they belong to.
  static Future<PageVersionTable?> readRow(PageVersionRowContext row) async {
    final table = await readTable(row.tableViewId, withPages: false);
    if (table == null) {
      return null;
    }
    final mine = table.rows.where((stored) => stored.id == row.rowId).toList();
    return PageVersionTable(columns: table.columns, rows: mine);
  }

  static Future<Document?> _readDocument(String viewId) async {
    try {
      final result = await DocumentService().getDocument(documentId: viewId);
      return result.fold((data) => data.toDocument(), (error) {
        Log.warn('The page $viewId could not be read for versioning: $error');
        return null;
      });
    } on Object catch (error) {
      Log.warn('The page $viewId could not be read for versioning: $error');
      return null;
    }
  }

  /// A collection whose contents live in somebody else's service.
  ///
  /// ⚠️ Reading it means reaching out over the network, so it only happens
  /// when that has been asked for. Otherwise the version records the binding
  /// and what the collection says about itself, which is what actually changes
  /// on this side.
  static Future<CapturedPage?> _readLinkedCollection(
    ViewPB view,
    PageVersionViewSettings settings,
    CollectionSource source,
    bool readContents,
  ) async {
    final link = PageVersionLink(
      service: source.service.name,
      name: source.remoteName,
      url: source.remoteUrl,
      readOnly: source.readOnly,
      listed: readContents,
    );

    if (!readContents) {
      return CapturedPage(
        payload: PageVersionPayload(
          shape: PageVersionShape.container,
          settings: settings,
          link: link,
        ),
      );
    }

    final controller = ProviderController(
      collectionId: view.id,
      source: source,
      autoRefresh: Duration.zero,
    );
    try {
      await controller.refresh(silent: true);
      final nodes = controller.childrenOf(null);
      return CapturedPage(
        payload: PageVersionPayload(
          shape: PageVersionShape.container,
          settings: settings,
          link: link,
          children: [
            for (final node in nodes)
              PageVersionChild(
                id: node.id,
                name: node.name,
                layout: 0,
                isFolder: node.isFolder,
              ),
          ],
        ),
      );
    } on Object catch (error) {
      Log.warn('A linked collection could not be read for versioning: $error');
      return CapturedPage(
        payload: PageVersionPayload(
          shape: PageVersionShape.container,
          settings: settings,
          link: link,
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  static Future<CapturedPage?> _readFile(
    ViewPB view,
    PageVersionViewSettings settings,
    int maximumFileBytes,
  ) async {
    final source = view.workspaceItem?.storageUrl ?? '';
    if (source.isEmpty) {
      return null;
    }
    final path = await resolveLocalStorageFilePath(source);
    if (path == null) {
      // A file kept in the cloud is not copied here; sending somebody's
      // whole library through a version list is not what history means.
      return _fileRecord(settings, view.name, '', 0);
    }
    final file = File(path);
    if (!file.existsSync()) {
      return null;
    }
    final length = file.lengthSync();
    // A film is worth a version even when it is too big to copy: the record of
    // what stood there is the point, and a history with gaps in it is worse.
    if (maximumFileBytes == 0 ||
        (maximumFileBytes > 0 && length > maximumFileBytes)) {
      return _fileRecord(settings, p.basename(path), path, length);
    }
    final bytes = await file.readAsBytes();
    return CapturedPage(
      payload: PageVersionPayload(
        shape: PageVersionShape.file,
        settings: settings,
        file: PageVersionFile(
          name: p.basename(path),
          extension: p.extension(path).replaceFirst('.', ''),
          bytes: length,
        ),
      ),
      fileBytes: bytes,
    );
  }

  static CapturedPage _fileRecord(
    PageVersionViewSettings settings,
    String name,
    String path,
    int length,
  ) {
    return CapturedPage(
      payload: PageVersionPayload(
        shape: PageVersionShape.file,
        settings: settings,
        file: PageVersionFile(
          name: name,
          extension: path.isEmpty
              ? p.extension(name).replaceFirst('.', '')
              : p.extension(path).replaceFirst('.', ''),
          bytes: length,
          stored: false,
        ),
      ),
    );
  }

  /// A table's columns and rows, as text.
  static Future<PageVersionTable?> readTable(
    String viewId, {
    bool withPages = true,
  }) async {
    try {
      final fields = await FieldBackendService.getFields(viewId: viewId)
          .fold<List<FieldPB>>((fields) => fields, (_) => const []);
      final rows = await DatabaseEventGetRowsAsText(
        DatabaseViewIdPB()..value = viewId,
      ).send().fold<RepeatedRowTextPB?>((rows) => rows, (failure) {
        Log.warn(
          'The table $viewId could not be read for versioning: $failure',
        );
        return null;
      });
      if (rows == null) {
        return null;
      }

      final named = {for (final field in fields) field.id: field};
      final columns = [
        for (final id in rows.fieldIds)
          PageVersionColumn(
            id: id,
            name: named[id]?.name ?? id,
            fieldType: named[id]?.fieldType.value ?? 0,
            isPrimary: named[id]?.isPrimary ?? false,
          ),
      ];
      // A row's cells arrive in the same order as the column ids, not keyed by
      // them.
      final stored = <PageVersionRow>[];
      for (final row in rows.rows) {
        stored.add(
          PageVersionRow(
            id: row.rowId,
            cells: {
              for (var i = 0;
                  i < rows.fieldIds.length && i < row.cells.length;
                  i++)
                rows.fieldIds[i]: row.cells[i],
            },
          ),
        );
      }
      return PageVersionTable(
        columns: columns,
        rows: withPages ? await _readRowPages(viewId, stored) : stored,
      );
    } on Object catch (error) {
      Log.warn('The table $viewId could not be read for versioning: $error');
      return null;
    }
  }

  /// How many rows of a table are asked about their pages.
  ///
  /// Reading a page costs a call per row, so a very long table records its
  /// cells for every row but its pages only for the ones near the top.
  static const int maximumRowPages = 200;

  /// Reads the page behind each row, for the rows that have one.
  static Future<List<PageVersionRow>> _readRowPages(
    String viewId,
    List<PageVersionRow> rows,
  ) async {
    final service = RowBackendService(viewId: viewId);
    final read = <PageVersionRow>[];
    for (final row in rows) {
      if (read.length >= maximumRowPages) {
        read.addAll(rows.sublist(read.length));
        break;
      }
      final meta = await service.getRowMeta(row.id).fold<RowMetaPB?>(
            (meta) => meta,
            (_) => null,
          );
      final documentId = meta?.documentId ?? '';
      if (documentId.isEmpty) {
        read.add(PageVersionRow(id: row.id, cells: row.cells));
        continue;
      }
      // ⚠️ `isDocumentEmpty` is not to be trusted here — a row whose page was
      // written after the flag was last set still reads as empty, and the page
      // would be dropped. Reading it is the only way to know.
      final document = await _readDocument(documentId);
      final wrote = document?.root.children.any(
            (node) =>
                (node.delta?.toPlainText().trim().isNotEmpty ?? false) ||
                node.children.isNotEmpty,
          ) ??
          false;
      read.add(
        PageVersionRow(
          id: row.id,
          cells: row.cells,
          documentId: documentId,
          document: wrote ? document!.toJson() : null,
        ),
      );
    }
    return read;
  }
}

/// Puts back what a view says about itself.
///
/// This is the one restore every shape shares, and for a chart, a map, a slide
/// deck, a dashboard, a canvas or a collection it is the whole restore — their
/// arrangement lives in `extra`.
Future<bool> restoreViewSettings(
  ViewPB view,
  PageVersionViewSettings settings, {
  bool restoreName = true,
}) async {
  var restored = true;

  final wantsName = restoreName && settings.name != view.name;
  final wantsExtra = settings.extra != view.extra;
  if (wantsName || wantsExtra) {
    final result = await ViewBackendService.updateView(
      viewId: view.id,
      name: wantsName ? settings.name : null,
      extra: wantsExtra ? settings.extra : null,
    );
    restored = result.fold((_) => restored, (error) {
      Log.warn('The settings of ${view.id} could not be restored: $error');
      return false;
    });
  }

  final currentIcon = view.hasIcon() ? view.icon.value : '';
  if (settings.iconValue != currentIcon) {
    final icon = ViewIconPB()
      ..ty = ViewIconTypePB.valueOf(settings.iconType) ?? ViewIconTypePB.Icon
      ..value = settings.iconValue;
    final result = await ViewBackendService.updateViewIcon(
      view: view,
      viewIcon: icon.toEmojiIconData(),
    );
    restored = result.fold((_) => restored, (error) {
      Log.warn('The icon of ${view.id} could not be restored: $error');
      return false;
    });
  }

  return restored;
}

/// Writes a workspace file's stored bytes back where they came from.
Future<bool> restoreWorkspaceFile(ViewPB view, File stored) async {
  final source = view.workspaceItem?.storageUrl ?? '';
  if (source.isEmpty) {
    return false;
  }
  final path = await resolveLocalStorageFilePath(source);
  if (path == null) {
    return false;
  }
  try {
    // Staged then renamed, so a half-written file never replaces a whole one.
    final staged = File('$path.restoring');
    await stored.copy(staged.path);
    await staged.rename(path);
    return true;
  } on Object catch (error) {
    Log.error('The file ${view.id} could not be restored: $error');
    return false;
  }
}

/// Puts a folder's contents back in the order they were in.
///
/// Only what still exists can be moved; anything deleted since is reported so
/// the person is told rather than left wondering.
Future<PageVersionOrderResult> restoreChildOrder(
  ViewPB view,
  List<PageVersionChild> children,
) async {
  final present = await ViewBackendService.getChildViews(viewId: view.id)
      .fold<List<ViewPB>>((views) => views, (_) => const []);
  final byId = {for (final child in present) child.id: child};

  final wanted = children
      .where((child) => byId.containsKey(child.id))
      .toList(growable: false);
  final missing = children.length - wanted.length;

  String? previous;
  for (final child in wanted) {
    await ViewBackendService.moveViewV2(
      viewId: child.id,
      newParentId: view.id,
      prevViewId: previous,
    );
    previous = child.id;
  }

  return PageVersionOrderResult(moved: wanted.length, missing: missing);
}

@immutable
class PageVersionOrderResult {
  const PageVersionOrderResult({required this.moved, required this.missing});

  final int moved;
  final int missing;
}

/// Brings a remembered table back as a new table beside the original.
///
/// ⚠️ Rows are deliberately NOT written back over the live table. A cell reads
/// out as text, and text cannot be written back into a select, a date, a
/// relation or a media column without corrupting it — so the honest restore is
/// a real table holding the old rows, to read, compare or copy from.
Future<ViewPB?> restoreTableAsCopy({
  required ViewPB view,
  required PageVersionTable table,
  required String name,
}) async {
  if (table.columns.isEmpty) {
    return null;
  }
  final parent = view.parentViewId;
  if (parent.isEmpty) {
    return null;
  }
  final result = await ImportBackendService.importPages(parent, [
    ImportItemPayloadPB.create()
      ..name = name
      ..data = utf8.encode(table.toCsv())
      ..viewLayout = ViewLayoutPB.Grid
      ..importType = ImportTypePB.CSV,
  ]);
  return result.fold(
    (views) => views.items.firstOrNull,
    (error) {
      Log.warn('A remembered table could not be brought back: $error');
      return null;
    },
  );
}
