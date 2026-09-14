import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/block_action_add_button.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/block_action_button.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/block_action_option_button.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/option/option_actions.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';

class BlockActionList extends StatefulWidget {
  const BlockActionList({
    super.key,
    required this.blockComponentContext,
    required this.blockComponentState,
    required this.editorState,
    required this.actions,
    required this.showSlashMenu,
    required this.blockComponentBuilder,
  });

  /// The height of the row, driven by the square action buttons.
  static const double height = BlockActionButton.size;

  /// The width the two buttons and their trailing gap take up.
  ///
  /// The editor lays this row out *before* the block, so a page that wants its
  /// text to begin on a given measure has to start a gutter's width earlier.
  static const double gutterWidth = BlockActionButton.size * 2 + 2.0 + 5.0;

  // Shared across blocks and editors. Only the 32 most recently used heights
  // are retained, never the native TextPainters used to measure them.
  static final _firstLineHeights = _createFirstLineHeightCache();

  static Map<(TextStyle, double, TextHeightBehavior), double>
      _createFirstLineHeightCache() {
    final cache = <(TextStyle, double, TextHeightBehavior), double>{};
    // Lazy static initialization registers once, not once per hovered block.
    PaintingBinding.instance.systemFonts.addListener(cache.clear);
    return cache;
  }

  @visibleForTesting
  static int get firstLineHeightCacheSize => _firstLineHeights.length;

  @visibleForTesting
  static VoidCallback? onFirstLineMeasuredForTesting;

  /// The vertical offset, measured from the top of the block's content, that
  /// vertically centers the action buttons on the first line of the block's
  /// text.
  ///
  /// The first line box is not simply `fontSize * lineHeight`: the editor
  /// disables [TextHeightBehavior.applyHeightToFirstAscent] on Windows, which
  /// drops the leading above the first line. Measuring keeps the buttons
  /// aligned whatever the font, font size and platform.
  static double topOffsetForFirstLine({
    required EditorState editorState,
    required TextStyle textStyle,
  }) {
    final configuration = editorState.editorStyle.textStyleConfiguration;
    final effectiveStyle = textStyle.copyWith(height: configuration.lineHeight);
    final textScaleFactor = editorState.editorStyle.textScaleFactor;
    final textHeightBehavior = TextHeightBehavior(
      applyHeightToFirstAscent: configuration.applyHeightToFirstAscent,
      applyHeightToLastDescent: configuration.applyHeightToLastDescent,
      leadingDistribution: configuration.leadingDistribution,
    );
    final key = (effectiveStyle, textScaleFactor, textHeightBehavior);
    final cache = _firstLineHeights;
    final cachedHeight = cache.remove(key);
    if (cachedHeight != null) {
      cache[key] = cachedHeight; // Move hits to the most recently used end.
      return (cachedHeight - height) / 2;
    }

    final painter = TextPainter(
      text: TextSpan(
        text: 'A',
        style: effectiveStyle,
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      textScaler: TextScaler.linear(textScaleFactor),
      textHeightBehavior: textHeightBehavior,
    );
    final double firstLineHeight;
    try {
      painter.layout();
      firstLineHeight = painter.height;
    } finally {
      painter.dispose();
    }
    if (cache.length == 32) {
      cache.remove(cache.keys.first);
    }
    cache[key] = firstLineHeight;
    onFirstLineMeasuredForTesting?.call();
    return (firstLineHeight - height) / 2;
  }

  final BlockComponentContext blockComponentContext;
  final BlockComponentActionState blockComponentState;
  final List<OptionAction> actions;
  final VoidCallback showSlashMenu;
  final EditorState editorState;
  final Map<String, BlockComponentBuilder> blockComponentBuilder;

  @override
  State<BlockActionList> createState() => _BlockActionListState();
}

class _BlockActionListState extends State<BlockActionList> {
  Row? _buttonRow;

  // The editor creates a new closure on hover. Keep the child callback stable,
  // but forward to the current widget so a replacement never becomes stale.
  late final VoidCallback _showSlashMenu = _invokeSlashMenu;

  void _invokeSlashMenu() => widget.showSlashMenu();

  @override
  void didUpdateWidget(covariant BlockActionList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(
          oldWidget.blockComponentContext,
          widget.blockComponentContext,
        ) ||
        !identical(oldWidget.blockComponentState, widget.blockComponentState) ||
        !identical(oldWidget.editorState, widget.editorState) ||
        !identical(oldWidget.actions, widget.actions) ||
        !identical(
          oldWidget.blockComponentBuilder,
          widget.blockComponentBuilder,
        )) {
      // Node rebuilds supply a fresh context even when the mutable node itself
      // is unchanged. Only hover-only updates may reuse the existing children.
      _buttonRow = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Identical widget instances skip parent-driven rebuilds. Descendants keep
    // their own inherited-theme and appearance subscriptions.
    return _buttonRow ??= Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        BlockAddButton(
          blockComponentContext: widget.blockComponentContext,
          blockComponentState: widget.blockComponentState,
          editorState: widget.editorState,
          showSlashMenu: _showSlashMenu,
        ),
        const HSpace(2.0),
        BlockOptionButton(
          blockComponentContext: widget.blockComponentContext,
          blockComponentState: widget.blockComponentState,
          actions: widget.actions,
          editorState: widget.editorState,
          blockComponentBuilder: widget.blockComponentBuilder,
        ),
        const HSpace(5.0),
      ],
    );
  }
}
