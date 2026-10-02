import 'dart:async';

import 'package:appflowy/extensions/dart/web_embed_registry.dart';
import 'package:appflowy/extensions/presentation/web_embed_widgets.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_chrome.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/bookmark/bookmark_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/link_embed/link_embed_block_component.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_link.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:universal_platform/universal_platform.dart';

import 'web_embed_sites.dart';

class WebEmbedBlockKeys {
  const WebEmbedBlockKeys._();

  static const String type = 'extension_web_embed';

  /// The `/` entry that made the block, so it asks for the right site.
  static const String entry = 'entry';
}

/// A block asking for a link to embed, worded for [entry].
Node webEmbedPlaceholderNode([String entry = '']) => Node(
      type: WebEmbedBlockKeys.type,
      attributes: {WebEmbedBlockKeys.entry: entry},
    );

/// Nothing to export until there is a link, and then it is a link embed.
class WebEmbedNodeParser extends NodeParser {
  @override
  String get id => WebEmbedBlockKeys.type;

  @override
  String transform(Node node, DocumentMarkdownEncoder? encoder) => '';
}

class WebEmbedBlockComponentBuilder extends BlockComponentBuilder {
  WebEmbedBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return WebEmbedBlockComponent(
      key: node.key,
      node: node,
      showActions: showActions(node),
      configuration: configuration,
      actionBuilder: (context, state) =>
          actionBuilder(blockComponentContext, state),
    );
  }

  @override
  BlockComponentValidate get validate => (node) => node.children.isEmpty;
}

/// Asks for the link a `/` embed should show.
///
/// It only asks. Given a link, it turns into the document's own link embed,
/// which already resizes, aligns, reloads and shares, turns into a mention or
/// a bookmark, and draws a registered site live. So an embed made here is the
/// same as one pasted, and with the extension off it is a preview card rather
/// than a block nothing can draw.
class WebEmbedBlockComponent extends BlockComponentStatefulWidget {
  const WebEmbedBlockComponent({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<WebEmbedBlockComponent> createState() => _WebEmbedBlockComponentState();
}

class _WebEmbedBlockComponentState extends State<WebEmbedBlockComponent>
    with BlockComponentConfigurable, WidgetsBindingObserver {
  @override
  Node get node => widget.node;

  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();

  /// A site chosen from the strip under the field, over the stored entry.
  String? _picked;

  /// The field's link, when a registered site recognises it.
  WebEmbedLink? _typed;

  /// A recognised link on the clipboard, offered as one click.
  WebEmbedLink? _copied;

  /// Why the last link was not embedded.
  String? _problem;

  /// A link the entry's site did not recognise, kept to embed anyway.
  String? _unrecognised;

  bool _busy = false;

  WebEmbedEntry get _entry => webEmbedEntryById(
        _picked ?? node.attributes[WebEmbedBlockKeys.entry] as String?,
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_lookAtClipboard());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Coming back from the browser is when a link has just been copied.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_lookAtClipboard());
    }
  }

  /// ⚠️ Desktop only: a phone asks the reader's leave, or announces it, each
  /// time an app reads the clipboard unprompted.
  Future<void> _lookAtClipboard() async {
    if (!UniversalPlatform.isDesktop) {
      return;
    }
    final link = ExtensionWebEmbedRegistry.recognize(
      webEmbedAddressFrom(await _clipboardText()),
    );
    if (mounted && link != _copied) {
      setState(() => _copied = link);
    }
  }

  static Future<String?> _clipboardText() async {
    try {
      return (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } on Object {
      return null;
    }
  }

  void _onChanged(String text) {
    setState(() {
      _typed = ExtensionWebEmbedRegistry.recognize(webEmbedAddressFrom(text));
      _problem = null;
      _unrecognised = null;
    });
  }

  Future<void> _paste() async {
    final text = (await _clipboardText())?.trim() ?? '';
    if (!mounted) {
      return;
    }
    if (text.isEmpty) {
      setState(() {
        _problem = 'There is no link on the clipboard.';
        _unrecognised = null;
      });
      return;
    }
    // Embed code arrives over several lines, which a one-line field would
    // run together, so the field shows the address found in it instead.
    _input.text =
        webEmbedAddressFrom(text) ?? text.replaceAll(RegExp(r'\s+'), ' ');
    _onChanged(_input.text);
    await _commit(text);
  }

  Future<void> _useCopied(WebEmbedLink link) async {
    _input.text = link.url;
    _onChanged(link.url);
    await _commit(link.url);
  }

  Future<void> _commit(String raw, {bool anyway = false}) async {
    final text = raw.trim();
    if (_busy || text.isEmpty) {
      return;
    }
    final address = webEmbedAddressFrom(text);
    if (address == null) {
      setState(() {
        _problem = 'That is not a link, or embed code with a link in it.';
        _unrecognised = null;
      });
      return;
    }
    final entry = _entry;
    final link = ExtensionWebEmbedRegistry.recognize(address);
    if (link == null && !entry.isAnySite && !anyway) {
      setState(() {
        _problem = 'That is not a link ${entry.name} can show live.';
        _unrecognised = address;
      });
      return;
    }
    var url = link?.url ?? address;
    if (link != null && link.needsResolution) {
      setState(() {
        _busy = true;
        _problem = null;
      });
      url = await ExtensionWebEmbedRegistry.settledUrl(link);
      if (!mounted) {
        return;
      }
    }
    await _becomeEmbed(url);
  }

  /// Swaps this block for the document's own link embed of [url].
  Future<void> _becomeEmbed(String url) async {
    final editorState = context.read<EditorState>();
    final transaction = editorState.transaction
      ..insertNode(node.path, linkEmbedNode(url: url))
      ..deleteNode(node);
    await editorState.apply(transaction);
  }

  @override
  Widget build(BuildContext context) {
    final theme = bookmarkThemeOf(context);
    Widget child =
        context.read<EditorState>().editable ? _asking(theme) : _waiting(theme);

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

  Widget _asking(BookmarkTheme theme) {
    final entry = _entry;
    final accent = _buttonColor(entry, theme);
    final text = _input.text.trim();
    return ViewerCard(
      reactsToPointer: false,
      color: theme.panel,
      child: Padding(
        padding: const EdgeInsets.all(BookmarkMetrics.space3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _EntryMark(entry: entry, theme: theme),
                const SizedBox(width: BookmarkMetrics.space3),
                Expanded(child: _field(theme, entry, accent)),
                const SizedBox(width: BookmarkMetrics.space3),
                BookmarkPlaceholderButton(
                  label: 'Paste and embed',
                  icon: Icons.content_paste_rounded,
                  theme: theme,
                  onPressed: _busy ? null : () => unawaited(_paste()),
                ),
                const SizedBox(width: BookmarkMetrics.space2 - 2),
                BookmarkPlaceholderButton(
                  label: 'Embed',
                  icon: Icons.arrow_forward_rounded,
                  theme: theme,
                  primary: true,
                  accent: accent,
                  onPressed: _busy || text.isEmpty
                      ? null
                      : () => unawaited(_commit(text)),
                ),
              ],
            ),
            const SizedBox(height: BookmarkMetrics.space2),
            Padding(
              padding: const EdgeInsets.only(
                left: _EntryMark.fieldSize + BookmarkMetrics.space3,
              ),
              child: AnimatedSize(
                duration: BookmarkMetrics.reveal,
                curve: BookmarkMetrics.curve,
                alignment: Alignment.topLeft,
                child: _footer(theme, entry, accent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(BookmarkTheme theme, WebEmbedEntry entry, Color accent) =>
      TextField(
        controller: _input,
        focusNode: _focus,
        autofocus: true,
        readOnly: _busy,
        cursorColor: accent,
        cursorWidth: 1.6,
        cursorRadius: const Radius.circular(1),
        style: theme.face(fontSize: 15, color: theme.textStrong, height: 1.2),
        onSubmitted: (value) => unawaited(_commit(value)),
        onChanged: _onChanged,
        decoration: InputDecoration(
          isDense: true,
          filled: false,
          hoverColor: Colors.transparent,
          contentPadding: EdgeInsets.zero,
          hintText: entry.prompt,
          hintStyle:
              theme.face(fontSize: 15, color: theme.textFaint, height: 1.2),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
      );

  /// One line under the field: what is happening, what went wrong, what was
  /// recognised, or else what the entry takes.
  Widget _footer(BookmarkTheme theme, WebEmbedEntry entry, Color accent) {
    if (_busy) {
      return _FooterLine(
        theme: theme,
        leading: SizedBox.square(
          dimension: 12,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: accent),
        ),
        text: 'Following the short link…',
      );
    }
    final problem = _problem;
    if (problem != null) {
      final unrecognised = _unrecognised;
      return _FooterLine(
        theme: theme,
        leading: Icon(
          Icons.error_outline_rounded,
          size: 14,
          color: theme.textSoft,
        ),
        text: problem,
        strong: true,
        action: unrecognised == null
            ? null
            : _FooterAction(
                label: 'Show it as a link preview',
                theme: theme,
                onTap: () => unawaited(_commit(unrecognised, anyway: true)),
              ),
      );
    }
    final typed = _typed;
    if (typed != null) {
      return _FooterLine(
        theme: theme,
        leading: WebEmbedBadge(link: typed),
        text: typed.needsResolution
            ? 'A short link. Press Enter to follow it and embed.'
            : 'Press Enter to embed.',
      );
    }
    final copied = _copied;
    if (copied != null && _input.text.trim().isEmpty && entry.accepts(copied)) {
      return _FooterLine(
        theme: theme,
        leading: WebEmbedBadge(link: copied, dense: true),
        text: bookmarkDisplayUrl(copied.url),
        action: _FooterAction(
          label: 'Embed the copied link',
          theme: theme,
          onTap: () => unawaited(_useCopied(copied)),
        ),
      );
    }
    if (entry.isAnySite) {
      return _SiteStrip(
        theme: theme,
        onPick: (picked) {
          setState(() => _picked = picked.id);
          _focus.requestFocus();
        },
      );
    }
    return _FooterLine(
      theme: theme,
      text: entry.hint,
      action: _picked == null
          ? null
          : _FooterAction(
              label: 'Any site',
              theme: theme,
              onTap: () {
                setState(() => _picked = null);
                _focus.requestFocus();
              },
            ),
    );
  }

  /// A site's own colour for the button, deepened where white would not read
  /// on it, like Slides' yellow.
  static Color _buttonColor(WebEmbedEntry entry, BookmarkTheme theme) {
    final color = entry.color;
    if (color == null) {
      return theme.accent;
    }
    return color.computeLuminance() > 0.4
        ? Color.lerp(color, Colors.black, 0.28)!
        : color;
  }

  Widget _waiting(BookmarkTheme theme) {
    final entry = _entry;
    return ViewerCard(
      reactsToPointer: false,
      color: theme.panel,
      child: Padding(
        padding: const EdgeInsets.all(BookmarkMetrics.space3),
        child: Row(
          children: [
            _EntryMark(entry: entry, theme: theme),
            const SizedBox(width: BookmarkMetrics.space3),
            Expanded(
              child: Text(
                entry.isAnySite
                    ? 'An embed still waiting for its link'
                    : 'A ${entry.name} embed still waiting for its link',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.face(fontSize: 14, color: theme.textSoft),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The entry's icon on a tint of its site's colour.
class _EntryMark extends StatelessWidget {
  const _EntryMark({
    required this.entry,
    required this.theme,
    this.size = fieldSize,
    this.emphasis = 1,
  });

  /// Level with the field and its buttons.
  static const double fieldSize = 38;

  final WebEmbedEntry entry;
  final BookmarkTheme theme;
  final double size;

  /// How strongly the tint shows, raised on hover.
  final double emphasis;

  @override
  Widget build(BuildContext context) {
    final color = entry.color ?? theme.accent;
    final brightness = Theme.of(context).brightness;
    final tint = brightness == Brightness.dark ? 0.22 : 0.12;
    return AnimatedContainer(
      duration: BookmarkMetrics.hover,
      curve: BookmarkMetrics.curve,
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: tint * emphasis),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(
        entry.icon,
        size: size * 0.5,
        color: webEmbedReadableColor(color, brightness),
      ),
    );
  }
}

/// The sites that show live, each a click away from asking for its links.
class _SiteStrip extends StatelessWidget {
  const _SiteStrip({required this.theme, required this.onPick});

  final BookmarkTheme theme;
  final ValueChanged<WebEmbedEntry> onPick;

  @override
  Widget build(BuildContext context) {
    final registered = {
      for (final provider in ExtensionWebEmbedRegistry.all()) provider.id,
    };
    return Wrap(
      spacing: 3,
      runSpacing: 3,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 5),
          child: Text('Live from', style: theme.meta),
        ),
        for (final entry in webEmbedEntries)
          if (!entry.isAnySite && registered.contains(entry.provider!.id))
            _SiteButton(entry: entry, theme: theme, onTap: () => onPick(entry)),
        Padding(
          padding: const EdgeInsets.only(left: 5),
          child: Text('· any other link shows as a preview', style: theme.meta),
        ),
      ],
    );
  }
}

class _SiteButton extends StatefulWidget {
  const _SiteButton({
    required this.entry,
    required this.theme,
    required this.onTap,
  });

  final WebEmbedEntry entry;
  final BookmarkTheme theme;
  final VoidCallback onTap;

  @override
  State<_SiteButton> createState() => _SiteButtonState();
}

class _SiteButtonState extends State<_SiteButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.entry.name,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: _EntryMark(
            entry: widget.entry,
            theme: widget.theme,
            size: 22,
            emphasis: _hovered ? 2.4 : 1,
          ),
        ),
      ),
    );
  }
}

class _FooterLine extends StatelessWidget {
  const _FooterLine({
    required this.theme,
    required this.text,
    this.leading,
    this.action,
    this.strong = false,
  });

  final BookmarkTheme theme;
  final String text;
  final Widget? leading;
  final Widget? action;

  /// Said plainly rather than as a hint, for a problem.
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (leading != null) ...[
          // A badge ellipsizes its label, which needs a width to ellipsize at.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: leading,
          ),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: strong ? theme.metaStrong : theme.meta,
          ),
        ),
        if (action != null) ...[
          const SizedBox(width: BookmarkMetrics.space2),
          action!,
        ],
      ],
    );
  }
}

class _FooterAction extends StatelessWidget {
  const _FooterAction({
    required this.label,
    required this.theme,
    required this.onTap,
  });

  final String label;
  final BookmarkTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Text(
          label,
          style: theme.face(
            fontSize: BookmarkMetrics.metaSize,
            color: theme.accent,
            weight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
