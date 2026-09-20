import 'dart:async';

import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/workspace/application/view/view_listener.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter/foundation.dart';

import 'file_block_component.dart';

/// The existing view service/notification boundary, replaceable in isolated
/// tests. Referenced files never store a second icon in the embedding document.
class FileIconBackend {
  const FileIconBackend();

  Future<FlowyResult<ViewPB, FlowyError>> getView(String viewId) =>
      ViewBackendService.getView(viewId);

  Future<FlowyResult<void, FlowyError>> updateIcon({
    required ViewPB view,
    required EmojiIconData icon,
  }) =>
      ViewBackendService.updateViewIcon(view: view, viewIcon: icon);

  ViewListener createListener(String viewId) => ViewListener(viewId: viewId);
}

/// An immutable attachment target with a live, non-persistent view binding.
/// A picker retains this target rather than looking up whatever node happens
/// to occupy its old path when an asynchronous selection finishes.
class FileBlockIconBinding extends ChangeNotifier {
  FileBlockIconBinding({
    required this.editorState,
    required this.node,
    this.backend = const FileIconBackend(),
  })  : _source = node.attributes[FileBlockKeys.url],
        _sourceType = node.attributes[FileBlockKeys.urlType],
        _name = node.attributes[FileBlockKeys.name],
        _referenceId = node.attributes[FileBlockKeys.workspaceFileId] {
    editorState.editableNotifier.addListener(_notify);
    _transactions = editorState.transactionStream.listen((event) {
      if (event.$1 == TransactionTime.after) _notify();
    });
    final viewId = workspaceFileId;
    if (viewId != null) {
      _listener = backend.createListener(viewId)
        ..start(
          onViewUpdated: _acceptView,
          onViewDeleted: (result) => result.onSuccess((_) => _unavailable()),
          onViewMoveToTrash: (result) =>
              result.onSuccess((_) => _unavailable()),
          onViewRestored: (result) => result.onSuccess(_acceptView),
        );
      unawaited(_loadView(viewId));
    }
  }

  final EditorState editorState;
  final Node node;
  final FileIconBackend backend;
  final Object? _source;
  final Object? _sourceType;
  final Object? _name;
  final Object? _referenceId;
  late final StreamSubscription<EditorTransactionValue> _transactions;
  ViewListener? _listener;
  ViewPB? _view;
  int _viewRevision = 0;
  bool _disposed = false;
  bool _saving = false;

  String? get workspaceFileId =>
      _referenceId is String && _referenceId.isNotEmpty
        ? _referenceId
          : null;

  bool matches(EditorState editor, Node target) =>
      identical(editorState, editor) &&
      identical(node, target) &&
      _source == target.attributes[FileBlockKeys.url] &&
      _sourceType == target.attributes[FileBlockKeys.urlType] &&
      _name == target.attributes[FileBlockKeys.name] &&
      _referenceId == target.attributes[FileBlockKeys.workspaceFileId];

  bool get isCurrent =>
      !_disposed &&
      !editorState.isDisposed &&
      node.parent != null &&
      identical(editorState.getNodeAtPath(node.path), node) &&
      matches(editorState, node);

  bool get canEdit =>
      isCurrent &&
      editorState.editable &&
      _source is String &&
      _source.isNotEmpty &&
      (workspaceFileId == null ||
          (_view?.workspaceFileReference != null && !_view!.isLocked));

  EmojiIconData get icon {
    if (workspaceFileId != null) {
      // Even while loading or after deletion, a reference must not fall back
      // to an unrelated native attachment's old node attribute.
      return _view?.icon.toEmojiIconData() ?? EmojiIconData.none();
    }
    final value = node.attributes[FileBlockKeys.icon];
    return EmojiIconData.fromStorageString(value is String ? value : null);
  }

  Future<void> _loadView(String viewId) async {
    final revision = _viewRevision;
    try {
      final result = await backend.getView(viewId);
      // A notification may have arrived while the initial read was pending.
      if (!isCurrent || revision != _viewRevision) return;
      result.onSuccess(_acceptView);
    } catch (_) {
      // An unavailable reference remains readable but cannot edit an identity
      // that has not been resolved. Never invent a local fallback identity.
    }
  }

  void _acceptView(ViewPB view) {
    if (!isCurrent || view.id != workspaceFileId) return;
    _viewRevision++;
    _view = view;
    _notify();
  }

  void _unavailable() {
    if (!isCurrent) return;
    _viewRevision++;
    _view = null;
    _notify();
  }

  Future<bool> save(EmojiIconData data) async {
    if (!canEdit || _saving) return false;
    if (icon.type == data.type && icon.emoji == data.emoji) return true;
    _saving = true;
    try {
      if (workspaceFileId != null) {
        final view = _view!;
        final revision = _viewRevision;
        final result = await backend.updateIcon(view: view, icon: data);
        if (!isCurrent) return false;
        return result.fold(
          (_) {
            if (revision == _viewRevision) {
              _acceptView(
                ViewPB.fromBuffer(view.writeToBuffer())
                  ..icon = data.toViewIcon(),
              );
            }
            return true;
          },
          (_) => throw StateError('Unable to update the workspace file icon.'),
        );
      }

      // Keep an icon edit independent of an unfinished text history item.
      final history = editorState.undoManager.undoStack;
      if (history.isNonEmpty) history.last.seal();
      final transaction = editorState.transaction
        ..updateNode(node, {
          FileBlockKeys.icon: data.isEmpty ? null : data.toStorageString(),
        })
        ..afterSelection = editorState.selection;
      await editorState.apply(
        transaction,
        withUpdateSelection: false,
        skipHistoryDebounce: true,
      );
      return isCurrent;
    } finally {
      _saving = false;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    editorState.editableNotifier.removeListener(_notify);
    unawaited(_transactions.cancel());
    unawaited(_listener?.stop());
    super.dispose();
  }
}
