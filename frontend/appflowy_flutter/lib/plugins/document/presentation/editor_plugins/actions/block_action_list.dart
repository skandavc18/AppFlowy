import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/block_action_add_button.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/block_action_button.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/block_action_option_button.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/option/option_actions.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';

class BlockActionList extends StatelessWidget {
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
    final painter = TextPainter(
      text: TextSpan(
        text: 'A',
        style: textStyle.copyWith(height: configuration.lineHeight),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      textScaler: TextScaler.linear(editorState.editorStyle.textScaleFactor),
      textHeightBehavior: TextHeightBehavior(
        applyHeightToFirstAscent: configuration.applyHeightToFirstAscent,
        applyHeightToLastDescent: configuration.applyHeightToLastDescent,
        leadingDistribution: configuration.leadingDistribution,
      ),
    )..layout();
    final firstLineHeight = painter.height;
    painter.dispose();
    return (firstLineHeight - height) / 2;
  }

  final BlockComponentContext blockComponentContext;
  final BlockComponentActionState blockComponentState;
  final List<OptionAction> actions;
  final VoidCallback showSlashMenu;
  final EditorState editorState;
  final Map<String, BlockComponentBuilder> blockComponentBuilder;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        BlockAddButton(
          blockComponentContext: blockComponentContext,
          blockComponentState: blockComponentState,
          editorState: editorState,
          showSlashMenu: showSlashMenu,
        ),
        const HSpace(2.0),
        BlockOptionButton(
          blockComponentContext: blockComponentContext,
          blockComponentState: blockComponentState,
          actions: actions,
          editorState: editorState,
          blockComponentBuilder: blockComponentBuilder,
        ),
        const HSpace(5.0),
      ],
    );
  }
}
