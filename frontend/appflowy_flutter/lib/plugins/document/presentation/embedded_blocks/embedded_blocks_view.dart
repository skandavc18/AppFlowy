import 'dart:async';

import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_configuration.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/shortcuts/text_field_aware_commands.dart';
import 'package:appflowy/plugins/document/presentation/editor_style.dart';
import 'package:appflowy/shared/editor_focus_node.dart';
import 'package:appflowy/shared/json_equality.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';

/// Page blocks, drawn and edited away from a page.
///
/// A dashboard widget or a canvas card can hold anything `/` puts into a page
/// — a diagram, a table, a map, a code block, an extension's island. It is
/// rendered with the page's own block builders, so it behaves exactly as it
/// does in a page, and it is kept by its host as a document's JSON: every
/// change is handed back through [onChanged].
///
/// A [document] that arrives changed from outside (an undo on the dashboard)
/// replaces what is shown; one this view handed out itself is not re-read.
///
/// ⚠️ It must be given a BOUNDED height. The editor's root is an `Overlay`,
/// which throws when laid out at unbounded height.
class EmbeddedBlocksView extends StatefulWidget {
  const EmbeddedBlocksView({
    super.key,
    required this.document,
    this.onChanged,
    this.editable = true,
    this.padding = EdgeInsets.zero,
    this.hostViewId = '',
  });

  /// `Document.toJson()` of the blocks.
  final Map<String, Object?> document;
  final ValueChanged<Map<String, Object?>>? onChanged;
  final bool editable;
  final EdgeInsets padding;

  /// The page, dashboard or canvas holding the blocks. When it is an open
  /// page its bloc is lent to the blocks, which read it for uploads.
  final String hostViewId;

  @override
  State<EmbeddedBlocksView> createState() => _EmbeddedBlocksViewState();
}

class _EmbeddedBlocksViewState extends State<EmbeddedBlocksView> {
  late EditorState _editorState;
  StreamSubscription<EditorTransactionValue>? _changes;
  Timer? _save;
  final EditorFocusNode _focusNode =
      EditorFocusNode(debugLabel: 'embedded blocks');
  late final List<CommandShortcutEvent> _commands =
      embeddedBlocksCommandShortcuts();

  /// What was last handed out, so it is not mistaken for news when it comes
  /// back down through the host.
  Map<String, Object?>? _handedOut;

  @override
  void initState() {
    super.initState();
    _adopt(widget.document);
  }

  @override
  void didUpdateWidget(covariant EmbeddedBlocksView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.editable != oldWidget.editable) {
      _editorState.editable = widget.editable;
    }
    if (!identical(widget.document, oldWidget.document) &&
        !_isOwnEcho(widget.document) &&
        !_sameDocument(widget.document, _editorState.document.toJson())) {
      // What arrived from outside wins over an edit not yet handed out — an
      // undo on the dashboard must not be re-done by a late save. Nothing is
      // reported from here: this runs during a build.
      _save?.cancel();
      _save = null;
      _release();
      _adopt(widget.document);
      // Host and view agree on this one now; only later news is news.
      _handedOut = widget.document;
    }
  }

  @override
  void dispose() {
    final pending = _save != null;
    _save?.cancel();
    _save = null;
    if (pending) {
      // Reported once the tree is unlocked, and only if the host still
      // listens: a closing dashboard may already have let go.
      final json = Map<String, Object?>.from(_editorState.document.toJson());
      final onChanged = widget.onChanged;
      scheduleMicrotask(() {
        try {
          onChanged?.call(json);
        } on Object {
          // The host is gone; the edit went with it.
        }
      });
    }
    _release();
    _focusNode.dispose();
    super.dispose();
  }

  /// Whether [document] is what this view last handed out, coming back. A
  /// host that saves and reads itself back hands down an equal copy rather
  /// than the same map; taken for news, it would replace the editor and lose
  /// whatever was typed or drawn since — including into a drawing still open.
  bool _isOwnEcho(Map<String, Object?> document) {
    final handedOut = _handedOut;
    return handedOut != null &&
        (identical(document, handedOut) ||
            jsonValuesEqual(document, handedOut));
  }

  void _adopt(Map<String, Object?> json) {
    _editorState = EditorState(document: embeddedBlocksDocument(json))
      ..editable = widget.editable;
    _changes = _editorState.transactionStream.listen((event) {
      if (event.$1 == TransactionTime.after) {
        _scheduleSave();
      }
    });
  }

  void _release() {
    unawaited(_changes?.cancel());
    _changes = null;
    _editorState.dispose();
  }

  void _scheduleSave() {
    _save?.cancel();
    _save = Timer(const Duration(milliseconds: 250), _flush);
  }

  void _flush() {
    final pending = _save;
    _save = null;
    if (pending == null) return;
    pending.cancel();
    final json = Map<String, Object?>.from(_editorState.document.toJson());
    _handedOut = json;
    widget.onChanged?.call(json);
  }

  @override
  Widget build(BuildContext context) {
    final editorState = _editorState;
    final body = LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (!width.isFinite || width <= 0 || !constraints.hasBoundedHeight) {
          return const SizedBox.shrink();
        }
        final styleCustomizer = EditorStyleCustomizer(
          context: context,
          padding: widget.padding,
          width: width,
          editorState: editorState,
        );
        return Provider(
          // An embedded database asks its host how wide the page is; here
          // the blocks are the whole measure, so it takes no gutter.
          create: (_) => const DatabasePluginWidgetBuilderSize(
            horizontalPadding: 0,
          ),
          child: AppFlowyEditor(
            key: ObjectKey(editorState),
            editorState: editorState,
            focusNode: _focusNode,
            editable: widget.editable,
            editorStyle: styleCustomizer.style(),
            commandShortcutEvents: _commands,
            blockComponentBuilders: buildBlockComponentBuilders(
              context: context,
              editorState: editorState,
              styleCustomizer: styleCustomizer,
              // No drag handles or `+`: the host arranges the blocks.
              editable: false,
            ),
            contextMenuItems: const [],
            disableAutoScroll: true,
          ),
        );
      },
    );

    // Blocks read the page's bloc for uploads and cloud files. On an open
    // page it is lent; elsewhere they fall back to keeping files locally.
    final documentBloc = widget.hostViewId.isEmpty
        ? null
        : DocumentBloc.findOpen(widget.hostViewId);
    return documentBloc == null
        ? body
        : BlocProvider<DocumentBloc>.value(value: documentBloc, child: body);
  }
}

/// The document [json] describes, or an empty page when it describes none.
Document embeddedBlocksDocument(Map<String, Object?> json) {
  try {
    if (json.isNotEmpty) {
      return Document.fromJson(Map<String, dynamic>.from(json));
    }
  } on Object {
    // A malformed document is shown as an empty one rather than as an error.
  }
  return Document.blank(withInitialText: true);
}

bool _sameDocument(Map<String, Object?> a, Map<String, Object?> b) =>
    jsonValuesEqual(a, b);
