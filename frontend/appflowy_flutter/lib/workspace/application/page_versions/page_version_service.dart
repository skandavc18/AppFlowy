import 'dart:async';

import 'package:appflowy/workspace/application/page_versions/page_version.dart';
import 'package:appflowy/workspace/application/page_versions/page_version_content.dart';
import 'package:appflowy/workspace/application/page_versions/page_version_settings.dart';
import 'package:appflowy/workspace/application/page_versions/page_version_stage.dart';
import 'package:appflowy/workspace/application/page_versions/page_version_store.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart'
    show Document, EditorState, Node, NodeIterator;
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:nanoid/nanoid.dart';

/// Reads what a page says, without drawing it.
///
/// PURE, so the counts a version row shows can be tested with no editor and
/// no disk.
PageVersionSummary summarizePageDocument(Document document) {
  final start = document.root.children.firstOrNull;
  if (start == null) {
    return const PageVersionSummary(
      blockCount: 0,
      wordCount: 0,
      characterCount: 0,
      excerpt: '',
    );
  }

  var blocks = 0;
  var characters = 0;
  var words = 0;
  final excerpt = StringBuffer();

  final iterator = NodeIterator(document: document, startNode: start);
  while (iterator.moveNext()) {
    blocks++;
    final text = iterator.current.delta?.toPlainText() ?? '';
    if (text.isEmpty) {
      continue;
    }
    characters += text.length;
    words += text.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).length;
    if (excerpt.length < maximumPageVersionExcerpt) {
      if (excerpt.isNotEmpty) {
        excerpt.write(' · ');
      }
      excerpt.write(text.trim());
    }
  }

  return PageVersionSummary(
    blockCount: blocks,
    wordCount: words,
    characterCount: characters,
    excerpt: trimPageVersionExcerpt(excerpt.toString()),
  );
}

/// What a captured object says about itself, whatever shape it is.
///
/// PURE. The counts mean different things per shape — rows for a table, items
/// for a folder, bytes for a file — and a version row reads them through
/// [PageVersion.shape].
PageVersionSummary summarizeCapturedPage(PageVersionPayload payload) {
  switch (payload.shape) {
    case PageVersionShape.document:
      final document = payload.editorDocument;
      return document == null
          ? const PageVersionSummary(
              blockCount: 0,
              wordCount: 0,
              characterCount: 0,
              excerpt: '',
            )
          : summarizePageDocument(document);

    case PageVersionShape.file:
      final file = payload.file;
      return PageVersionSummary(
        blockCount: 0,
        wordCount: 0,
        characterCount: file?.bytes ?? 0,
        excerpt: file?.name ?? '',
      );

    case PageVersionShape.container:
      final children = payload.children ?? const <PageVersionChild>[];
      final link = payload.link;
      return PageVersionSummary(
        blockCount: children.length,
        wordCount: children.where((child) => child.isFolder).length,
        characterCount: 0,
        excerpt: children.isEmpty && link != null
            ? link.name.isEmpty
                ? link.service
                : '${link.service} · ${link.name}'
            : trimPageVersionExcerpt(
                children.take(8).map((child) => child.name).join(' · '),
              ),
      );

    case PageVersionShape.database:
      final table = payload.table;
      return PageVersionSummary(
        blockCount: table?.rows.length ?? 0,
        wordCount: table?.columns.length ?? 0,
        characterCount: 0,
        excerpt: trimPageVersionExcerpt(
          (table?.columns ?? const <PageVersionColumn>[])
              .take(8)
              .map((column) => column.name)
              .join(' · '),
        ),
      );

    case PageVersionShape.row:
      final row = payload.table?.rows.firstOrNull;
      final document = payload.editorDocument;
      final page = document == null ? null : summarizePageDocument(document);
      return PageVersionSummary(
        blockCount: page?.blockCount ?? 0,
        wordCount: page?.wordCount ?? 0,
        characterCount: page?.characterCount ?? 0,
        excerpt: trimPageVersionExcerpt(
          [
            for (final column in payload.table?.columns ?? const [])
              if ((row?.cells[column.id] ?? '').trim().isNotEmpty)
                row!.cells[column.id]!,
          ].join(' · '),
        ),
      );

    case PageVersionShape.board:
    case PageVersionShape.settings:
      return PageVersionSummary(
        blockCount: 0,
        wordCount: 0,
        characterCount: 0,
        excerpt: payload.settings.name,
      );
  }
}

String trimPageVersionExcerpt(String value) {
  final opening = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  return opening.length > maximumPageVersionExcerpt
      ? '${opening.substring(0, maximumPageVersionExcerpt)}…'
      : opening;
}

const maximumPageVersionExcerpt = 160;

/// Taking, reading back and putting back a view's remembered states.
class PageVersionService {
  const PageVersionService._();

  static const instance = PageVersionService._();

  PageVersionStore get _store => PageVersionStore.instance;

  PageVersionPolicy get _policy => PageVersionSettings.instance.policy;

  /// Remembers a view as it is now, whatever kind it is.
  ///
  /// Returns null when there was nothing worth keeping — an unchanged object,
  /// a copy taken a moment ago, automatic copies turned off, or a kind whose
  /// content could not be read.
  Future<PageVersion?> capture({
    required ViewPB view,
    Document? openDocument,
    PageVersionKind kind = PageVersionKind.automatic,
    String name = '',
    DateTime? now,
    PageVersionRowContext? row,
  }) async {
    if (view.id.isEmpty) {
      return null;
    }
    // ⚠️ A preview stages throwaway copies of a table and its row pages. They
    // are real views while they exist, so without this every preview writes a
    // history for pages that are about to be deleted.
    if (decodeViewExtra(view.extra)[pageVersionScratchKey] == true ||
        (row != null && PageVersionStage.instance.isStaged(row.tableViewId))) {
      return null;
    }
    await PageVersionSettings.instance.ensureLoaded();

    final captured = await PageVersionReader.read(
      view,
      openDocument: openDocument,
      maximumFileBytes: _policy.maximumFileBytes,
      readLinkedCollections: _policy.readLinkedCollections,
      row: row,
    );
    if (captured == null) {
      return null;
    }

    final content = captured.payload.toJson();
    final hash = pageContentFingerprint(content);
    final existing = await _store.read(view.id);
    final moment = (now ?? DateTime.now()).toUtc();

    if (!shouldCapturePageVersion(
      policy: _policy,
      contentHash: hash,
      existing: existing,
      now: moment,
      manual: kind != PageVersionKind.automatic,
    )) {
      return null;
    }

    final summary = summarizeCapturedPage(captured.payload);
    final version = PageVersion(
      id: nanoid(12),
      viewId: view.id,
      createdAt: moment,
      kind: kind,
      contentHash: hash,
      shape: captured.payload.shape,
      name: name,
      pageName: view.name,
      blockCount: summary.blockCount,
      wordCount: summary.wordCount,
      characterCount: summary.characterCount,
      excerpt: summary.excerpt,
    );

    await _store.write(
      version,
      content,
      fileBytes: captured.fileBytes,
      fileExtension: captured.payload.file?.extension ?? '',
    );
    await _store.prune(view.id, _policy, now: moment);
    return version;
  }

  /// Remembers a view the caller only knows the id of.
  Future<PageVersion?> captureById(
    String viewId, {
    PageVersionKind kind = PageVersionKind.automatic,
    String name = '',
  }) async {
    final view = await readView(viewId);
    if (view == null) {
      return null;
    }
    return capture(view: view, kind: kind, name: name);
  }

  Future<ViewPB?> readView(String viewId) async {
    if (viewId.isEmpty) {
      return null;
    }
    final result = await ViewBackendService.getView(viewId);
    return result.fold((view) => view, (error) {
      Log.warn('The view $viewId could not be read for versioning: $error');
      return null;
    });
  }

  /// Everything one version holds.
  Future<PageVersionPayload?> readPayload(
    String viewId,
    String versionId,
  ) async {
    final stored = await _store.readDocument(viewId, versionId);
    if (stored == null) {
      return null;
    }
    try {
      return PageVersionPayload.fromJson(stored);
    } on Object catch (error) {
      Log.warn('Version $versionId of $viewId could not be read: $error');
      return null;
    }
  }

  /// The document one version holds, ready to be drawn or put back.
  Future<Document?> readVersion(String viewId, String versionId) async {
    final payload = await readPayload(viewId, versionId);
    return payload?.editorDocument;
  }

  /// Puts a remembered state back.
  ///
  /// The object as it stands is remembered first, so a restore is itself
  /// reversible; that copy is never swept away.
  Future<PageVersionRestoreOutcome> restore({
    required ViewPB view,
    required PageVersion version,
    EditorState? editorState,
  }) async {
    final payload = await readPayload(view.id, version.id);
    if (payload == null) {
      return const PageVersionRestoreOutcome(
        result: PageVersionRestoreResult.missing,
      );
    }

    await capture(
      view: view,
      openDocument: editorState?.document,
      kind: PageVersionKind.restorePoint,
    );

    // Everything a view says about itself comes back for every kind: the name,
    // the icon, the cover, and every arrangement the application keeps in the
    // view's own extra.
    final settled = await restoreViewSettings(view, payload.settings);

    switch (payload.shape) {
      case PageVersionShape.document:
        return _restoreDocument(view, payload, editorState, settled);

      case PageVersionShape.file:
        return _restoreFile(view, version, payload);

      case PageVersionShape.container:
        final children = payload.children;
        if (children == null || children.isEmpty) {
          return PageVersionRestoreOutcome(result: _settledResult(settled));
        }
        final order = await restoreChildOrder(view, children);
        return PageVersionRestoreOutcome(
          result: PageVersionRestoreResult.restored,
          restoredCount: order.moved,
          missingCount: order.missing,
        );

      case PageVersionShape.database:
        return _restoreTable(view, version, payload, settled);

      // A row's page goes back the way any page does; its cells are kept as a
      // record beside it, not written back over the table.
      case PageVersionShape.row:
        return _restoreDocument(view, payload, editorState, settled);

      // A canvas and a dashboard live entirely in their settings, which have
      // already been put back by the time this is reached.
      case PageVersionShape.board:
      case PageVersionShape.settings:
        return PageVersionRestoreOutcome(result: _settledResult(settled));
    }
  }

  static PageVersionRestoreResult _settledResult(bool settled) => settled
      ? PageVersionRestoreResult.restored
      : PageVersionRestoreResult.failed;

  Future<PageVersionRestoreOutcome> _restoreDocument(
    ViewPB view,
    PageVersionPayload payload,
    EditorState? editorState,
    bool settled,
  ) async {
    final restored = payload.editorDocument;
    if (restored == null) {
      return PageVersionRestoreOutcome(result: _settledResult(settled));
    }
    if (editorState == null) {
      return const PageVersionRestoreOutcome(
        result: PageVersionRestoreResult.needsOpenPage,
      );
    }
    if (!editorState.editable) {
      return const PageVersionRestoreOutcome(
        result: PageVersionRestoreResult.readOnly,
      );
    }

    try {
      await _replaceDocument(editorState, restored.root.children.toList());
    } on Object catch (error) {
      Log.error('The page ${view.id} could not be restored: $error');
      return const PageVersionRestoreOutcome(
        result: PageVersionRestoreResult.failed,
      );
    }
    return const PageVersionRestoreOutcome(
      result: PageVersionRestoreResult.restored,
    );
  }

  Future<PageVersionRestoreOutcome> _restoreFile(
    ViewPB view,
    PageVersion version,
    PageVersionPayload payload,
  ) async {
    final stored = await _store.contentFile(
      view.id,
      version.id,
      payload.file?.extension ?? '',
    );
    if (stored == null) {
      return const PageVersionRestoreOutcome(
        result: PageVersionRestoreResult.missing,
      );
    }
    final written = await restoreWorkspaceFile(view, stored);
    return PageVersionRestoreOutcome(
      result: written
          ? PageVersionRestoreResult.restored
          : PageVersionRestoreResult.failed,
    );
  }

  Future<PageVersionRestoreOutcome> _restoreTable(
    ViewPB view,
    PageVersion version,
    PageVersionPayload payload,
    bool settled,
  ) async {
    final table = payload.table;
    if (table == null || table.isEmpty) {
      return PageVersionRestoreOutcome(result: _settledResult(settled));
    }
    final copy = await restoreTableAsCopy(
      view: view,
      table: table,
      name: '${view.name} · ${stampPageVersion(version.createdAt)}',
    );
    return PageVersionRestoreOutcome(
      result: copy == null
          ? PageVersionRestoreResult.failed
          : PageVersionRestoreResult.restoredAsCopy,
      restoredCount: table.rows.length,
      createdView: copy,
    );
  }

  /// Writes the new page in before taking the old one away, so the document is
  /// never momentarily empty — an empty document makes the editor's own rules
  /// insert a stray paragraph underneath everything that has just landed.
  Future<void> _replaceDocument(
    EditorState editorState,
    List<Node> replacement,
  ) async {
    final previous = editorState.document.root.children.toList();

    if (replacement.isNotEmpty) {
      final insert = editorState.transaction
        ..insertNodes([previous.length], replacement);
      await editorState.apply(insert);
    }

    if (previous.isNotEmpty) {
      final remove = editorState.transaction..deleteNodes(previous);
      await editorState.apply(remove);
    }

    editorState.selection = null;
  }

  Future<List<PageVersion>> versions(String viewId) => _store.read(viewId);

  Future<List<PageVersion>> rename(
    String viewId,
    String versionId,
    String name,
  ) =>
      _store.rename(viewId, versionId, name);

  Future<List<PageVersion>> discard(String viewId, String versionId) =>
      _store.remove(viewId, [versionId]);

  Future<List<PageVersion>> discardAll(String viewId) async {
    final existing = await _store.read(viewId);
    return _store.remove(viewId, existing.map((version) => version.id));
  }
}

/// A moment written the way a restored copy is named.
String stampPageVersion(DateTime when) {
  final local = when.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

enum PageVersionRestoreResult {
  restored,

  /// A table's rows came back as a new table beside the original.
  restoredAsCopy,

  missing,
  readOnly,

  /// A page's blocks can only be put back through its open editor.
  needsOpenPage,

  failed;

  bool get isSuccess =>
      this == PageVersionRestoreResult.restored ||
      this == PageVersionRestoreResult.restoredAsCopy;
}

/// What a restore actually did, so the message afterwards can say so.
@immutable
class PageVersionRestoreOutcome {
  const PageVersionRestoreOutcome({
    required this.result,
    this.restoredCount = 0,
    this.missingCount = 0,
    this.createdView,
  });

  final PageVersionRestoreResult result;

  /// Rows brought back, or items put back in order.
  final int restoredCount;

  /// Items that were in the folder then and are gone now.
  final int missingCount;

  /// The table a copy restore created.
  final ViewPB? createdView;

  bool get isSuccess => result.isSuccess;
}
