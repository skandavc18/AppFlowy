import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy/plugins/database/application/cell/bloc/date_cell_editor_bloc.dart';
import 'package:appflowy/plugins/database/application/field/field_info.dart';
import 'package:appflowy/plugins/database/widgets/cell/editable_cell_skeleton/date.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_util.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_format.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_formula.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_model.dart';
import 'package:appflowy/shared/encryption/encryption.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/encryption/encryption_mark.dart';
import 'package:appflowy/workspace/application/encryption/encryption_vault.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-document/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/notification.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/rust_stream.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:markdown/markdown.dart' as markdown;
import 'package:path/path.dart' as p;

/// Limits apply to referenced content, not the owning document's writable text.
/// Native document/database APIs return a bulk response: these bound traversal,
/// decoding and retained text, not bytes transferred by the native backend.
class DocumentFindLimits {
  const DocumentFindLimits({
    this.maxDepth = 3,
    this.maxViews = 24,
    this.maxEntries = 2048,
    this.maxBytes = 512 * 1024,
    this.maxSourceBytes = 256 * 1024,
  })  : assert(maxDepth >= 0),
        assert(maxViews > 0),
        assert(maxEntries > 0),
        assert(maxBytes > 0),
        assert(maxSourceBytes > 0);

  final int maxDepth;
  final int maxViews;
  final int maxEntries;
  final int maxBytes;
  final int maxSourceBytes;
}

class DocumentFindReference {
  const DocumentFindReference(this.viewId, {this.blockId})
      : fileSource = null,
        fileName = null;

  /// An imported attachment belongs to the document containing this block.
  /// The index supplies that document's ID and preflights it, even when nested.
  const DocumentFindReference.localFile(String source, String name)
      : viewId = '',
        blockId = null,
        fileSource = source,
        fileName = name;

  final String viewId;
  final String? blockId;
  final String? fileSource;
  final String? fileName;
  bool get isLocalFile => fileSource != null;

  @override
  bool operator ==(Object other) =>
      other is DocumentFindReference &&
      viewId == other.viewId &&
      blockId == other.blockId &&
      fileSource == other.fileSource &&
      fileName == other.fileName;

  @override
  int get hashCode => Object.hash(viewId, blockId, fileSource, fileName);
}

class DocumentFindText {
  const DocumentFindText(this.id, this.text, this.location);

  final String id;
  final String text;
  final String location;
}

class DocumentFindContent {
  const DocumentFindContent({
    this.texts = const [],
    this.references = const [],
    this.truncated = false,
    this.unavailable = false,
    this.coverageUnknown = false,
    this.cacheable = true,
  });

  final List<DocumentFindText> texts;
  final List<DocumentFindReference> references;
  final bool truncated;
  final bool unavailable;
  final bool coverageUnknown;
  final bool cacheable;

  int get byteCount => texts.fold(
        0,
        (sum, part) => sum + utf8.encode(part.text).length,
      );
}

/// One slot for ALL document Find sessions, including close/reopen. A UI
/// deadline invalidates a request but never completes its native future here.
/// Pending work is replaceable/removable; an active slot is released only by
/// the real operation finishing. No text or authorization is shared.
class DocumentFindReadScheduler {
  static final shared = DocumentFindReadScheduler();
  final _pending = <Object, (bool Function(), Future<void> Function())>{};
  final _available = <Object, (bool Function(), VoidCallback)>{};
  bool _running = false;

  void schedule(
    Object owner,
    bool Function() isCurrent,
    Future<void> Function() read,
  ) {
    cancel(owner);
    _pending.removeWhere((_, request) => !request.$1());
    if (!isCurrent()) return;
    _pending[owner] = (isCurrent, read);
    if (_running) return;
    _running = true;
    scheduleMicrotask(_drain);
  }

  void cancel(Object owner) {
    _pending.remove(owner);
    _available.remove(owner);
  }

  /// One-shot, data-free recovery after the actual occupied slot completes.
  /// A deadline may remove queued I/O without making the latest query inert.
  /// Callers bound retries; close/rebind cancels this alongside queued work.
  void whenAvailable(
    Object owner,
    bool Function() isCurrent,
    VoidCallback retry,
  ) {
    _available[owner] = (isCurrent, retry);
    if (!_running) scheduleMicrotask(_publishAvailable);
  }

  void _publishAvailable() {
    final callbacks = _available.values.toList();
    _available.clear();
    for (final callback in callbacks) {
      if (callback.$1()) callback.$2();
    }
  }

  @visibleForTesting
  int get pendingCount => _pending.length;

  Future<void> _drain() async {
    try {
      while (_pending.isNotEmpty) {
        final request = _pending.remove(_pending.keys.first)!;
        if (!request.$1()) continue;
        // _scan catches failures and publishes a partial result. Do NOT race
        // this future with a timeout: that would release a still-occupied slot.
        await request.$2();
        _publishAvailable();
      }
    } finally {
      _running = false;
    }
  }
}

/// Small, injectable filesystem boundary. The provider performs all path and
/// type checks before calling readBytes. This reader never materializes a URL,
/// downloads a cloud attachment, runs OCR, or reads an unbounded byte stream.
class DocumentFindFileAccess {
  const DocumentFindFileAccess();

  Future<String?> storageRoot() async =>
      getIt.isRegistered<ApplicationDataStorage>()
          ? await getIt<ApplicationDataStorage>().getPath()
          : null;

  Future<String?> resolve(String source) => resolveLocalStorageFilePath(source);

  Future<String> canonicalPath(String path, {bool directory = false}) =>
      directory
          ? Directory(path).resolveSymbolicLinks()
          : File(path).resolveSymbolicLinks();

  /// One lookahead byte distinguishes an exact-size file from truncation.
  Future<List<int>?> readBytes(String path, int limit) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in File(path).openRead(0, limit + 1)) {
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }
}

/// Read-only native boundary. Tests inject reads, never a fake search engine.
/// No openDocument, transactions, exports, workspace scans or plugin mounting.
class DocumentFindReadProvider {
  const DocumentFindReadProvider({
    required this.readView,
    required this.preflight,
    required this.readDocument,
    required this.readViewRows,
    required this.readFields,
    this.readRows,
    this.readCell,
    this.fileAccess,
    this.scheduler,
    this.deadline = const Duration(seconds: 3),
    this.accessChanges,
    this.contentChanges,
  });

  factory DocumentFindReadProvider.native() => DocumentFindReadProvider(
        readView: (id) async => (await ViewBackendService.getView(id))
            .fold((view) => view, (_) => null),
        preflight: documentFindCanReadView,
        readDocument: (id) async =>
            (await DocumentService().getDocument(documentId: id))
                .fold((document) => document, (_) => null),
        // GetRowsAsText expands relation names in Rust, opening unrelated
        // databases without the Dart vault gate. Never use it for Find.
        readCell: (id, row, field) async => (await DatabaseEventGetCell(
          CellIdPB(viewId: id, rowId: row.id, fieldId: field.id),
        ).send())
            .fold((cell) => cell, (_) => null),
        readViewRows: (id) async => (await DatabaseEventGetAllRows(
          DatabaseViewIdPB(value: id),
        ).send())
            .fold((rows) => rows.items, (_) => null),
        readFields: (id, fields) async => (await DatabaseEventGetFields(
          GetFieldPayloadPB(
            viewId: id,
            fieldIds: fields.isEmpty
                ? null
                : RepeatedFieldIdPB(
                    items: fields.map((field) => FieldIdPB(fieldId: field)),
                  ),
          ),
        ).send())
            .fold((fields) => fields.items, (_) => null),
        fileAccess: const DocumentFindFileAccess(),
        accessChanges: EncryptionVault.instance,
        contentChanges:
            RustStreamReceiver.shared.observable.stream.where((event) {
          if (event.source == 'Document') {
            return event.ty == DocumentNotification.DidReceiveUpdate.value;
          }
          if (event.source == 'Folder') {
            return {
              FolderNotification.DidUpdateView.value,
              FolderNotification.DidDeleteView.value,
              FolderNotification.DidMoveViewToTrash.value,
              FolderNotification.DidRestoreView.value,
            }.contains(event.ty);
          }
          return event.source == 'Database' &&
              {
                DatabaseNotification.DidUpdateRow.value,
                DatabaseNotification.DidUpdateFields.value,
                DatabaseNotification.DidUpdateFilter.value,
                DatabaseNotification.DidUpdateSort.value,
                DatabaseNotification.DidUpdateViewRowsVisibility.value,
                DatabaseNotification.DidReorderRows.value,
                DatabaseNotification.DidReorderSingleRow.value,
              }.contains(event.ty);
        }).map((event) => event.id),
      );

  /// Must return only a current, readable native view, not a cached/trash view.
  final Future<ViewPB?> Function(String id) readView;
  final Future<bool> Function(ViewPB view) preflight;
  final Future<DocumentDataPB?> Function(String id) readDocument;

  /// Legacy injection retained for callers, but deliberately NEVER invoked.
  /// Missing typed/file seams fail closed; they do not fall back to native I/O.
  final Future<RepeatedRowTextPB?> Function(String id)? readRows;
  final Future<CellPB?> Function(String id, RowMetaPB row, FieldPB field)?
      readCell;
  final Future<List<RowMetaPB>?> Function(String id) readViewRows;
  final Future<List<FieldPB>?> Function(String id, List<String> fields)
      readFields;
  final DocumentFindFileAccess? fileAccess;
  final DocumentFindReadScheduler? scheduler;
  final Duration deadline;
  DocumentFindReadScheduler get readScheduler =>
      scheduler ?? DocumentFindReadScheduler.shared;
  final Listenable? accessChanges;
  final Stream<String>? contentChanges;

  Future<DocumentFindContent> read(
    ViewPB view,
    DocumentFindReference reference,
    DocumentFindLimits limits,
    bool Function() isCurrent,
  ) async {
    if (!isCurrent()) return const DocumentFindContent();
    if (reference.isLocalFile) {
      return _readFile(
        reference.fileSource!,
        reference.fileName!,
        limits,
        isCurrent,
      );
    }
    // Workspace files also use Document layout. Never treat an unavailable
    // file as an empty collaborative document, or trust the embed's copied URL.
    final item = view.workspaceItem;
    if (item?.isFile == true && !item!.isCollaborativeText) {
      return _readFile(item.storageUrl ?? '', view.name, limits, isCurrent);
    }
    if (item?.isFolder == true ||
        (item == null &&
            decodeViewExtra(view.extra)
                .containsKey(WorkspaceItemMetadata.envelopeKey))) {
      return const DocumentFindContent(unavailable: true);
    }
    if (view.layout == ViewLayoutPB.Document) {
      final document = await readDocument(view.id);
      if (!isCurrent()) return const DocumentFindContent();
      return document == null
          ? const DocumentFindContent(unavailable: true)
          : documentFindDocumentContent(document, reference, limits);
    }
    if (view.layout != ViewLayoutPB.Grid &&
        view.layout != ViewLayoutPB.Board &&
        view.layout != ViewLayoutPB.Calendar) {
      return const DocumentFindContent(unavailable: true);
    }
    final cellReader = readCell;
    if (cellReader == null) {
      return const DocumentFindContent(unavailable: true);
    }
    // An absent fieldIds payload means this view's actual fields, with their
    // real type_option_data. No relation resolution or all-database fallback.
    final fields = await readFields(view.id, const []);
    if (!isCurrent()) return const DocumentFindContent();
    if (fields == null) return const DocumentFindContent(unavailable: true);
    final visible = await readViewRows(view.id);
    if (!isCurrent()) return const DocumentFindContent();
    if (visible == null) {
      return const DocumentFindContent(unavailable: true);
    }
    // Rust's membership loader omits failed rows, and GetCell substitutes an
    // empty CellPB on failure. Neither API attests completeness, even for an
    // empty database. Keep useful values but NEVER advertise full coverage.
    final budget = _ContentBuilder(limits)..coverageUnknown = true;
    final boundedFields = fields.take(limits.maxEntries).toList();
    var sourceBytes = 0;
    for (final field in boundedFields) {
      sourceBytes += field.typeOptionData.length;
      if (sourceBytes > limits.maxSourceBytes) {
        budget.full = budget.truncated = true;
        break;
      }
      if (!budget
          .add(DocumentFindText('field:${field.id}', field.name, 'Column'))) {
        break;
      }
    }
    var rowNumber = 0;
    var reads = 0;
    final visited = <String>{};
    for (final row in visible.take(limits.maxEntries)) {
      if (budget.full) break;
      if (row.id.isEmpty || !visited.add(row.id)) {
        budget.unavailable = true;
        continue;
      }
      rowNumber++;
      for (final field in boundedFields) {
        if (!isCurrent()) return const DocumentFindContent();
        // GetCell(Relation) returns IDs, not display names. Do not resolve
        // them, read their targets, or search opaque IDs instead of names.
        if (field.id.isEmpty ||
            field.fieldType == FieldType.Relation ||
            field.fieldType == FieldType.Time ||
            looksSealed(field.name.trimLeft())) {
          budget.unavailable = true;
          continue;
        }
        if (++reads > limits.maxEntries ||
            field.typeOptionData.length > limits.maxSourceBytes) {
          budget.full = budget.truncated = true;
          break;
        }
        try {
          final cell = await cellReader(view.id, row, field);
          if (!isCurrent()) return const DocumentFindContent();
          if (cell == null ||
              cell.rowId != row.id ||
              cell.fieldId != field.id ||
              !cell.hasFieldType() ||
              cell.fieldType != field.fieldType) {
            budget.unavailable = true;
            continue;
          }
          sourceBytes += cell.data.length;
          if (sourceBytes > limits.maxSourceBytes) {
            budget.full = budget.truncated = true;
            break;
          }
          final text = _cellDisplayText(cell, field);
          if (text == null) {
            budget.unavailable = true;
            continue;
          }
          if (field.fieldType == FieldType.Media) budget.unavailable = true;
          if (!budget.add(
            DocumentFindText(
              'row:${row.id}:${field.id}',
              text,
              'Row $rowNumber · ${field.name}',
            ),
          )) {
            break;
          }
        } on Object {
          if (!isCurrent()) return const DocumentFindContent();
          budget.unavailable = true;
        }
      }
    }
    budget.truncated = budget.truncated ||
        fields.length > boundedFields.length ||
        visible.length > limits.maxEntries;
    return budget.build();
  }

  Future<DocumentFindContent> _readFile(
    String source,
    String name,
    DocumentFindLimits limits,
    bool Function() isCurrent,
  ) async {
    final access = fileAccess;
    final kind = filePreviewKindFromName(name);
    final local = _localFilePath(source);
    if (access == null ||
        local == null ||
        !const {
          FilePreviewKind.text,
          FilePreviewKind.code,
          FilePreviewKind.markdown,
          FilePreviewKind.html,
          FilePreviewKind.csv,
          FilePreviewKind.json,
        }.contains(kind)) {
      return const DocumentFindContent(unavailable: true, cacheable: false);
    }
    try {
      final storage = await access.storageRoot();
      if (!isCurrent()) return const DocumentFindContent();
      final root = storage == null ? null : _localFilePath(storage);
      // Refuse even filesystem probes outside imported storage. In particular
      // the generic resolver is never given a remote, UNC or arbitrary path.
      if (root == null || !p.isWithin(p.join(root, 'files'), local)) {
        return const DocumentFindContent(unavailable: true, cacheable: false);
      }
      final resolved = await access.resolve(local);
      if (!isCurrent()) return const DocumentFindContent();
      final path = resolved == null ? null : _localFilePath(resolved);
      if (path == null || !p.isWithin(p.join(root, 'files'), path)) {
        return const DocumentFindContent(unavailable: true, cacheable: false);
      }
      final canonicalStorage =
          await access.canonicalPath(root, directory: true);
      if (!isCurrent()) return const DocumentFindContent();
      final canonicalRoot = await access.canonicalPath(
        p.join(root, 'files'),
        directory: true,
      );
      if (!isCurrent()) return const DocumentFindContent();
      // Do not let a redirected files directory authorize an unrelated tree.
      if (_localFilePath(canonicalStorage) == null ||
          !p.equals(canonicalRoot, p.join(canonicalStorage, 'files'))) {
        return const DocumentFindContent(unavailable: true, cacheable: false);
      }
      final canonical = await access.canonicalPath(path);
      if (!isCurrent()) return const DocumentFindContent();
      if (_localFilePath(canonicalRoot) == null ||
          _localFilePath(canonical) == null ||
          !p.isWithin(canonicalRoot, canonical)) {
        return const DocumentFindContent(unavailable: true, cacheable: false);
      }
      final cap = limits.maxSourceBytes < limits.maxBytes
          ? limits.maxSourceBytes
          : limits.maxBytes;
      final bytes = await access.readBytes(canonical, cap);
      if (!isCurrent()) return const DocumentFindContent();
      if (bytes == null) {
        return const DocumentFindContent(unavailable: true, cacheable: false);
      }
      if (bytes.length > cap) {
        return const DocumentFindContent(truncated: true, cacheable: false);
      }
      // Strict UTF-8 and control-byte rejection: a renamed binary is not text.
      if (bytes.any((byte) => byte < 9 || (byte > 13 && byte < 32))) {
        return const DocumentFindContent(unavailable: true, cacheable: false);
      }
      final text = utf8.decode(bytes).replaceFirst(RegExp('^\uFEFF'), '');
      // Disk text cannot attest to an unsaved mounted source editor's draft.
      // Do not cache a file snapshot without a renderer/file revision signal.
      final budget = _ContentBuilder(limits)
        ..cacheable = false
        ..coverageUnknown = true;
      if (looksSealed(text.trimLeft())) {
        budget.unavailable = true;
      } else if (kind == FilePreviewKind.markdown ||
          kind == FilePreviewKind.html) {
        // Same GFM conversion as FilePreview, but no renderer, scripts,
        // resources, CSS evaluation or URL loading. Static text is not a
        // claim to cover the live browser/unsaved source editor.
        _addMarkupText(
          budget,
          kind == FilePreviewKind.markdown
              ? markdown.markdownToHtml(
                  text,
                  extensionSet: markdown.ExtensionSet.gitHubFlavored,
                  encodeHtml: false,
                  enableTagfilter: true,
                )
              : text,
        );
      } else {
        budget.add(DocumentFindText('file:text', text, 'File text / source'));
      }
      return budget.build();
    } on Object {
      return const DocumentFindContent(unavailable: true, cacheable: false);
    }
  }
}

String? _cellDisplayText(CellPB cell, FieldPB field) {
  // Native Number and Timestamp payloads are already formatted by the real
  // field options. Date uses the same frontend formatter as the grid.
  switch (field.fieldType) {
    case FieldType.RichText:
    case FieldType.Number:
    case FieldType.Summary:
    case FieldType.Translate:
      return utf8.decode(cell.data);
    case FieldType.SingleSelect:
    case FieldType.MultiSelect:
      final options = field.fieldType == FieldType.SingleSelect
          ? SingleSelectTypeOptionPB.fromBuffer(field.typeOptionData).options
          : MultiSelectTypeOptionPB.fromBuffer(field.typeOptionData).options;
      final names = {for (final option in options) option.id: option.name};
      final selected =
          SelectOptionCellDataPB.fromBuffer(cell.data).selectOptions;
      if (selected.any((option) => !names.containsKey(option.id))) return null;
      return _displayNames(selected.map((option) => names[option.id]!));
    case FieldType.DateTime:
      return getDateCellStrFromCellData(
        FieldInfo.initial(field),
        DateCellData.fromPB(DateCellDataPB.fromBuffer(cell.data)),
      );
    case FieldType.CreatedTime:
    case FieldType.LastEditedTime:
      return TimestampCellDataPB.fromBuffer(cell.data).dateTime;
    case FieldType.Checkbox:
      return CheckboxCellDataPB.fromBuffer(cell.data).isChecked ? 'Yes' : 'No';
    case FieldType.URL:
      return URLCellDataPB.fromBuffer(cell.data).content;
    case FieldType.Checklist:
      return _displayNames(
        ChecklistCellDataPB.fromBuffer(cell.data)
            .options
            .map((option) => option.name),
      );
    case FieldType.Media:
      return _displayNames(
        MediaCellDataPB.fromBuffer(cell.data).files.map((file) => file.name),
      );
    default:
      return null;
  }
}

String? _displayNames(Iterable<String> names) =>
    names.any((name) => looksSealed(name.trimLeft())) ? null : names.join(', ');

String? _localFilePath(String source) {
  if (source.isEmpty ||
      source.contains('\u0000') ||
      source.startsWith(r'\\') ||
      source.startsWith('//')) {
    return null;
  }
  final uri = Uri.tryParse(source);
  if (uri == null) return null;
  var path = source;
  if (uri.isScheme('file')) {
    if (uri.host.isNotEmpty || uri.hasQuery || uri.hasFragment) return null;
    try {
      path = uri.toFilePath(windows: Platform.isWindows);
    } on Object {
      return null;
    }
  } else if (uri.hasScheme &&
      !(Platform.isWindows && RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(source))) {
    return null;
  }
  if (!p.isAbsolute(path) || path.startsWith(r'\\') || path.startsWith('//')) {
    return null;
  }
  if (Platform.isWindows &&
      (!RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path) ||
          path.substring(2).contains(':'))) {
    return null;
  }
  return p.normalize(path);
}

void _addMarkupText(_ContentBuilder budget, String source) {
  final document = html_parser.parse(source);
  for (final hidden in document.querySelectorAll(
    'head, script, style, template, noscript, iframe, object, embed, '
    '[hidden], [aria-hidden="true"]',
  )) {
    hidden.remove();
  }
  final pending = <(html_dom.Node?, int)>[(document.body, 0)];
  final text = StringBuffer();
  var visited = 0;
  while (pending.isNotEmpty) {
    final (node, depth) = pending.removeLast();
    if (++visited > budget.limits.maxEntries || depth > 64) {
      budget.truncated = true;
      break;
    }
    if (node == null) {
      text.writeln();
    } else if (node is html_dom.Text) {
      text.write(node.data);
    } else if (node is html_dom.Element) {
      final style = node.attributes['style'] ?? '';
      if (RegExp(
        r'(?:^|;)\s*(?:display\s*:\s*none|visibility\s*:\s*(?:hidden|collapse))\b',
        caseSensitive: false,
      ).hasMatch(style)) {
        continue;
      }
      final block = const {
        'p',
        'div',
        'pre',
        'li',
        'tr',
        'h1',
        'h2',
        'h3',
        'h4',
        'h5',
        'h6',
        'br',
      }.contains(node.localName);
      if (block) {
        text.writeln();
        pending.add((null, depth));
      }
      for (final child in node.nodes.reversed) {
        pending.add((child, depth + 1));
      }
    }
  }
  budget.add(
    DocumentFindText(
      'file:text',
      text.toString().trim(),
      'Static file text',
    ),
  );
}

/// Backend getView is still required; local encryption is an additional gate.
/// Unlike the navigation helper, failed ancestor reads fail CLOSED here.
Future<bool> documentFindCanReadView(
  ViewPB view, {
  Future<List<ViewPB>?> Function(String id)? readAncestors,
}) async {
  try {
    final vault = EncryptionVault.instance;
    await vault.ensureLoaded();
    if (!vault.isLoaded) return false;
    if (!vault.isConfigured) return true;
    if (vault.policy.gateWholeWorkspace && !vault.isUnlocked) return false;
    if (vault.isRevealed(view.id)) return true;
    final ancestors = await (readAncestors ?? _readAncestors)(view.id);
    if (ancestors == null) return false;
    final protected = ancestors.where((ancestor) => ancestor.isProtected);
    if (protected.any((ancestor) => vault.isRevealed(ancestor.id))) return true;
    return !view.isProtected && protected.isEmpty;
  } on Object {
    return false;
  }
}

Future<List<ViewPB>?> _readAncestors(String id) async =>
    (await ViewBackendService.getViewAncestors(id))
        .fold((views) => views.items, (_) => null);

/// Only actual reference shapes are followed. Arbitrary attributes, URLs and
/// ViewPB.childViews are NOT a licence to crawl other workspace content.
Iterable<DocumentFindReference> documentFindReferences(Node node) sync* {
  if (node.type == 'file' || node.type == 'image') {
    final id = node.attributes['workspace_file_id'];
    if (id is String && id.isNotEmpty) {
      yield DocumentFindReference(id);
    } else if (node.type == 'file' && (node.attributes['url_type'] ?? 0) == 0) {
      final source = node.attributes['url'];
      final name = node.attributes['name'];
      if (source is String && source.isNotEmpty && name is String) {
        yield DocumentFindReference.localFile(source, name);
      }
    }
  }
  // PagePreviewBlockKeys, SubPageBlockKeys, ChartBlockKeys and DatabaseBlockKeys store
  // their target under view_id. Keep this reader independent of UI renderers.
  if (const {'page_preview', 'sub_page', 'grid', 'board', 'calendar', 'chart'}
      .contains(node.type)) {
    final id = node.attributes['view_id'];
    if (id is String && id.isNotEmpty) yield DocumentFindReference(id);
  }
  for (final operation
      in node.delta?.whereType<TextInsert>() ?? const <TextInsert>[]) {
    final mention = operation.attributes?['mention'];
    if (mention is! Map ||
        (mention['type'] != 'page' && mention['type'] != 'childPage')) {
      continue;
    }
    final id = mention['page_id'];
    final block = mention['block_id'];
    if (id is String && id.isNotEmpty) {
      yield DocumentFindReference(
        id,
        blockId: block is String && block.isNotEmpty ? block : null,
      );
    }
  }
}

/// Native non-delta shapes only. In particular, file identity copied into an
/// embed is not authority to publish the referenced file's name before its gate.
Iterable<(String, String)> documentFindNodeScalars(Node node) sync* {
  final key = switch (node.type) {
    'image' => 'caption',
    'math_equation' => 'formula',
    'file' => 'name',
    _ => null,
  };
  if (key == null) return;
  final reference = node.attributes['workspace_file_id'];
  if (node.type == 'file' && reference is String && reference.isNotEmpty) {
    return;
  }
  final value = node.attributes[key];
  if (value is String && value.isNotEmpty) yield (key, value);
}

DocumentFindContent documentFindNodeContent(
  Node node,
  DocumentFindLimits limits,
) {
  final result = _ContentBuilder(limits);
  for (final (key, text) in documentFindNodeScalars(node)) {
    result.add(DocumentFindText('attribute:$key', text, '${node.type} · $key'));
  }
  if (const {'image', 'multi_image', 'link_preview', 'encrypted_block'}
          .contains(node.type) ||
      (node.type == 'file' && documentFindReferences(node).isEmpty)) {
    // Captions are searchable, pixels/remote previews/secrets are not. Never
    // auto-OCR or fetch web content just because whole-page Find was opened.
    result.unavailable = true;
  }
  return result.build();
}

/// Decode one bounded block at a time, with a visited-block set. toDocument's
/// recursive conversion is deliberately not used on untrusted reference data.
DocumentFindContent documentFindDocumentContent(
  DocumentDataPB document,
  DocumentFindReference reference,
  DocumentFindLimits limits,
) {
  final result = _ContentBuilder(limits);
  final pending = <(String, String)>[
    (reference.blockId ?? document.pageId, ''),
  ];
  final visited = <String>{};
  var sourceBytes = 0;
  while (pending.isNotEmpty && !result.full) {
    final (id, location) = pending.removeLast();
    if (!visited.add(id)) continue;
    if (visited.length > limits.maxEntries) {
      result.truncated = true;
      break;
    }
    final block = document.blocks[id];
    if (block == null) {
      result.unavailable = true;
      continue;
    }
    final external = document.meta.textMap[block.externalId] ?? '';
    if (block.data.length > limits.maxSourceBytes ||
        external.length > limits.maxSourceBytes) {
      result.truncated = true;
      break;
    }
    sourceBytes +=
        utf8.encode(block.data).length + utf8.encode(external).length;
    if (sourceBytes > limits.maxSourceBytes) {
      result.truncated = true;
      break;
    }
    if (block.ty == 'encrypted_block') {
      result.unavailable = true;
      continue;
    }
    try {
      final node = block.toNode(meta: document.meta);
      final text = node.delta?.toPlainText() ?? '';
      result.add(DocumentFindText(id, text, 'Block $location'));
      final local = documentFindNodeContent(node, limits);
      for (final part in local.texts) {
        if (!result.add(
          DocumentFindText(
            '$id:${part.id}',
            part.text,
            '$location · ${part.location}',
          ),
        )) {
          break;
        }
      }
      result.truncated = result.truncated || local.truncated;
      result.unavailable = result.unavailable || local.unavailable;
      final sheet = documentFindSpreadsheetContent(node, limits);
      for (final part in sheet.texts) {
        if (!result.add(
          DocumentFindText(
            '$id:${part.id}',
            part.text,
            '$location · ${part.location}',
          ),
        )) {
          break;
        }
      }
      result.truncated = result.truncated || sheet.truncated;
      result.unavailable = result.unavailable || sheet.unavailable;
      for (final reference in documentFindReferences(node)) {
        if (result.references.length >= limits.maxViews) {
          result.truncated = true;
          break;
        }
        result.references.add(reference);
      }
      node.dispose();
    } on Object {
      result.unavailable = true;
    }
    final children = document.meta.childrenMap[block.childrenId]?.children;
    if (children != null) {
      final count =
          children.length.clamp(0, limits.maxEntries - pending.length);
      if (count < children.length) result.truncated = true;
      for (var i = count - 1; i >= 0; i--) {
        pending.add(
          (children[i], location.isEmpty ? '${i + 1}' : '$location.${i + 1}'),
        );
      }
    }
  }
  return result.build();
}

/// Native displayed values (not formulas, JSON, hidden columns or filtered
/// rows). Attribute edits are observed by the document session's node watches.
DocumentFindContent documentFindSpreadsheetContent(
  Node node,
  DocumentFindLimits limits, {
  SpreadsheetData? liveData,
}) {
  if (node.type != 'spreadsheet') return const DocumentFindContent();
  final result = _ContentBuilder(limits);
  try {
    final raw = node.attributes['data'];
    if (liveData == null && raw is! Map) {
      return const DocumentFindContent(unavailable: true);
    }
    if (liveData == null) {
      if (utf8.encode(jsonEncode(raw)).length > limits.maxSourceBytes) {
        return const DocumentFindContent(truncated: true);
      }
      // The native codec grows its column list up to each key. Reject malformed
      // indices before decoding rather than letting a tiny map allocate forever.
      final columns = (raw as Map)['cols'];
      if (columns is Map &&
          columns.keys.any((key) {
            final index = int.tryParse('$key');
            return index == null ||
                index < 0 ||
                index >= SpreadsheetData.maxColumns;
          })) {
        return const DocumentFindContent(unavailable: true);
      }
    }
    final data = liveData ?? SpreadsheetData.fromJson(raw as Map);
    final evaluator = _FindSpreadsheetEvaluator(data, limits.maxEntries * 8);
    for (var column = 0; column < data.columnCount; column++) {
      if (data.isColumnHidden(column)) continue;
      if (!result.add(
        DocumentFindText(
          'header:$column',
          data.headerLabel(column),
          'Column ${CellRef.columnLabel(column)}',
        ),
      )) {
        break;
      }
    }
    var visited = 0;
    for (var row = 0; row < data.rowCount && !result.full; row++) {
      if (++visited > limits.maxEntries) {
        result.truncated = true;
        break;
      }
      if (data.row(row).hidden) continue;
      String display(CellRef cell) => data.rawAt(cell).isEmpty
          ? ''
          : formatCellValue(
              evaluator.valueAt(cell),
              data.styleAt(cell),
              raw: data.rawAt(cell),
            );
      if (data.filters.any(
        (filter) => !display(CellRef(row, filter.column))
            .toLowerCase()
            .contains(filter.query.toLowerCase()),
      )) {
        continue;
      }
      for (var column = 0; column < data.columnCount; column++) {
        if (data.isColumnHidden(column)) continue;
        if (++visited > limits.maxEntries) {
          result.truncated = true;
          break;
        }
        final ref = CellRef(row, column);
        if (!result.add(
          DocumentFindText(ref.a1, display(ref), 'Cell ${ref.a1}'),
        )) {
          break;
        }
      }
      if (result.truncated) break;
    }
  } on _FindEvaluationLimit {
    result.truncated = true;
  } on Object {
    result.unavailable = true;
  }
  return result.build();
}

class _FindEvaluationLimit implements Exception {}

/// Bound formula ranges and dependency chains while reusing native semantics.
class _FindSpreadsheetEvaluator extends SpreadsheetEvaluator {
  _FindSpreadsheetEvaluator(super.data, this.remaining);
  int remaining;
  int _depth = 0;

  @override
  SheetValue valueAt(CellRef ref) {
    if (--remaining < 0 || _depth >= 64 || data.rawAt(ref).length > 2048) {
      throw _FindEvaluationLimit();
    }
    _depth++;
    try {
      return super.valueAt(ref);
    } finally {
      _depth--;
    }
  }
}

class _ContentBuilder {
  _ContentBuilder(this.limits);
  final DocumentFindLimits limits;
  final texts = <DocumentFindText>[];
  final references = <DocumentFindReference>[];
  int _bytes = 0;
  bool truncated = false;
  bool unavailable = false;
  bool coverageUnknown = false;
  bool cacheable = true;
  bool full = false;

  bool add(DocumentFindText part) {
    if (part.text.isEmpty) return true;
    if (looksSealed(part.text.trimLeft())) {
      unavailable = true;
      return true;
    }
    if (part.text.length > limits.maxBytes) {
      full = truncated = true;
      return false;
    }
    final bytes = utf8.encode(part.text).length;
    if (full ||
        texts.length >= limits.maxEntries ||
        _bytes + bytes > limits.maxBytes) {
      full = truncated = true;
      return false;
    }
    _bytes += bytes;
    texts.add(part);
    return true;
  }

  DocumentFindContent build() => DocumentFindContent(
        texts: List.unmodifiable(texts),
        references: List.unmodifiable(references),
        truncated: truncated,
        unavailable: unavailable,
        coverageUnknown: coverageUnknown,
        cacheable: cacheable,
      );
}
