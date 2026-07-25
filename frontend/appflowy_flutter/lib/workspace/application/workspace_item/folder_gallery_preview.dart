import 'dart:collection';
import 'dart:convert';

import 'package:appflowy/plugins/database/application/cell/cell_controller.dart';
import 'package:appflowy/plugins/database/application/cell/cell_data_loader.dart';
import 'package:appflowy/plugins/database/domain/cell_service.dart';
import 'package:appflowy/plugins/database/domain/database_view_service.dart';
import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/util/int64_extension.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-document/entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

enum FolderGalleryPreviewKind {
  document,
  code,
  image,
  pdf,
  video,
  file,
  folder,
  database,
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
    this.unavailable = false,
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
  final bool unavailable;

  bool get hasHero => heroUrl?.isNotEmpty ?? false;
}

@immutable
class FolderGalleryDatabaseSnapshot {
  const FolderGalleryDatabaseSnapshot({
    required this.columns,
    required this.rows,
    required this.totalRowCount,
  });

  final List<String> columns;
  final List<List<String>> rows;
  final int totalRowCount;
}

class FolderGalleryPreviewLoader {
  FolderGalleryPreviewLoader({
    DocumentService? documentService,
    FolderGalleryDatabasePreviewLoader? databasePreviewLoader,
  })  : _documentService = documentService ?? DocumentService(),
        _databasePreviewLoader =
            databasePreviewLoader ?? const FolderGalleryDatabasePreviewLoader();

  final DocumentService _documentService;
  final FolderGalleryDatabasePreviewLoader _databasePreviewLoader;

  Future<FolderGalleryPreview> load({
    required ViewPB view,
    required WorkspaceExplorerItem item,
  }) async {
    if (item.kind == WorkspaceExplorerItemKind.database) {
      return _databasePreviewLoader.load(view: view);
    }

    final immediate = FolderGalleryPreviewParser.withoutDocument(
      view: view,
      item: item,
    );
    if (immediate != null) {
      return immediate;
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
  }
}

class FolderGalleryDatabasePreviewLoader {
  const FolderGalleryDatabasePreviewLoader();

  static const maximumColumns = 3;
  static const maximumRows = 4;

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
    final requestedFields =
        database.fields.take(maximumColumns).toList(growable: false);
    final fieldsResult = await service.getFields(fieldIds: requestedFields);
    return fieldsResult.fold(
      (fields) async {
        final visibleFields =
            fields.take(maximumColumns).toList(growable: false);
        final visibleRows =
            database.rows.take(maximumRows).toList(growable: false);
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
              rows.map((row) => List<String>.unmodifiable(row)),
            ),
            totalRowCount: database.rows.length,
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

  Future<String> _loadCell({
    required String viewId,
    required String rowId,
    required FieldPB field,
  }) async {
    final result = await CellBackendService.getCell(
      viewId: viewId,
      cellContext: CellContext(fieldId: field.id, rowId: rowId),
    );
    return result.fold(
      (cell) => _displayValue(cell.data, field.fieldType),
      (error) {
        Log.warn(
          'Unable to load gallery cell $rowId/${field.id}: $error',
        );
        return '';
      },
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
    if (item.kind == WorkspaceExplorerItemKind.folder) {
      return FolderGalleryPreview(
        kind: FolderGalleryPreviewKind.folder,
        blocks: const [],
        wordCount: 0,
        readingMinutes: 0,
        tags: _tagsFromExtra(view.extra),
        fileTypeLabel: 'COLLECTION',
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
      heroUrl: metadata?.storageUrl,
      language:
          kind == FolderGalleryPreviewKind.code ? _extension(item.name) : null,
      unavailable: metadata?.storageUrl?.isEmpty ?? true,
    );
  }

  static FolderGalleryPreview unavailable({
    required ViewPB view,
    required WorkspaceExplorerItem item,
  }) {
    final kind = item.isFile
        ? _kindForFile(
            name: item.name,
            mimeType: item.metadata?.mimeType,
          )
        : FolderGalleryPreviewKind.document;
    return FolderGalleryPreview(
      kind: kind,
      blocks: const [],
      wordCount: _wordCount(view.name),
      readingMinutes: view.name.trim().isEmpty ? 0 : 1,
      tags: _tagsFromExtra(view.extra),
      fileTypeLabel: item.isFile
          ? _fileTypeLabel(item.name, item.metadata?.mimeType)
          : 'PAGE',
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
    final previewBlocks = <FolderGalleryPreviewBlock>[];
    final allText = StringBuffer(view.name);
    final visited = <String>{};
    String? heroUrl;
    var hasMeaningfulContent = false;
    String? firstCodeLanguage;

    void visit(String id) {
      if (!visited.add(id)) {
        return;
      }
      final block = document.blocks[id];
      if (block == null) {
        return;
      }
      final attributes = _attributes(block, document);
      final runs = _runsFromDelta(attributes[_delta]);
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
    if (rootChildrenId != null && rootChildrenId.isNotEmpty) {
      for (final childId
          in document.meta.childrenMap[rootChildrenId]?.children ?? const []) {
        visit(childId);
      }
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
      tags: _collectTags(view.extra, text),
      fileTypeLabel: item.isFile
          ? _fileTypeLabel(item.name, item.metadata?.mimeType)
          : 'PAGE',
      heroUrl: heroUrl,
      language: language,
    );
  }

  static Map<String, dynamic> _attributes(
    BlockPB block,
    DocumentDataPB document,
  ) {
    Object? decoded;
    try {
      decoded = block.data.isEmpty
          ? const <String, dynamic>{}
          : jsonDecode(block.data);
    } on FormatException {
      return <String, dynamic>{};
    }
    final attributes = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
    if (block.externalType == 'text' && block.externalId.isNotEmpty) {
      final externalDelta = document.meta.textMap[block.externalId];
      if (externalDelta != null && externalDelta.isNotEmpty) {
        try {
          attributes[_delta] = jsonDecode(externalDelta);
        } on FormatException {
          // Keep the inline delta when an external text payload is malformed.
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

  static List<FolderGalleryTextRun> _runsFromDelta(Object? rawDelta) {
    Object? decoded = rawDelta;
    if (decoded case final String encoded) {
      try {
        decoded = jsonDecode(encoded);
      } on FormatException {
        return encoded.isEmpty
            ? const []
            : [FolderGalleryTextRun(text: encoded)];
      }
    }
    if (decoded is Map) {
      decoded = decoded['ops'];
    }
    if (decoded is! List) {
      return const [];
    }

    final runs = <FolderGalleryTextRun>[];
    for (final operation in decoded) {
      if (operation is! Map) {
        continue;
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
}

class _FolderGalleryPreviewCacheEntry {
  const _FolderGalleryPreviewCacheEntry({
    required this.stamp,
    required this.preview,
  });

  final String stamp;
  final Future<FolderGalleryPreview> preview;
}
