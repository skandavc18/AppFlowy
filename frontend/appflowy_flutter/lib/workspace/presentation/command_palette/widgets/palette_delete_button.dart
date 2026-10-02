import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/context_menu/app_menu_style.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/command_palette/command_palette_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/widget/flowy_tooltip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Moves the object a palette row names into the trash, without leaving the
/// palette.
///
/// It keeps its slot whether or not it is shown, so a row does not change
/// width the moment the pointer arrives.
class PaletteDeleteButton extends StatefulWidget {
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
  State<PaletteDeleteButton> createState() => _PaletteDeleteButtonState();
}

class _PaletteDeleteButtonState extends State<PaletteDeleteButton> {
  bool _hovered = false;

  @override
  void didUpdateWidget(covariant PaletteDeleteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.visible) _hovered = false;
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    if (!PaletteDeleteButton.canDelete(view)) {
      return const SizedBox.shrink();
    }
    final danger = AppMenuStyle.of(context).danger;
    final duration =
        WorkspaceTokens.motion(context, WorkspaceTokens.hoverDuration);
    return AnimatedOpacity(
      opacity: widget.visible ? 1 : 0,
      duration: duration,
      curve: WorkspaceTokens.curve,
      child: AnimatedSlide(
        offset: widget.visible ? Offset.zero : const Offset(0.25, 0),
        duration: duration,
        curve: WorkspaceTokens.curve,
        child: IgnorePointer(
          ignoring: !widget.visible,
          child: FlowyTooltip(
            message: LocaleKeys.commandPalette_moveToTrash.tr(),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _hovered = true),
              onExit: (_) => setState(() => _hovered = false),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _delete(context, view!),
                child: AnimatedContainer(
                  duration: duration,
                  curve: WorkspaceTokens.curve,
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: danger.withValues(alpha: _hovered ? 0.12 : 0),
                    borderRadius:
                        BorderRadius.circular(WorkspaceTokens.controlRadius),
                  ),
                  child: AnimatedScale(
                    scale: _hovered ? 1.08 : 1,
                    duration: duration,
                    curve: WorkspaceTokens.curve,
                    // Vivid keeps its artwork; monochrome ink turns red.
                    child: WorkspaceGlyph(
                      Icons.delete_outline_rounded,
                      size: 16,
                      color: _hovered ? danger : null,
                    ),
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
        widget.onDeleted?.call();
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
