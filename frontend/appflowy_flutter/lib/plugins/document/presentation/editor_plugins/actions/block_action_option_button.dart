import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/block_action_option_cubit.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/block_option_menu.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/option/option_actions.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'drag_to_reorder/draggable_option_button.dart';

class BlockOptionButton extends StatefulWidget {
  const BlockOptionButton({
    super.key,
    required this.blockComponentContext,
    required this.blockComponentState,
    required this.actions,
    required this.editorState,
    required this.blockComponentBuilder,
  });

  final BlockComponentContext blockComponentContext;
  final BlockComponentActionState blockComponentState;
  final List<OptionAction> actions;
  final EditorState editorState;
  final Map<String, BlockComponentBuilder> blockComponentBuilder;

  @override
  State<BlockOptionButton> createState() => _BlockOptionButtonState();
}

class _BlockOptionButtonState extends State<BlockOptionButton> {
  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => BlockActionOptionCubit(
        editorState: widget.editorState,
        blockComponentBuilder: widget.blockComponentBuilder,
      ),
      child: Builder(
        builder: (context) => DraggableOptionButton(
          onShowMenu: () => _showMenu(context),
          editorState: widget.editorState,
          blockComponentContext: widget.blockComponentContext,
          blockComponentBuilder: widget.blockComponentBuilder,
        ),
      ),
    );
  }

  Future<void> _showMenu(BuildContext context) async {
    final cubit = context.read<BlockActionOptionCubit>();
    // In a right-to-left layout the handle sits on the other side of the
    // block, so the menu has to open the other way too.
    final rtl = context.read<AppearanceSettingsCubit>().state.layoutDirection ==
        LayoutDirection.rtlLayout;

    keepEditorFocusNotifier.increase();
    widget.blockComponentState.alwaysShowActions = true;

    await showAppMenuForWidget<void>(
      context: context,
      placement: rtl ? AppMenuPlacement.endTop : AppMenuPlacement.startTop,
      entries: buildBlockOptionMenu(
        context: context,
        editorState: widget.editorState,
        node: widget.blockComponentContext.node,
        actions: widget.actions,
        cubit: cubit,
      ),
    );

    keepEditorFocusNotifier.decrease();
    if (!mounted) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.editorState.selectionType = null;
      widget.editorState.selection = null;
      widget.blockComponentState.alwaysShowActions = false;
    });
  }
}
