import 'dart:math' as math;

import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/find_and_replace_menu.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'document_find_content.dart';

/// A non-modal, pane-bounded find overlay belonging to one live document.
abstract final class DocumentFindMenu {
  static _DocumentFindOwner? _owner;
  static int _request = 0;
  static final _activeEditor = _DocumentFindOwnerListenable();

  static bool get isOpen => _owner != null;
  static EditorState? get activeEditor => _owner?.editor;
  // A scope identifies BOTH external query fields to the contextual router.
  static FocusNode? get findFocusNode => _owner?.findScopeNode;
  static ValueListenable<EditorState?> get activeEditorListenable =>
      _activeEditor;

  static void show(
    BuildContext context,
    EditorState editorState, {
    bool replace = false,
    bool Function()? canReplace,
    bool Function()? isSelected,
    ViewPB? Function()? currentView,
    Stream<ViewPB>? viewChanges,
    DocumentFindReadProvider? referenceProvider,
    String? documentId,
  }) {
    if (editorState.isDisposed ||
        !_isVisibleOwner(context) ||
        !(isSelected?.call() ?? true)) {
      return;
    }
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      return;
    }
    final request = ++_request;
    final current = _owner;
    if (current != null &&
        identical(current.editor, editorState) &&
        current.isActive) {
      current
        ..canReplace = canReplace
        ..isSelected = isSelected
        ..reveal(replace: replace);
      return;
    }
    current?.close();
    if (request != _request) {
      return; // A close listener opened/dismissed a newer request.
    }
    final owner = _DocumentFindOwner(
      context,
      editorState,
      overlay,
      canReplace: canReplace,
      isSelected: isSelected,
      currentView: currentView,
      viewChanges: viewChanges,
      referenceProvider: referenceProvider,
      documentId: documentId,
    );
    _owner = owner;
    owner.insert(replace: replace);
    _publishOwner();
  }

  /// Passing an editor prevents an old page's teardown closing a newer menu.
  static void dismiss({EditorState? editorState}) {
    final owner = _owner;
    if (editorState == null || identical(editorState, owner?.editor)) {
      _request++;
    }
    if (owner != null &&
        (editorState == null || identical(editorState, owner.editor))) {
      owner.close();
    }
  }

  static void _publishOwner() {
    void publish() => _activeEditor.publish(_owner);
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => publish());
    } else {
      publish();
    }
  }
}

/// A close/reopen may coalesce during a frame while the editor stays the same.
/// Publish the new owner identity too, or the router retains its disposed scope.
class _DocumentFindOwnerListenable extends ChangeNotifier
    implements ValueListenable<EditorState?> {
  _DocumentFindOwner? _owner;

  @override
  EditorState? get value => _owner?.editor;

  void publish(_DocumentFindOwner? owner) {
    if (identical(owner, _owner)) {
      return;
    }
    _owner = owner;
    notifyListeners();
  }
}

class _DocumentFindOwner {
  _DocumentFindOwner(
    this.context,
    this.editor,
    this.overlay, {
    this.canReplace,
    this.isSelected,
    this.currentView,
    this.viewChanges,
    this.referenceProvider,
    this.documentId,
  })  : _pageId = documentId ?? currentView?.call()?.id,
        themes = InheritedTheme.capture(from: context, to: overlay.context) {
    entry = OverlayEntry(builder: _build);
  }

  static const _minimumBarWidth = 180.0;

  final BuildContext context;
  final EditorState editor;
  final OverlayState overlay;
  final CapturedThemes themes;
  final ViewPB? Function()? currentView;
  final Stream<ViewPB>? viewChanges;
  final DocumentFindReadProvider? referenceProvider;
  final String? documentId;
  final String? _pageId;
  final findScopeNode = FocusScopeNode(debugLabel: 'document find bar');
  final findFocusNode = FocusNode(debugLabel: 'document find');
  final replaceFocusNode = FocusNode(debugLabel: 'document replace');
  final _hostKey = GlobalKey<_DocumentFindOverlayState>();
  late final OverlayEntry entry;
  bool Function()? canReplace;
  bool Function()? isSelected;
  bool _closed = false;
  bool _inserted = false;
  bool _hostMounted = false;
  bool _focusDisposed = false;
  bool _replace = false;
  bool _lastReplaceAllowed = false;
  Rect? _bounds;

  bool get isActive =>
      !_closed &&
      identical(DocumentFindMenu._owner, this) &&
      !editor.isDisposed &&
      overlay.mounted &&
      _isVisibleOwner(context) &&
      (isSelected?.call() ?? true) &&
      (currentView == null ||
          currentView?.call()?.id == _pageId ||
          (documentId != null && currentView?.call() == null));

  bool get replaceAllowed =>
      isActive &&
      editor.editable &&
      (canReplace?.call() ?? true) &&
      currentView?.call()?.isLocked != true;

  void insert({required bool replace}) {
    editor.onDispose.addListener(close);
    editor.editableNotifier.addListener(_permissionsChanged);
    _replace = replace && replaceAllowed;
    _lastReplaceAllowed = replaceAllowed;
    _bounds = _ownerBounds();
    overlay.insert(entry);
    _inserted = true;
    WidgetsBinding.instance.addPostFrameCallback(_checkOwner);
  }

  void reveal({required bool replace}) {
    if (!isActive) {
      return;
    }
    _replace = replace && replaceAllowed;
    _markNeedsBuild();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isActive) {
        (_replace && replaceAllowed ? replaceFocusNode : findFocusNode)
            .requestFocus();
      }
    });
  }

  void _permissionsChanged() {
    if (_closed) {
      return;
    }
    if (!replaceAllowed) {
      _replace = false;
    }
    _markNeedsBuild();
  }

  void _markNeedsBuild() {
    void rebuild() {
      if (!_closed && _inserted) {
        entry.markNeedsBuild();
      }
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => rebuild());
    } else {
      rebuild();
    }
  }

  void _checkOwner(Duration _) {
    if (_closed) {
      return;
    }
    if (!isActive) {
      close();
      return;
    }
    final bounds = _ownerBounds();
    final allowed = replaceAllowed;
    if (bounds != _bounds || allowed != _lastReplaceAllowed) {
      _bounds = bounds;
      _lastReplaceAllowed = allowed;
      if (!allowed) {
        _replace = false;
      }
      _markNeedsBuild();
    }
    // Observe frames caused by layout/tab/route changes, but do not schedule
    // frames or a polling timer just because Find is open.
    WidgetsBinding.instance.addPostFrameCallback(_checkOwner);
  }

  Rect? _ownerBounds() {
    if (!context.mounted || !overlay.mounted) {
      return null;
    }
    final ownerBox = context.findRenderObject();
    final overlayBox = overlay.context.findRenderObject();
    if (ownerBox is! RenderBox ||
        overlayBox is! RenderBox ||
        !ownerBox.attached ||
        !ownerBox.hasSize ||
        !overlayBox.hasSize) {
      return null;
    }
    final origin = ownerBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    final media = MediaQuery.maybeOf(context);
    final padding = media?.padding ?? EdgeInsets.zero;
    final safe = Rect.fromLTRB(
      padding.left,
      padding.top,
      overlayBox.size.width - padding.right,
      overlayBox.size.height - padding.bottom - (media?.viewInsets.bottom ?? 0),
    );
    return (origin & ownerBox.size).intersect(safe);
  }

  Rect? _searchBounds() {
    final box = _hostKey.currentContext?.findRenderObject();
    return box is RenderBox && box.attached && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
  }

  Widget _build(BuildContext overlayContext) {
    final bounds = _ownerBounds();
    if (!isActive || bounds == null || bounds.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_closed && !isActive) {
          close();
        }
      });
      return const SizedBox.shrink();
    }
    final margin = math.min(8.0, bounds.shortestSide / 4);
    // Keep the input usable at 180 px; margins must not steal its last 16 px.
    final horizontalMargin = math.min(
      margin,
      math.max(0.0, (bounds.width - _minimumBarWidth) / 2),
    );
    final width = math.max(0.0, bounds.width - horizontalMargin * 2);
    final top =
        bounds.top + math.min(52.0, math.max(margin, bounds.height - 100));
    return Positioned(
      top: top,
      left: bounds.left + horizontalMargin,
      width: width,
      child: Align(
        alignment: Alignment.topRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: math.max(0, bounds.bottom - top - margin),
          ),
          // On a very narrow/short pane retain every control without overflow
          // or shrinking text. These viewports hit-test only the bar, not the
          // underlying page; normal document clicks still go through.
          child: SingleChildScrollView(
            primary: false,
            child: _buildHorizontalScroll(width),
          ),
        ),
      ),
    );
  }

  Widget _buildHorizontalScroll(double paneWidth) {
    final bar = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: math.max(_minimumBarWidth, paneWidth),
      ),
      // Crossing the tiny-pane boundary must not dispose the host: disposal
      // closes this owner and releases its session and native field focus.
      child: themes.wrap(_DocumentFindOverlay(key: _hostKey, owner: this)),
    );
    // Normal panes give the responsive bar a finite width and a stable parent.
    // Only genuinely tiny panes scroll; never squeeze controls below 180 px.
    if (paneWidth >= _minimumBarWidth) {
      return bar;
    }
    return SingleChildScrollView(
      primary: false,
      scrollDirection: Axis.horizontal,
      child: bar,
    );
  }

  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    // Clear the static owner before removing the entry: callbacks from the
    // old subtree are harmless even if a new menu is opened reentrantly.
    if (identical(DocumentFindMenu._owner, this)) {
      DocumentFindMenu._owner = null;
      DocumentFindMenu._publishOwner();
    }
    editor.onDispose.removeListener(close);
    editor.editableNotifier.removeListener(_permissionsChanged);
    if (_inserted) {
      _inserted = false;
      // mounted is false before the first frame, but the entry was inserted
      // and must still be removed, otherwise it becomes a ghost overlay.
      entry.remove();
    }
    entry.dispose();
    if (!_hostMounted) {
      _disposeFocus();
    }
  }

  void _disposeFocus() {
    if (_focusDisposed) {
      return;
    }
    _focusDisposed = true;
    findFocusNode.dispose();
    replaceFocusNode.dispose();
    findScopeNode.dispose();
  }
}

class _DocumentFindOverlay extends StatefulWidget {
  const _DocumentFindOverlay({super.key, required this.owner});

  final _DocumentFindOwner owner;

  @override
  State<_DocumentFindOverlay> createState() => _DocumentFindOverlayState();
}

class _DocumentFindOverlayState extends State<_DocumentFindOverlay> {
  @override
  void initState() {
    super.initState();
    widget.owner._hostMounted = true;
  }

  @override
  void dispose() {
    widget.owner
      ..close()
      .._disposeFocus();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final owner = widget.owner;
    return FocusScope(
      node: owner.findScopeNode,
      child: Material(
        color: Colors.transparent,
        child: FindAndReplaceMenuWidget(
          editorState: owner.editor,
          documentId: owner.documentId,
          titleObstruction: owner._searchBounds,
          currentView: owner.currentView,
          viewChanges: owner.viewChanges,
          referenceProvider: owner.referenceProvider,
          showReplaceMenu: owner._replace,
          canReplace: () => owner.replaceAllowed,
          isOwnerActive: () => owner.isActive,
          findFocusNode: owner.findFocusNode,
          replaceFocusNode: owner.replaceFocusNode,
          onDismiss: owner.close,
        ),
      ),
    );
  }
}

bool _isVisibleOwner(BuildContext context) {
  if (!context.mounted) {
    return false;
  }
  final routes = <ModalRoute<dynamic>>{};
  var route = ModalRoute.of(context);
  while (route != null && routes.add(route)) {
    if (!route.isCurrent) {
      return false;
    }
    final navigator = route.navigator;
    route = navigator != null && navigator.mounted
        ? ModalRoute.of(navigator.context)
        : null;
  }
  var visible = true;
  context.visitAncestorElements((element) {
    final widget = element.widget;
    if ((widget is Offstage && widget.offstage) ||
        (widget is Visibility && !widget.visible) ||
        (widget is TickerMode && !widget.enabled)) {
      visible = false;
      return false;
    }
    return true;
  });
  return visible;
}
