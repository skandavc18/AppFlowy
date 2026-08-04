import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_chrome.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_page_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/resizable_media.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_browser_reader.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_fetcher.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_link.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class BookmarkBlockKeys {
  const BookmarkBlockKeys._();

  static const String type = 'bookmark';

  static const String url = 'url';
  static const String title = 'title';
  static const String description = 'description';
  static const String siteName = 'site_name';
  static const String imageUrl = 'image_url';
  static const String faviconUrl = 'favicon_url';
  static const String width = 'width';
  static const String height = 'height';
}

Node bookmarkBlockNode({String url = ''}) => Node(
      type: BookmarkBlockKeys.type,
      attributes: {BookmarkBlockKeys.url: url},
    );

class BookmarkBlockComponentBuilder extends BlockComponentBuilder {
  BookmarkBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return BookmarkBlockComponent(
      key: node.key,
      node: node,
      showActions: showActions(node),
      configuration: configuration,
      actionBuilder: (context, state) => actionBuilder(
        blockComponentContext,
        state,
      ),
    );
  }

  @override
  BlockComponentValidate get validate => (node) => node.children.isEmpty;
}

class BookmarkBlockComponent extends BlockComponentStatefulWidget {
  const BookmarkBlockComponent({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<BookmarkBlockComponent> createState() => BookmarkBlockComponentState();
}

class BookmarkBlockComponentState extends State<BookmarkBlockComponent>
    with BlockComponentConfigurable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _loading = false;

  String get _url => node.attributes[BookmarkBlockKeys.url] as String? ?? '';

  double? get _storedWidth =>
      (node.attributes[BookmarkBlockKeys.width] as num?)?.toDouble();

  double? get _storedHeight =>
      (node.attributes[BookmarkBlockKeys.height] as num?)?.toDouble();

  @override
  void initState() {
    super.initState();
    if (_url.isNotEmpty && node.attributes[BookmarkBlockKeys.title] == null) {
      unawaited(_read(_url));
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = bookmarkThemeOf(context);
    Widget child = _url.isEmpty
        ? _placeholder(theme)
        : ResizableMedia(
            width: _storedWidth ?? double.infinity,
            minWidth: 260,
            height: _storedHeight ?? BookmarkMetrics.feedRowHeight,
            minHeight: 72,
            maxHeight: 640,
            alignment: Alignment.centerLeft,
            editable: context.read<EditorState>().editable,
            onResize: (value) => _write({BookmarkBlockKeys.width: value}),
            onResizeHeight: (value) =>
                _write({BookmarkBlockKeys.height: value}),
            child: _card(theme, fill: true),
          );

    child = Padding(padding: padding, child: child);

    if (widget.showActions && widget.actionBuilder != null) {
      child = BlockComponentActionWrapper(
        node: node,
        actionBuilder: widget.actionBuilder!,
        child: child,
      );
    }
    // The editor owns Backspace, Enter and paste until nothing is selected,
    // so keys typed into the field would delete this block instead.
    return FocusScope(
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (hasFocus && keepEditorFocusNotifier.value == 0) {
          context.read<EditorState>().selection = null;
        }
      },
      child: child,
    );
  }

  Widget _placeholder(BookmarkTheme theme) => ViewerCard(
        reactsToPointer: false,
        color: theme.panel,
        child: Padding(
          padding: const EdgeInsets.all(BookmarkMetrics.space3),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.link_rounded, size: 19, color: theme.accent),
              ),
              const SizedBox(width: BookmarkMetrics.space3),
              Expanded(
                child: TextField(
                  controller: _input,
                  focusNode: _focus,
                  autofocus: true,
                  cursorColor: theme.accent,
                  cursorWidth: 1.6,
                  cursorRadius: const Radius.circular(1),
                  style: theme.face(
                    fontSize: 15,
                    color: theme.textStrong,
                    height: 1.2,
                  ),
                  onSubmitted: _commit,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: false,
                    hoverColor: Colors.transparent,
                    contentPadding: EdgeInsets.zero,
                    hintText: LocaleKeys.collections_bookmark_addLinkHint.tr(),
                    hintStyle: theme.face(
                      fontSize: 15,
                      color: theme.textFaint,
                      height: 1.2,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
              const SizedBox(width: BookmarkMetrics.space3),
              _PlaceholderButton(
                label: LocaleKeys.collections_bookmark_pasteFromClipboard.tr(),
                icon: Icons.content_paste_rounded,
                theme: theme,
                onPressed: _pasteAndCommit,
              ),
              const SizedBox(width: BookmarkMetrics.space2 - 2),
              _PlaceholderButton(
                label: LocaleKeys.collections_bookmark_addLink.tr(),
                icon: Icons.arrow_forward_rounded,
                theme: theme,
                primary: true,
                onPressed: _input.text.trim().isEmpty
                    ? null
                    : () => _commit(_input.text),
              ),
            ],
          ),
        ),
      );

  Widget _card(BookmarkTheme theme, {bool fill = false}) {
    final attributes = node.attributes;
    final title = attributes[BookmarkBlockKeys.title] as String?;
    final description = attributes[BookmarkBlockKeys.description] as String?;
    final image = attributes[BookmarkBlockKeys.imageUrl] as String?;
    final site = attributes[BookmarkBlockKeys.siteName] as String? ??
        bookmarkHost(_url) ??
        _url;
    final favicon = attributes[BookmarkBlockKeys.faviconUrl] as String?;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => openBookmarkPagePreview(
          context: context,
          url: _url,
          title: title,
        ),
        child: ViewerCard(
          reactsToPointer: false,
          color: theme.panel,
          child: SizedBox(
            height: fill ? double.infinity : BookmarkMetrics.feedRowHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (image != null && image.isNotEmpty)
                  SizedBox(
                    width: BookmarkMetrics.feedThumbWidth,
                    child: Image.network(
                      image,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) =>
                          ColoredBox(color: theme.sunken),
                    ),
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      BookmarkMetrics.space4,
                      BookmarkMetrics.space3,
                      BookmarkMetrics.space3,
                      BookmarkMetrics.space3,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title?.isNotEmpty == true ? title! : site,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.cardTitle,
                        ),
                        if (description != null && description.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Expanded(
                            child: Text(
                              description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.body,
                            ),
                          ),
                        ] else
                          const Spacer(),
                        const SizedBox(height: BookmarkMetrics.space2 - 2),
                        Row(
                          children: [
                            if (favicon != null && favicon.isNotEmpty) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Image.network(
                                  favicon,
                                  width: 14,
                                  height: 14,
                                  gaplessPlayback: true,
                                  errorBuilder: (_, __, ___) =>
                                      const SizedBox.shrink(),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Expanded(
                              child: Text(
                                bookmarkDisplayUrl(_url),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.meta,
                              ),
                            ),
                            if (_loading)
                              SizedBox(
                                width: 11,
                                height: 11,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: theme.accent,
                                ),
                              )
                            else
                              BookmarkAction(
                                icon: Icons.open_in_new_rounded,
                                tooltip: LocaleKeys
                                    .collections_bookmark_openInBrowser
                                    .tr(),
                                theme: theme,
                                size: 24,
                                onPressed: _open,
                              ),
                          ],
                        ),
                      ],
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

  Future<void> _pasteAndCommit() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) {
      await _commit(text);
    }
  }

  Future<void> _commit(String raw) async {
    final url = normalizeBookmarkUrl(raw);
    if (url == null) {
      return;
    }
    await _write({BookmarkBlockKeys.url: url});
    await _read(url);
  }

  /// Reads what the page says about itself and caches it on the block, so it
  /// draws instantly the next time the document opens.
  Future<void> _read(String url) async {
    if (mounted) {
      setState(() => _loading = true);
    }
    final fetcher = BookmarkFetcher(browserFallback: readPageInBrowser);
    try {
      final result = await fetcher.fetch(url);
      final metadata = result.metadata;
      if (metadata == null || !mounted) {
        return;
      }
      await _write({
        BookmarkBlockKeys.title: metadata.title,
        BookmarkBlockKeys.description: metadata.description,
        BookmarkBlockKeys.siteName: metadata.siteName,
        BookmarkBlockKeys.imageUrl:
            metadata.imageUrl ?? result.article?.leadImageUrl,
        BookmarkBlockKeys.faviconUrl: metadata.faviconUrl,
      });
    } finally {
      fetcher.close();
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _write(Map<String, dynamic> attributes) async {
    final editorState = context.read<EditorState>();
    final transaction = editorState.transaction
      ..updateNode(node, {...node.attributes, ...attributes});
    await editorState.apply(transaction);
  }

  Future<void> _open() async {
    final uri = Uri.tryParse(_url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _PlaceholderButton extends StatefulWidget {
  const _PlaceholderButton({
    required this.label,
    required this.icon,
    required this.theme,
    required this.onPressed,
    this.primary = false,
  });

  final String label;
  final IconData icon;
  final BookmarkTheme theme;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  State<_PlaceholderButton> createState() => _PlaceholderButtonState();
}

class _PlaceholderButtonState extends State<_PlaceholderButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final enabled = widget.onPressed != null;
    final background = widget.primary
        ? theme.accent.withValues(alpha: enabled ? (_hovered ? 1 : 0.9) : 0.28)
        : theme.sunken.withValues(alpha: _hovered ? 1 : 0.75);
    final foreground = widget.primary
        ? Colors.white
        : (_hovered ? theme.textStrong : theme.textBody);

    return Tooltip(
      message: widget.label,
      child: MouseRegion(
        cursor:
            enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: BookmarkMetrics.hover,
            curve: Curves.easeOutCubic,
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(widget.icon, size: 18, color: foreground),
          ),
        ),
      ),
    );
  }
}
