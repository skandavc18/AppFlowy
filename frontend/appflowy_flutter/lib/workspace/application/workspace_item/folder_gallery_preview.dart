import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/plugins/database/application/cell/cell_controller.dart';
import 'package:appflowy/plugins/database/application/cell/cell_data_loader.dart';
import 'package:appflowy/plugins/database/domain/cell_service.dart';
import 'package:appflowy/plugins/database/domain/database_view_service.dart';
import 'package:appflowy/plugins/database/domain/field_settings_service.dart';
import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/util/int64_extension.dart';
import 'package:appflowy/workspace/application/canvas/canvas_metadata.dart';
import 'package:appflowy/workspace/application/canvas/canvas_model.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_link.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_metadata.dart';
import 'package:appflowy/workspace/application/workspace_item/remote_file_head.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-document/entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:intl/intl.dart';
import 'package:markdown/markdown.dart' as markdown;

enum FolderGalleryPreviewKind {
  document,
  code,
  image,
  pdf,
  video,
  file,
  folder,
  database,
  chat,

  /// A dashboard, drawn from the widgets it holds.
  dashboard,

  /// A canvas, drawn from its cards, frames and connections.
  canvas,

  /// A saved link, drawn from what was learned about the page.
  link,
}

enum FolderGalleryPreviewBlockKind {
  paragraph,
  heading,
  bulletedList,
  numberedList,
  todo,
  quote,
  code,
  math,
}

/// Why a preview that was read has nothing to draw.
enum FolderGalleryPreviewNote {
  /// The page or file was read and holds nothing yet.
  empty,

  /// The file's bytes are not on this device, so there is nothing to read.
  missing,
}

@immutable
class FolderGalleryTextRun {
  const FolderGalleryTextRun({
    required this.text,
    this.bold = false,
    this.italic = false,
    this.inlineCode = false,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool inlineCode;
}

@immutable
class FolderGalleryPreviewBlock {
  const FolderGalleryPreviewBlock({
    required this.kind,
    required this.runs,
    this.level = 1,
    this.checked = false,
    this.language,
  });

  final FolderGalleryPreviewBlockKind kind;
  final List<FolderGalleryTextRun> runs;
  final int level;
  final bool checked;
  final String? language;

  String get plainText => runs.map((run) => run.text).join();
}

@immutable
class FolderGalleryPreview {
  const FolderGalleryPreview({
    required this.kind,
    required this.blocks,
    required this.wordCount,
    required this.readingMinutes,
    required this.tags,
    required this.fileTypeLabel,
    this.heroUrl,
    this.language,
    this.database,
    this.dashboard,
    this.canvas,
    this.link,
    this.unavailable = false,
    this.note,
  });

  final FolderGalleryPreviewKind kind;
  final List<FolderGalleryPreviewBlock> blocks;
  final int wordCount;
  final int readingMinutes;
  final List<String> tags;
  final String fileTypeLabel;
  final String? heroUrl;
  final String? language;
  final FolderGalleryDatabaseSnapshot? database;
  final DashboardDocument? dashboard;
  final CanvasDocument? canvas;
  final BookmarkMetadata? link;
  final bool unavailable;
  final FolderGalleryPreviewNote? note;

  bool get hasHero => heroUrl?.isNotEmpty ?? false;

  FolderGalleryPreview withNote(FolderGalleryPreviewNote note) =>
      FolderGalleryPreview(
        kind: kind,
        blocks: blocks,
        wordCount: wordCount,
        readingMinutes: readingMinutes,
        tags: tags,
        fileTypeLabel: fileTypeLabel,
        heroUrl: heroUrl,
        language: language,
        database: database,
        dashboard: dashboard,
        canvas: canvas,
        link: link,
        unavailable: unavailable,
        note: note,
      );
}

/// One select option as a table cell shows it: a tinted tag.
@immutable
class FolderGalleryTableOption {
  const FolderGalleryTableOption({required this.name, required this.color});

  final String name;
  final SelectOptionColorPB color;
}

@immutable
class FolderGalleryDatabaseSnapshot {
  const FolderGalleryDatabaseSnapshot({
    required this.columns,
    required this.rows,
    required this.totalRowCount,
    this.fieldTypes = const [],
    this.widths = const [],
    this.options = const {},
  });

  final List<String> columns;
  final List<List<String>> rows;
  final int totalRowCount;

  /// Native types for the displayed columns. Missing type information is not
  /// authority to index a cell (in particular a URL or opaque provider value).
  final List<FieldType> fieldTypes;

  /// The widths the table's own view saved for the displayed columns. Zero or
  /// missing means the column was never resized.
  final List<double> widths;

  /// Select options by (row, column), for cells drawn as tags. [rows] still
  /// holds their joined names, so every reader sees the same cell text.
  final Map<(int, int), List<FolderGalleryTableOption>> options;

  FieldType? typeAt(int column) =>
      column < fieldTypes.length ? fieldTypes[column] : null;

  double? widthAt(int column) {
    final width = column < widths.length ? widths[column] : 0.0;
    return width > 0 ? width : null;
  }

  List<FolderGalleryTableOption> optionsAt(int row, int column) =>
      options[(row, column)] ?? const [];
}

class FolderGalleryPreviewLoader {
  FolderGalleryPreviewLoader({
    DocumentService? documentService,
    FolderGalleryDatabasePreviewLoader? databasePreviewLoader,
    RemoteFileHeadReader? remoteReader,
  })  : _documentService = documentService ?? DocumentService(),
        _databasePreviewLoader =
            databasePreviewLoader ?? const FolderGalleryDatabasePreviewLoader(),
        _remoteReader = remoteReader ?? readRemoteFileHead;

  final DocumentService _documentService;
  final FolderGalleryDatabasePreviewLoader _databasePreviewLoader;
  final RemoteFileHeadReader _remoteReader;

  Future<FolderGalleryPreview> load({
    required ViewPB view,
    required WorkspaceExplorerItem item,
  }) async {
    try {
      // Chat is a real layout, not a provider node or a collab document. The
      // explorer's coarse item kind currently also calls it a database, so
      // this must precede BOTH content readers. Never invent message content.
      if (view.layout == ViewLayoutPB.Chat) {
        return FolderGalleryPreviewParser.chat(view);
      }
      if (item.kind == WorkspaceExplorerItemKind.database) {
        return await _databasePreviewLoader.load(view: view);
      }

      final immediate = FolderGalleryPreviewParser.withoutDocument(
        view: view,
        item: item,
      );
      if (immediate != null) {
        return await _withFileContent(immediate, view: view, item: item);
      }

      final result = await _documentService.getDocument(documentId: view.id);
      return result.fold(
        (document) => FolderGalleryPreviewParser.parse(
          view: view,
          item: item,
          document: document,
        ),
        (error) {
          Log.warn('Unable to load gallery preview for ${view.id}: $error');
          return FolderGalleryPreviewParser.unavailable(
            view: view,
            item: item,
          );
        },
      );
    } on Object catch (error) {
      Log.warn('Unable to load gallery preview for ${view.id}: $error');
      return FolderGalleryPreviewParser.unavailable(
        view: view,
        item: item,
      );
    }
  }

  /// Fills a text file's card with what the file actually says.
  ///
  /// A stored file has no collab document to parse, so the opening of the file
  /// itself becomes the preview — markdown keeps its structure, everything
  /// else reads as plain paragraphs.
  Future<FolderGalleryPreview> _withFileContent(
    FolderGalleryPreview preview, {
    required ViewPB view,
    required WorkspaceExplorerItem item,
  }) async {
    if (preview.kind != FolderGalleryPreviewKind.document &&
        preview.kind != FolderGalleryPreviewKind.code) {
      return preview;
    }
    final path = item.metadata?.storageUrl;
    if (path == null || path.isEmpty) {
      return FolderGalleryPreviewParser.unavailable(view: view, item: item);
    }
    final uri = Uri.tryParse(path);
    final scheme = uri?.scheme.toLowerCase() ?? '';
    // A file kept online is read the same way, but only its opening bytes are
    // fetched. An unread file is still not an empty file.
    final String? source;
    if (scheme == 'http' || scheme == 'https') {
      source = await _readRemoteHead(uri!);
    } else {
      final local = await _readHead(path);
      // Retrying cannot bring back a file that is not on this device.
      if (local.missing) {
        return preview.withNote(FolderGalleryPreviewNote.missing);
      }
      source = local.text;
    }
    if (source == null) {
      return FolderGalleryPreviewParser.unavailable(view: view, item: item);
    }
    if (source.trim().isEmpty) {
      return preview.withNote(FolderGalleryPreviewNote.empty);
    }

    final blocks = preview.kind == FolderGalleryPreviewKind.code
        ? [
            FolderGalleryPreviewBlock(
              kind: FolderGalleryPreviewBlockKind.code,
              runs: [FolderGalleryTextRun(text: source.trimRight())],
              language: preview.language,
            ),
          ]
        : isMarkdownFileName(item.name)
            ? parseMarkdownPreviewBlocks(source)
            : parsePlainTextPreviewBlocks(source);
    if (blocks.isEmpty) {
      return preview;
    }

    final words = blocks.map((block) => block.plainText).join(' ');
    return FolderGalleryPreview(
      kind: preview.kind,
      blocks: blocks,
      wordCount: FolderGalleryPreviewParser._wordCount(words),
      readingMinutes: words.trim().isEmpty ? 0 : 1,
      tags: preview.tags,
      fileTypeLabel: preview.fileTypeLabel,
      heroUrl: preview.heroUrl,
      language: preview.language,
      database: preview.database,
      unavailable: preview.unavailable,
    );
  }

  static const _maxPreviewBytes = 8 * 1024;

  Future<({String? text, bool missing})> _readHead(String path) async {
    try {
      final uri = Uri.tryParse(path);
      final file = uri?.scheme == 'file' ? File.fromUri(uri!) : File(path);
      final handle = await file.open();
      try {
        return (
          text: _decodeHead(await handle.read(_maxPreviewBytes + 1)),
          missing: false,
        );
      } finally {
        await handle.close();
      }
    } on PathNotFoundException {
      return (text: null, missing: true);
    } on Object catch (error) {
      Log.info('Unable to read the gallery file preview: $error');
      return (text: null, missing: false);
    }
  }

  Future<String?> _readRemoteHead(Uri uri) async {
    final bytes = await _remoteReader(uri, _maxPreviewBytes + 1);
    return bytes == null ? null : _decodeHead(bytes);
  }

  static String? _decodeHead(List<int> bytes) {
    final truncated = bytes.length > _maxPreviewBytes;
    final source = const Utf8Decoder(allowMalformed: true).convert(
      bytes,
      0,
      truncated ? _maxPreviewBytes : bytes.length,
    );
    // A bounded prefix with no words is not evidence that the whole file is
    // empty. Do not read the remainder merely to decorate a card.
    return truncated && source.trim().isEmpty ? null : source;
  }
}

bool isMarkdownFileName(String name) {
  final extension = name.split('.').last.toLowerCase();
  return extension == 'md' || extension == 'markdown';
}

/// Turns the opening of a plain file into paragraphs.
List<FolderGalleryPreviewBlock> parsePlainTextPreviewBlocks(
  String source, {
  int maximumBlocks = 12,
}) {
  final blocks = <FolderGalleryPreviewBlock>[];
  for (final line in const LineSplitter().convert(source)) {
    if (blocks.length >= maximumBlocks) {
      break;
    }
    if (line.trim().isEmpty) {
      continue;
    }
    blocks.add(
      FolderGalleryPreviewBlock(
        kind: FolderGalleryPreviewBlockKind.paragraph,
        runs: [FolderGalleryTextRun(text: line.trimRight())],
      ),
    );
  }
  return List.unmodifiable(blocks);
}

/// Lowers markdown source into the blocks the gallery card already renders,
/// so a `.md` file previews with its headings, lists and quotes intact.
///
/// The source goes through the markdown parser and then through the HTML
/// parser rather than being read line by line: a README is usually part
/// markdown and part raw HTML, and reading it as lines showed the tags.
List<FolderGalleryPreviewBlock> parseMarkdownPreviewBlocks(
  String source, {
  int maximumBlocks = 12,
}) {
  final String rendered;
  try {
    rendered = markdown.markdownToHtml(
      source,
      extensionSet: markdown.ExtensionSet.gitHubFlavored,
    );
  } on Object catch (error) {
    Log.info('Unable to render the markdown preview: $error');
    return parsePlainTextPreviewBlocks(source, maximumBlocks: maximumBlocks);
  }

  final blocks = <FolderGalleryPreviewBlock>[];
  final body = html_parser.parse(rendered).body;
  if (body != null) {
    _collectHtmlBlocks(body.nodes, blocks, maximumBlocks);
  }
  // An empty result means the file genuinely has nothing to read — a page of
  // badges, say. Only a renderer that produced nothing at all falls back to
  // the raw source, which would otherwise put the markup back on screen.
  if (blocks.isEmpty && rendered.trim().isEmpty) {
    return parsePlainTextPreviewBlocks(source, maximumBlocks: maximumBlocks);
  }
  return List.unmodifiable(blocks);
}

void _collectHtmlBlocks(
  List<html_dom.Node> nodes,
  List<FolderGalleryPreviewBlock> out,
  int maximumBlocks, {
  bool insideQuote = false,
}) {
  for (final node in nodes) {
    if (out.length >= maximumBlocks) {
      return;
    }
    if (node is html_dom.Text) {
      final text = node.text.trim();
      if (text.isNotEmpty) {
        _addBlock(
          out,
          FolderGalleryPreviewBlockKind.paragraph,
          [FolderGalleryTextRun(text: text)],
        );
      }
      continue;
    }
    if (node is! html_dom.Element) {
      continue;
    }

    switch (node.localName) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        _addBlock(
          out,
          FolderGalleryPreviewBlockKind.heading,
          _htmlInlineRuns(node),
          level: int.parse(node.localName!.substring(1)).clamp(1, 3),
        );
      case 'p':
        _addBlock(
          out,
          insideQuote
              ? FolderGalleryPreviewBlockKind.quote
              : FolderGalleryPreviewBlockKind.paragraph,
          _htmlInlineRuns(node),
        );
      case 'ul':
      case 'ol':
        final numbered = node.localName == 'ol';
        for (final item in node.children) {
          if (out.length >= maximumBlocks) {
            return;
          }
          if (item.localName != 'li') {
            continue;
          }
          final checkbox = item.querySelector('input[type="checkbox"]');
          if (checkbox != null) {
            _addBlock(
              out,
              FolderGalleryPreviewBlockKind.todo,
              _htmlInlineRuns(item),
              checked: checkbox.attributes.containsKey('checked'),
            );
            continue;
          }
          _addBlock(
            out,
            numbered
                ? FolderGalleryPreviewBlockKind.numberedList
                : FolderGalleryPreviewBlockKind.bulletedList,
            _htmlInlineRuns(item),
          );
        }
      case 'blockquote':
        _collectHtmlBlocks(
          node.nodes,
          out,
          maximumBlocks,
          insideQuote: true,
        );
      case 'pre':
        final code = node.text.trimRight();
        if (code.trim().isNotEmpty) {
          final language = node
              .querySelector('code')
              ?.className
              .split(RegExp(r'\s+'))
              .firstWhere(
                (name) => name.startsWith('language-'),
                orElse: () => '',
              )
              .replaceFirst('language-', '');
          out.add(
            FolderGalleryPreviewBlock(
              kind: FolderGalleryPreviewBlockKind.code,
              runs: [FolderGalleryTextRun(text: code)],
              language: language == null || language.isEmpty ? null : language,
            ),
          );
        }
      case 'hr':
      case 'script':
      case 'style':
      case 'table':
        break;
      default:
        // Containers a README wraps its banner in — div, center, section.
        _collectHtmlBlocks(
          node.nodes,
          out,
          maximumBlocks,
          insideQuote: insideQuote,
        );
    }
  }
}

void _addBlock(
  List<FolderGalleryPreviewBlock> out,
  FolderGalleryPreviewBlockKind kind,
  List<FolderGalleryTextRun> runs, {
  int level = 1,
  bool checked = false,
}) {
  // Image-only paragraphs — badge strips, banners — leave nothing to read.
  if (runs.every((run) => run.text.trim().isEmpty)) {
    return;
  }
  out.add(
    FolderGalleryPreviewBlock(
      kind: kind,
      runs: List.unmodifiable(runs),
      level: level,
      checked: checked,
    ),
  );
}

/// Flattens one HTML element into bold, italic and inline code runs.
List<FolderGalleryTextRun> _htmlInlineRuns(html_dom.Element element) {
  final runs = <FolderGalleryTextRun>[];

  void walk(
    List<html_dom.Node> nodes, {
    required bool bold,
    required bool italic,
    required bool inlineCode,
  }) {
    for (final node in nodes) {
      if (node is html_dom.Text) {
        final text = node.text.replaceAll(RegExp(r'\s+'), ' ');
        if (text.isNotEmpty) {
          runs.add(
            FolderGalleryTextRun(
              text: text,
              bold: bold,
              italic: italic,
              inlineCode: inlineCode,
            ),
          );
        }
        continue;
      }
      if (node is! html_dom.Element) {
        continue;
      }
      switch (node.localName) {
        case 'br':
          runs.add(const FolderGalleryTextRun(text: ' '));
        case 'img':
        case 'input':
        case 'script':
        case 'style':
          break;
        case 'strong':
        case 'b':
          walk(node.nodes, bold: true, italic: italic, inlineCode: inlineCode);
        case 'em':
        case 'i':
          walk(node.nodes, bold: bold, italic: true, inlineCode: inlineCode);
        case 'code':
          walk(node.nodes, bold: bold, italic: italic, inlineCode: true);
        default:
          walk(
            node.nodes,
            bold: bold,
            italic: italic,
            inlineCode: inlineCode,
          );
      }
    }
  }

  walk(element.nodes, bold: false, italic: false, inlineCode: false);
  final collapsed = runs
      .map(
        (run) => FolderGalleryTextRun(
          text: run.text,
          bold: run.bold,
          italic: run.italic,
          inlineCode: run.inlineCode,
        ),
      )
      .toList();
  if (collapsed.isNotEmpty) {
    collapsed[0] = FolderGalleryTextRun(
      text: collapsed.first.text.trimLeft(),
      bold: collapsed.first.bold,
      italic: collapsed.first.italic,
      inlineCode: collapsed.first.inlineCode,
    );
    collapsed[collapsed.length - 1] = FolderGalleryTextRun(
      text: collapsed.last.text.trimRight(),
      bold: collapsed.last.bold,
      italic: collapsed.last.italic,
      inlineCode: collapsed.last.inlineCode,
    );
  }
  return collapsed;
}

class FolderGalleryDatabasePreviewLoader {
  const FolderGalleryDatabasePreviewLoader({
    this.columnLimit = maximumColumns,
    this.rowLimit = maximumRows,
  });

  /// Enough of a table to fill a tall gallery card: the first columns as the
  /// view lays them out, and the first rows. Bigger previews ask for more.
  static const maximumColumns = 5;
  static const maximumRows = 8;

  final int columnLimit;
  final int rowLimit;

  Future<FolderGalleryPreview> load({required ViewPB view}) async {
    final service = DatabaseViewBackendService(viewId: view.id);
    final databaseResult = await service.openDatabase();
    return databaseResult.fold(
      (database) => _loadSnapshot(
        view: view,
        database: database,
        service: service,
      ),
      (error) async {
        Log.warn(
          'Unable to load database gallery preview for ${view.id}: $error',
        );
        return _unavailable(view);
      },
    );
  }

  Future<FolderGalleryPreview> _loadSnapshot({
    required ViewPB view,
    required DatabasePB database,
    required DatabaseViewBackendService service,
  }) async {
    // A column hidden in the view stays hidden in its preview. Settings only
    // shape the drawing: without them every column keeps its default width.
    final settings = await _fieldSettings(view.id);
    final requestedFields = database.fields
        .where(
          (field) =>
              settings[field.fieldId]?.visibility !=
              FieldVisibility.AlwaysHidden,
        )
        .take(columnLimit)
        .toList(growable: false);
    final fieldsResult = await service.getFields(fieldIds: requestedFields);
    return fieldsResult.fold(
      (fields) async {
        final byId = {for (final field in fields) field.id: field};
        final visibleFields = [
          for (final requested in requestedFields)
            if (byId[requested.fieldId] case final FieldPB field) field,
        ];
        final visibleRows =
            database.rows.take(rowLimit).toList(growable: false);
        final rows = await Future.wait(
          visibleRows.map(
            (row) => Future.wait(
              visibleFields.map(
                (field) => _loadCell(
                  viewId: view.id,
                  rowId: row.id,
                  field: field,
                ),
              ),
            ),
          ),
        );
        final options = <(int, int), List<FolderGalleryTableOption>>{};
        for (var row = 0; row < rows.length; row++) {
          for (var column = 0; column < rows[row].length; column++) {
            final tags = rows[row][column].options;
            if (tags.isNotEmpty) options[(row, column)] = tags;
          }
        }
        return FolderGalleryPreview(
          kind: FolderGalleryPreviewKind.database,
          blocks: const [],
          wordCount: 0,
          readingMinutes: 0,
          tags: FolderGalleryPreviewParser.tagsFromExtra(view.extra),
          fileTypeLabel: 'TABLE',
          database: FolderGalleryDatabaseSnapshot(
            columns: List.unmodifiable(
              visibleFields.map(
                (field) => field.name.trim().isEmpty ? 'Untitled' : field.name,
              ),
            ),
            rows: List.unmodifiable(
              rows.map(
                (row) => List<String>.unmodifiable(
                  row.map((cell) => cell.text),
                ),
              ),
            ),
            totalRowCount: database.rows.length,
            fieldTypes: List.unmodifiable(
              visibleFields.map((field) => field.fieldType),
            ),
            widths: List.unmodifiable(
              visibleFields.map(
                (field) => (settings[field.id]?.width ?? 0).toDouble(),
              ),
            ),
            options: Map.unmodifiable(options),
          ),
        );
      },
      (error) async {
        Log.warn(
          'Unable to load database fields for gallery preview ${view.id}: '
          '$error',
        );
        return _unavailable(view);
      },
    );
  }

  Future<Map<String, FieldSettingsPB>> _fieldSettings(String viewId) async {
    final result =
        await FieldSettingsBackendService(viewId: viewId).getAllFieldSettings();
    return result.fold(
      (settings) => {for (final setting in settings) setting.fieldId: setting},
      (error) {
        Log.warn('Unable to load gallery preview field settings: $error');
        return const {};
      },
    );
  }

  Future<({String text, List<FolderGalleryTableOption> options})> _loadCell({
    required String viewId,
    required String rowId,
    required FieldPB field,
  }) async {
    final result = await CellBackendService.getCell(
      viewId: viewId,
      cellContext: CellContext(fieldId: field.id, rowId: rowId),
    );
    return result.fold(
      (cell) => (
        text: _displayValue(cell.data, field.fieldType),
        options: _selectOptions(cell.data, field.fieldType),
      ),
      (error) {
        Log.warn(
          'Unable to load gallery cell $rowId/${field.id}: $error',
        );
        // An unread cell must not become a fabricated empty value in a table.
        throw StateError('Unable to read gallery cell');
      },
    );
  }

  List<FolderGalleryTableOption> _selectOptions(
    List<int> data,
    FieldType fieldType,
  ) {
    if (data.isEmpty ||
        (fieldType != FieldType.SingleSelect &&
            fieldType != FieldType.MultiSelect)) {
      return const [];
    }
    final options =
        SelectOptionCellDataParser().parserData(data)?.selectOptions;
    if (options == null) return const [];
    return List.unmodifiable(
      options.where((option) => option.name.isNotEmpty).map(
            (option) => FolderGalleryTableOption(
              name: option.name,
              color: option.color,
            ),
          ),
    );
  }

  String _displayValue(List<int> data, FieldType fieldType) {
    if (data.isEmpty) {
      return '';
    }
    return switch (fieldType) {
      FieldType.RichText ||
      FieldType.Number ||
      FieldType.Summary ||
      FieldType.Translate =>
        StringCellDataParser().parserData(data)?.trim() ?? '',
      FieldType.Checkbox =>
        CheckboxCellDataParser().parserData(data)?.isChecked == true ? '✓' : '',
      FieldType.SingleSelect ||
      FieldType.MultiSelect =>
        SelectOptionCellDataParser()
                .parserData(data)
                ?.selectOptions
                .map((option) => option.name)
                .where((name) => name.isNotEmpty)
                .join(', ') ??
            '',
      FieldType.URL =>
        URLCellDataParser().parserData(data)?.content.trim() ?? '',
      FieldType.DateTime => _dateValue(data),
      FieldType.LastEditedTime ||
      FieldType.CreatedTime =>
        TimestampCellDataParser().parserData(data)?.dateTime.trim() ?? '',
      FieldType.Checklist => ChecklistCellDataParser()
              .parserData(data)
              ?.options
              .map((option) => option.name)
              .where((name) => name.isNotEmpty)
              .join(', ') ??
          '',
      FieldType.Relation => _relationValue(data),
      FieldType.Time => _timeValue(data),
      FieldType.Media => _mediaValue(data),
      _ => '',
    };
  }

  String _dateValue(List<int> data) {
    final value = DateCellDataParser().parserData(data);
    if (value == null || !value.hasTimestamp()) {
      return '';
    }
    return DateFormat.MMMd().format(value.timestamp.toDateTime());
  }

  String _relationValue(List<int> data) {
    final count = RelationCellDataParser().parserData(data)?.rowIds.length ?? 0;
    return count == 0 ? '' : '$count linked';
  }

  String _timeValue(List<int> data) {
    final value = TimeCellDataParser().parserData(data);
    if (value == null || !value.hasTime()) {
      return '';
    }
    final minutes = value.time.toInt();
    final hour = (minutes ~/ 60).toString().padLeft(2, '0');
    final minute = (minutes % 60).toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _mediaValue(List<int> data) {
    final count = MediaCellDataParser().parserData(data)?.files.length ?? 0;
    return count == 0 ? '' : '$count media';
  }

  FolderGalleryPreview _unavailable(ViewPB view) => FolderGalleryPreview(
        kind: FolderGalleryPreviewKind.database,
        blocks: const [],
        wordCount: 0,
        readingMinutes: 0,
        tags: FolderGalleryPreviewParser.tagsFromExtra(view.extra),
        fileTypeLabel: 'TABLE',
        unavailable: true,
      );
}

class FolderGalleryPreviewCache {
  FolderGalleryPreviewCache({
    FolderGalleryPreviewLoader? loader,
    this.maximumEntries = 96,
  }) : _loader = loader ?? FolderGalleryPreviewLoader();

  final FolderGalleryPreviewLoader _loader;
  final int maximumEntries;
  final LinkedHashMap<String, _FolderGalleryPreviewCacheEntry> _entries =
      LinkedHashMap();

  Future<FolderGalleryPreview> previewFor({
    required ViewPB view,
    required WorkspaceExplorerItem item,
  }) {
    final stamp = _stamp(view, item);
    final previous = _entries.remove(view.id);
    if (previous != null && previous.stamp == stamp) {
      _entries[view.id] = previous;
      return previous.preview;
    }

    final preview = _loader.load(view: view, item: item);
    _entries[view.id] = _FolderGalleryPreviewCacheEntry(
      stamp: stamp,
      preview: preview,
    );
    while (_entries.length > maximumEntries) {
      _entries.remove(_entries.keys.first);
    }
    return preview;
  }

  void invalidate(String viewId) => _entries.remove(viewId);

  void clear() => _entries.clear();

  String _stamp(ViewPB view, WorkspaceExplorerItem item) => [
        view.layout.value,
        view.lastEdited.toString(),
        item.lastEdited?.millisecondsSinceEpoch ?? 0,
        item.metadata?.modifiedAt?.millisecondsSinceEpoch ?? 0,
        view.extra.hashCode,
        view.name.hashCode,
      ].join(':');
}

class FolderGalleryPreviewParser {
  const FolderGalleryPreviewParser._();

  static const int maximumPreviewBlocks = 10;
  static const int wordsPerMinute = 220;

  static const _paragraph = 'paragraph';
  static const _heading = 'heading';
  static const _bulletedList = 'bulleted_list';
  static const _numberedList = 'numbered_list';
  static const _todoList = 'todo_list';
  static const _quote = 'quote';
  static const _code = 'code';
  static const _math = 'math_equation';
  static const _image = 'image';
  static const _file = 'file';
  static const _delta = 'delta';

  static const _textBlockTypes = {
    _paragraph,
    _heading,
    _bulletedList,
    _numberedList,
    _todoList,
    _quote,
    _code,
    _math,
  };

  static const _codeExtensions = {
    'c',
    'cc',
    'cpp',
    'cs',
    'css',
    'dart',
    'go',
    'h',
    'hpp',
    'html',
    'java',
    'js',
    'jsx',
    'json',
    'kt',
    'kts',
    'php',
    'ps1',
    'py',
    'rb',
    'rs',
    'scss',
    'sh',
    'sql',
    'swift',
    'ts',
    'tsx',
    'xml',
    'yaml',
    'yml',
  };
  static const _imageExtensions = {
    'avif',
    'bmp',
    'gif',
    'heic',
    'jpeg',
    'jpg',
    'png',
    'svg',
    'webp',
  };
  static const _videoExtensions = {
    'avi',
    'm4v',
    'mkv',
    'mov',
    'mp4',
    'mpeg',
    'mpg',
    'webm',
  };

  static FolderGalleryPreview? withoutDocument({
    required ViewPB view,
    required WorkspaceExplorerItem item,
  }) {
    if (view.layout == ViewLayoutPB.Chat) return chat(view);
    final selfContained = FolderGalleryPreviewParser.selfContained(
      view: view,
      item: item,
    );
    if (selfContained != null) return selfContained;
    if (item.kind == WorkspaceExplorerItemKind.folder) {
      return FolderGalleryPreview(
        kind: FolderGalleryPreviewKind.folder,
        blocks: const [],
        wordCount: 0,
        readingMinutes: 0,
        tags: _tagsFromExtra(view.extra),
        fileTypeLabel: item.isCollection ? 'COLLECTION' : 'FOLDER',
      );
    }
    final metadata = item.metadata;
    if (metadata?.contentKind != WorkspaceFileContentKind.binary) {
      return null;
    }

    final kind = _kindForFile(
      name: item.name,
      mimeType: metadata?.mimeType,
    );
    return FolderGalleryPreview(
      kind: kind,
      blocks: const [],
      wordCount: 0,
      readingMinutes: 0,
      tags: _tagsFromExtra(view.extra),
      fileTypeLabel: _fileTypeLabel(item.name, metadata?.mimeType),
      // Only the kinds that paint an actual picture carry a hero. Handing a
      // text file's path to the image loader is what drew a broken thumbnail.
      heroUrl: switch (kind) {
        FolderGalleryPreviewKind.image ||
        FolderGalleryPreviewKind.pdf ||
        FolderGalleryPreviewKind.video =>
          metadata?.storageUrl,
        _ => null,
      },
      language:
          kind == FolderGalleryPreviewKind.code ? _extension(item.name) : null,
      unavailable: metadata?.storageUrl?.isEmpty ?? true,
    );
  }

  /// A page whose whole content is kept on the view itself: a saved link, a
  /// dashboard or a canvas. There is no document or file to read for any of
  /// them, so they can never be unavailable for want of one.
  static FolderGalleryPreview? selfContained({
    required ViewPB view,
    required WorkspaceExplorerItem item,
  }) {
    final link = item.bookmark ?? view.bookmark;
    if (link != null) {
      return FolderGalleryPreview(
        kind: FolderGalleryPreviewKind.link,
        blocks: const [],
        wordCount: 0,
        readingMinutes: link.readingMinutes ?? 0,
        tags: link.tags.isNotEmpty
            ? List.unmodifiable(link.tags.take(6))
            : _tagsFromExtra(view.extra),
        fileTypeLabel: 'LINK',
        // Never a hero: the link face paints its own picture, and a hero
        // would send the card down the image path instead.
        link: link,
      );
    }
    if (view.layout != ViewLayoutPB.Document) return null;
    final dashboard = view.dashboard;
    if (dashboard != null) {
      return FolderGalleryPreview(
        kind: FolderGalleryPreviewKind.dashboard,
        blocks: const [],
        wordCount: 0,
        readingMinutes: 0,
        tags: _tagsFromExtra(view.extra),
        fileTypeLabel: 'DASHBOARD',
        dashboard: dashboard.document,
      );
    }
    final canvas = view.canvas;
    if (canvas != null) {
      return FolderGalleryPreview(
        kind: FolderGalleryPreviewKind.canvas,
        blocks: const [],
        wordCount: 0,
        readingMinutes: 0,
        tags: _tagsFromExtra(view.extra),
        fileTypeLabel: 'CANVAS',
        canvas: canvas.document,
      );
    }
    return null;
  }

  static FolderGalleryPreview unavailable({
    required ViewPB view,
    required WorkspaceExplorerItem item,
  }) {
    if (view.layout == ViewLayoutPB.Chat) return chat(view);
    final selfContained = FolderGalleryPreviewParser.selfContained(
      view: view,
      item: item,
    );
    if (selfContained != null) return selfContained;
    final kind = switch (item.kind) {
      WorkspaceExplorerItemKind.folder => FolderGalleryPreviewKind.folder,
      WorkspaceExplorerItemKind.database => FolderGalleryPreviewKind.database,
      WorkspaceExplorerItemKind.file => _kindForFile(
          name: item.name,
          mimeType: item.metadata?.mimeType,
        ),
      WorkspaceExplorerItemKind.document => FolderGalleryPreviewKind.document,
    };
    return FolderGalleryPreview(
      kind: kind,
      blocks: const [],
      wordCount: 0,
      readingMinutes: 0,
      tags: _tagsFromExtra(view.extra),
      fileTypeLabel: switch (item.kind) {
        WorkspaceExplorerItemKind.folder =>
          item.isCollection ? 'COLLECTION' : 'FOLDER',
        WorkspaceExplorerItemKind.database => 'TABLE',
        WorkspaceExplorerItemKind.file =>
          _fileTypeLabel(item.name, item.metadata?.mimeType),
        WorkspaceExplorerItemKind.document => 'PAGE',
      },
      language:
          kind == FolderGalleryPreviewKind.code ? _extension(item.name) : null,
      unavailable: true,
    );
  }

  static FolderGalleryPreview parse({
    required ViewPB view,
    required WorkspaceExplorerItem item,
    required DocumentDataPB document,
  }) {
    if (view.layout == ViewLayoutPB.Chat) return chat(view);
    final selfContained = FolderGalleryPreviewParser.selfContained(
      view: view,
      item: item,
    );
    if (selfContained != null) return selfContained;
    final previewBlocks = <FolderGalleryPreviewBlock>[];
    final allText = StringBuffer();
    final visited = <String>{};
    String? heroUrl;
    var hasMeaningfulContent = false;
    // Anything other than text — a divider, an embed, an empty picture slot —
    // means the page is not blank even when it has no words.
    var holdsOtherContent = false;
    var incomplete = false;
    String? firstCodeLanguage;

    void visit(String id) {
      if (!visited.add(id)) {
        return;
      }
      final block = document.blocks[id];
      if (block == null) {
        incomplete = true;
        return;
      }
      final attributes = _attributes(block, document);
      if (attributes == null) {
        incomplete = true;
        return;
      }
      final runs = _runsFromDelta(attributes[_delta]);
      if (runs == null) {
        incomplete = true;
        return;
      }
      final plainText = runs.map((run) => run.text).join().trim();
      if (plainText.isNotEmpty) {
        allText
          ..write(' ')
          ..write(plainText);
      }

      if (block.ty == _image) {
        final url = attributes['url'];
        if (!hasMeaningfulContent && url is String && url.isNotEmpty) {
          heroUrl = url;
        }
        holdsOtherContent = true;
      } else {
        final previewBlock = _previewBlock(
          type: block.ty,
          attributes: attributes,
          runs: runs,
        );
        if (previewBlock != null && previewBlock.plainText.trim().isNotEmpty) {
          hasMeaningfulContent = true;
          if (previewBlock.kind == FolderGalleryPreviewBlockKind.code) {
            firstCodeLanguage ??= previewBlock.language;
          }
          if (previewBlocks.length < maximumPreviewBlocks) {
            previewBlocks.add(previewBlock);
          }
        } else if (block.ty == _file) {
          hasMeaningfulContent = true;
        } else if (!_textBlockTypes.contains(block.ty)) {
          holdsOtherContent = true;
        }
      }

      final childrenId = block.childrenId;
      if (childrenId.isEmpty) {
        return;
      }
      for (final childId
          in document.meta.childrenMap[childrenId]?.children ?? const []) {
        visit(childId);
      }
    }

    final root = document.blocks[document.pageId];
    final rootChildrenId = root?.childrenId;
    final children = document.meta.childrenMap[rootChildrenId]?.children;
    if (root == null || rootChildrenId == null || children == null) {
      return unavailable(view: view, item: item);
    }
    for (final childId in children) {
      visit(childId);
    }
    if (incomplete) {
      return unavailable(view: view, item: item);
    }

    final text = allText.toString();
    final wordCount = _wordCount(text);
    final fileKind = item.isFile
        ? _kindForFile(
            name: item.name,
            mimeType: item.metadata?.mimeType,
          )
        : FolderGalleryPreviewKind.document;
    final language = fileKind == FolderGalleryPreviewKind.code
        ? _extension(item.name)
        : firstCodeLanguage;
    return FolderGalleryPreview(
      kind: fileKind,
      blocks: List.unmodifiable(previewBlocks),
      wordCount: wordCount,
      readingMinutes: wordCount == 0 ? 0 : (wordCount / wordsPerMinute).ceil(),
      tags: _collectTags(view.extra, '${view.name} $text'),
      fileTypeLabel: item.isFile
          ? _fileTypeLabel(item.name, item.metadata?.mimeType)
          : 'PAGE',
      heroUrl: heroUrl,
      language: language,
      note: previewBlocks.isEmpty &&
              heroUrl == null &&
              !hasMeaningfulContent &&
              !holdsOtherContent &&
              wordCount == 0
          ? FolderGalleryPreviewNote.empty
          : null,
    );
  }

  static Map<String, dynamic>? _attributes(
    BlockPB block,
    DocumentDataPB document,
  ) {
    Object? decoded;
    try {
      decoded = block.data.isEmpty
          ? const <String, dynamic>{}
          : jsonDecode(block.data);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    final attributes = Map<String, dynamic>.from(decoded);
    if (block.externalType == 'text' && block.externalId.isNotEmpty) {
      final externalDelta = document.meta.textMap[block.externalId];
      if (externalDelta == null && attributes[_delta] == null) return null;
      if (externalDelta != null && externalDelta.isNotEmpty) {
        try {
          attributes[_delta] = jsonDecode(externalDelta);
        } on FormatException {
          // Keep the inline delta when an external text payload is malformed.
          if (attributes[_delta] == null) return null;
        }
      }
    }
    return attributes;
  }

  static FolderGalleryPreviewBlock? _previewBlock({
    required String type,
    required Map<String, dynamic> attributes,
    required List<FolderGalleryTextRun> runs,
  }) {
    return switch (type) {
      _paragraph => FolderGalleryPreviewBlock(
          kind: FolderGalleryPreviewBlockKind.paragraph,
          runs: runs,
        ),
      _heading => FolderGalleryPreviewBlock(
          kind: FolderGalleryPreviewBlockKind.heading,
          runs: runs,
          level: (attributes['level'] as num?)?.toInt().clamp(1, 6) ?? 1,
        ),
      _bulletedList => FolderGalleryPreviewBlock(
          kind: FolderGalleryPreviewBlockKind.bulletedList,
          runs: runs,
        ),
      _numberedList => FolderGalleryPreviewBlock(
          kind: FolderGalleryPreviewBlockKind.numberedList,
          runs: runs,
        ),
      _todoList => FolderGalleryPreviewBlock(
          kind: FolderGalleryPreviewBlockKind.todo,
          runs: runs,
          checked: attributes['checked'] == true,
        ),
      _quote => FolderGalleryPreviewBlock(
          kind: FolderGalleryPreviewBlockKind.quote,
          runs: runs,
        ),
      _code => FolderGalleryPreviewBlock(
          kind: FolderGalleryPreviewBlockKind.code,
          runs: runs,
          language: attributes['language'] as String?,
        ),
      _math => FolderGalleryPreviewBlock(
          kind: FolderGalleryPreviewBlockKind.math,
          runs: [
            FolderGalleryTextRun(
              text: attributes['formula'] as String? ?? '',
            ),
          ],
        ),
      _ => runs.isEmpty
          ? null
          : FolderGalleryPreviewBlock(
              kind: FolderGalleryPreviewBlockKind.paragraph,
              runs: runs,
            ),
    };
  }

  static List<FolderGalleryTextRun>? _runsFromDelta(Object? rawDelta) {
    if (rawDelta == null) return const [];
    Object? decoded = rawDelta;
    if (decoded case final String encoded) {
      try {
        decoded = jsonDecode(encoded);
      } on FormatException {
        // Serialized/partial deltas are not prose. Never leak their raw text
        // into a card or classify a decoding failure as an empty document.
        return null;
      }
    }
    if (decoded is Map) {
      decoded = decoded['ops'];
    }
    if (decoded is! List) {
      return null;
    }

    final runs = <FolderGalleryTextRun>[];
    for (final operation in decoded) {
      if (operation is! Map) {
        return null;
      }
      final insert = operation['insert'];
      final attributes = operation['attributes'];
      final formatting = attributes is Map ? attributes : const {};
      final formula = formatting['formula'];
      final text = switch (insert) {
        final String value => value,
        _ when formula is String && formula.isNotEmpty => '[$formula]',
        final Map value when value['text'] is String => value['text'] as String,
        _ => '',
      };
      if (text.isEmpty) {
        continue;
      }
      runs.add(
        FolderGalleryTextRun(
          text: text,
          bold: formatting['bold'] == true,
          italic: formatting['italic'] == true,
          inlineCode:
              formatting['code'] == true || formatting['inlineCode'] == true,
        ),
      );
    }
    return List.unmodifiable(runs);
  }

  static FolderGalleryPreviewKind _kindForFile({
    required String name,
    String? mimeType,
  }) {
    final extension = _extension(name);
    final mime = mimeType?.toLowerCase() ?? '';
    if (mime == 'application/pdf' || extension == 'pdf') {
      return FolderGalleryPreviewKind.pdf;
    }
    if (mime.startsWith('image/') || _imageExtensions.contains(extension)) {
      return FolderGalleryPreviewKind.image;
    }
    if (mime.startsWith('video/') || _videoExtensions.contains(extension)) {
      return FolderGalleryPreviewKind.video;
    }
    if (_codeExtensions.contains(extension)) {
      return FolderGalleryPreviewKind.code;
    }
    if (mime.startsWith('text/') ||
        const {'md', 'markdown', 'txt'}.contains(extension)) {
      return FolderGalleryPreviewKind.document;
    }
    return FolderGalleryPreviewKind.file;
  }

  static String _fileTypeLabel(String name, String? mimeType) {
    final extension = _extension(name);
    if (extension.isNotEmpty) {
      return extension.toUpperCase();
    }
    final subtype = mimeType?.split('/').last.trim();
    return subtype == null || subtype.isEmpty ? 'FILE' : subtype.toUpperCase();
  }

  static String _extension(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) {
      return '';
    }
    return name.substring(dot + 1).toLowerCase();
  }

  static int _wordCount(String text) =>
      RegExp("[A-Za-z0-9]+(?:['’-][A-Za-z0-9]+)*").allMatches(text).length;

  static List<String> _collectTags(String extra, String text) {
    final tags = LinkedHashSet<String>.from(_tagsFromExtra(extra));
    final tagPattern = RegExp(r'(?:^|\s)#([A-Za-z0-9_-]+)');
    for (final match in tagPattern.allMatches(text)) {
      final value = match.group(1);
      if (value != null && value.isNotEmpty) {
        tags.add(value);
      }
      if (tags.length == 6) {
        break;
      }
    }
    return List.unmodifiable(tags.take(6));
  }

  static List<String> _tagsFromExtra(String extra) {
    final values = decodeViewExtra(extra);
    final rawTags = values['tags'];
    if (rawTags is! List) {
      return const [];
    }
    return List.unmodifiable(
      rawTags
          .whereType<String>()
          .map((tag) => tag.trim().replaceFirst(RegExp('^#'), ''))
          .where((tag) => tag.isNotEmpty)
          .take(6),
    );
  }

  static List<String> tagsFromExtra(String extra) => _tagsFromExtra(extra);

  /// Identity only: no transcript read, fake messages, counts or loading state.
  /// The rendering host still gives a saved cover/icon precedence.
  static FolderGalleryPreview chat(ViewPB view) => FolderGalleryPreview(
        kind: FolderGalleryPreviewKind.chat,
        blocks: const [],
        wordCount: 0,
        readingMinutes: 0,
        tags: _tagsFromExtra(view.extra),
        fileTypeLabel: 'AI CHAT',
      );
}

class _FolderGalleryPreviewCacheEntry {
  const _FolderGalleryPreviewCacheEntry({
    required this.stamp,
    required this.preview,
  });

  final String stamp;
  final Future<FolderGalleryPreview> preview;
}
