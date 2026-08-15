import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/application/command_palette/command_palette_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/widget/flowy_tooltip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Moves the object a palette row names into the trash, without leaving the
/// palette.
///
/// It keeps its slot whether or not it is shown, so a row does not change
/// width the moment the pointer arrives.
class PaletteDeleteButton extends StatelessWidget {
  const PaletteDeleteButton({
    super.key,
    required this.view,
    required this.visible,
    this.onDeleted,
  });

  final ViewPB? view;
  final bool visible;
  final VoidCallback? onDeleted;

  /// A space, and the workspace itself, are not somebody's page to bin.
  static bool canDelete(ViewPB? view) =>
      view != null && view.parentViewId.isNotEmpty && !view.isSpace;

  @override
  Widget build(BuildContext context) {
    final view = this.view;
    if (!canDelete(view)) {
      return const SizedBox.shrink();
    }
    final theme = AppFlowyTheme.of(context);
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 140),
      child: IgnorePointer(
        ignoring: !visible,
        child: FlowyTooltip(
          message: LocaleKeys.commandPalette_moveToTrash.tr(),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _delete(context, view!),
              child: SizedBox.square(
                dimension: 24,
                child: Center(
                  child: Icon(
                    Icons.delete_outline_rounded,
                    size: 17,
                    color: theme.iconColorScheme.secondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context, ViewPB view) async {
    final paletteBloc = context.read<CommandPaletteBloc?>();
    final result = await ViewBackendService.deleteView(viewId: view.id);
    if (!context.mounted) {
      return;
    }
    result.fold(
      (_) {
        // The results are filtered against the cached views, so re-reading them
        // is what takes the row away.
        paletteBloc?.add(CommandPaletteEvent.refreshCachedViews());
        onDeleted?.call();
        showToastNotification(
          context: context,
          message: LocaleKeys.commandPalette_movedToTrash.tr(),
        );
      },
      (error) => showToastNotification(
        context: context,
        message: error.msg.isEmpty
            ? LocaleKeys.commandPalette_couldNotDelete.tr()
            : error.msg,
        type: ToastificationType.error,
      ),
    );
  }
}
