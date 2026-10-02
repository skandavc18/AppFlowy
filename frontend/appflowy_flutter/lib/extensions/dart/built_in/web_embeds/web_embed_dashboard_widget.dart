import 'dart:async';

import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/extensions/dart/web_embed_registry.dart';
import 'package:appflowy/extensions/presentation/web_embed_widgets.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_config_field.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/content_widgets.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_action.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'web_embed_sites.dart';

/// The dashboard card for a post, video, map or document from the web.
const webEmbedWidgetType = 'ext.web_embeds.embed';

const _keyUrl = 'url';
const _keyDisplay = 'display';

const _displayLive = 'live';
const _displayPoster = 'poster';

DashboardWidgetDefinition webEmbedDashboardWidget(String extensionId) =>
    DashboardWidgetDefinition(
      type: webEmbedWidgetType,
      extensionId: extensionId,
      label: () => 'Web embed',
      description: () =>
          'A post, video, song, document, article or file from the web, live '
          'on the board',
      icon: webEmbedEntries.first.icon,
      group: DashboardWidgetGroup.content,
      defaultColumnSpan: 6,
      defaultRowSpan: 9,
      minimumColumnSpan: 3,
      minimumRowSpan: 3,
      showsTitleByDefault: false,
      // A live page draws edge to edge, like a picture.
      paintsOwnSurface: true,
      // The page scrolls over it until it is clicked, and only then does the
      // site get the pointer.
      requiresScrollActivation: true,
      keywords: {
        for (final entry in webEmbedEntries) ...[
          entry.name.toLowerCase(),
          ...entry.keywords,
        ],
      }.toList(),
      defaultSettings: const {_keyUrl: '', _keyDisplay: _displayLive},
      builder: (context) => _WebEmbedCard(context: context),
      configure: (context) => [
        DashboardConfigText(
          label: 'Link',
          value: context.spec.setting(_keyUrl),
          placeholder: 'https://',
          hint: 'A post, video, song, map, document, shared file, news '
              'article, product or PDF link — X, LinkedIn, YouTube, Spotify, '
              'Notion, GitHub, Google Drive, Dropbox, Amazon and more — or '
              'its embed code',
          onChanged: (value) => context.setSettings({_keyUrl: _tidy(value)}),
        ),
        DashboardConfigChoice(
          label: 'Show',
          value: context.spec.setting(_keyDisplay, fallback: _displayLive),
          choices: const [
            DashboardChoice(
              value: _displayLive,
              label: 'Live',
              icon: Icons.play_circle_outline_rounded,
              description: 'The site itself: scroll, play and click through',
            ),
            DashboardChoice(
              value: _displayPoster,
              label: 'Picture',
              icon: Icons.image_outlined,
              description: 'Its picture and title; click to open it live',
            ),
          ],
          onChanged: (value) => context.setSettings({_keyDisplay: value}),
        ),
      ],
    );

/// The address in what was typed or pasted: embed code gives up its link, a
/// plain address is kept as written.
String _tidy(String value) => value.contains('<')
    ? webEmbedAddressFrom(value) ?? value.trim()
    : value.trim();

class _WebEmbedCard extends StatefulWidget {
  const _WebEmbedCard({required this.context});

  final DashboardWidgetContext context;

  @override
  State<_WebEmbedCard> createState() => _WebEmbedCardState();
}

class _WebEmbedCardState extends State<_WebEmbedCard> {
  int _reload = 0;

  /// The short link last followed, so each one is followed once.
  String _settling = '';

  DashboardWidgetContext get _dashboard => widget.context;

  String get _raw => _dashboard.spec.setting(_keyUrl).trim();

  @override
  void initState() {
    super.initState();
    ExtensionWebEmbedRegistry.revision.addListener(_onSitesChanged);
  }

  @override
  void dispose() {
    ExtensionWebEmbedRegistry.revision.removeListener(_onSitesChanged);
    super.dispose();
  }

  void _onSitesChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// Keeps where a short link leads rather than the short link, so the card
  /// does not ask the site again every time the board is opened.
  void _settle(WebEmbedLink link) {
    final raw = _raw;
    if (!link.needsResolution || !_dashboard.isTypable || raw == _settling) {
      return;
    }
    _settling = raw;
    unawaited(
      ExtensionWebEmbedRegistry.settledUrl(link).then((url) {
        if (!mounted || url == link.url) {
          return;
        }
        // Only if nobody changed the link while it was being followed.
        _dashboard.update(
          (spec) => spec.setting(_keyUrl).trim() == raw
              ? spec.withSettings({_keyUrl: url})
              : spec,
        );
      }),
    );
  }

  Future<void> _askForLink() async {
    final answer = await askForDashboardLink(
      _dashboard.context,
      palette: _dashboard.palette,
      initialValue: _raw,
    );
    final url = _tidy(answer ?? '');
    if (url.isEmpty || !mounted) {
      return;
    }
    _dashboard.setSettings({_keyUrl: url});
  }

  void _openFullscreen(WebEmbedLink link) => unawaited(
        showWebEmbedFullscreen(
          _dashboard.context,
          link,
          title: _dashboard.spec.title.isEmpty ? null : _dashboard.spec.title,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final dashboard = _dashboard;
    final palette = dashboard.palette;
    final raw = _raw;

    if (raw.isEmpty) {
      return ColoredBox(
        color: dashboard.tone.surface,
        child: DashboardPlaceholder(
          palette: palette,
          icon: webEmbedEntries.first.icon,
          message: 'A post, video, map or document, live on the board',
          action: dashboard.isTypable ? 'Add link' : null,
          onAction: dashboard.isTypable ? () => unawaited(_askForLink()) : null,
        ),
      );
    }

    final link = ExtensionWebEmbedRegistry.recognize(raw);
    if (link == null) {
      final uri = parseWebEmbedUri(raw);
      return ColoredBox(
        color: dashboard.tone.surface,
        child: DashboardPlaceholder(
          palette: palette,
          icon: Icons.link_off_rounded,
          message: uri == null
              ? 'That is not a link'
              : '${uri.host} has no live view. A Bookmark card shows its '
                  'preview.',
          action: uri == null
              ? (dashboard.isTypable ? 'Change link' : null)
              : 'Open link',
          onAction: uri == null
              ? (dashboard.isTypable ? () => unawaited(_askForLink()) : null)
              : () => unawaited(
                    dashboard.run(
                      DashboardAction(
                        kind: DashboardActionKind.openUrl,
                        target: uri.toString(),
                      ),
                    ),
                  ),
        ),
      );
    }
    _settle(link);

    // A board drawn small as a preview is looked at, never used, and a live
    // page in it would load a whole site for a thumbnail.
    final live = dashboard.spec.setting(_keyDisplay, fallback: _displayLive) ==
            _displayLive &&
        dashboard.controller.viewId.isNotEmpty;
    if (!live) {
      return WebEmbedPoster(
        link: link,
        dense: true,
        onOpen: () => _openFullscreen(link),
      );
    }

    // While the board can be rearranged, the card is dragged by its surface,
    // so the site only gets the pointer once the card is clicked.
    final selected = dashboard.controller.selectedWidgetId == dashboard.spec.id;
    final interactive = !dashboard.isEditable || selected;
    return ColoredBox(
      color: dashboard.tone.surface,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _PointerClaim(
            claimed: interactive && dashboard.isEditable,
            child: WebEmbedSurface(
              link: link,
              interactive: interactive,
              reloadToken: _reload,
            ),
          ),
          Positioned(
            top: 8,
            right: 12,
            child: PreviewToolbar(
              child: _EmbedTools(
                palette: palette,
                onFullscreen: () => _openFullscreen(link),
                onReload: () => setState(() => _reload++),
                onBrowser: () => unawaited(afLaunchUrlString(link.url)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Keeps a press on a live page from also picking up the card it is on.
///
/// The page takes raw pointer events, which never enter the gesture arena, so
/// without a claim the card's drag would win and move the card while the site
/// scrolls or selects underneath it.
class _PointerClaim extends StatelessWidget {
  const _PointerClaim({required this.claimed, required this.child});

  final bool claimed;
  final Widget child;

  @override
  Widget build(BuildContext context) => RawGestureDetector(
        behavior: HitTestBehavior.translucent,
        gestures: {
          if (claimed)
            EagerGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
              EagerGestureRecognizer.new,
              (_) {},
            ),
        },
        child: child,
      );
}

class _EmbedTools extends StatelessWidget {
  const _EmbedTools({
    required this.palette,
    required this.onFullscreen,
    required this.onReload,
    required this.onBrowser,
  });

  final DashboardPalette palette;
  final VoidCallback onFullscreen;
  final VoidCallback onReload;
  final VoidCallback onBrowser;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: palette.raised,
          borderRadius: BorderRadius.circular(DashboardMetrics.controlRadius),
          boxShadow: palette.cardShadow(raised: true),
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DashboardIconButton(
                icon: Icons.open_in_full_rounded,
                palette: palette,
                iconSize: 15,
                tooltip: 'Open full screen',
                onPressed: onFullscreen,
              ),
              DashboardIconButton(
                icon: Icons.refresh_rounded,
                palette: palette,
                iconSize: 15,
                tooltip: 'Reload',
                onPressed: onReload,
              ),
              DashboardIconButton(
                icon: Icons.open_in_new_rounded,
                palette: palette,
                iconSize: 15,
                tooltip: 'Open in browser',
                onPressed: onBrowser,
              ),
            ],
          ),
        ),
      );
}
