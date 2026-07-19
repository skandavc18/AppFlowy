import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/block_action_button.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/block_action_option_cubit.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/option/option_actions.dart';
import 'package:appflowy/shared/context_menu_surface_style.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/presentation/widgets/pop_up_action.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_popover/appflowy_popover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class BlockAddButton extends StatelessWidget {
  const BlockAddButton({
    super.key,
    required this.blockComponentContext,
    required this.blockComponentState,
    required this.editorState,
    required this.showSlashMenu,
  });

  final BlockComponentContext blockComponentContext;
  final BlockComponentActionState blockComponentState;

  final EditorState editorState;
  final VoidCallback showSlashMenu;

  @override
  Widget build(BuildContext context) {
    final direction =
        context.read<AppearanceSettingsCubit>().state.layoutDirection ==
                LayoutDirection.rtlLayout
            ? PopoverDirection.rightWithCenterAligned
            : PopoverDirection.leftWithCenterAligned;
    return BlocProvider(
      create: (_) => BlockActionOptionCubit(
        editorState: editorState,
        blockComponentBuilder: const {},
      ),
      child: Builder(
        builder: (context) => PopoverActionList<PopoverAction>(
          actions: [
            OptionActionWrapper(OptionAction.addAbove),
            OptionActionWrapper(OptionAction.addBelow),
          ],
          direction: direction,
          constraints: const BoxConstraints(minWidth: 220, maxWidth: 300),
          backgroundColor: ContextMenuSurfaceStyle.background(context),
          onPopupBuilder: () => blockComponentState.alwaysShowActions = true,
          onClosed: () => blockComponentState.alwaysShowActions = false,
          onSelected: (action, controller) async {
            if (action is! OptionActionWrapper) {
              return;
            }
            await context.read<BlockActionOptionCubit>().handleAction(
                  action.inner,
                  blockComponentContext.node,
                );
            controller.close();
            WidgetsBinding.instance
                .addPostFrameCallback((_) => showSlashMenu());
          },
          buildChild: (controller) => BlockActionButton(
            svg: FlowySvgs.add_s,
            richMessage: const TextSpan(text: 'Add block'),
            onTap: controller.show,
          ),
        ),
      ),
    );
  }
}
