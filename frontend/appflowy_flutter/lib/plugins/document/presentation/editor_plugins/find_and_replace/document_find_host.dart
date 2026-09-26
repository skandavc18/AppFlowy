import 'dart:async';

import 'package:appflowy/features/page_access_level/data/repositories/page_access_level_repository.dart';
import 'package:appflowy/features/page_access_level/data/repositories/rust_page_access_level_repository_impl.dart';
import 'package:appflowy/features/share_tab/data/models/models.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/notification.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/rust_stream.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

import 'document_find_menu.dart';
import 'document_find_title.dart';

enum DocumentFindHostChangeKind { updated, deleted, restored }

class DocumentFindHostChange {
  const DocumentFindHostChange(
    this.viewId, {
    this.kind = DocumentFindHostChangeKind.updated,
  });

  final String viewId;
  final DocumentFindHostChangeKind kind;
}

/// A row's document identity is NOT its table's identity or primary-cell text.
/// Only real document metadata is lent to Find; table access is a separate,
/// fail-closed authority. Neither lookup creates/renames a view or opens a doc.
class DocumentFindMetadataScope extends ChangeNotifier {
  DocumentFindMetadataScope.row({
    required this.documentId,
    required this.tableViewId,
    ViewPB? initialDocumentView,
    PageAccessLevelRepository? repository,
    Stream<DocumentFindHostChange>? changes,
  }) : _repository = repository ?? RustPageAccessLevelRepositoryImpl() {
    _view = initialDocumentView?.id == documentId ? initialDocumentView : null;
    _subscription = (changes ?? _nativeChanges()).listen(_onChange);
    unawaited(refresh());
  }

  final String documentId;
  final String tableViewId;
  final PageAccessLevelRepository _repository;
  final _viewChanges = StreamController<ViewPB>.broadcast(sync: true);
  StreamSubscription<DocumentFindHostChange>? _subscription;
  ViewPB? _view;
  bool _writable = false;
  final _deletedViews = <String>{};
  bool _disposed = false;
  int _revision = 0;

  ViewPB? get currentView => isActive ? _view : null;
  Stream<ViewPB> get viewChanges => _viewChanges.stream;
  bool get isActive =>
      !_disposed &&
      _deletedViews.isEmpty &&
      documentId.isNotEmpty &&
      tableViewId.isNotEmpty;
  bool get canReplace => isActive && _writable && _view?.isLocked == false;

  /// Local access is also resolved by the native repository, never inferred
  /// from a missing PageAccessLevelBloc or a user-profile default. A pending,
  /// failed or mismatched read revokes writes immediately, not after a frame.
  Future<void> refresh() async {
    if (!isActive) return;
    final revision = ++_revision;
    _writable = false;
    notifyListeners();
    bool current() => isActive && revision == _revision;
    try {
      final document = await _repository.getView(documentId);
      if (!current()) return;
      final view = document.fold((view) => view, (_) => null);
      _view = view?.id == documentId ? view : null;
      if (_view != null) _viewChanges.add(_view!);
      notifyListeners();

      final table = await _repository.getView(tableViewId);
      if (!current()) return;
      final tableView = table.fold((view) => view, (_) => null);
      if (_view == null ||
          tableView?.id != tableViewId ||
          tableView!.isLocked) {
        return;
      }

      final permission = await _repository.getAccessLevel(tableViewId);
      if (!current()) return;
      final access = permission.fold((access) => access, (_) => null);
      if (access == null || access == ShareAccessLevel.readOnly) return;

      // Permission resolution can await user/workspace reads. Re-read the
      // table lock afterwards; never authorize against that earlier snapshot.
      final latest = await _repository.getView(tableViewId);
      if (!current()) return;
      final latestView = latest.fold((view) => view, (_) => null);
      _writable = latestView?.id == tableViewId && !latestView!.isLocked;
      notifyListeners();
    } on Object {
      if (!current()) return;
      _writable = false;
      notifyListeners();
    }
  }

  void _onChange(DocumentFindHostChange change) {
    if (_disposed ||
        (change.viewId.isNotEmpty &&
            change.viewId != documentId &&
            change.viewId != tableViewId)) {
      return;
    }
    if (change.kind == DocumentFindHostChangeKind.deleted) {
      ++_revision;
      _deletedViews.add(change.viewId);
      _writable = false;
      notifyListeners();
      return;
    }
    if (change.kind == DocumentFindHostChangeKind.restored) {
      _deletedViews.remove(change.viewId);
    }
    unawaited(refresh());
  }

  @override
  void dispose() {
    _disposed = true;
    ++_revision;
    _writable = false;
    unawaited(_subscription?.cancel());
    unawaited(_viewChanges.close());
    super.dispose();
  }

  static Stream<DocumentFindHostChange> _nativeChanges() =>
      RustStreamReceiver.shared.observable.stream.where((event) {
        return event.source == 'Folder' &&
            {
              FolderNotification.DidUpdateView.value,
              FolderNotification.DidDeleteView.value,
              FolderNotification.DidMoveViewToTrash.value,
              FolderNotification.DidRestoreView.value,
              FolderNotification.DidUpdateSharedUsers.value,
              FolderNotification.DidUpdateSharedViews.value,
              FolderNotification.DidUpdateSectionViews.value,
            }.contains(event.ty);
      }).map((event) {
        final deleted = event.ty == FolderNotification.DidDeleteView.value ||
            event.ty == FolderNotification.DidMoveViewToTrash.value;
        return DocumentFindHostChange(
          // Shared/section membership changes can be workspace-scoped. They
          // invalidate this row's table authority, not its document identity.
          event.ty == FolderNotification.DidUpdateSharedViews.value ||
                  event.ty == FolderNotification.DidUpdateSectionViews.value
              ? ''
              : event.id,
          kind: deleted
              ? DocumentFindHostChangeKind.deleted
              : event.ty == FolderNotification.DidRestoreView.value
                  ? DocumentFindHostChangeKind.restored
                  : DocumentFindHostChangeKind.updated,
        );
      });
}

/// Shared by popup and full-page row hosts. Owns only Find metadata/authority,
/// not the cell controller, editor, table ViewBloc or a PageAccessLevelBloc.
class RowDocumentFindHost extends StatefulWidget {
  const RowDocumentFindHost({
    super.key,
    required this.documentId,
    required this.tableViewId,
    required this.editorState,
    required this.builder,
    this.initialDocumentView,
    this.repository,
    this.changes,
  });

  final String documentId;
  final String tableViewId;
  final EditorState editorState;
  final ViewPB? initialDocumentView;
  final Widget Function(BuildContext, DocumentFindMetadataScope) builder;
  final PageAccessLevelRepository? repository;
  final Stream<DocumentFindHostChange>? changes;

  @override
  State<RowDocumentFindHost> createState() => _RowDocumentFindHostState();
}

class _RowDocumentFindHostState extends State<RowDocumentFindHost> {
  late DocumentFindMetadataScope _scope;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  void _bind() {
    _scope = DocumentFindMetadataScope.row(
      documentId: widget.documentId,
      tableViewId: widget.tableViewId,
      initialDocumentView: widget.initialDocumentView,
      repository: widget.repository,
      changes: widget.changes,
    );
    DocumentFindTitle.of(widget.editorState).requireNativeTitle(this);
  }

  @override
  void didUpdateWidget(covariant RowDocumentFindHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.documentId != widget.documentId ||
        oldWidget.tableViewId != widget.tableViewId ||
        !identical(oldWidget.editorState, widget.editorState) ||
        !identical(oldWidget.repository, widget.repository) ||
        !identical(oldWidget.changes, widget.changes)) {
      _unbind(oldWidget.editorState);
      _bind();
    }
  }

  void _unbind(EditorState editor) {
    DocumentFindMenu.dismiss(editorState: editor);
    DocumentFindTitle.of(editor).releaseNativeTitle(this);
    _scope.dispose();
  }

  @override
  void dispose() {
    _unbind(widget.editorState);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _scope,
        builder: (context, _) => widget.builder(context, _scope),
      );
}
