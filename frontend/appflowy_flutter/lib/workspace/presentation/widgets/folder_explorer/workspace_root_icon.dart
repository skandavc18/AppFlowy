import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:flutter/material.dart';

class WorkspaceRootIcon extends StatelessWidget {
  const WorkspaceRootIcon({
    super.key,
    this.size = 22,
    this.color,
  });

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final iconColor = color ?? palette.accent;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(size * 0.29),
      ),
      child: SizedBox.square(
        dimension: size,
        child: Icon(
          Icons.home_work_rounded,
          key: const ValueKey('workspace-root-icon'),
          size: size * 0.64,
          color: iconColor,
        ),
      ),
    );
  }
}
