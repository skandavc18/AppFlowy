import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/table_views/gallery_spec.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_preview_mode.dart';
import 'package:appflowy/workspace/application/view_gallery/view_gallery_source.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/gallery_card_surface.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef ViewGalleryMenu = Future<void> Function(Offset globalPosition);

/// A page's own icon, or the glyph of its kind when it has none.
class ViewGalleryIcon extends StatelessWidget {
  const ViewGalleryIcon({super.key, required this.view, this.size = 16});

  final ViewPB view;
  final double size;

  @override
  Widget build(BuildContext context) {
    final icon = view.icon;
    return SizedBox.square(
      dimension: size + 4,
      child: Center(
        child: icon.value.isNotEmpty
            ? RawEmojiIconWidget(
                emoji: icon.toEmojiIconData(),
                emojiSize: size,
                lineHeight: 1.2,
              )
            : view.defaultIcon(size: Size.square(size)),
      ),
    );
  }
}

/// The ⋯ button every card and row shares. Keyboard users reach it with Tab.
class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.onPressed, this.compact = false});

  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final label = LocaleKeys.workspaceFolderExplorer_more.tr();
    final palette = WorkspacePalette.of(context);
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: IconButton(
        key: const ValueKey('view-gallery-more'),
        style: WorkspaceChrome.controlStyle(context).copyWith(
          minimumSize: WidgetStatePropertyAll(Size.square(compact ? 28 : 32)),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          backgroundColor: WidgetStatePropertyAll(
            compact ? Colors.transparent : palette.elevatedSurface,
          ),
        ),
        onPressed: onPressed,
        icon: Semantics(
          label: label,
          child: const Icon(Icons.more_horiz_rounded, size: 18),
        ),
      ),
    );
  }
}

/// Shared focus/keyboard/hover behavior of a card or a row.
mixin _ViewGalleryItemState<T extends StatefulWidget> on State<T> {
  final focusNode = FocusNode(debugLabel: 'View gallery item');
  final menuAnchor = GlobalKey();
  bool focused = false;
  bool hovered = false;

  VoidCallback? get onOpen;
  ViewGalleryMenu? get onMenu;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_syncFocus);
  }

  void _syncFocus() {
    final next = focusNode.hasFocus;
    if (mounted && next != focused) setState(() => focused = next);
  }

  void setHovered(bool value) {
    if (hovered != value) setState(() => hovered = value);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_syncFocus);
    focusNode.dispose();
    super.dispose();
  }

  void openMenuFromButton() {
    final anchor = menuAnchor.currentContext;
    final box = anchor?.findRenderObject() as RenderBox?;
    if (anchor == null || box == null || !box.hasSize) return;
    unawaited(
      showMenuAt(
        anchor,
        box.localToGlobal(Offset(box.size.width, box.size.height + 4)),
      ),
    );
  }

  Future<void> showMenuAt(BuildContext anchor, Offset position) async {
    final show = onMenu;
    if (show == null) return;
    final release = PreviewToolbarRegion.hold(anchor);
    try {
      await show(position);
    } finally {
      release();
    }
  }

  KeyEventResult handleKey(FocusNode node, KeyEvent event) {
    if (!node.hasPrimaryFocus || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if ((key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter ||
            key == LogicalKeyboardKey.space) &&
        onOpen != null) {
      onOpen!();
      return KeyEventResult.handled;
    }
    if (onMenu != null &&
        (key == LogicalKeyboardKey.contextMenu ||
            (key == LogicalKeyboardKey.f10 &&
                HardwareKeyboard.instance.isShiftPressed))) {
      final box = context.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        unawaited(
          showMenuAt(context, box.localToGlobal(box.size.center(Offset.zero))),
        );
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// The pointer, keyboard, hover and focus shell a tile or a details row
  /// wears around its own layout.
  Widget itemShell({
    required String label,
    required Key contentKey,
    required EdgeInsetsGeometry padding,
    required Widget child,
    String? value,
    double minHeight = 0,
  }) {
    final palette = WorkspacePalette.of(context);
    return Focus(
      focusNode: focusNode,
      canRequestFocus: onOpen != null,
      onKeyEvent: handleKey,
      child: PreviewToolbarRegion(
        child: MouseRegion(
          cursor: onOpen == null ? MouseCursor.defer : SystemMouseCursors.click,
          onEnter: (_) => setHovered(true),
          onHover: (_) => setHovered(true),
          onExit: (_) => setHovered(false),
          child: Semantics(
            button: onOpen != null,
            label: label,
            value: value == null || value.isEmpty ? null : value,
            child: GestureDetector(
              key: contentKey,
              behavior: HitTestBehavior.opaque,
              onTap: onOpen,
              onSecondaryTapUp: onMenu == null
                  ? null
                  : (details) =>
                      unawaited(showMenuAt(context, details.globalPosition)),
              child: AnimatedContainer(
                duration: WorkspaceTokens.motion(
                  context,
                  WorkspaceTokens.hoverDuration,
                ),
                curve: WorkspaceTokens.curve,
                constraints: BoxConstraints(minHeight: minHeight),
                padding: padding,
                decoration: BoxDecoration(
                  color: hovered || focused
                      ? palette.hover
                      : palette.hover.withValues(alpha: 0),
                  borderRadius:
                      BorderRadius.circular(WorkspaceTokens.controlRadius),
                  border: Border.all(
                    color: focused ? palette.focus : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget menuButton({bool compact = true}) => onMenu == null
      ? const SizedBox.shrink()
      : PreviewToolbar(
          keepVisible: focused,
          child: KeyedSubtree(
            key: menuAnchor,
            child: _MoreButton(onPressed: openMenuFromButton, compact: compact),
          ),
        );
}

/// One page on a library wall. Every face shares the same interaction shell;
/// only the artwork changes, never the gesture/focus owner.
class ViewGalleryCard extends StatefulWidget {
  const ViewGalleryCard({
    super.key,
    required this.entry,
    required this.face,
    required this.loadPreview,
    required this.caption,
    this.details = '',
    this.userProfile,
    this.coverHeight = 120,
    this.showPlaceholder = true,
    this.onOpen,
    this.onMenu,
  });

  final ViewGalleryEntry entry;
  final GalleryCardFace face;

  /// Asked only by faces that draw the page itself; covers never read pages.
  final Future<FolderGalleryPreview> Function() loadPreview;
  final String caption;
  final String details;
  final UserProfilePB? userProfile;
  final double coverHeight;
  final bool showPlaceholder;
  final VoidCallback? onOpen;
  final ViewGalleryMenu? onMenu;

  @override
  State<ViewGalleryCard> createState() => _ViewGalleryCardState();
}

class _ViewGalleryCardState extends State<ViewGalleryCard>
    with _ViewGalleryItemState<ViewGalleryCard> {
  @override
  VoidCallback? get onOpen => widget.onOpen;
  @override
  ViewGalleryMenu? get onMenu => widget.onMenu;

  bool get _hasCover {
    final cover = widget.entry.view.cover;
    return cover != null && !cover.isNone;
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.entry.view;
    final content = Semantics(
      button: widget.onOpen != null,
      label: view.nameOrDefault,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            key: const ValueKey('view-gallery-card-content'),
            behavior: HitTestBehavior.opaque,
            onTap: widget.onOpen,
            onSecondaryTapUp: widget.onMenu == null
                ? null
                : (details) =>
                    unawaited(showMenuAt(context, details.globalPosition)),
            child: ExcludeSemantics(child: _buildFace(context)),
          ),
          if (widget.onMenu != null)
            PositionedDirectional(
              top: WorkspaceTokens.space2,
              end: WorkspaceTokens.space2,
              child: PreviewToolbar(
                keepVisible: focused,
                child: KeyedSubtree(
                  key: menuAnchor,
                  child: _MoreButton(onPressed: openMenuFromButton),
                ),
              ),
            ),
        ],
      ),
    );
    return Focus(
      focusNode: focusNode,
      canRequestFocus: widget.onOpen != null,
      onKeyEvent: handleKey,
      child: PreviewToolbarRegion(
        child: MouseRegion(
          cursor: widget.onOpen == null
              ? MouseCursor.defer
              : SystemMouseCursors.click,
          onEnter: (_) => setHovered(true),
          onHover: (_) => setHovered(true),
          onExit: (_) => setHovered(false),
          child: GalleryCardSurface(
            focused: focused,
            hovered: hovered,
            child: content,
          ),
        ),
      ),
    );
  }

  Widget _buildFace(BuildContext context) => switch (widget.face) {
        GalleryCardFace.page => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The page's own choice: its cover when it has one, else its text.
              Expanded(child: _pagePreview(double.infinity, mode: null)),
              GalleryCardFooter(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
                child: _caption(context),
              ),
            ],
          ),
        GalleryCardFace.portrait => _portrait(context),
        GalleryCardFace.none => _body(context, titleLines: 3, showIcon: true),
        GalleryCardFace.content || GalleryCardFace.cover => LayoutBuilder(
            builder: (context, constraints) {
              final room = math.max(0.0, constraints.maxHeight - 76);
              final height = math.min(widget.coverHeight, room);
              final band = widget.face == GalleryCardFace.content
                  ? _pagePreview(height)
                  : _coverBand(height);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (band != null) SizedBox(height: height, child: band),
                  Expanded(child: _body(context, titleLines: 2)),
                ],
              );
            },
          ),
      };

  Widget _pagePreview(
    double height, {
    ViewPreviewMode? mode = ViewPreviewMode.content,
  }) {
    final view = widget.entry.view;
    return FolderGalleryPreviewThumbnail(
      item: WorkspaceExplorerItem.fromView(view),
      view: view,
      preview: widget.loadPreview(),
      userProfile: widget.userProfile,
      height: height,
      borderRadius: BorderRadius.zero,
      compact: true,
      lightweight: true,
      previewMode: mode,
    );
  }

  Widget? _coverBand(double height) {
    final cover = widget.entry.view.cover;
    if (_hasCover) {
      return IgnorePointer(
        child: ViewCoverImage(
          cover: cover!,
          userProfile: widget.userProfile,
          width: double.infinity,
          height: height,
        ),
      );
    }
    if (!widget.showPlaceholder) return null;
    // A quiet band keeps the wall even; it never pretends to be a picture.
    final palette = WorkspacePalette.of(context);
    return ColoredBox(
      key: const ValueKey('view-gallery-cover-placeholder'),
      color: Color.alphaBlend(
        palette.accent.withValues(alpha: palette.isDark ? 0.14 : 0.08),
        GalleryCardPalette.previewSurface(context),
      ),
      child: Center(
        child: Opacity(
          opacity: 0.7,
          child: ViewGalleryIcon(view: widget.entry.view, size: 22),
        ),
      ),
    );
  }

  Widget _portrait(BuildContext context) {
    if (!_hasCover) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _pagePreview(double.infinity)),
          GalleryCardFooter(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
            child: _caption(context),
          ),
        ],
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: ViewCoverImage(
            cover: widget.entry.view.cover!,
            userProfile: widget.userProfile,
            width: double.infinity,
            height: double.infinity,
          ),
        ),
        PositionedDirectional(
          start: 0,
          end: 0,
          bottom: 0,
          child: DecoratedBox(
            // A real photograph needs contrast behind its title in any theme.
            decoration: const BoxDecoration(color: Color(0xB3000000)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 11),
              child: _caption(context, onImage: true),
            ),
          ),
        ),
      ],
    );
  }

  Widget _body(
    BuildContext context, {
    required int titleLines,
    bool showIcon = false,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          primary: false,
          physics: const NeverScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showIcon) ...[
                      ViewGalleryIcon(view: widget.entry.view, size: 22),
                      const SizedBox(height: WorkspaceTokens.space2),
                    ],
                    _title(context, maxLines: titleLines, icon: !showIcon),
                    if (widget.details.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.details,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WorkspaceTypography.style(
                          context,
                          WorkspaceTextRole.metadata,
                        ),
                      ),
                    ],
                  ],
                ),
                if (widget.caption.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: WorkspaceTokens.space2),
                    child: Text(
                      widget.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WorkspaceTypography.style(
                        context,
                        WorkspaceTextRole.caption,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _caption(BuildContext context, {bool onImage = false}) {
    final line = widget.caption.isNotEmpty ? widget.caption : widget.details;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _title(
          context,
          maxLines: 1,
          icon: true,
          color: onImage ? Colors.white : null,
        ),
        if (line.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              line,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: WorkspaceTypography.style(
                context,
                WorkspaceTextRole.caption,
                color: onImage ? const Color(0xD9FFFFFF) : null,
              ),
            ),
          ),
      ],
    );
  }

  Widget _title(
    BuildContext context, {
    required int maxLines,
    required bool icon,
    Color? color,
  }) {
    final view = widget.entry.view;
    final name = view.nameOrDefault;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 6),
            child: ViewGalleryIcon(view: view, size: 14),
          ),
        Expanded(
          child: Tooltip(
            message: name,
            excludeFromSemantics: true,
            child: Text(
              name,
              key: const ValueKey('view-gallery-title'),
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: WorkspaceTypography.style(
                context,
                WorkspaceTextRole.cardTitle,
                color: color,
              ).copyWith(fontSize: 14),
            ),
          ),
        ),
        if (widget.entry.pinned)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, top: 2),
            child: Tooltip(
              message: LocaleKeys.viewLibrary_column_pinned.tr(),
              child: WorkspaceGlyph(
                Icons.push_pin_rounded,
                size: 13,
                color: color ?? WorkspacePalette.of(context).mutedText,
              ),
            ),
          ),
      ],
    );
  }
}

/// One page as a compact row, for readers who scan names rather than faces.
class ViewGalleryListRow extends StatefulWidget {
  const ViewGalleryListRow({
    super.key,
    required this.entry,
    required this.caption,
    this.details = '',
    this.onOpen,
    this.onMenu,
  });

  final ViewGalleryEntry entry;
  final String caption;
  final String details;
  final VoidCallback? onOpen;
  final ViewGalleryMenu? onMenu;

  @override
  State<ViewGalleryListRow> createState() => _ViewGalleryListRowState();
}

class _ViewGalleryListRowState extends State<ViewGalleryListRow>
    with _ViewGalleryItemState<ViewGalleryListRow> {
  @override
  VoidCallback? get onOpen => widget.onOpen;
  @override
  ViewGalleryMenu? get onMenu => widget.onMenu;

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    final view = widget.entry.view;
    final radius = BorderRadius.circular(WorkspaceTokens.controlRadius);
    return Focus(
      focusNode: focusNode,
      canRequestFocus: widget.onOpen != null,
      onKeyEvent: handleKey,
      child: PreviewToolbarRegion(
        child: MouseRegion(
          cursor: widget.onOpen == null
              ? MouseCursor.defer
              : SystemMouseCursors.click,
          onEnter: (_) => setHovered(true),
          onHover: (_) => setHovered(true),
          onExit: (_) => setHovered(false),
          child: Semantics(
            button: widget.onOpen != null,
            label: view.nameOrDefault,
            child: GestureDetector(
              key: const ValueKey('view-gallery-row-content'),
              behavior: HitTestBehavior.opaque,
              onTap: widget.onOpen,
              onSecondaryTapUp: widget.onMenu == null
                  ? null
                  : (details) =>
                      unawaited(showMenuAt(context, details.globalPosition)),
              child: AnimatedContainer(
                duration: WorkspaceTokens.motion(
                  context,
                  WorkspaceTokens.hoverDuration,
                ),
                curve: WorkspaceTokens.curve,
                constraints: const BoxConstraints(minHeight: 44),
                padding: const EdgeInsetsDirectional.fromSTEB(10, 6, 6, 6),
                decoration: BoxDecoration(
                  color: hovered || focused
                      ? palette.hover
                      : palette.hover.withValues(alpha: 0),
                  borderRadius: radius,
                  border: Border.all(
                    color: focused ? palette.focus : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 560;
                    return Row(
                      children: [
                        ExcludeSemantics(
                          child: ViewGalleryIcon(view: view),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 5,
                          child: ExcludeSemantics(
                            child: Text(
                              view.nameOrDefault,
                              key: const ValueKey('view-gallery-title'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: WorkspaceTypography.style(
                                context,
                                WorkspaceTextRole.body,
                              ).copyWith(fontWeight: FontWeight.w500),
                            ),
                          ),
                        ),
                        if (widget.entry.pinned)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(start: 6),
                            child: WorkspaceGlyph(
                              Icons.push_pin_rounded,
                              size: 13,
                              color: palette.mutedText,
                            ),
                          ),
                        if (wide && widget.details.isNotEmpty) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 3,
                            child: Text(
                              widget.details,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: WorkspaceTypography.style(
                                context,
                                WorkspaceTextRole.metadata,
                              ),
                            ),
                          ),
                        ],
                        if (widget.caption.isNotEmpty) ...[
                          const SizedBox(width: 12),
                          Flexible(
                            flex: 2,
                            child: Text(
                              widget.caption,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: WorkspaceTypography.style(
                                context,
                                WorkspaceTextRole.caption,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 4),
                        if (widget.onMenu != null)
                          PreviewToolbar(
                            keepVisible: focused,
                            child: KeyedSubtree(
                              key: menuAnchor,
                              child: _MoreButton(
                                onPressed: openMenuFromButton,
                                compact: true,
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
        ),
      ),
    );
  }
}

/// One page on a contact sheet: a square picture of it and its name, as a
/// folder's Thumbnails view shows its files.
class ViewGalleryThumbnail extends StatefulWidget {
  const ViewGalleryThumbnail({
    super.key,
    required this.entry,
    required this.loadPreview,
    this.userProfile,
    this.onOpen,
    this.onMenu,
  });

  final ViewGalleryEntry entry;
  final Future<FolderGalleryPreview> Function() loadPreview;
  final UserProfilePB? userProfile;
  final VoidCallback? onOpen;
  final ViewGalleryMenu? onMenu;

  @override
  State<ViewGalleryThumbnail> createState() => _ViewGalleryThumbnailState();
}

class _ViewGalleryThumbnailState extends State<ViewGalleryThumbnail>
    with _ViewGalleryItemState<ViewGalleryThumbnail> {
  @override
  VoidCallback? get onOpen => widget.onOpen;
  @override
  ViewGalleryMenu? get onMenu => widget.onMenu;

  @override
  Widget build(BuildContext context) {
    final view = widget.entry.view;
    final name = view.nameOrDefault;
    return Focus(
      focusNode: focusNode,
      canRequestFocus: widget.onOpen != null,
      onKeyEvent: handleKey,
      child: PreviewToolbarRegion(
        child: MouseRegion(
          cursor: widget.onOpen == null
              ? MouseCursor.defer
              : SystemMouseCursors.click,
          onEnter: (_) => setHovered(true),
          onHover: (_) => setHovered(true),
          onExit: (_) => setHovered(false),
          child: Semantics(
            button: widget.onOpen != null,
            label: name,
            child: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  key: const ValueKey('view-gallery-thumbnail-content'),
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onOpen,
                  onSecondaryTapUp: widget.onMenu == null
                      ? null
                      : (details) => unawaited(
                            showMenuAt(context, details.globalPosition),
                          ),
                  child: ExcludeSemantics(
                    child: FolderThumbnailTile(
                      focused: focused,
                      hovered: hovered,
                      preview: FolderGalleryPreviewThumbnail(
                        item: WorkspaceExplorerItem.fromView(view),
                        view: view,
                        preview: widget.loadPreview(),
                        userProfile: widget.userProfile,
                        height: double.infinity,
                        compact: true,
                        lightweight: true,
                        borderRadius: BorderRadius.zero,
                      ),
                      name: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: ViewGalleryIcon(view: view, size: 14),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Tooltip(
                              message: name,
                              excludeFromSemantics: true,
                              child: Text(
                                name,
                                key: const ValueKey('view-gallery-title'),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: WorkspaceTypography.style(
                                  context,
                                  WorkspaceTextRole.body,
                                ).copyWith(fontSize: 13, height: 1.4),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (widget.onMenu != null)
                  PositionedDirectional(
                    top: WorkspaceTokens.space2,
                    end: WorkspaceTokens.space2,
                    child: menuButton(compact: false),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One page as an Explorer-style tile: its glyph, its name and two quiet
/// lines saying what it is, where it lives and when it was last touched.
class ViewGalleryTile extends StatefulWidget {
  const ViewGalleryTile({
    super.key,
    required this.entry,
    required this.caption,
    this.details = '',
    this.onOpen,
    this.onMenu,
  });

  final ViewGalleryEntry entry;
  final String caption;
  final String details;
  final VoidCallback? onOpen;
  final ViewGalleryMenu? onMenu;

  @override
  State<ViewGalleryTile> createState() => _ViewGalleryTileState();
}

class _ViewGalleryTileState extends State<ViewGalleryTile>
    with _ViewGalleryItemState<ViewGalleryTile> {
  @override
  VoidCallback? get onOpen => widget.onOpen;
  @override
  ViewGalleryMenu? get onMenu => widget.onMenu;

  @override
  Widget build(BuildContext context) {
    final view = widget.entry.view;
    final name = view.nameOrDefault;
    final lines = [widget.details, widget.caption]
        .where((line) => line.trim().isNotEmpty)
        .toList();
    final lineStyle = WorkspaceTypography.style(
      context,
      WorkspaceTextRole.metadata,
    ).copyWith(fontSize: 11, height: 1.4);
    return itemShell(
      label: name,
      value: lines.join('; '),
      contentKey: const ValueKey('view-gallery-tile-content'),
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 6, 8),
      child: Row(
        children: [
          ExcludeSemantics(child: ViewGalleryIcon(view: view, size: 30)),
          const SizedBox(width: 12),
          Expanded(
            child: ExcludeSemantics(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Tooltip(
                          message: name,
                          excludeFromSemantics: true,
                          child: Text(
                            name,
                            key: const ValueKey('view-gallery-title'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: WorkspaceTypography.style(
                              context,
                              WorkspaceTextRole.body,
                            ).copyWith(
                              fontSize: 13,
                              height: 1.4,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      if (widget.entry.pinned) const _PinnedMark(),
                    ],
                  ),
                  for (final line in lines) ...[
                    const SizedBox(height: 2),
                    Text(
                      line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: lineStyle,
                    ),
                  ],
                ],
              ),
            ),
          ),
          menuButton(),
        ],
      ),
    );
  }
}

/// The inset every details row and its heading share, so columns line up.
const viewGalleryDetailsPadding = EdgeInsetsDirectional.fromSTEB(10, 6, 6, 6);

/// Room kept at the end of a details row for its ⋯ button.
const _detailsMenuRoom = 32.0;

/// One column of a library's details table.
@immutable
class ViewGalleryDetailsColumn {
  const ViewGalleryDetailsColumn({
    required this.id,
    required this.label,
    required this.width,
  });

  final String id;
  final String label;
  final double width;
}

/// The names of a details table's columns. Pressing one orders by it.
class ViewGalleryDetailsHeading extends StatelessWidget {
  const ViewGalleryDetailsHeading({
    super.key,
    required this.nameId,
    required this.nameLabel,
    required this.columns,
    required this.sortColumn,
    required this.descending,
    required this.onSort,
  });

  final String nameId;
  final String nameLabel;
  final List<ViewGalleryDetailsColumn> columns;
  final String sortColumn;
  final bool descending;
  final ValueChanged<String> onSort;

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    Widget label(String id, String text, double start) {
      final sorted = sortColumn == id;
      return TextButton(
        key: ValueKey('view-library-sort-$id'),
        onPressed: () => onSort(id),
        style: WorkspaceChrome.controlStyle(context).copyWith(
          alignment: AlignmentDirectional.centerStart,
          minimumSize: const WidgetStatePropertyAll(Size(0, 28)),
          padding: WidgetStatePropertyAll(
            EdgeInsetsDirectional.fromSTEB(start, 0, 4, 0),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WorkspaceTypography.style(
                  context,
                  WorkspaceTextRole.metadata,
                  color: sorted ? palette.primaryText : null,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (sorted) ...[
              const SizedBox(width: 4),
              WorkspaceGlyph(
                descending
                    ? Icons.arrow_downward_rounded
                    : Icons.arrow_upward_rounded,
                size: 12,
                color: palette.primaryText,
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      key: const ValueKey('view-library-details-heading'),
      height: 34,
      padding: EdgeInsetsDirectional.only(
        start: viewGalleryDetailsPadding.start,
        end: viewGalleryDetailsPadding.end,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          // The row's icon and its gap, less the label's own inset.
          const SizedBox(width: 22),
          Expanded(child: label(nameId, nameLabel, 8)),
          for (final column in columns)
            SizedBox(
              width: column.width,
              child: label(column.id, column.label, 12),
            ),
          const SizedBox(width: _detailsMenuRoom),
        ],
      ),
    );
  }
}

/// One page as a row of a details table.
class ViewGalleryDetailsRow extends StatefulWidget {
  const ViewGalleryDetailsRow({
    super.key,
    required this.entry,
    required this.cells,
    this.onOpen,
    this.onMenu,
  });

  final ViewGalleryEntry entry;

  /// The text of each column after the name, in the heading's order.
  final List<(String, double)> cells;
  final VoidCallback? onOpen;
  final ViewGalleryMenu? onMenu;

  @override
  State<ViewGalleryDetailsRow> createState() => _ViewGalleryDetailsRowState();
}

class _ViewGalleryDetailsRowState extends State<ViewGalleryDetailsRow>
    with _ViewGalleryItemState<ViewGalleryDetailsRow> {
  @override
  VoidCallback? get onOpen => widget.onOpen;
  @override
  ViewGalleryMenu? get onMenu => widget.onMenu;

  @override
  Widget build(BuildContext context) {
    final view = widget.entry.view;
    final name = view.nameOrDefault;
    final cellStyle = WorkspaceTypography.style(
      context,
      WorkspaceTextRole.metadata,
    );
    return itemShell(
      label: name,
      value: [for (final (text, _) in widget.cells) text].join('; '),
      contentKey: const ValueKey('view-gallery-details-content'),
      padding: viewGalleryDetailsPadding,
      minHeight: 40,
      child: Row(
        children: [
          ExcludeSemantics(child: ViewGalleryIcon(view: view)),
          const SizedBox(width: 10),
          Expanded(
            child: ExcludeSemantics(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      name,
                      key: const ValueKey('view-gallery-title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WorkspaceTypography.style(
                        context,
                        WorkspaceTextRole.body,
                      ).copyWith(fontWeight: FontWeight.w500),
                    ),
                  ),
                  if (widget.entry.pinned) const _PinnedMark(),
                ],
              ),
            ),
          ),
          for (final (text, width) in widget.cells)
            SizedBox(
              width: width,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: 12),
                child: ExcludeSemantics(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: cellStyle,
                  ),
                ),
              ),
            ),
          SizedBox(
            width: _detailsMenuRoom,
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: menuButton(),
            ),
          ),
        ],
      ),
    );
  }
}

class _PinnedMark extends StatelessWidget {
  const _PinnedMark();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.only(start: 6),
        child: Tooltip(
          message: LocaleKeys.viewLibrary_column_pinned.tr(),
          child: WorkspaceGlyph(
            Icons.push_pin_rounded,
            size: 13,
            color: WorkspacePalette.of(context).mutedText,
          ),
        ),
      );
}
