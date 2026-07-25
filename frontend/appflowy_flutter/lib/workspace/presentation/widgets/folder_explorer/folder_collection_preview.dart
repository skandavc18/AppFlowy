import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_listener.dart';
import 'package:appflowy/workspace/application/view/view_preview_mode.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_item_icon.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

const kFolderCollectionPreviewItemLimit = 6;

class FolderCollectionPreview extends StatefulWidget {
  const FolderCollectionPreview({
    super.key,
    required this.folder,
    required this.userProfile,
    required this.onOpen,
    this.repository = const WorkspaceItemService(),
    this.hoverControl,
    this.previewMode = ViewPreviewMode.cover,
  });

  final ViewPB folder;
  final UserProfilePB? userProfile;
  final VoidCallback onOpen;
  final WorkspaceItemRepository repository;
  final Widget? hoverControl;
  final ViewPreviewMode previewMode;

  @override
  State<FolderCollectionPreview> createState() =>
      _FolderCollectionPreviewState();
}

class _FolderCollectionPreviewState extends State<FolderCollectionPreview> {
  late ViewPB folder;
  late Future<List<ViewPB>> children;
  late FolderGalleryPreviewCache previewCache;
  ViewListener? listener;
  bool hovered = false;

  @override
  void initState() {
    super.initState();
    folder = widget.folder;
    previewCache = FolderGalleryPreviewCache();
    children = _loadChildren();
    _listen(folder.id);
  }

  @override
  void didUpdateWidget(covariant FolderCollectionPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.folder.id != widget.folder.id) {
      folder = widget.folder;
      listener?.stop();
      _listen(folder.id);
      _reload();
    } else if (oldWidget.folder != widget.folder) {
      folder = widget.folder;
    }
  }

  @override
  void dispose() {
    listener?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final theme = Theme.of(context);
    final isPaper = PaperTheme.isEnabled(context);
    final base = EditorSurfaceStyle.previewBackgroundFor(
      theme.brightness,
      palette.surface,
      isPaper: isPaper,
    );
    final surface = hovered
        ? Color.alphaBlend(
            palette.accent.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.035 : 0.018,
            ),
            base,
          )
        : base;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: AnimatedContainer(
        key: const ValueKey('folder-collection-preview'),
        duration: const Duration(milliseconds: 190),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, hovered ? -2 : 0, 0),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: palette.border.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.45 : 0.32,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: palette.shadow.withValues(
                alpha: hovered
                    ? theme.brightness == Brightness.dark
                        ? 0.24
                        : 0.12
                    : theme.brightness == Brightness.dark
                        ? 0.16
                        : 0.07,
              ),
              blurRadius: hovered ? 34 : 25,
              offset: Offset(0, hovered ? 14 : 10),
              spreadRadius: -12,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onOpen,
            child: FutureBuilder<List<ViewPB>>(
              future: children,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _CollectionError(error: snapshot.error!);
                }
                final views = snapshot.data;
                if (views == null) {
                  return _LoadingCollection(palette: palette);
                }
                return Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 17, 18, 19),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _CollectionHeader(
                            folder: folder,
                            itemCount: views.length,
                          ),
                          const SizedBox(height: 15),
                          _CollectionHero(
                            folder: folder,
                            children: views,
                            previewCache: previewCache,
                            userProfile: widget.userProfile,
                            previewMode: widget.previewMode,
                          ),
                          if (views.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            _KnowledgeCardGrid(
                              children: views
                                  .take(kFolderCollectionPreviewItemLimit)
                                  .toList(growable: false),
                              previewCache: previewCache,
                              userProfile: widget.userProfile,
                              previewMode: widget.previewMode,
                            ),
                          ],
                          if (views.length >
                              kFolderCollectionPreviewItemLimit) ...[
                            const SizedBox(height: 11),
                            Align(
                              alignment: Alignment.centerRight,
                              child: _MoreItemsLabel(
                                count: views.length -
                                    kFolderCollectionPreviewItemLimit,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (widget.hoverControl case final control?)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: IgnorePointer(
                          ignoring: !hovered,
                          child: AnimatedOpacity(
                            opacity: hovered ? 1 : 0,
                            duration: const Duration(milliseconds: 140),
                            child: control,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _listen(String folderId) {
    listener = ViewListener(viewId: folderId)
      ..start(
        onViewUpdated: (updated) {
          if (mounted) {
            setState(() => folder = updated);
          }
        },
        onViewChildViewsUpdated: (_) {
          if (mounted) {
            _reload();
          }
        },
      );
  }

  void _reload() {
    if (!mounted) {
      return;
    }
    previewCache.clear();
    setState(() => children = _loadChildren());
  }

  Future<List<ViewPB>> _loadChildren() async {
    final result = await widget.repository.getChildren(folder.id);
    return result.fold(
      (views) => views,
      (error) => throw StateError(error.msg),
    );
  }
}

class _CollectionHeader extends StatelessWidget {
  const _CollectionHeader({
    required this.folder,
    required this.itemCount,
  });

  final ViewPB folder;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final item = WorkspaceExplorerItem.fromView(folder);
    final modified = item.lastEdited;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final metadata = [
      LocaleKeys.workspaceFolderExplorer_itemCount.tr(
        args: ['$itemCount'],
      ),
      if (modified != null)
        LocaleKeys.workspaceFolderExplorer_modifiedAt.tr(
          args: [DateFormat.MMMd(locale).format(modified)],
        ),
    ].join('  •  ');
    return Padding(
      padding: const EdgeInsets.only(right: 34),
      child: Row(
        children: [
          _ViewIdentityIcon(view: folder, size: 24),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  folder.nameOrDefault,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontFamily: 'Inter',
                    fontSize: 16,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.25,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  metadata,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.textMuted,
                    fontFamily: 'Inter',
                    fontSize: 11,
                    height: 1.2,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CollectionHero extends StatelessWidget {
  const _CollectionHero({
    required this.folder,
    required this.children,
    required this.previewCache,
    required this.userProfile,
    required this.previewMode,
  });

  final ViewPB folder;
  final List<ViewPB> children;
  final FolderGalleryPreviewCache previewCache;
  final UserProfilePB? userProfile;
  final ViewPreviewMode previewMode;

  @override
  Widget build(BuildContext context) {
    final cover = folder.cover;
    return ClipRRect(
      borderRadius: BorderRadius.circular(17),
      child: SizedBox(
        key: const ValueKey('folder-collection-cover'),
        height: 176,
        child: previewMode == ViewPreviewMode.cover && cover != null
            ? ViewCoverImage(
                cover: cover,
                userProfile: userProfile,
                width: double.infinity,
                height: 176,
              )
            : children.isEmpty
                ? FolderGalleryCollectionArtwork(
                    item: WorkspaceExplorerItem.fromView(folder),
                  )
                : _PreviewCollage(
                    children: children.take(4).toList(growable: false),
                    previewCache: previewCache,
                    userProfile: userProfile,
                    previewMode: previewMode,
                  ),
      ),
    );
  }
}

class _PreviewCollage extends StatelessWidget {
  const _PreviewCollage({
    required this.children,
    required this.previewCache,
    required this.userProfile,
    required this.previewMode,
  });

  final List<ViewPB> children;
  final FolderGalleryPreviewCache previewCache;
  final UserProfilePB? userProfile;
  final ViewPreviewMode previewMode;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = children.length == 1 ? 1 : 2;
        final rows = children.length <= 2 ? 1 : 2;
        const gap = 3.0;
        final tileWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        final tileHeight = (constraints.maxHeight - gap * (rows - 1)) / rows;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final view in children)
              SizedBox(
                width: tileWidth,
                height: tileHeight,
                child: _PreviewTile(
                  view: view,
                  previewCache: previewCache,
                  userProfile: userProfile,
                  previewMode: previewMode,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _KnowledgeCardGrid extends StatelessWidget {
  const _KnowledgeCardGrid({
    required this.children,
    required this.previewCache,
    required this.userProfile,
    required this.previewMode,
  });

  final List<ViewPB> children;
  final FolderGalleryPreviewCache previewCache;
  final UserProfilePB? userProfile;
  final ViewPreviewMode previewMode;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 610
            ? 3
            : constraints.maxWidth >= 370
                ? 2
                : 1;
        const spacing = 11.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final view in children)
              SizedBox(
                width: width,
                child: _MiniKnowledgeCard(
                  view: view,
                  previewCache: previewCache,
                  userProfile: userProfile,
                  previewMode: previewMode,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MiniKnowledgeCard extends StatefulWidget {
  const _MiniKnowledgeCard({
    required this.view,
    required this.previewCache,
    required this.userProfile,
    required this.previewMode,
  });

  final ViewPB view;
  final FolderGalleryPreviewCache previewCache;
  final UserProfilePB? userProfile;
  final ViewPreviewMode previewMode;

  @override
  State<_MiniKnowledgeCard> createState() => _MiniKnowledgeCardState();
}

class _MiniKnowledgeCardState extends State<_MiniKnowledgeCard> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final theme = Theme.of(context);
    final isPaper = PaperTheme.isEnabled(context);
    final item = WorkspaceExplorerItem.fromView(widget.view);
    final base = EditorSurfaceStyle.previewBackgroundFor(
      theme.brightness,
      palette.floatingSurface,
      isPaper: isPaper,
    );
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, hovered ? -2 : 0, 0),
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: hovered
              ? Color.alphaBlend(
                  palette.accent.withValues(alpha: 0.035),
                  base,
                )
              : base,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: palette.border.withValues(alpha: hovered ? 0.52 : 0.30),
          ),
          boxShadow: [
            BoxShadow(
              color: palette.shadow.withValues(
                alpha: hovered ? 0.10 : 0.045,
              ),
              blurRadius: hovered ? 16 : 9,
              offset: Offset(0, hovered ? 7 : 4),
              spreadRadius: -5,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FolderGalleryPreviewThumbnail(
              item: item,
              view: widget.view,
              preview: widget.previewCache.previewFor(
                view: widget.view,
                item: item,
              ),
              userProfile: widget.userProfile,
              height: 102,
              compact: true,
              borderRadius: BorderRadius.circular(10),
              previewMode: widget.previewMode,
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                _ViewIdentityIcon(view: widget.view, size: 15),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.view.nameOrDefault,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontFamily: 'Inter',
                      fontSize: 12,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.12,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewTile extends StatelessWidget {
  const _PreviewTile({
    required this.view,
    required this.previewCache,
    required this.userProfile,
    required this.previewMode,
  });

  final ViewPB view;
  final FolderGalleryPreviewCache previewCache;
  final UserProfilePB? userProfile;
  final ViewPreviewMode previewMode;

  @override
  Widget build(BuildContext context) {
    final item = WorkspaceExplorerItem.fromView(view);
    return LayoutBuilder(
      builder: (context, constraints) => FolderGalleryPreviewThumbnail(
        item: item,
        view: view,
        preview: previewCache.previewFor(view: view, item: item),
        userProfile: userProfile,
        height: constraints.maxHeight,
        compact: true,
        borderRadius: BorderRadius.zero,
        previewMode: previewMode,
      ),
    );
  }
}

class _ViewIdentityIcon extends StatelessWidget {
  const _ViewIdentityIcon({
    required this.view,
    required this.size,
  });

  final ViewPB view;
  final double size;

  @override
  Widget build(BuildContext context) {
    final icon = view.icon.toEmojiIconData();
    return SizedBox.square(
      dimension: size,
      child: icon.isNotEmpty
          ? RawEmojiIconWidget(
              emoji: icon,
              emojiSize: size,
              lineHeight: 1,
            )
          : WorkspaceItemIcon.fromView(
              view: view,
              size: size,
              color: FolderExplorerPalette.of(context).accent,
            ),
    );
  }
}

class _MoreItemsLabel extends StatelessWidget {
  const _MoreItemsLabel({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.hover.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          '+$count ${LocaleKeys.workspaceFolderExplorer_more.tr().toLowerCase()}',
          style: TextStyle(
            color: palette.textSecondary,
            fontFamily: 'Inter',
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _LoadingCollection extends StatelessWidget {
  const _LoadingCollection({required this.palette});

  final FolderExplorerPalette palette;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 278,
      child: Center(
        child: SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(
            strokeWidth: 1.7,
            color: palette.accent,
          ),
        ),
      ),
    );
  }
}

class _CollectionError extends StatelessWidget {
  const _CollectionError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return Tooltip(
      message: error.toString(),
      child: SizedBox(
        height: 176,
        child: Center(
          child: Text(
            LocaleKeys.workspaceFolderExplorer_operationFailed.tr(),
            style: TextStyle(
              color: palette.danger,
              fontFamily: 'Inter',
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
