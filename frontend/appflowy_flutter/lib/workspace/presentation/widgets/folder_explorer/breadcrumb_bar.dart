import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:flutter/material.dart';

class BreadcrumbBar extends StatelessWidget {
  const BreadcrumbBar({
    super.key,
    required this.items,
    required this.onSelected,
  });

  final List<WorkspaceExplorerItem> items;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return SizedBox(
      height: 28,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => Icon(
          Icons.chevron_right_rounded,
          size: 15,
          color: palette.textMuted,
        ),
        itemBuilder: (context, index) {
          final item = items[index];
          final isLast = index == items.length - 1;
          return TextButton(
            onPressed: isLast ? null : () => onSelected(item.id),
            style: TextButton.styleFrom(
              foregroundColor:
                  isLast ? palette.textPrimary : palette.textSecondary,
              disabledForegroundColor: palette.textPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: TextStyle(
                fontSize: 12,
                fontWeight: isLast ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            child: Text(
              item.name.isEmpty ? 'Untitled' : item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
        },
      ),
    );
  }
}
