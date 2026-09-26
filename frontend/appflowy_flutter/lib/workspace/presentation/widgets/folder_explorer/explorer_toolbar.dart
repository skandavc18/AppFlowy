import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_kind.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_database_menu.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_file_kind_menu.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class ExplorerToolbar extends StatelessWidget {
  const ExplorerToolbar({
    super.key,
    required this.searchController,
    required this.onNewFile,
    required this.onNewFolder,
    required this.onCreateCollection,
    required this.onCreateDatabase,
    required this.onPaste,
    required this.onRefresh,
    required this.onMore,
    required this.onSearchChanged,
    required this.canPaste,
    required this.isSearching,
    this.canWrite = true,
    this.onImportFromService,
    this.onMountService,
    this.trailing,
  });

  final TextEditingController searchController;
  final ValueChanged<WorkspaceFileMenuAction> onNewFile;
  final VoidCallback onNewFolder;
  final ValueChanged<CollectionKind> onCreateCollection;
  final ValueChanged<WorkspaceTableKind> onCreateDatabase;
  final VoidCallback? onPaste;
  final VoidCallback onRefresh;
  final VoidCallback onMore;
  final ValueChanged<String> onSearchChanged;
  final bool canPaste;
  final bool isSearching;
  final bool canWrite;
  final ValueChanged<ProviderServiceInfo>? onImportFromService;
  final ValueChanged<ProviderServiceInfo>? onMountService;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => Wrap(
        spacing: 4,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _NewFileButton(
            enabled: canWrite,
            onSelected: onNewFile,
            onCreateCollection: onCreateCollection,
            onCreateDatabase: onCreateDatabase,
            onImportFromService: onImportFromService,
            onMountService: onMountService,
          ),
          _ToolbarButton(
            icon: workspaceAddFolderIcon,
            tooltip: LocaleKeys.workspaceFolderExplorer_newFolder.tr(),
            onPressed: canWrite ? onNewFolder : null,
          ),
          if (canPaste && onPaste != null)
            _ToolbarButton(
              icon: Icons.content_paste_rounded,
              tooltip: LocaleKeys.workspaceFolderExplorer_paste.tr(),
              onPressed: canWrite ? onPaste : null,
            ),
          _ToolbarButton(
            icon: Icons.refresh_rounded,
            tooltip: LocaleKeys.workspaceFolderExplorer_refresh.tr(),
            onPressed: onRefresh,
          ),
          SizedBox(
            width: constraints.maxWidth < 560 ? constraints.maxWidth : 260,
            child: TextEntryShortcuts(
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
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                            ),
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
                      : palette.hover.withValues(alpha: palette.hover.a * 0.55),
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
      ),
    );
  }
}

class _NewFileButton extends StatelessWidget {
  const _NewFileButton({
    required this.enabled,
    required this.onSelected,
    required this.onCreateCollection,
    required this.onCreateDatabase,
    this.onImportFromService,
    this.onMountService,
  });

  final bool enabled;
  final ValueChanged<WorkspaceFileMenuAction> onSelected;
  final ValueChanged<CollectionKind> onCreateCollection;
  final ValueChanged<WorkspaceTableKind> onCreateDatabase;
  final ValueChanged<ProviderServiceInfo>? onImportFromService;
  final ValueChanged<ProviderServiceInfo>? onMountService;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (buttonContext) => _ToolbarButton(
        icon: workspaceAddFileIcon,
        tooltip: LocaleKeys.workspaceFolderExplorer_addFile.tr(),
        onPressed: !enabled
            ? null
            : () async {
                final box = buttonContext.findRenderObject() as RenderBox?;
                if (box == null) {
                  return;
                }
                final action = await showWorkspaceFileKindMenu(
                  context: buttonContext,
                  globalPosition: box.localToGlobal(Offset(0, box.size.height)),
                  onCreateCollection: onCreateCollection,
                  onCreateDatabase: onCreateDatabase,
                  onImportFromService: onImportFromService,
                  onMountService: onMountService,
                );
                if (action != null) {
                  onSelected(action);
                }
              },
      ),
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
        style: ButtonStyle(
          // The explicit hover overlay already paints the wash. Do not also
          // inherit the global IconButton background wash underneath it.
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.hovered) &&
                    !states.contains(WidgetState.focused) &&
                    !states.contains(WidgetState.pressed) &&
                    !states.contains(WidgetState.disabled)
                ? palette.hover.withValues(alpha: 0)
                : null,
          ),
        ),
        splashRadius: 16,
        constraints: const BoxConstraints.tightFor(width: 32, height: 30),
        padding: EdgeInsets.zero,
      ),
    );
  }
}
