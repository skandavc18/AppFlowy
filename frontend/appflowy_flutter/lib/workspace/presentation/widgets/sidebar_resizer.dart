import 'package:appflowy/shared/workspace_tokens.dart';
import 'package:appflowy/workspace/application/home/home_setting_bloc.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_design.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class SidebarResizer extends StatefulWidget {
  const SidebarResizer({super.key});

  @override
  State<SidebarResizer> createState() => _SidebarResizerState();
}

class _SidebarResizerState extends State<SidebarResizer> {
  final ValueNotifier<bool> isHovered = ValueNotifier(false);
  final ValueNotifier<bool> isDragging = ValueNotifier(false);

  @override
  void dispose() {
    isHovered.dispose();
    isDragging.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      onEnter: (_) => isHovered.value = true,
      onExit: (_) => isHovered.value = false,
      child: GestureDetector(
        dragStartBehavior: DragStartBehavior.down,
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (details) {
          isDragging.value = true;

          context
              .read<HomeSettingBloc>()
              .add(const HomeSettingEvent.editPanelResizeStart());
        },
        onHorizontalDragUpdate: (details) {
          isDragging.value = true;

          context
              .read<HomeSettingBloc>()
              .add(HomeSettingEvent.editPanelResized(details.localPosition.dx));
        },
        onHorizontalDragEnd: (details) {
          isDragging.value = false;

          context
              .read<HomeSettingBloc>()
              .add(const HomeSettingEvent.editPanelResizeEnd());
        },
        onHorizontalDragCancel: () {
          isDragging.value = false;

          context
              .read<HomeSettingBloc>()
              .add(const HomeSettingEvent.editPanelResizeEnd());
        },
        child: ValueListenableBuilder(
          valueListenable: isHovered,
          builder: (context, isHovered, _) {
            return ValueListenableBuilder(
              valueListenable: isDragging,
              builder: (context, isDragging, _) {
                final color = SidebarPalette.of(context).dropIndicator;
                return SizedBox(
                  width: WorkspaceTokens.space2,
                  height: MediaQuery.of(context).size.height,
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: AnimatedContainer(
                      key: const ValueKey('sidebar-resize-indicator'),
                      width: 2,
                      duration: WorkspaceTokens.motion(
                        context,
                        WorkspaceTokens.hoverDuration,
                      ),
                      color: isHovered || isDragging
                          ? color
                          : color.withValues(alpha: 0),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
