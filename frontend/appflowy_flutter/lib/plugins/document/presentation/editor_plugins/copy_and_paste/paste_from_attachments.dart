import 'dart:async';
import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/clipboard_service.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_util.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/custom_image_block_component/custom_image_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/image_util.dart';
import 'package:appflowy/util/xfile_ext.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/widgets.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef AttachmentFileSaver = Future<String?> Function(
  String path, {
  required String documentId,
  required bool isLocalMode,
  required bool isImage,
});

/// Imports native clipboard files into the same managed storage as uploads.
/// Files are prepared before any selection is replaced. A URI is an actual
/// attachment; its accompanying bitmap/HTML/path-text is not another item.
class AttachmentPasteService {
  const AttachmentPasteService({
    this.saveFile = _saveAttachment,
    this.temporaryDirectory = getTemporaryDirectory,
  });

  final AttachmentFileSaver saveFile;
  final Future<Directory> Function() temporaryDirectory;

  Future<PreparedAttachments> prepare(
    ClipboardServiceData data, {
    required String documentId,
    required bool isLocalMode,
  }) async {
    final originals = <File>[];
    final storedLocalFiles = <File>[];
    Directory? scratch;
    try {
      // Preflight the whole list so an unreadable URI/directory does not leave
      // half a pasted batch or start uploading its other members.
      for (final uri in List<Uri>.of(data.files)) {
        if (!uri.isScheme('file') ||
            !uri.hasAbsolutePath ||
            uri.hasQuery ||
            uri.hasFragment) {
          throw const FormatException('The clipboard file is unavailable.');
        }
        final file = File.fromUri(uri);
        if (file.path.contains('\u0000') || !await file.exists()) {
          throw const FileSystemException('The clipboard file is unavailable.');
        }
        originals.add(file);
      }
      if (originals.isEmpty) {
        final image = data.image;
        if (image == null || image.$2?.isNotEmpty != true) {
          throw const FormatException('The clipboard has no attachment.');
        }
        if (!const {'png', 'jpeg', 'gif', 'webp'}.contains(image.$1)) {
          throw const FormatException('Unsupported clipboard image.');
        }
        scratch = await (await temporaryDirectory())
            .createTemp('appflowy_clipboard_');
        originals.add(
          await File(p.join(scratch.path, 'Pasted image.${image.$1}'))
              .writeAsBytes(image.$2!, flush: true),
        );
      }

      final nodes = <Node>[];
      for (final file in originals) {
        // Sniff only the header, not an entire video/audio file. MIME fallback
        // also recognises extension-less photos from clipboard providers.
        final input = await file.open();
        final List<int> header;
        try {
          header = await input.read(64);
        } finally {
          await input.close();
        }
        final isImage = inferFileType(
              file.path,
              mimeType: lookupMimeType(file.path, headerBytes: header),
            ) ==
            FileType.image;
        final saved = await saveFile(
          file.path,
          documentId: documentId,
          isLocalMode: isLocalMode,
          isImage: isImage,
        );
        if (saved == null || saved.isEmpty) {
          throw const FileSystemException('The attachment could not be saved.');
        }
        if (isLocalMode && !p.equals(saved, file.path)) {
          storedLocalFiles.add(File(saved));
        }
        nodes.add(
          isImage
              ? customImageNode(
                  url: saved,
                  type: isLocalMode
                      ? CustomImageType.local
                      : CustomImageType.internal,
                )
              : fileNode(
                  url: saved,
                  type: isLocalMode ? FileUrlType.local : FileUrlType.cloud,
                  name: p.basename(file.path),
                ),
        );
      }
      return PreparedAttachments(nodes, storedLocalFiles);
    } catch (_) {
      await _discardFiles(storedLocalFiles);
      rethrow;
    } finally {
      try {
        await scratch?.delete(recursive: true);
      } on FileSystemException {
        // Never mask the import result with temporary-file cleanup errors.
      }
    }
  }
}

class PreparedAttachments {
  PreparedAttachments(List<Node> nodes, List<File> localFiles)
      : nodes = List.unmodifiable(nodes),
        _localFiles = List.unmodifiable(localFiles);

  final List<Node> nodes;
  final List<File> _localFiles;

  /// Only newly imported local copies belong to this operation. Original
  /// files are never removed, and cloud uploads have no rollback API here.
  Future<void> discard() => _discardFiles(_localFiles);
}

Future<void> _discardFiles(List<File> files) async {
  for (final file in files) {
    try {
      await file.delete();
    } on FileSystemException {
      // Best effort; retain the original failure and never delete parents.
    }
  }
}

Future<String?> _saveAttachment(
  String path, {
  required String documentId,
  required bool isLocalMode,
  required bool isImage,
}) async {
  if (isLocalMode) {
    return isImage
        ? saveImageToLocalStorage(path)
        : saveFileToLocalStorage(path);
  }
  if (documentId.isEmpty) {
    throw StateError('A document is required for cloud uploads.');
  }
  final result = isImage
      ? await saveImageToCloudStorage(path, documentId)
      : await saveFileToCloudStorage(path, documentId);
  if (result.$2 != null) {
    throw StateError('The attachment could not be uploaded.');
  }
  return result.$1;
}

/// A clipboard read/upload can outlive the caret, the page, or its permissions.
/// Reject late writes rather than replacing a new selection with old media.
class AttachmentPasteTarget {
  AttachmentPasteTarget(this.editor, {this.isActive})
      : selection = editor.selection,
        selectionType = editor.selectionType,
        _context = editor.document.root.context {
    editor.selectionNotifier.addListener(_selectionChanged);
    editor.editableNotifier.addListener(_permissionChanged);
    _subscription = editor.transactionStream.listen((event) {
      if (event.$1 == TransactionTime.before) _changed = true;
    });
    // Remote edits bypass the local transaction stream. Observe the actual
    // selected nodes and their containers too, including structural changes.
    if (selection != null) {
      for (final selected in editor.getNodesInSelection(selection!)) {
        for (Node? node = selected; node != null; node = node.parent) {
          if (_nodes.add(node)) node.addListener(_documentChanged);
        }
      }
    }
  }

  final EditorState editor;
  final bool Function()? isActive;
  final Selection? selection;
  final SelectionType? selectionType;
  final BuildContext? _context;
  final Set<Node> _nodes = {};
  late final StreamSubscription<EditorTransactionValue> _subscription;
  bool _changed = false;

  bool get isCurrent {
    if (!_changed &&
        (editor.isDisposed ||
            !editor.editable ||
            selection == null ||
            editor.selection != selection ||
            editor.selectionType != selectionType ||
            (_context != null && !_context.mounted) ||
            isActive?.call() == false)) {
      _changed = true;
    }
    return !_changed;
  }

  void _documentChanged() => _changed = true;

  void _selectionChanged() {
    if (editor.selection != selection) _changed = true;
  }

  void _permissionChanged() {
    if (!editor.editable) _changed = true;
  }

  void dispose() {
    if (!editor.isDisposed) {
      editor.selectionNotifier.removeListener(_selectionChanged);
    }
    editor.editableNotifier.removeListener(_permissionChanged);
    for (final node in _nodes) {
      node.removeListener(_documentChanged);
    }
    _nodes.clear();
    unawaited(_subscription.cancel());
  }
}

/// Inserts media as blocks at the caret, retaining text on both sides and a
/// trailing editable paragraph. Same-container replacements are one undoable
/// transaction, including backward selections and block selections.
Future<bool> insertPastedAttachments(
  EditorState editor,
  List<Node> attachments,
) async {
  final selection = editor.selection?.normalized;
  if (editor.isDisposed ||
      !editor.editable ||
      selection == null ||
      attachments.isEmpty) {
    return false;
  }
  final start = editor.getNodeAtPath(selection.start.path);
  final end = editor.getNodeAtPath(selection.end.path);
  if (start == null || end == null || start.parent == null) return false;
  if (selection.startIndex < 0 ||
      selection.startIndex > (start.delta?.length ?? 1) ||
      selection.endIndex < 0 ||
      selection.endIndex > (end.delta?.length ?? 1)) {
    return false;
  }

  // Reuse the editor's nested deletion rules on an isolated tree, then commit
  // their operations and the insertion together. No live half-deleted page or
  // separate undo step is exposed while crossing a list/table boundary.
  if (!identical(start.parent, end.parent)) {
    return _insertAcrossContainers(editor, attachments, selection);
  }

  final blockSelection = editor.selectionType == SelectionType.block;
  final prefix = <Node>[];
  Node? suffix;
  if (!blockSelection) {
    final left = start.delta;
    final right = end.delta;
    if (left != null &&
        (selection.startIndex > 0 ||
            (!identical(start, end) && start.children.isNotEmpty))) {
      prefix.add(
        start.copyWith(
          attributes: {
            ...start.attributes,
            blockComponentDelta: left.slice(0, selection.startIndex).toJson(),
          },
          children: identical(start, end)
              ? []
              : start.children.map((node) => node.copyWith()).toList(),
        ),
      );
    } else if (selection.isCollapsed && left == null) {
      // A caret on an existing image/file inserts after it; an explicit block
      // selection above replaces that block instead.
      prefix.add(start.copyWith());
    }
    if (right != null) {
      final tail = right.slice(selection.endIndex);
      suffix = tail.isNotEmpty
          ? end.copyWith(
              attributes: {
                ...end.attributes,
                blockComponentDelta: tail.toJson(),
              },
            )
          : paragraphNode(
              children: end.children.map((node) => node.copyWith()).toList(),
            );
    }
  }
  suffix ??= paragraphNode();
  final path = start.path;
  final selected = start.parent!.children
      .skip(path.last)
      .take(end.path.last - path.last + 1)
      .toList();
  final transaction = editor.transaction
    ..insertNodes(path, [...prefix, ...attachments, suffix])
    ..deleteNodes(selected)
    ..afterSelection = Selection.collapsed(
      Position(path: path.nextNPath(prefix.length + attachments.length)),
    )
    ..customSelectionType = SelectionType.inline;
  await editor.apply(transaction);
  return true;
}

Future<bool> _insertAcrossContainers(
  EditorState editor,
  List<Node> attachments,
  Selection selection,
) async {
  final target = AttachmentPasteTarget(editor);
  final staged = EditorState(
    document: Document(root: _snapshotNode(editor.document.root)),
  )
    ..disableSealTimer = true
    ..selection = selection
    ..selectionType = editor.selectionType;
  final operations = <Operation>[];
  final subscription = staged.transactionStream.listen((event) {
    if (event.$1 != TransactionTime.before) return;
    // Snapshots must outlive the staging tree and retain original IDs for undo.
    operations.addAll(event.$2.operations.map(_snapshotOperation));
  });
  try {
    await staged.deleteSelection(selection);
    if (!await insertPastedAttachments(staged, attachments) ||
        !target.isCurrent) {
      return false;
    }
    final transaction = editor.transaction
      // Already sequential coordinates; do not transform these a second time.
      ..operations = operations
      ..afterSelection = staged.selection
      ..customSelectionType = SelectionType.inline;
    await editor.apply(transaction);
    return true;
  } finally {
    target.dispose();
    unawaited(subscription.cancel());
    staged.dispose();
    staged.editableNotifier.dispose();
  }
}

Node _snapshotNode(Node node) => Node(
      id: node.id,
      type: node.type,
      attributes: node.attributes,
      children: node.children.map(_snapshotNode).toList(),
    );

Operation _snapshotOperation(Operation operation) => switch (operation) {
      InsertOperation() => InsertOperation(
          List.of(operation.path),
          operation.nodes.map(_snapshotNode).toList(),
        ),
      DeleteOperation() => DeleteOperation(
          List.of(operation.path),
          operation.nodes.map(_snapshotNode).toList(),
        ),
      _ => operation.copyWith(path: List.of(operation.path)),
    };
