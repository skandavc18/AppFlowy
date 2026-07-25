import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class ExplorerToolbar extends StatelessWidget {
  const ExplorerToolbar({
    super.key,
    required this.searchController,
    required this.onNewFile,
    required this.onNewFolder,
    required this.onPaste,
    required this.onRefresh,
    required this.onMore,
    required this.onSearchChanged,
    required this.canPaste,
    required this.isSearching,
    this.trailing,
  });

  final TextEditingController searchController;
  final VoidCallback onNewFile;
  final VoidCallback onNewFolder;
  final VoidCallback? onPaste;
  final VoidCallback onRefresh;
  final VoidCallback onMore;
  final ValueChanged<String> onSearchChanged;
  final bool canPaste;
  final bool isSearching;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return Row(
      children: [
        _ToolbarButton(
          icon: Icons.note_add_outlined,
          tooltip: LocaleKeys.workspaceFolderExplorer_newFile.tr(),
          onPressed: onNewFile,
        ),
        _ToolbarButton(
          icon: Icons.create_new_folder_outlined,
          tooltip: LocaleKeys.workspaceFolderExplorer_newFolder.tr(),
          onPressed: onNewFolder,
        ),
        if (canPaste && onPaste != null)
          _ToolbarButton(
            icon: Icons.content_paste_outlined,
            tooltip: LocaleKeys.workspaceFolderExplorer_paste.tr(),
            onPressed: onPaste,
          ),
        _ToolbarButton(
          icon: Icons.refresh_rounded,
          tooltip: LocaleKeys.workspaceFolderExplorer_refresh.tr(),
          onPressed: onRefresh,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: SizedBox(
              height: 30,
              child: TextField(
                controller: searchController,
                onChanged: onSearchChanged,
                style: TextStyle(fontSize: 13, color: palette.textPrimary),
                decoration: InputDecoration(
                  isDense: true,
                  hintText:
                      LocaleKeys.workspaceFolderExplorer_searchThisFolder.tr(),
                  hintStyle: TextStyle(color: palette.textMuted, fontSize: 13),
                  prefixIcon: isSearching
                      ? const Padding(
                          padding: EdgeInsets.all(8),
                          child: SizedBox.square(
                            dimension: 12,
                            child: CircularProgressIndicator(strokeWidth: 1.5),
                          ),
                        )
                      : Icon(
                          Icons.search_rounded,
                          size: 17,
                          color: palette.textSecondary,
                        ),
                  suffixIcon: searchController.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 15),
                          onPressed: () {
                            searchController.clear();
                            onSearchChanged('');
                          },
                          splashRadius: 14,
                        ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  filled: true,
                  fillColor: Theme.of(context).brightness == Brightness.dark
                      ? Color.alphaBlend(
                          palette.accent.withValues(alpha: 0.08),
                          palette.surface,
                        )
                      : palette.hover.withValues(alpha: 0.55),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: palette.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: palette.accent),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        if (trailing != null) ...[
          trailing!,
          const SizedBox(width: 4),
        ],
        _ToolbarButton(
          icon: Icons.more_horiz_rounded,
          tooltip: LocaleKeys.workspaceFolderExplorer_more.tr(),
          onPressed: onMore,
        ),
      ],
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 450),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        color: palette.textSecondary,
        disabledColor: palette.textMuted.withValues(alpha: 0.45),
        hoverColor: palette.hover,
        highlightColor: palette.selected,
        splashRadius: 16,
        constraints: const BoxConstraints.tightFor(width: 32, height: 30),
        padding: EdgeInsets.zero,
      ),
    );
  }
}
