import 'dart:async';

import 'package:appflowy/plugins/database/widgets/database_view_widget.dart';
import 'package:appflowy/plugins/document/presentation/compact_mode_event.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/block_align.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/built_in_page_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/resizable_media.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/mention/mention_page_block.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class DatabaseBlockKeys {
  const DatabaseBlockKeys._();

  static const String gridType = 'grid';
  static const String boardType = 'board';
  static const String calendarType = 'calendar';

  static const String parentID = 'parent_id';
  static const String viewID = 'view_id';
  static const String enableCompactMode = 'enable_compact_mode';
  static const String width = 'width';
  static const String height = 'height';
}

const overflowTypes = {
  DatabaseBlockKeys.gridType,
  DatabaseBlockKeys.boardType,
};

class DatabaseViewBlockComponentBuilder extends BlockComponentBuilder {
  DatabaseViewBlockComponentBuilder({
    super.configuration,
  });

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return DatabaseBlockComponentWidget(
      key: node.key,
      node: node,
      configuration: configuration,
      showActions: showActions(node),
      actionBuilder: (context, state) => actionBuilder(
        blockComponentContext,
        state,
      ),
      actionTrailingBuilder: (context, state) => actionTrailingBuilder(
        blockComponentContext,
        state,
      ),
    );
  }

  @override
  BlockComponentValidate get validate => (node) =>
      node.children.isEmpty &&
      node.attributes[DatabaseBlockKeys.parentID] is String &&
      node.attributes[DatabaseBlockKeys.viewID] is String;
}

class DatabaseBlockComponentWidget extends BlockComponentStatefulWidget {
  const DatabaseBlockComponentWidget({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<DatabaseBlockComponentWidget> createState() =>
      _DatabaseBlockComponentWidgetState();
}

class _DatabaseBlockComponentWidgetState
    extends State<DatabaseBlockComponentWidget>
    with BlockComponentConfigurable {
  @override
  Node get node => widget.node;

  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  late StreamSubscription<CompactModeEvent> compactModeSubscription;
  EditorState? editorState;

  double? get _width {
    final stored = node.attributes[DatabaseBlockKeys.width];
    return stored is num ? stored.toDouble() : null;
  }

  double? get _height {
    final stored = node.attributes[DatabaseBlockKeys.height];
    return stored is num ? stored.toDouble() : null;
  }

  Future<void> _updateSize(Map<String, Object?> attributes) async {
    final state = editorState;
    if (state == null) {
      return;
    }
    final transaction = state.transaction
      ..updateNode(node, {...node.attributes, ...attributes});
    await state.apply(transaction);
  }

  @override
  void initState() {
    super.initState();
    compactModeSubscription =
        compactModeEventBus.on<CompactModeEvent>().listen((event) {
      if (event.id != node.id) return;
      final newAttributes = {
        ...node.attributes,
        DatabaseBlockKeys.enableCompactMode: event.enable,
      };
      final theEditorState = editorState;
      if (theEditorState == null) return;
      final transaction = theEditorState.transaction;
      transaction.updateNode(node, newAttributes);
      theEditorState.apply(transaction);
    });
  }

  @override
  void dispose() {
    super.dispose();
    compactModeSubscription.cancel();
    editorState = null;
  }

  @override
  Widget build(BuildContext context) {
    final editorState = Provider.of<EditorState>(context, listen: false);
    this.editorState = editorState;
    Widget child = BuiltInPageWidget(
      node: widget.node,
      editorState: editorState,
      builder: (view) => Provider.value(
        value: ReferenceState(true),
        child: _buildResizableDatabase(view, editorState),
      ),
    );

    child = FocusScope(
      skipTraversal: true,
      onFocusChange: (value) {
        if (value && keepEditorFocusNotifier.value == 0) {
          context.read<EditorState>().selection = null;
        }
      },
      child: child,
    );

    if (!editorState.editable) {
      child = IgnorePointer(
        child: child,
      );
    }

    child = Padding(padding: padding, child: child);

    if (widget.showActions && widget.actionBuilder != null) {
      child = BlockComponentActionWrapper(
        node: node,
        actionBuilder: widget.actionBuilder!,
        actionTrailingBuilder: widget.actionTrailingBuilder,
        child: child,
      );
    }

    return child;
  }

  Widget _buildResizableDatabase(ViewPB view, EditorState editorState) {
    // A chart, a map, a slide deck and the shared table readings are written
    // as pages, so they take whatever height they are given. A grid, a board
    // and a calendar grow with their rows — pinning them to a shorter box only
    // clips what is in them, so they are resized by width alone.
    final givesHeight = embeddedDatabaseViewFillsItsBox(view);
    return ResizableMedia(
      // Unset means "as wide as the page": clamping infinity to the incoming
      // constraint is exactly the full measure, with no magic number.
      width: _width ?? double.infinity,
      minWidth: 320,
      height: givesHeight ? (_height ?? embeddedDatabaseViewHeight) : null,
      minHeight: 220,
      maxHeight: 1600,
      alignment: blockEmbedAlignment(node),
      editable: editorState.editable,
      onResize: (value) => unawaited(
        _updateSize({DatabaseBlockKeys.width: value}),
      ),
      onResizeHeight: givesHeight
          ? (value) => unawaited(_updateSize({DatabaseBlockKeys.height: value}))
          : null,
      // The block draws the drag handles and the block menu itself, so the
      // database must not draw a second set beside its own tab bar. shrinkWrap
      // stays on: flipping it would re-parent the whole database, and its
      // header reorders through global keys that cannot survive that.
      child: DatabaseViewWidget(
        key: ValueKey(view.id),
        view: view,
        showActions: false,
        node: widget.node,
      ),
    );
  }
}
