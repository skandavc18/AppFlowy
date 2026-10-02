import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/extensions/dart/extension_boundary.dart';
import 'package:appflowy/extensions/dart/web_embed_registry.dart';
import 'package:appflowy/extensions/presentation/web_embed_frame.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/visual_block/visual_block_fullscreen.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/visual_block/visual_block_style.dart';
import 'package:appflowy/shared/appflowy_network_image.dart';
import 'package:flutter/material.dart';

/// The kinds of link that play rather than read.
const _playableKinds = {
  'Video',
  'Short',
  'Reel',
  'Track',
  'Song',
  'Episode',
  'Music video',
  'Spotlight',
  'Talk',
  'Clip',
};

/// [color] shifted until it reads as text on the workspace's own background:
/// a site's yellow or pink is a fine fill but a poor letter.
Color webEmbedReadableColor(Color color, Brightness brightness) =>
    brightness == Brightness.dark
        ? Color.lerp(color, Colors.white, 0.3)!
        : Color.lerp(color, Colors.black, 0.18)!;

/// The site's icon on a tint of its colour.
class WebEmbedMark extends StatelessWidget {
  const WebEmbedMark({
    super.key,
    required this.link,
    this.size = 32,
    this.brightness,
  });

  final WebEmbedLink link;
  final double size;

  /// The surface it sits on, where that is not the app's own: a dark canvas
  /// in a light workspace.
  final Brightness? brightness;

  @override
  Widget build(BuildContext context) {
    final brightness = this.brightness ?? Theme.of(context).brightness;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: link.color
            .withValues(alpha: brightness == Brightness.dark ? 0.24 : 0.13),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(
        link.icon,
        size: size * 0.56,
        color: webEmbedReadableColor(link.color, brightness),
      ),
    );
  }
}

/// What a link is, as a small chip: `Reddit · Comment`, `Google Sheets`.
class WebEmbedBadge extends StatelessWidget {
  const WebEmbedBadge({
    super.key,
    required this.link,
    this.dense = false,
    this.overImage = false,
  });

  final WebEmbedLink link;

  /// Only the site's name, for a narrow card.
  final bool dense;

  /// White on dark glass, for a badge laid over a picture.
  final bool overImage;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final foreground = overImage
        ? Colors.white
        : webEmbedReadableColor(link.color, brightness);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : 8,
        vertical: dense ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: overImage
            ? Colors.black.withValues(alpha: 0.55)
            : link.color
                .withValues(alpha: brightness == Brightness.dark ? 0.22 : 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(link.icon, size: dense ? 11 : 13, color: foreground),
          SizedBox(width: dense ? 3 : 4),
          Flexible(
            child: Text(
              dense ? link.site : link.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: dense ? 10 : 11,
                height: 1.2,
                fontWeight: FontWeight.w600,
                color: foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown while a recognised link's page is on its way: the site's own mark,
/// so a page of embeds reads as Pinterest, Reddit and Docs before any loads.
class WebEmbedLoadingPlaceholder extends StatelessWidget {
  const WebEmbedLoadingPlaceholder({super.key, required this.link});

  final WebEmbedLink link;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  WebEmbedMark(link: link, size: 40),
                  const SizedBox(height: 10),
                  Text(
                    link.title ?? link.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.6,
                      color: link.color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A recognised link drawn live by its site.
///
/// A short link is followed first. Whatever the site's code does wrong stays
/// inside this box, named after the extension that registered the site.
class WebEmbedSurface extends StatefulWidget {
  const WebEmbedSurface({
    super.key,
    required this.link,
    this.interactive = true,
    this.reloadToken = 0,
    this.onContentHeight,
  });

  final WebEmbedLink link;

  /// False where a live page must not take the pointer, like a canvas that
  /// is being dragged.
  final bool interactive;

  /// Changed to load the page again.
  final int reloadToken;

  /// Told how tall a single-card page draws, for a host that hugs it.
  final ValueChanged<double>? onContentHeight;

  @override
  State<WebEmbedSurface> createState() => _WebEmbedSurfaceState();
}

class _WebEmbedSurfaceState extends State<WebEmbedSurface> {
  WebEmbedLink? _resolved;
  bool _failed = false;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant WebEmbedSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.link != widget.link) {
      _resolve();
    }
  }

  void _resolve() {
    final link = widget.link;
    final attempt = ++_attempt;
    _failed = false;
    if (!link.needsResolution) {
      _resolved = link;
      return;
    }
    _resolved = null;
    unawaited(
      ExtensionWebEmbedRegistry.resolve(link).then((found) {
        if (!mounted || attempt != _attempt) {
          return;
        }
        setState(() {
          _resolved = found;
          _failed = found == null;
        });
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final resolved = _resolved;
    if (_failed) {
      return WebEmbedFailure(
        url: widget.link.url,
        message: '${widget.link.site} would not say where this link leads.',
        onRetry: () => setState(_resolve),
      );
    }
    if (resolved == null) {
      return WebEmbedLoadingPlaceholder(link: widget.link);
    }
    return ExtensionBoundary(
      extensionId: ExtensionWebEmbedRegistry.extensionIdOf(resolved.provider) ??
          'web_embeds',
      label: resolved.site,
      child: resolved.provider.buildView(
        context,
        resolved,
        WebEmbedViewOptions(
          interactive: widget.interactive,
          brightness: Theme.of(context).brightness,
          reloadToken: widget.reloadToken,
          onContentHeight: widget.onContentHeight,
        ),
      ),
    );
  }
}

/// A still of a recognised link — its picture, site and title — for places a
/// live page would be too heavy or would take the pointer: a canvas being
/// zoomed, a dashboard card, a grid of bookmarks.
class WebEmbedPoster extends StatefulWidget {
  const WebEmbedPoster({
    super.key,
    required this.link,
    this.details,
    this.onOpen,
    this.dense = false,
    this.caption = true,
    this.badge = true,
  });

  final WebEmbedLink link;

  /// What the host already keeps about the link, like a bookmark read when it
  /// was saved. The site is asked only when this is null.
  final WebEmbedDetails? details;
  final VoidCallback? onOpen;

  /// A single line of title and the site's bare name, for small cards.
  final bool dense;

  /// Whether the title and author are printed over the picture, for hosts
  /// that do not print them underneath.
  final bool caption;

  /// Whether the site's chip is laid over the picture, for hosts that do not
  /// name the site beside it.
  final bool badge;

  @override
  State<WebEmbedPoster> createState() => _WebEmbedPosterState();
}

class _WebEmbedPosterState extends State<WebEmbedPoster> {
  late Future<WebEmbedDetails?>? _details = _ask();

  Future<WebEmbedDetails?>? _ask() => widget.details == null
      ? ExtensionWebEmbedRegistry.details(widget.link)
      : null;

  @override
  void didUpdateWidget(covariant WebEmbedPoster oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.link != widget.link ||
        (oldWidget.details == null) != (widget.details == null)) {
      _details = _ask();
    }
  }

  @override
  Widget build(BuildContext context) {
    final link = widget.link;
    return FutureBuilder<WebEmbedDetails?>(
      future: _details,
      builder: (context, snapshot) {
        final details = widget.details ?? snapshot.data;
        final image = details?.thumbnailUrl ?? link.thumbnailUrl;
        final title = details?.title ?? link.title;
        final byline = details?.author ?? link.host;
        return MouseRegion(
          cursor: widget.onOpen == null
              ? MouseCursor.defer
              : SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onOpen,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final roomForText =
                    constraints.maxHeight >= 96 && constraints.maxWidth >= 120;
                final roomForBadge =
                    constraints.maxHeight >= 40 && constraints.maxWidth >= 90;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    _WebEmbedBackdrop(link: link),
                    if (image != null)
                      FlowyNetworkImage(
                        url: image,
                        retryErrorCodes: const {},
                        fadeInDuration: const Duration(milliseconds: 200),
                        placeholderBuilder: (_, __) => const SizedBox.shrink(),
                        errorWidgetBuilder: (_, __, ___) =>
                            const SizedBox.shrink(),
                      ),
                    if (widget.caption &&
                        roomForText &&
                        (title != null || byline.isNotEmpty))
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: _PosterCaption(
                          title: title,
                          byline: byline,
                          dense: widget.dense,
                        ),
                      ),
                    if (widget.badge && roomForBadge)
                      Positioned(
                        top: 8,
                        left: 8,
                        right: 8,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: WebEmbedBadge(
                            link: link,
                            dense: widget.dense,
                            overImage: true,
                          ),
                        ),
                      ),
                    if (_playableKinds.contains(link.kind))
                      const Center(child: _PlayButton()),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// The site's colour and icon, for a link that has no picture of its own.
class _WebEmbedBackdrop extends StatelessWidget {
  const _WebEmbedBackdrop({required this.link});

  final WebEmbedLink link;

  @override
  Widget build(BuildContext context) {
    final color = link.color;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(color, Colors.black, 0.05)!,
            Color.lerp(color, Colors.black, 0.45)!,
          ],
        ),
      ),
      child: Align(
        alignment: const Alignment(0, -0.15),
        child: FractionallySizedBox(
          widthFactor: 0.3,
          heightFactor: 0.3,
          child: FittedBox(
            child: Icon(
              link.icon,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ),
      ),
    );
  }
}

class _PosterCaption extends StatelessWidget {
  const _PosterCaption({
    required this.title,
    required this.byline,
    required this.dense,
  });

  final String? title;
  final String byline;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.72)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 22, 10, 9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null)
              Text(
                title!,
                maxLines: dense ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: dense ? 12 : 13.5,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
            if (byline.isNotEmpty)
              Text(
                byline,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 11,
                  height: 1.3,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        shape: BoxShape.circle,
      ),
      child:
          const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
    );
  }
}

/// Opens [link] live at window size, with a way out to the browser.
Future<void> showWebEmbedFullscreen(
  BuildContext context,
  WebEmbedLink link, {
  String? title,
}) {
  final heading = title ?? link.title ?? link.label;
  return showVisualBlockFullscreen<void>(
    context: context,
    icon: link.icon,
    title: heading,
    subtitle: heading == link.label ? link.host : link.label,
    actions: (context) => [
      VisualBlockButton(
        icon: Icons.open_in_new_rounded,
        tooltip: 'Open in browser',
        onTap: () => unawaited(afLaunchUrlString(link.url)),
      ),
    ],
    builder: (context) => WebEmbedFullView(link: link),
  );
}

/// A recognised link given a whole window or pane: cards and phone pages near
/// their own width, documents, maps and videos across all of it.
class WebEmbedFullView extends StatelessWidget {
  const WebEmbedFullView({super.key, required this.link});

  final WebEmbedLink link;

  @override
  Widget build(BuildContext context) {
    // Cards and phone pages read best near their own width; documents, maps
    // and videos take the whole window.
    if (link.defaultWidth >= 600) {
      return WebEmbedSurface(link: link);
    }
    return LayoutBuilder(
      builder: (context, constraints) => Center(
        child: SizedBox(
          width: math.min(
            constraints.maxWidth,
            math.max(link.defaultWidth * 1.25, 480),
          ),
          height: constraints.maxHeight,
          child: WebEmbedSurface(link: link),
        ),
      ),
    );
  }
}
