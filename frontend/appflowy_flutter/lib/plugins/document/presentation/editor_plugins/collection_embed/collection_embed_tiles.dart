import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_artwork.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_link.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:flutter/material.dart';

/// Anything a widget puts under the pointer: it lifts, it shades, it opens.
///
/// One recipe so a photo, a bookmark and a file all answer the pointer in
/// exactly the same way — which is what makes a page of different widgets
/// feel like one application.
class CollectionEmbedTappable extends StatefulWidget {
  const CollectionEmbedTappable({
    super.key,
    required this.builder,
    this.onTap,
    this.onSecondaryTap,
    this.onHoverChanged,
    this.lift = 2,
    this.growth = 1.0,
    this.cursor = SystemMouseCursors.click,
  });

  final Widget Function(BuildContext context, bool hovered) builder;
  final VoidCallback? onTap;
  final ValueChanged<Offset>? onSecondaryTap;
  final ValueChanged<bool>? onHoverChanged;
  final double lift;
  final double growth;
  final MouseCursor cursor;

  @override
  State<CollectionEmbedTappable> createState() =>
      _CollectionEmbedTappableState();
}

class _CollectionEmbedTappableState extends State<CollectionEmbedTappable> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    Widget child = widget.builder(context, hovered);
    if (widget.lift != 0 || widget.growth != 1) {
      child = AnimatedScale(
        scale: hovered ? widget.growth : 1,
        duration: CollectionEmbedMetrics.hover,
        curve: CollectionEmbedMetrics.ease,
        child: AnimatedContainer(
          duration: CollectionEmbedMetrics.hover,
          curve: CollectionEmbedMetrics.ease,
          transform:
              Matrix4.translationValues(0, hovered ? -widget.lift : 0, 0),
          child: child,
        ),
      );
    }
    return MouseRegion(
      cursor: widget.onTap == null ? MouseCursor.defer : widget.cursor,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onSecondaryTapDown: widget.onSecondaryTap == null
            ? null
            : (details) => widget.onSecondaryTap!(details.globalPosition),
        child: child,
      ),
    );
  }

  void _setHovered(bool value) {
    setState(() => hovered = value);
    widget.onHoverChanged?.call(value);
  }
}

/// One object as a card: artwork above, name and one fact below.
class CollectionObjectCard extends StatelessWidget {
  const CollectionObjectCard({
    super.key,
    required this.view,
    required this.theme,
    this.userProfile,
    this.onTap,
    this.onSecondaryTap,
    this.decodeWidth,
    this.showCaption = true,
    this.aspectRatio,
    this.radius = CollectionEmbedMetrics.tileRadius,
  });

  final ViewPB view;
  final CollectionEmbedTheme theme;
  final UserProfilePB? userProfile;
  final VoidCallback? onTap;
  final ValueChanged<Offset>? onSecondaryTap;
  final double? decodeWidth;
  final bool showCaption;
  final double? aspectRatio;
  final double radius;

  @override
  Widget build(BuildContext context) => CollectionEmbedTappable(
        onTap: onTap,
        onSecondaryTap: onSecondaryTap,
        growth: 1.012,
        builder: (context, hovered) {
          Widget artwork = ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CollectionArtwork(
                  view: view,
                  theme: theme,
                  userProfile: userProfile,
                  decodeWidth: decodeWidth,
                ),
                AnimatedOpacity(
                  opacity: hovered ? 1 : 0,
                  duration: CollectionEmbedMetrics.hover,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0),
                          Colors.black.withValues(alpha: 0.16),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
          if (aspectRatio != null) {
            artwork = AspectRatio(aspectRatio: aspectRatio!, child: artwork);
          } else {
            artwork = Expanded(child: artwork);
          }
          if (!showCaption) {
            return artwork;
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              artwork,
              const SizedBox(height: 7),
              Text(
                view.name.isEmpty ? _untitled : view.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.face(
                  context,
                  size: 12,
                  color: hovered ? theme.textPrimary : theme.textBody,
                  weightAxis: 580,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                collectionObjectSubtitle(view),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.caption(context, size: 10.5),
              ),
            ],
          );
        },
      );
}

/// One object as a row: glyph, name, one fact, right aligned detail.
class CollectionObjectRow extends StatelessWidget {
  const CollectionObjectRow({
    super.key,
    required this.view,
    required this.theme,
    this.onTap,
    this.onSecondaryTap,
    this.onHoverChanged,
    this.trailing,
    this.height = 34,
    this.leading,
    this.subtitle,
    this.selected = false,
  });

  final ViewPB view;
  final CollectionEmbedTheme theme;
  final VoidCallback? onTap;
  final ValueChanged<Offset>? onSecondaryTap;
  final ValueChanged<bool>? onHoverChanged;
  final Widget? trailing;
  final double height;
  final Widget? leading;
  final String? subtitle;
  final bool selected;

  @override
  Widget build(BuildContext context) => CollectionEmbedTappable(
        onTap: onTap,
        onSecondaryTap: onSecondaryTap,
        onHoverChanged: onHoverChanged,
        lift: 0,
        builder: (context, hovered) => AnimatedContainer(
          duration: CollectionEmbedMetrics.hover,
          curve: CollectionEmbedMetrics.ease,
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            // Fading from a real colour at alpha 0 keeps the tween in one
            // hue; Colors.transparent would pass through grey.
            color: hovered || selected
                ? theme.rowHover
                : theme.rowHover.withValues(alpha: 0),
            borderRadius:
                BorderRadius.circular(CollectionEmbedMetrics.controlRadius),
          ),
          child: Row(
            children: [
              leading ??
                  Icon(
                    collectionObjectGlyph(view),
                    size: 16,
                    color: collectionObjectHue(view.id, dark: theme.isDark),
                  ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      view.name.isEmpty ? _untitled : view.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.face(
                        context,
                        size: 12.5,
                        color: hovered ? theme.textPrimary : theme.textBody,
                        weightAxis: 560,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.caption(context, size: 10.5),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
        ),
      );
}

const String _untitled = 'Untitled';

IconData collectionObjectGlyph(ViewPB view) {
  final collection = view.collection;
  if (collection != null) {
    return CollectionRegistry.typeFor(collection.kind).icon;
  }
  if (view.bookmark != null) {
    return Icons.link_rounded;
  }
  if (view.isWorkspaceFolder) {
    return Icons.folder_rounded;
  }
  if (view.isWorkspaceFile) {
    return fileIconForName(view.name);
  }
  if (view.isDatabase) {
    return Icons.table_chart_rounded;
  }
  return Icons.description_rounded;
}

/// One short fact about an object — its type, not a file path.
String collectionObjectSubtitle(ViewPB view) {
  final collection = view.collection;
  if (collection != null) {
    return CollectionRegistry.typeFor(collection.kind).label;
  }
  final bookmark = view.bookmark;
  if (bookmark != null) {
    return bookmarkHost(bookmark.url) ?? bookmark.url;
  }
  if (view.isWorkspaceFolder) {
    return 'Folder';
  }
  if (view.isWorkspaceFile) {
    final extension = view.name.contains('.')
        ? view.name.split('.').last.toUpperCase()
        : '';
    return extension;
  }
  if (view.isDatabase) {
    return view.layout.name;
  }
  return 'Page';
}
