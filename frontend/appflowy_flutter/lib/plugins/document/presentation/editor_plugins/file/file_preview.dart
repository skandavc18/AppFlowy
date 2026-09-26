import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/code_block/syntax_highlighter.dart';
import 'package:appflowy/shared/document_viewer/document_viewer.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/find_replace/find_replace.dart';
import 'package:appflowy/shared/google_fonts_extension.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/shared/scrolling/trackpad_history_navigation.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:linked_scroll_controller/linked_scroll_controller.dart';
import 'package:markdown/markdown.dart' as markdown;
import 'package:path/path.dart' as p;

import 'archive/archive_explorer.dart';
import 'csv_preview.dart';
import 'file_preview_kind.dart';
import 'html_preview_resource_host.dart';
import 'markdown_preview_fonts.dart';
import 'notebook/notebook_view.dart';
import 'pdf_preview.dart';
import 'pdf_preview_scroll_physics.dart';
import 'pdf_preview_theme.dart';
import 'sandboxed_code_runner.dart';

const maxTextPreviewBytes = 10 * 1024 * 1024;

/// How tall an embedded preview is before the reader resizes it.
///
/// Code brings its own toolbar and terminal, an archive brings the folder
/// chrome, and a notebook brings a whole page of cells, so all three need more
/// than a plain document preview.
double defaultFilePreviewHeight(FilePreviewKind kind) => switch (kind) {
      FilePreviewKind.code => 560,
      FilePreviewKind.archive => 560,
      FilePreviewKind.notebook => 620,
      _ => 420,
    };

class FilePreview extends StatefulWidget {
  const FilePreview({
    super.key,
    required this.file,
    required this.name,
    required this.kind,
    required this.metadata,
    required this.onMetadataChanged,
    this.editable = true,
    this.toolbarTrailing,
    this.pdfMenuBuilder,
    this.height,
    this.previewScrollController,
    this.bare = false,
    this.framed = true,
  });

  final File file;
  final String name;
  final FilePreviewKind kind;
  final Map<String, dynamic> metadata;
  final ValueChanged<Map<String, dynamic>> onMetadataChanged;
  final bool editable;
  final Widget? toolbarTrailing;
  final PdfPreviewMenuBuilder? pdfMenuBuilder;
  final double? height;
  final PdfPreviewScrollController? previewScrollController;

  /// Renders the content alone — no card, no header, no background of its
  /// own — for a host that supplies the surface, such as the book reader.
  final bool bare;

  /// Embedded previews keep their card. Full-window files keep the same fixed
  /// header but sit flush against the workspace rather than inside a card.
  final bool framed;

  @override
  State<FilePreview> createState() => _FilePreviewState();
}

class _FilePreviewState extends State<FilePreview> {
  late Future<Widget> preview;

  @override
  void initState() {
    super.initState();
    preview = _buildPreview();
  }

  @override
  void didUpdateWidget(covariant FilePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path ||
        oldWidget.kind != widget.kind ||
        oldWidget.name != widget.name ||
        (oldWidget.editable != widget.editable &&
            widget.kind != FilePreviewKind.code &&
            widget.kind != FilePreviewKind.archive) ||
        oldWidget.bare != widget.bare ||
        (widget.kind.supportsSourceEditing &&
            oldWidget.metadata[filePreviewEditModeKey] !=
                widget.metadata[filePreviewEditModeKey])) {
      preview = _buildPreview();
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = _FilePreviewConfiguration(
      configuration: widget,
      child: FutureBuilder<Widget>(
        // A new file must not inherit the previous FutureBuilder's last data or
        // editable renderer while its own IO is pending.
        key: ObjectKey(preview),
        future: preview,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _PreviewError(
              message: snapshot.error.toString(),
              onRetry: () {
                setState(() {
                  preview = _buildPreview();
                });
              },
            );
          }
          return snapshot.data ??
              const Center(child: CircularProgressIndicator());
        },
      ),
    );

    if (widget.bare) {
      return widget.height == null
          ? content
          : SizedBox(height: widget.height, child: content);
    }

    final materialTheme = Theme.of(context);
    final appFlowyTheme = AppFlowyTheme.of(context);
    final isPremiumPreview = widget.kind == FilePreviewKind.pdf;
    final pdfPalette = isPremiumPreview ? PdfPreviewPalette.of(context) : null;
    final backgroundColor = StandaloneFileScope.maybeOf(context)?.canvas ??
        pdfPalette?.canvas ??
        EditorSurfaceStyle.previewBackgroundFor(
          materialTheme.brightness,
          appFlowyTheme.surfaceColorScheme.layer01,
          isPaper: PaperTheme.isEnabled(context),
        );
    final sized = SizedBox(
      height: widget.height ?? defaultFilePreviewHeight(widget.kind),
      child: content,
    );
    return widget.framed
        ? PreviewToolbarRegion(
            // Source editing is an explicit mode. Keep its Done/menu actions
            // available even when the pointer returns to the surrounding page.
            enabled: widget.metadata[filePreviewEditModeKey] != true ||
                !widget.kind.supportsSourceEditing,
            child: ViewerCard(color: backgroundColor, child: sized),
          )
        : ColoredBox(color: backgroundColor, child: sized);
  }

  Future<Widget> _buildPreview() => _FilePreviewLoader(widget).build();
}

/// IO captures an immutable request, but controls must not capture its initial
/// settings forever. A loaded code editor observes configuration without a new
/// future/key, file read, editor controller, selection or execution session.
class _FilePreviewConfiguration extends InheritedWidget {
  const _FilePreviewConfiguration({
    required this.configuration,
    required super.child,
  });

  final FilePreview configuration;

  static FilePreview? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_FilePreviewConfiguration>()
      ?.configuration;

  @override
  bool updateShouldNotify(_FilePreviewConfiguration oldWidget) =>
      configuration != oldWidget.configuration;
}

/// An immutable request, so an await cannot mix one file's bytes with the
/// next file's name, base directory, renderer kind or edit destination.
class _FilePreviewLoader {
  _FilePreviewLoader(this.widget);

  final FilePreview widget;

  bool get isEditingSource =>
      widget.metadata[filePreviewEditModeKey] == true &&
      widget.kind.supportsSourceEditing;

  Future<Widget> build() async {
    if (!await widget.file.exists()) {
      throw const FileSystemException('The preview file is unavailable.');
    }
    // Editing shows the file exactly as authored, with the same editor the
    // code viewer uses, so nothing is reinterpreted on the way in or out.
    if (isEditingSource) {
      return _buildPreviewScaffold(
        _EditableCodeFile(
          file: widget.file,
          initialCode: await _readText(maxTextPreviewBytes),
          editable: widget.editable,
          language: widget.kind.sourceLanguage,
          showLineNumbers: true,
          // The viewport already paints the sheet; a second surface here
          // would read as a grey band under the header.
          surfaceColor: Colors.transparent,
          onChanged: (_) {},
        ),
        writingSurface: true,
      );
    }
    return switch (widget.kind) {
      FilePreviewKind.pdf => PdfPreview(
          key: ValueKey(widget.file.path),
          file: widget.file,
          name: widget.name,
          metadata: widget.metadata,
          onMetadataChanged: widget.onMetadataChanged,
          editable: widget.editable,
          menuBuilder: widget.pdfMenuBuilder,
          scrollController: widget.previewScrollController,
          bare: widget.bare,
        ),
      FilePreviewKind.html => _buildPreviewScaffold(
          _HtmlPreview(
            html: await _readText(maxTextPreviewBytes),
            baseDirectory: widget.file.parent.path,
          ),
        ),
      FilePreviewKind.markdown => _buildPreviewScaffold(
          _MarkdownPreview(
            markdown: await _readText(maxTextPreviewBytes),
            baseDirectory: widget.file.parent.path,
          ),
        ),
      FilePreviewKind.archive => Builder(
          builder: (context) {
            final live = _FilePreviewConfiguration.maybeOf(context) ?? widget;
            return ArchiveExplorer(
              key: ValueKey('${widget.file.path}_archive'),
              file: widget.file,
              name: widget.name,
              editable: live.editable,
              embedded: false,
              metadata: live.metadata,
              onMetadataChanged: live.onMetadataChanged,
              toolbarTrailing: live.toolbarTrailing,
            );
          },
        ),
      FilePreviewKind.csv => _buildPreviewScaffold(
          CsvPreview(
            text: await _readText(maxTextPreviewBytes),
            separator: p.extension(widget.file.path).toLowerCase() == '.tsv'
                ? '\t'
                : ',',
          ),
        ),
      FilePreviewKind.json => _buildPreviewScaffold(
          _TextPreview(
            text: const JsonEncoder.withIndent('  ').convert(
              jsonDecode(await _readText(maxTextPreviewBytes)),
            ),
          ),
        ),
      // A notebook is written, run and re-run cell by cell, so it brings its
      // own surface instead of the shared read-only preview.
      FilePreviewKind.notebook => NotebookView(
          key: ValueKey('${widget.file.path}_notebook'),
          file: widget.file,
          name: widget.name,
          source: await _readText(maxTextPreviewBytes),
          editable: widget.editable,
          toolbarTrailing: widget.toolbarTrailing,
        ),
      FilePreviewKind.code => _CodeFilePreview(
          file: widget.file,
          name: widget.name,
          initialCode: await _readText(maxTextPreviewBytes),
          editable: widget.editable,
          metadata: widget.metadata,
          onMetadataChanged: widget.onMetadataChanged,
          toolbarTrailing: widget.toolbarTrailing,
        ),
      FilePreviewKind.text => _buildPreviewScaffold(
          _TextPreview(
            text: await _readText(maxTextPreviewBytes),
          ),
        ),
    };
  }

  Widget _buildPreviewScaffold(Widget child, {bool writingSurface = false}) {
    if (widget.bare) {
      return DocumentScrollScope(child: child);
    }
    return Builder(
      builder: (context) => DocumentViewport(
        framed: false,
        // Typing happens on the same sheet the header sits on. The viewport's
        // usual canvas is a shade darker, which read as a grey band the
        // moment the editor appeared.
        background: writingSurface
            ? DocumentViewportStyle.of(context).chrome.withValues(alpha: 1)
            : null,
        revealKey: widget.file.path,
        identity: _documentIdentity(),
        actions: [
          if (widget.toolbarTrailing != null) widget.toolbarTrailing!,
        ],
        child: DocumentScrollScope(child: child),
      ),
    );
  }

  /// What the fixed header says about this file.
  DocumentIdentity _documentIdentity() {
    final extension =
        p.extension(widget.name).replaceFirst('.', '').toUpperCase();
    final label = switch (widget.kind) {
      FilePreviewKind.pdf => 'PDF',
      FilePreviewKind.html => 'HTML',
      FilePreviewKind.markdown => 'Markdown',
      FilePreviewKind.archive => 'Archive',
      FilePreviewKind.notebook => 'Notebook',
      FilePreviewKind.json => 'JSON',
      _ => extension.isEmpty ? 'Document' : extension,
    };
    int? size;
    try {
      final stat = widget.file.statSync();
      if (stat.type != FileSystemEntityType.notFound) {
        size = stat.size;
      }
    } on FileSystemException {
      size = null;
    }
    return DocumentIdentity(
      title: widget.name,
      icon: fileIconForName(widget.name),
      subtitle: [
        label,
        if (size != null) _formatBytes(size),
        if (isEditingSource) 'Editing',
      ].join('  ·  '),
    );
  }

  Future<String> _readText(int limit) async {
    final length = await widget.file.length();
    if (length > limit) {
      throw FileSystemException(
        'This file is too large to preview (${_formatBytes(length)}).',
      );
    }
    return widget.file.readAsString();
  }
}

class _MarkdownPreview extends StatefulWidget {
  const _MarkdownPreview({
    required this.markdown,
    required this.baseDirectory,
  });

  final String markdown;
  final String baseDirectory;

  @override
  State<_MarkdownPreview> createState() => _MarkdownPreviewState();
}

class _MarkdownPreviewState extends State<_MarkdownPreview> {
  late String renderedHtml;

  @override
  void initState() {
    super.initState();
    // The bundled faces are read once for the whole application; the first
    // preview to open pays for it and re-renders when they arrive.
    if (markdownPreviewFontFaces == null) {
      unawaited(
        loadMarkdownPreviewFontFaces().then((_) {
          if (mounted) {
            setState(_renderMarkdown);
          }
        }),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _renderMarkdown();
  }

  @override
  void didUpdateWidget(covariant _MarkdownPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.markdown != widget.markdown) {
      _renderMarkdown();
    }
  }

  @override
  Widget build(BuildContext context) {
    return _HtmlPreview(
      html: renderedHtml,
      baseDirectory: widget.baseDirectory,
    );
  }

  void _renderMarkdown() {
    renderedHtml = buildThemedMarkdownPreviewHtml(context, widget.markdown);
  }
}

@visibleForTesting
String buildThemedMarkdownPreviewHtml(
  BuildContext context,
  String source,
) {
  final materialTheme = Theme.of(context);
  final appFlowyTheme = AppFlowyTheme.of(context);
  final isPaper = PaperTheme.isEnabled(context);
  return buildMarkdownPreviewHtml(
    source,
    brightness: materialTheme.brightness,
    backgroundColor: EditorSurfaceStyle.previewBackgroundFor(
      materialTheme.brightness,
      appFlowyTheme.surfaceColorScheme.layer01,
      isPaper: isPaper,
    ),
    textColor: appFlowyTheme.textColorScheme.primary,
    linkColor: materialTheme.colorScheme.primary,
    borderColor: appFlowyTheme.borderColorScheme.primary,
    codeBackground: EditorSurfaceStyle.codeBlockBackgroundFor(
      materialTheme.brightness,
      materialTheme.colorScheme.surfaceContainer,
      isPaper: isPaper,
    ),
    fontFaces: markdownPreviewFontFaces ?? '',
  );
}

String buildMarkdownPreviewHtml(
  String source, {
  required Brightness brightness,
  required Color backgroundColor,
  required Color textColor,
  required Color linkColor,
  required Color borderColor,
  required Color codeBackground,
  String fontFaces = '',
}) {
  final body = markdown.markdownToHtml(
    source,
    extensionSet: markdown.ExtensionSet.gitHubFlavored,
    encodeHtml: false,
    enableTagfilter: true,
  );
  return '''
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
$fontFaces
  :root {
    color-scheme: ${_cssColorScheme(brightness)};
    --rule: ${_cssRgba(borderColor.withValues(alpha: 0.22))};
    --rule-strong: ${_cssRgba(borderColor.withValues(alpha: 0.32))};
    --muted: ${_cssRgba(textColor.withValues(alpha: 0.6))};
  }
  * { box-sizing: border-box; }
  html { background: ${_cssColor(backgroundColor)}; }
  body {
    margin: 0;
    padding: 32px 36px 40px;
    color: ${_cssColor(textColor)};
    background: ${_cssColor(backgroundColor)};
    font-family: "$previewUiFontFamily", "Segoe UI Variable Text", "Segoe UI",
      -apple-system, BlinkMacSystemFont, "Inter", "Helvetica Neue", Arial,
      sans-serif;
    font-size: 14.5px;
    line-height: 1.65;
    overflow-wrap: anywhere;
    -webkit-font-smoothing: antialiased;
    -moz-osx-font-smoothing: grayscale;
    text-rendering: optimizeLegibility;
    font-feature-settings: "kern" 1, "liga" 1;
  }
  h1, h2, h3, h4, h5, h6 {
    margin: 28px 0 14px;
    font-weight: 600;
    line-height: 1.3;
    letter-spacing: -0.014em;
  }
  h1 { font-size: 1.7em; }
  h2 { font-size: 1.32em; }
  h3 { font-size: 1.12em; }
  h4 { font-size: 1em; }
  h5, h6 { font-size: 0.92em; color: var(--muted); }
  /* A hairline, the way GitHub sets it — never a drawn border. */
  h1, h2 { padding-bottom: 0.32em; border-bottom: 1px solid var(--rule); }
  body > *:first-child { margin-top: 0; }
  p { margin: 0 0 14px; }
  a { color: ${_cssColor(linkColor)}; text-decoration: none; }
  a:hover { text-decoration: underline; }
  img { max-width: 100%; height: auto; border-radius: 6px; }
  ul, ol { margin: 0 0 14px; padding-left: 26px; }
  li { margin: 0.25em 0; }
  li > ul, li > ol { margin: 0.25em 0; }
  pre, code {
    background: ${_cssColor(codeBackground)};
    font-family: "$previewCodeFontFamily", "JetBrains Mono", "Geist Mono",
      "Cascadia Mono", Consolas, monospace;
    font-size: 0.88em;
  }
  code { padding: 0.16em 0.4em; border-radius: 5px; }
  pre {
    padding: 14px 16px;
    margin: 0 0 16px;
    border-radius: 10px;
    overflow-x: auto;
    overflow-y: hidden;
    line-height: 1.55;
  }
  pre code { padding: 0; background: transparent; font-size: 1em; }
  blockquote {
    margin: 0 0 14px;
    padding: 2px 0 2px 14px;
    color: var(--muted);
    border-left: 3px solid var(--rule-strong);
  }
  table {
    border-collapse: separate;
    border-spacing: 0;
    max-width: 100%;
    margin: 0 0 16px;
    border: 1px solid var(--rule);
    border-radius: 8px;
    overflow: hidden;
  }
  th, td { padding: 7px 13px; border-bottom: 1px solid var(--rule); }
  th { text-align: left; font-weight: 600; background: ${_cssColor(codeBackground)}; }
  tr:last-child td { border-bottom: 0; }
  hr { border: 0; border-top: 1px solid var(--rule); margin: 24px 0; }
  kbd {
    padding: 2px 6px;
    border-radius: 5px;
    border: 1px solid var(--rule-strong);
    font-size: 0.85em;
  }
</style>
</head>
<body>$body</body>
</html>
''';
}

String _cssColor(Color color) =>
    '#${_cssChannel(color.r)}${_cssChannel(color.g)}${_cssChannel(color.b)}';

String _cssChannel(double value) =>
    (value * 255).round().toRadixString(16).padLeft(2, '0');

String _cssRgba(Color color) => 'rgba(${(color.r * 255).round()}, '
    '${(color.g * 255).round()}, '
    '${(color.b * 255).round()}, '
    '${color.a.toStringAsFixed(3)})';

/// Keeps the renderer's user-agent surfaces aligned with the AppFlowy theme
/// instead of the operating system appearance.
String _cssColorScheme(Brightness brightness) =>
    brightness == Brightness.dark ? 'dark' : 'light';

const _htmlPreviewContentSecurityPolicy = "script-src 'none'; "
    "connect-src 'none'; "
    "object-src 'none'; "
    "frame-src 'none'; "
    "worker-src 'none'; "
    "base-uri 'none'; "
    "form-action 'none'";

/// Applied to the document element while the preview is scrolling so the
/// renderer only reveals its scrollbar thumbs during movement.
const htmlPreviewScrollingClassName = 'appflowy-preview-scrolling';

@visibleForTesting
const htmlPreviewScrollbarIdleDelay = Duration(milliseconds: 700);

const _defaultPreviewScrollbarThumbColor = Color(0x5C000000);

@visibleForTesting
String buildHtmlPreviewStabilityCss({
  required Brightness brightness,
  required Color scrollbarThumbColor,
  required bool autoHideScrollbars,
}) =>
    '''
:root {
  color-scheme: ${_cssColorScheme(brightness)};
  overflow-anchor: none !important;
  scroll-behavior: auto !important;
  scrollbar-gutter: stable;
}
html, body {
  overflow-anchor: none !important;
  scroll-behavior: auto !important;
}
pre {
  max-width: 100%;
  overscroll-behavior-x: contain;
}
${autoHideScrollbars ? _autoHidingScrollbarCss(scrollbarThumbColor) : ''}''';

/// Overlay-style scrollbars that stay transparent until
/// [buildHtmlPreviewScrollbarAutoHideScript] marks the document as scrolling.
String _autoHidingScrollbarCss(Color thumbColor) => '''
::-webkit-scrollbar {
  width: 12px;
  height: 12px;
  background: transparent;
}
::-webkit-scrollbar-track, ::-webkit-scrollbar-corner {
  background: transparent;
}
::-webkit-scrollbar-thumb {
  background-color: transparent;
  background-clip: padding-box;
  border: 4px solid transparent;
  border-radius: 999px;
  transition: background-color 160ms ease;
}
html.$htmlPreviewScrollingClassName::-webkit-scrollbar-thumb,
html.$htmlPreviewScrollingClassName ::-webkit-scrollbar-thumb {
  background-color: ${_cssRgba(thumbColor)};
}
''';

/// Reveals the preview scrollbars while the document scrolls and hides them
/// again once movement stops.
String buildHtmlPreviewScrollbarAutoHideScript() => '''
(function () {
  const root = document.documentElement;
  if (!root) {
    return;
  }
  const installed = globalThis.__appflowyPreviewScrollbarRoot;
  if (installed === root) {
    return;
  }
  globalThis.__appflowyPreviewScrollbarRoot = root;
  let timer = 0;
  const reveal = function () {
    root.classList.add('$htmlPreviewScrollingClassName');
    if (timer) {
      clearTimeout(timer);
    }
    timer = setTimeout(function () {
      timer = 0;
      root.classList.remove('$htmlPreviewScrollingClassName');
    }, ${htmlPreviewScrollbarIdleDelay.inMilliseconds});
  };
  document.addEventListener(
    'scroll',
    reveal,
    { capture: true, passive: true },
  );
})();
''';

const _blockedPreviewElements = {
  'animate',
  'animatemotion',
  'animatetransform',
  'applet',
  'base',
  'embed',
  'frame',
  'frameset',
  'iframe',
  'object',
  'script',
  'set',
};

const _previewUrlAttributes = {
  'action',
  'background',
  'cite',
  'data',
  'formaction',
  'href',
  'poster',
  'src',
  'usemap',
  'xlink:href',
};

/// Produces a static, scriptless document before JavaScript is enabled for the
/// isolated host scrolling runtime.
@visibleForTesting
String prepareHtmlPreviewDocument(
  String source, {
  Brightness brightness = Brightness.light,
  Color scrollbarThumbColor = _defaultPreviewScrollbarThumbColor,
  bool autoHideScrollbars = true,
}) {
  final document = html_parser.parse(source);
  for (final element in document.querySelectorAll('*').toList()) {
    final tag = element.localName;
    if (tag != null && _blockedPreviewElements.contains(tag)) {
      element.remove();
      continue;
    }
    if (tag == 'meta') {
      final directive = element.attributes['http-equiv']?.trim().toLowerCase();
      if (directive == 'refresh' || directive == 'content-security-policy') {
        element.remove();
        continue;
      }
    }
    if (tag == 'link') {
      final rel = element.attributes['rel']
          ?.toLowerCase()
          .split(RegExp(r'\s+'))
          .where((value) => value.isNotEmpty)
          .toSet();
      if (rel == null ||
          !rel.any(const {'stylesheet', 'icon', 'shortcut'}.contains)) {
        element.remove();
        continue;
      }
    }

    for (final key in element.attributes.keys.toList()) {
      final name = key is html_dom.AttributeName
          ? key.name.toLowerCase()
          : key.toString().toLowerCase();
      final qualifiedName = key.toString().toLowerCase();
      final value = element.attributes[key] ?? '';
      if (name.startsWith('on') ||
          name == 'srcdoc' ||
          name == 'ping' ||
          name == 'target' ||
          name == 'autofocus' ||
          name == 'autoplay') {
        element.attributes.remove(key);
      } else if (name == 'style' && _containsUnsafeCss(value)) {
        element.attributes.remove(key);
      } else if ((tag == 'a' || tag == 'area') &&
          name == 'href' &&
          !value.trim().startsWith('#')) {
        element.attributes.remove(key);
      } else if ((_previewUrlAttributes.contains(name) ||
              _previewUrlAttributes.contains(qualifiedName)) &&
          !_isSafePreviewUrl(
            value,
            allowData: _allowsDataUrl(element, name),
          )) {
        element.attributes.remove(key);
      }
    }

    if (tag == 'img') {
      element.attributes['loading'] = 'eager';
      element.attributes['decoding'] = 'sync';
    }
  }

  final head = document.head;
  if (head == null) {
    throw const FormatException('Unable to prepare the HTML preview document.');
  }
  head.nodes.insert(
    0,
    html_dom.Element.tag('meta')
      ..attributes['http-equiv'] = 'Content-Security-Policy'
      ..attributes['content'] = _htmlPreviewContentSecurityPolicy,
  );
  head.append(
    html_dom.Element.tag('style')
      ..attributes['data-appflowy-preview-stability'] = ''
      ..text = buildHtmlPreviewStabilityCss(
        brightness: brightness,
        scrollbarThumbColor: scrollbarThumbColor,
        autoHideScrollbars: autoHideScrollbars,
      ),
  );
  return '<!doctype html>\n${document.documentElement!.outerHtml}';
}

bool _containsUnsafeCss(String value) {
  final normalized = value.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  return normalized.contains('expression(') ||
      normalized.contains('javascript:') ||
      normalized.contains('vbscript:') ||
      normalized.contains('-moz-binding') ||
      normalized.contains('data:text/html');
}

bool _allowsDataUrl(html_dom.Element element, String attributeName) {
  return (attributeName == 'src' || attributeName == 'poster') &&
      const {'audio', 'img', 'source', 'video'}.contains(element.localName);
}

bool _isSafePreviewUrl(String value, {required bool allowData}) {
  final normalized = value.trim().replaceAll(RegExp(r'[\u0000-\u0020]'), '');
  if (normalized.isEmpty || normalized.startsWith('#')) {
    return true;
  }
  if (normalized.startsWith('//') || normalized.startsWith(r'\\')) {
    return false;
  }
  final uri = Uri.tryParse(normalized);
  if (uri == null || !uri.hasScheme) {
    return true;
  }
  final scheme = uri.scheme.toLowerCase();
  if (const {'file', 'http', 'https'}.contains(scheme)) {
    return true;
  }
  return allowData &&
      scheme == 'data' &&
      RegExp(
        '^data:(?:image/(?:avif|bmp|gif|jpeg|png|webp)|'
        'audio/|video/)',
        caseSensitive: false,
      ).hasMatch(normalized);
}

class _CodeFilePreview extends StatefulWidget {
  const _CodeFilePreview({
    required this.file,
    required this.name,
    required this.initialCode,
    required this.editable,
    required this.metadata,
    required this.onMetadataChanged,
    this.toolbarTrailing,
  });

  final File file;
  final String name;
  final String initialCode;
  final bool editable;
  final Map<String, dynamic> metadata;
  final ValueChanged<Map<String, dynamic>> onMetadataChanged;
  final Widget? toolbarTrailing;

  @override
  State<_CodeFilePreview> createState() => _CodeFilePreviewState();
}

class _CodeFilePreviewState extends State<_CodeFilePreview> {
  FilePreview? _configuration;
  Map<String, dynamic>? _incomingMetadata;
  late Map<String, dynamic> _metadata = Map.of(widget.metadata);
  late String code = widget.initialCode;
  late String language = normalizeCodeLanguage(
    widget.metadata['code_language'] as String? ??
        codeLanguageForName(widget.name),
  );
  late bool showLineNumbers =
      widget.metadata['show_code_line_numbers'] as bool? ?? true;
  late List<CodeTestCase> testCases =
      decodeCodeTestCases(widget.metadata['code_test_cases']);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configuration = _FilePreviewConfiguration.maybeOf(context);
    final incoming =
        StandaloneFileScope.forName(context, widget.name)?.metadata ??
            _configuration?.metadata ??
            widget.metadata;
    if (!mapEquals(_incomingMetadata, incoming)) {
      _incomingMetadata = Map.of(incoming);
      _metadata = Map.of(incoming);
      language = normalizeCodeLanguage(
        incoming['code_language'] as String? ??
            codeLanguageForName(widget.name),
      );
      showLineNumbers = incoming['show_code_line_numbers'] as bool? ?? true;
      testCases = decodeCodeTestCases(incoming['code_test_cases']);
    }
  }

  void _storeSetting(String key, dynamic value) {
    // Each activation starts from the last choice, not the loader's snapshot.
    // Hosts are allowed to persist asynchronously or omit an immediate echo.
    _metadata = {..._metadata, key: value};
    (_configuration?.onMetadataChanged ?? widget.onMetadataChanged)(
      Map.of(_metadata),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editable = _configuration?.editable ?? widget.editable;
    return SandboxedCodeRunner(
      code: code,
      fileName: fileNameForCodeLanguage(language),
      displayName: widget.name,
      language: language,
      showLineNumbers: showLineNumbers,
      onLanguageChanged: (value) {
        final normalizedLanguage = normalizeCodeLanguage(value);
        setState(() => language = normalizedLanguage);
        _storeSetting('code_language', normalizedLanguage);
      },
      onToggleLineNumbers: () {
        setState(() => showLineNumbers = !showLineNumbers);
        _storeSetting('show_code_line_numbers', showLineNumbers);
      },
      editable: editable,
      testCases: testCases,
      onTestCasesChanged: (cases) {
        setState(() => testCases = cases);
        _storeSetting('code_test_cases', encodeCodeTestCases(cases));
      },
      toolbarTrailing:
          _configuration?.toolbarTrailing ?? widget.toolbarTrailing,
      expandEditor: true,
      framed: false,
      child: _EditableCodeFile(
        file: widget.file,
        initialCode: widget.initialCode,
        editable: editable,
        language: language,
        showLineNumbers: showLineNumbers,
        onChanged: (value) => setState(() => code = value),
      ),
    );
  }
}

class _EditableCodeFile extends StatefulWidget {
  const _EditableCodeFile({
    required this.file,
    required this.initialCode,
    required this.editable,
    required this.language,
    required this.showLineNumbers,
    required this.onChanged,
    this.surfaceColor,
  });

  final File file;
  final String initialCode;
  final bool editable;
  final String language;
  final bool showLineNumbers;
  final ValueChanged<String> onChanged;

  /// What to paint behind the code. Defaults to the code shell's own surface;
  /// pass a transparent colour to let the host's page show through.
  final Color? surfaceColor;

  @override
  State<_EditableCodeFile> createState() => _EditableCodeFileState();
}

class _EditableCodeFileState extends State<_EditableCodeFile> {
  final scrollControllers = LinkedScrollControllerGroup();
  late final codeScrollController = scrollControllers.addAndGet();
  late final lineNumberScrollController = scrollControllers.addAndGet();
  late final controller = _CodeFileEditingController(
    text: widget.initialCode,
    language: widget.language,
  );
  final findSession = TextFindSession();
  final codeFieldKey = GlobalKey();
  final codeFocusNode = FocusNode();
  bool findVisible = false;
  bool _active = true;
  Timer? saveTimer;

  @override
  void initState() {
    super.initState();
    findSession
      ..setText(widget.initialCode)
      ..addListener(_onFindChanged);
  }

  @override
  void didUpdateWidget(covariant _EditableCodeFile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.language != widget.language) {
      controller.updateLanguage(widget.language);
    }
  }

  @override
  void deactivate() {
    _active = false;
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _active = true;
  }

  @override
  void dispose() {
    _flushPendingSave();
    findSession
      ..removeListener(_onFindChanged)
      ..dispose();
    codeFocusNode.dispose();
    codeScrollController.dispose();
    lineNumberScrollController.dispose();
    controller.dispose();
    super.dispose();
  }

  /// Commits the debounced edit before the editor goes away.
  ///
  /// Leaving edit mode rebuilds the preview from disk, so an in-flight save
  /// would otherwise be dropped and the last keystrokes lost.
  void _flushPendingSave() {
    if (saveTimer?.isActive ?? false) {
      saveTimer!.cancel();
      try {
        widget.file.writeAsStringSync(controller.text, flush: true);
      } on FileSystemException catch (error, stackTrace) {
        Log.error('Failed to save the edited file', error, stackTrace);
      }
    }
    saveTimer = null;
  }

  /// Opens the find bar, seeded with whatever is selected, the way an editor
  /// does. Ctrl+H opens it with the replace row already showing.
  void _openFind({bool replace = false}) {
    if (!mounted || !_active) {
      return;
    }
    final selection = controller.selection;
    final selected = selection.isValid && !selection.isCollapsed
        ? selection.textInside(controller.text)
        : '';
    setState(() => findVisible = true);
    if (selected.isNotEmpty && !selected.contains('\n')) {
      findSession.findController.text = selected;
    }
    findSession
      ..replaceVisible = replace && widget.editable
      ..setText(
        controller.text,
        caret: selection.isValid ? selection.start : 0,
        keepPosition: false,
      );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_active || !findVisible) {
        return;
      }
      final node = replace && widget.editable
          ? findSession.replaceFocusNode
          : findSession.findFocusNode;
      node.requestFocus();
      findSession.findController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: findSession.findController.text.length,
      );
    });
  }

  void _closeFind({bool restoreFocus = true}) {
    if (!mounted || !_active || !findVisible) {
      return;
    }
    setState(() => findVisible = false);
    controller.updateFindHighlights(const [], null);
    if (restoreFocus) codeFocusNode.requestFocus();
  }

  void _onFindChanged() {
    if (!mounted || !_active) {
      return;
    }
    controller.updateFindHighlights(
      findVisible ? findSession.ranges : const [],
      findVisible ? findSession.currentRange : null,
    );
    setState(() {});
    if (findVisible) _revealCurrentMatch();
  }

  void _revealCurrentMatch() {
    final match = findSession.currentMatch;
    if (match == null) {
      return;
    }
    // The caret follows the match so closing the bar leaves the cursor where
    // the reader was looking.
    controller.selection = TextSelection(
      baseOffset: match.start,
      extentOffset: match.end,
    );
    _scrollToOffset(match.start);
  }

  /// Brings a character offset into view.
  ///
  /// A programmatic selection change does not scroll a text field, so the line
  /// is measured with the same layout the field uses and the scroll position
  /// is set directly.
  void _scrollToOffset(int offset) {
    final renderObject = codeFieldKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.hasSize ||
        !codeScrollController.hasClients) {
      return;
    }
    final width = renderObject.size.width - _codeFileContentInset * 2;
    if (width <= 0) {
      return;
    }
    final painter = TextPainter(
      text: controller.buildTextSpan(
        context: context,
        style: _codeFileTextStyle(
          AppFlowyTheme.of(context).textColorScheme.primary,
        ),
        withComposing: false,
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width);
    final dy =
        painter.getOffsetForCaret(TextPosition(offset: offset), Rect.zero).dy;
    painter.dispose();
    final position = codeScrollController.position;
    final target = dy + _codeFileContentInset - position.viewportDimension / 3;
    codeScrollController.jumpTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
  }

  void _replaceCurrent() {
    if (!widget.editable) return;
    final replaced = findSession.replaceCurrent();
    if (replaced != null) {
      _applyText(replaced);
    }
  }

  void _replaceAll() {
    if (!widget.editable) return;
    final replaced = findSession.replaceAll();
    if (replaced != null) {
      _applyText(replaced);
    }
  }

  /// Writes a rewritten file back through the same path an edit takes, so the
  /// host and the debounced save both see it.
  void _applyText(String value) {
    final caret = controller.selection.baseOffset.clamp(0, value.length);
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: caret),
    );
    widget.onChanged(value);
    findSession.setText(value, keepPosition: false);
    _scheduleSave(value);
    setState(() {});
  }

  void _scheduleSave(String value) {
    saveTimer?.cancel();
    saveTimer = Timer(
      const Duration(milliseconds: 400),
      () => widget.file.writeAsString(value, flush: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lineCount = '\n'.allMatches(controller.text).length + 1;
    final appFlowyTheme = AppFlowyTheme.of(context);
    // The same surface the code chrome uses, so the card stays uniform.
    final surfaceColor = widget.surfaceColor ?? codeBlockSurfaceColor(context);
    // The gutter and the code must share one metric, otherwise the numbers
    // drift away from their lines as the file grows.
    final codeStyle = _codeFileTextStyle(
      appFlowyTheme.textColorScheme.primary,
    );
    final gutterStyle = _codeFileTextStyle(
      appFlowyTheme.textColorScheme.tertiary,
    );
    final content = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _openFind,
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _openFind,
        if (widget.editable) ...{
          const SingleActivator(LogicalKeyboardKey.keyH, control: true): () =>
              _openFind(replace: true),
          const SingleActivator(LogicalKeyboardKey.keyH, meta: true): () =>
              _openFind(replace: true),
        },
        const SingleActivator(LogicalKeyboardKey.f3): findSession.next,
        const SingleActivator(LogicalKeyboardKey.f3, shift: true):
            findSession.previous,
      },
      child: ColoredBox(
        color: surfaceColor,
        child: Stack(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.showLineNumbers)
                  Container(
                    width: 26 + '$lineCount'.length * 9,
                    // The gutter is told apart by its muted numbers and the
                    // space beside them; a drawn rule reads as a table border.
                    color: surfaceColor,
                    child: SingleChildScrollView(
                      controller: lineNumberScrollController,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(top: 12, right: 8),
                      child: Text(
                        List.generate(lineCount, (index) => '${index + 1}')
                            .join('\n'),
                        textAlign: TextAlign.right,
                        style: gutterStyle,
                      ),
                    ),
                  ),
                Expanded(
                  child: TextField(
                    key: codeFieldKey,
                    controller: controller,
                    focusNode: codeFocusNode,
                    scrollController: codeScrollController,
                    readOnly: !widget.editable,
                    expands: true,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    style: codeStyle,
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.all(_codeFileContentInset),
                      border: InputBorder.none,
                      // The surrounding box already paints the sheet. A filled
                      // field would blend Material's hover colour over it and
                      // grey the whole editor out under the pointer.
                      filled: false,
                      hoverColor: Colors.transparent,
                    ),
                    onChanged: (value) {
                      setState(() {});
                      widget.onChanged(value);
                      findSession.setText(
                        value,
                        caret: controller.selection.start,
                      );
                      _scheduleSave(value);
                    },
                  ),
                ),
              ],
            ),
            if (findVisible)
              Positioned(
                top: 8,
                left: 16,
                right: 16,
                child: Align(
                  alignment: Alignment.topRight,
                  child: FindReplaceBar(
                    findController: findSession.findController,
                    findFocusNode: findSession.findFocusNode,
                    options: findSession.options,
                    onOptionsChanged: (value) => findSession.options = value,
                    matchCount: findSession.matches.length,
                    currentMatch: findSession.displayIndex,
                    queryInvalid: findSession.invalid,
                    onPrevious: findSession.matches.isEmpty
                        ? null
                        : findSession.previous,
                    onNext:
                        findSession.matches.isEmpty ? null : findSession.next,
                    onClose: _closeFind,
                    onTapOutside: () => _closeFind(restoreFocus: false),
                    replaceController:
                        widget.editable ? findSession.replaceController : null,
                    replaceFocusNode: findSession.replaceFocusNode,
                    showReplace: findSession.replaceVisible,
                    onToggleReplace: () => findSession.replaceVisible =
                        !findSession.replaceVisible,
                    onReplace: _replaceCurrent,
                    onReplaceAll: _replaceAll,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    return ContextualFindRegion(
      debugLabel: 'File source',
      findInEditable: true,
      onFind: _openFind,
      onReplace: widget.editable ? () => _openFind(replace: true) : null,
      onDismiss: () => _closeFind(restoreFocus: false),
      findOpen: findVisible,
      findFocusNode: findSession.findFocusNode,
      child: content,
    );
  }
}

/// The inset the source editor prints its text at. Shared with the scroll
/// measurement, which has to reproduce the field's own layout.
const _codeFileContentInset = 12.0;

/// One metric for the code column and its line numbers.
///
/// Both must use the same size and line height or the gutter slowly slips out
/// of step with the code it is numbering.
TextStyle _codeFileTextStyle(Color color) => getGoogleFontSafely(
      'JetBrains Mono',
      fontSize: 15,
      fontWeight: FontWeight.w500,
      fontColor: color,
      lineHeight: 1.6,
    ).copyWith(
      fontFamilyFallback: const [
        'Geist Mono',
        'RobotoMono',
        'monospace',
      ],
    );

class _CodeFileEditingController extends TextEditingController {
  _CodeFileEditingController({
    required super.text,
    required String language,
  }) : language = normalizeCodeLanguage(language);

  String language;

  List<TextRange> findRanges = const [];
  TextRange? currentFindRange;

  void updateLanguage(String value) {
    language = normalizeCodeLanguage(value);
    notifyListeners();
  }

  /// Marks what the open search found, so every hit is visible at once
  /// instead of only the one being read.
  void updateFindHighlights(List<TextRange> ranges, TextRange? current) {
    findRanges = ranges;
    currentFindRange = current;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final span = buildSyntaxHighlightedTextSpan(
      code: text,
      language: language,
      brightness: Theme.of(context).brightness,
      isPaper: PaperTheme.isEnabled(context),
      style: style,
    );
    if (findRanges.isEmpty) {
      return span;
    }
    final brightness = Theme.of(context).brightness;
    return applyFindHighlights(
      span,
      ranges: findRanges,
      current: currentFindRange,
      matchStyle: TextStyle(
        backgroundColor: FindHighlightColors.match(brightness),
      ),
      currentStyle: TextStyle(
        backgroundColor: FindHighlightColors.current(brightness),
      ),
    );
  }
}

class _TextPreview extends StatefulWidget {
  const _TextPreview({required this.text});

  final String text;

  @override
  State<_TextPreview> createState() => _TextPreviewState();
}

class _TextPreviewState extends State<_TextPreview> {
  static const _padding = 16.0;

  final findSession = TextFindSession();
  final scrollController = ScrollController();
  final contentKey = GlobalKey();
  final focusNode = FocusNode();
  final selectableFocusNode = FocusNode(skipTraversal: true);
  TextSelection? _selectionBeforeFind;
  bool findVisible = false;
  bool _active = true;

  @override
  void initState() {
    super.initState();
    findSession
      ..setText(widget.text)
      ..addListener(_onFindChanged);
  }

  @override
  void didUpdateWidget(covariant _TextPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _selectionBeforeFind = null;
      findSession.setText(widget.text);
    }
  }

  @override
  void deactivate() {
    _active = false;
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _active = true;
  }

  @override
  void dispose() {
    findSession
      ..removeListener(_onFindChanged)
      ..dispose();
    scrollController.dispose();
    focusNode.dispose();
    selectableFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    // SelectableText replaces its native controller when textSpan changes,
    // even when only a highlight colour changed. Keep its text independent of
    // find and paint the matches against the actual native layout instead.
    final span = TextSpan(
      text: widget.text,
      style: const TextStyle(fontFamily: 'monospace', height: 1.4),
    );
    final content = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _openFind,
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _openFind,
        const SingleActivator(LogicalKeyboardKey.f3): findSession.next,
        const SingleActivator(LogicalKeyboardKey.f3, shift: true):
            findSession.previous,
      },
      child: Focus(
        focusNode: focusNode,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          // Reading is the point here, so the pane only claims the keyboard
          // once somebody has actually clicked into it.
          onPointerDown: (_) => focusNode.requestFocus(),
          child: Stack(
            children: [
              SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.all(_padding),
                child: CustomPaint(
                  painter: _TextPreviewFindPainter(
                    contentKey: contentKey,
                    ranges: findVisible ? findSession.ranges : const [],
                    current: findVisible ? findSession.currentRange : null,
                    matchColor: FindHighlightColors.match(brightness),
                    currentColor: FindHighlightColors.current(brightness),
                  ),
                  child: SelectableText.rich(
                    span,
                    key: contentKey,
                    focusNode: selectableFocusNode,
                  ),
                ),
              ),
              if (findVisible)
                Positioned(
                  top: 8,
                  left: 16,
                  right: 16,
                  child: Align(
                    alignment: Alignment.topRight,
                    child: FindReplaceBar(
                      findController: findSession.findController,
                      findFocusNode: findSession.findFocusNode,
                      options: findSession.options,
                      onOptionsChanged: (value) => findSession.options = value,
                      matchCount: findSession.matches.length,
                      currentMatch: findSession.displayIndex,
                      queryInvalid: findSession.invalid,
                      onPrevious: findSession.matches.isEmpty
                          ? null
                          : findSession.previous,
                      onNext:
                          findSession.matches.isEmpty ? null : findSession.next,
                      onClose: _closeFind,
                      onTapOutside: () => _closeFind(restoreFocus: false),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return ContextualFindRegion(
      debugLabel: 'File text',
      findInEditable: true,
      onFind: _openFind,
      onDismiss: () => _closeFind(restoreFocus: false),
      findOpen: findVisible,
      findFocusNode: findSession.findFocusNode,
      child: content,
    );
  }

  void _openFind() {
    if (!mounted || !_active) return;
    if (!findVisible) {
      _selectionBeforeFind = _textPreviewEditable(
        contentKey.currentContext?.findRenderObject(),
      )?.textSelectionDelegate.textEditingValue.selection;
    }
    setState(() => findVisible = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_active || !findVisible) {
        return;
      }
      findSession.findFocusNode.requestFocus();
      findSession.findController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: findSession.findController.text.length,
      );
    });
  }

  void _closeFind({bool restoreFocus = true}) {
    if (!mounted || !_active || !findVisible) {
      return;
    }
    final selection = _selectionBeforeFind;
    _selectionBeforeFind = null;
    setState(() => findVisible = false);
    if (!restoreFocus) return;

    // Native SelectableText clears its selection on blur. Restore it only on
    // an explicit return from find, never over a user's outside click. Repeated
    // Ctrl+F must not replace the saved range with the query's selection.
    final editable = _textPreviewEditable(
      contentKey.currentContext?.findRenderObject(),
    );
    if (editable != null &&
        selection != null &&
        selection.isValid &&
        selection.end <= widget.text.length) {
      selectableFocusNode.requestFocus();
      final delegate = editable.textSelectionDelegate;
      delegate.userUpdateTextEditingValue(
        delegate.textEditingValue.copyWith(selection: selection),
        SelectionChangedCause.keyboard,
      );
    } else {
      focusNode.requestFocus();
    }
  }

  void _onFindChanged() {
    if (!mounted || !_active) {
      return;
    }
    setState(() {});
    final match = findSession.currentMatch;
    if (findVisible && match != null) {
      _scrollToOffset(match.start);
    }
  }

  void _scrollToOffset(int offset) {
    final renderObject = contentKey.currentContext?.findRenderObject();
    final editable = _textPreviewEditable(renderObject);
    if (renderObject == null ||
        editable == null ||
        !editable.hasSize ||
        !scrollController.hasClients) {
      return;
    }
    final caret = editable.getLocalRectForCaret(TextPosition(offset: offset));
    final dy = editable.localToGlobal(caret.topLeft, ancestor: renderObject).dy;
    final position = scrollController.position;
    final target = dy + _padding - position.viewportDimension / 3;
    scrollController.jumpTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
  }
}

/// Uses the public native renderer, without depending on SelectableText's
/// private State/controller or substituting a different text widget.
RenderEditable? _textPreviewEditable(RenderObject? root) {
  if (root is RenderEditable) return root;
  RenderEditable? result;
  root?.visitChildren((child) => result ??= _textPreviewEditable(child));
  return result;
}

class _TextPreviewFindPainter extends CustomPainter {
  const _TextPreviewFindPainter({
    required this.contentKey,
    required this.ranges,
    required this.current,
    required this.matchColor,
    required this.currentColor,
  });

  final GlobalKey contentKey;
  final List<TextRange> ranges;
  final TextRange? current;
  final Color matchColor;
  final Color currentColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (ranges.isEmpty) return;
    final content = contentKey.currentContext?.findRenderObject();
    final editable = _textPreviewEditable(content);
    if (content == null || editable == null || !editable.hasSize) return;
    canvas
      ..save()
      ..clipRect(Offset.zero & size)
      ..transform(editable.getTransformTo(content).storage);
    final paint = Paint();
    for (final range in ranges) {
      paint.color = range == current ? currentColor : matchColor;
      for (final box in editable.getBoxesForSelection(
        TextSelection(baseOffset: range.start, extentOffset: range.end),
      )) {
        canvas.drawRect(box.toRect(), paint);
      }
    }
    canvas.restore();
  }

  @override
  bool hitTest(Offset position) => false;

  // Inherited typography/scale can change native geometry even when the
  // ranges and highlight colours are unchanged.
  @override
  bool shouldRepaint(_TextPreviewFindPainter oldDelegate) => true;
}

class _HtmlPreview extends StatefulWidget {
  const _HtmlPreview({
    required this.html,
    required this.baseDirectory,
  });

  final String html;
  final String baseDirectory;

  @override
  State<_HtmlPreview> createState() => _HtmlPreviewState();
}

final htmlPreviewScrollContentWorld =
    ContentWorld.world(name: 'appflowyDocumentScroll');

class _HtmlPreviewState extends State<_HtmlPreview> {
  InAppWebViewController? webViewController;
  final List<_PendingWebViewScrollCommand> pendingScrollCommands = [];
  final webViewViewportKey = GlobalKey();
  final findController = TextEditingController();
  final findFocusNode = FocusNode();
  final previewFocusNode = FocusNode();
  final findSession = WebViewFindSession();
  FindOptions findOptions = const FindOptions();
  WebViewFindResult findResult = WebViewFindResult.empty;
  Timer? findDebounce;
  bool findVisible = false;
  bool _active = true;
  late String preparedHtml;
  HtmlPreviewResourceHost? resourceHost;
  Future<Uri>? documentUrl;
  Brightness? documentBrightness;
  Color? documentScrollbarThumbColor;
  PremiumScrollPhysicsConfig physicsConfig = const PremiumScrollPhysicsConfig();
  bool smoothScrollingEnabled = true;
  bool scrollReady = false;
  bool scrollOperationInFlight = false;
  bool rendererScrollAvailable = false;
  Future<void>? rendererScrollInitialization;
  int documentRevision = 0;
  VelocityTracker? trackpadVelocityTracker;

  @override
  void initState() {
    super.initState();
    findController.addListener(_scheduleFind);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reducedMotion = MediaQuery.maybeOf(context)?.disableAnimations ??
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures
            .disableAnimations;
    final behavior = ScrollConfiguration.of(context);
    final nextSmoothScrollingEnabled = behavior is PremiumScrollBehavior
        ? behavior.kineticEnabled
        : !reducedMotion;
    final nextPhysicsConfig = behavior is PremiumScrollBehavior
        ? behavior.config
        : const PremiumScrollPhysicsConfig();
    final shouldReinstallEngine = nextPhysicsConfig != physicsConfig;
    final shouldStopMomentum =
        smoothScrollingEnabled && !nextSmoothScrollingEnabled;
    smoothScrollingEnabled = nextSmoothScrollingEnabled;
    physicsConfig = nextPhysicsConfig;
    if (scrollReady && (shouldReinstallEngine || shouldStopMomentum)) {
      _queueRendererCommand(
        shouldReinstallEngine
            ? buildPremiumKineticScrollEngineScript(config: physicsConfig)
            : buildPremiumKineticStopCommand(),
      );
    }
    _syncDocumentWithTheme();
  }

  @override
  void didUpdateWidget(covariant _HtmlPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.baseDirectory != widget.baseDirectory) {
      unawaited(resourceHost?.dispose());
      resourceHost = null;
    }
    if (oldWidget.html != widget.html ||
        oldWidget.baseDirectory != widget.baseDirectory) {
      _reloadDocument();
    }
  }

  /// Keeps the renderer aligned with the AppFlowy appearance so previews never
  /// fall back to the operating system light/dark surfaces.
  void _syncDocumentWithTheme() {
    final materialTheme = Theme.of(context);
    final brightness = materialTheme.brightness;
    final scrollbarThumbColor =
        materialTheme.scrollbarTheme.thumbColor?.resolve(const {}) ??
            materialTheme.colorScheme.onSurface.withValues(alpha: 0.36);
    if (documentBrightness == brightness &&
        documentScrollbarThumbColor == scrollbarThumbColor) {
      return;
    }
    final isInitialDocument = documentBrightness == null;
    documentBrightness = brightness;
    documentScrollbarThumbColor = scrollbarThumbColor;
    if (isInitialDocument) {
      preparedHtml = _prepareDocument();
      _loadDocumentUrl();
      return;
    }
    _reloadDocument();
  }

  void _reloadDocument() {
    preparedHtml = _prepareDocument();
    pendingScrollCommands.clear();
    scrollReady = false;
    rendererScrollAvailable = false;
    rendererScrollInitialization = null;
    findDebounce?.cancel();
    findSession.attach(null);
    findResult = WebViewFindResult.empty;
    webViewController = null;
    documentRevision++;
    _loadDocumentUrl();
  }

  void _loadDocumentUrl() {
    if (!Platform.isWindows) return;
    resourceHost ??= HtmlPreviewResourceHost(directory: widget.baseDirectory);
    documentUrl = resourceHost!.load(preparedHtml);
  }

  String _prepareDocument() => prepareHtmlPreviewDocument(
        widget.html,
        brightness: documentBrightness ?? Brightness.light,
        scrollbarThumbColor:
            documentScrollbarThumbColor ?? _defaultPreviewScrollbarThumbColor,
        autoHideScrollbars: Platform.isWindows,
      );

  @override
  void deactivate() {
    _active = false;
    findDebounce?.cancel();
    findSession.invalidatePending();
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _active = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = webViewController;
      if (mounted && _active && controller != null) {
        unawaited(_installFindEngine(controller));
      }
    });
  }

  @override
  void dispose() {
    pendingScrollCommands.clear();
    unawaited(resourceHost?.dispose());
    webViewController = null;
    findDebounce?.cancel();
    findSession.dispose();
    findController.removeListener(_scheduleFind);
    findController.dispose();
    findFocusNode.dispose();
    previewFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ContextualFindRegion(
      debugLabel: 'HTML file',
      onFind: _openFind,
      onDismiss: () => _closeFind(restoreFocus: false),
      findOpen: findVisible,
      findFocusNode: findFocusNode,
      child: _buildFindOverlay(_buildPreviewContent()),
    );
  }

  Widget _buildPreviewContent() {
    if (Platform.isWindows) {
      return FutureBuilder<Uri>(
        key: ObjectKey(documentUrl),
        future: documentUrl,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _PreviewError(
              message: 'The preview resources could not be opened.',
              onRetry: () {
                unawaited(resourceHost?.dispose());
                resourceHost = null;
                setState(_reloadDocument);
              },
            );
          }
          final url = snapshot.data;
          return url == null
              ? const Center(child: CircularProgressIndicator())
              : _buildWebView(url);
        },
      );
    }
    return _buildWebView(null);
  }

  Widget _buildWebView(Uri? url) {
    final revision = documentRevision;
    final child = SizedBox.expand(
      key: webViewViewportKey,
      child: InAppWebView(
        key: ValueKey(documentRevision),
        initialUrlRequest:
            url == null ? null : URLRequest(url: WebUri.uri(url)),
        initialData: url != null
            ? null
            : InAppWebViewInitialData(
                data: preparedHtml,
                baseUrl: WebUri(Uri.directory(widget.baseDirectory).toString()),
              ),
        onWebViewCreated: (controller) {
          if (!mounted || revision != documentRevision) return;
          webViewController = controller;
          _attachFindController(controller);
          unawaited(_installFindBridge(controller));
          _scheduleScroll();
        },
        onLoadStart: (controller, _) {
          if (!mounted ||
              revision != documentRevision ||
              !sameWebViewController(controller, webViewController)) {
            return;
          }
          findDebounce?.cancel();
          _attachFindController(controller);
          if (_active) setState(() => findResult = WebViewFindResult.empty);
        },
        onLoadStop: (controller, _) async {
          if (!mounted ||
              revision != documentRevision ||
              !sameWebViewController(controller, webViewController)) {
            return;
          }
          // A slow/failed scrolling world must not hold find hostage.
          unawaited(_prepareScrollAfterLoad(controller));
          await _installFindEngine(controller);
        },
        initialSettings: InAppWebViewSettings(
          allowFileAccessFromFileURLs: true,
          disableHorizontalScroll: Platform.isWindows,
          disableVerticalScroll: Platform.isWindows,
          javaScriptEnabled: Platform.isWindows,
          transparentBackground: true,
          useShouldOverrideUrlLoading: true,
        ),
        shouldOverrideUrlLoading: (controller, action) async {
          final uri = action.request.url;
          if (url != null) {
            // Permit only this sanitized document (and its fragment links),
            // never a link navigating the renderer into an arbitrary page.
            return mounted &&
                    revision == documentRevision &&
                    uri != null &&
                    Uri.parse(uri.toString()).replace(fragment: '') ==
                        url.replace(fragment: '')
                ? NavigationActionPolicy.ALLOW
                : NavigationActionPolicy.CANCEL;
          }
          if (!scrollReady &&
              uri != null &&
              (uri.scheme == 'file' || uri.scheme == 'data')) {
            return NavigationActionPolicy.ALLOW;
          }
          return NavigationActionPolicy.CANCEL;
        },
      ),
    );
    final guardedChild = HistorySwipeBoundaryFeedback(
      child: PremiumScrollExclusion(
        child: PdfEmbedScrollGuard(
          onPointerSignal: _handlePointerSignal,
          onPointerPanZoomStart: _handlePointerPanZoomStart,
          onPointerPanZoomUpdate: _handlePointerPanZoomUpdate,
          onPointerPanZoomEnd: _handlePointerPanZoomEnd,
          child: child,
        ),
      ),
    );
    return guardedChild;
  }

  Widget _buildFindOverlay(Widget child) {
    return RepaintBoundary(
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyF, control: true):
              _openFind,
          const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _openFind,
        },
        child: Focus(
          focusNode: previewFocusNode,
          child: Stack(
            fit: StackFit.expand,
            children: [
              child,
              if (findVisible)
                Positioned(
                  top: 8,
                  left: 16,
                  right: 16,
                  child: Align(
                    alignment: Alignment.topRight,
                    child: FindReplaceBar(
                      findController: findController,
                      findFocusNode: findFocusNode,
                      options: findOptions,
                      onOptionsChanged: (value) {
                        setState(() => findOptions = value);
                        _scheduleFind();
                      },
                      matchCount: findResult.count,
                      currentMatch: findResult.index,
                      queryInvalid: findResult.invalid,
                      busy: findSession.pending,
                      onPrevious: findResult.count == 0
                          ? null
                          : () => unawaited(_moveFind(forward: false)),
                      onNext: findResult.count == 0
                          ? null
                          : () => unawaited(_moveFind(forward: true)),
                      onClose: _closeFind,
                      onTapOutside: () => _closeFind(restoreFocus: false),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _attachFindController(InAppWebViewController controller) {
    findSession.attach(
      (source) => controller.evaluateJavascript(
        source: source,
        contentWorld: htmlPreviewScrollContentWorld,
      ),
    );
  }

  Future<void> _installFindBridge(InAppWebViewController controller) async {
    try {
      await installWebViewFindOpenBridge(
        controller,
        contentWorld: htmlPreviewScrollContentWorld,
        onFind: _openFind,
        isCurrent: () =>
            mounted && sameWebViewController(controller, webViewController),
      );
    } on PlatformException catch (error, stackTrace) {
      Log.error(
        'Failed to install the preview find shortcut',
        error,
        stackTrace,
      );
    }
  }

  Future<void> _prepareScrollAfterLoad(
    InAppWebViewController controller,
  ) async {
    if (await _ensureRendererScrollReady(controller)) _scheduleScroll();
  }

  /// A rendered document does its own searching: only the renderer knows
  /// where a word ended up once the page was laid out.
  Future<void> _installFindEngine(InAppWebViewController controller) async {
    if (!Platform.isWindows ||
        !mounted ||
        !_active ||
        !sameWebViewController(controller, webViewController)) {
      return;
    }
    final palette = FindBarPalette.of(context);
    final brightness = Theme.of(context).brightness;
    findDebounce?.cancel();
    await _acceptFindResponse(
      findSession.install(
        buildWebViewFindInstallScript(
          matchColor: _cssRgba(FindHighlightColors.match(brightness)),
          currentColor: _cssRgba(FindHighlightColors.current(brightness)),
          currentTextColor: _cssColor(palette.textPrimary),
        ),
      ),
    );
  }

  void _openFind() {
    if (!mounted || !_active) {
      return;
    }
    final wasVisible = findVisible;
    findSession
      ..setQuery(findController.text, findOptions)
      ..open();
    setState(() => findVisible = true);
    if (!wasVisible) unawaited(_runFind());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_active || !findVisible) {
        return;
      }
      findFocusNode.requestFocus();
      findController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: findController.text.length,
      );
    });
  }

  void _closeFind({bool restoreFocus = true}) {
    if (!mounted || !_active || !findVisible) {
      return;
    }
    findDebounce?.cancel();
    setState(() {
      findVisible = false;
      findResult = WebViewFindResult.empty;
    });
    unawaited(_clearFind());
    if (restoreFocus) previewFocusNode.requestFocus();
  }

  Future<void> _clearFind() async {
    try {
      await findSession.close();
    } on PlatformException catch (error, stackTrace) {
      Log.error('Failed to clear preview find highlights', error, stackTrace);
    }
  }

  /// Marking a whole document costs a layout, so it waits for a pause in the
  /// typing rather than running on every keystroke.
  void _scheduleFind() {
    if (!findSession.setQuery(findController.text, findOptions)) return;
    findDebounce?.cancel();
    if (!mounted || !_active || !findVisible) return;
    setState(() => findResult = WebViewFindResult.empty);
    findDebounce = Timer(
      const Duration(milliseconds: 180),
      () => unawaited(_runFind()),
    );
  }

  Future<void> _runFind() => _acceptFindResponse(findSession.find());

  Future<void> _moveFind({required bool forward}) =>
      _acceptFindResponse(findSession.move(forward: forward));

  Future<void> _acceptFindResponse(Future<WebViewFindResult?> request) async {
    try {
      final result = await request;
      if (!mounted || !_active || result == null || !findVisible) return;
      setState(() => findResult = result);
    } on PlatformException catch (error, stackTrace) {
      Log.error('Preview find failed', error, stackTrace);
    } on FormatException catch (error, stackTrace) {
      Log.error('Invalid preview find response', error, stackTrace);
    }
  }

  Future<bool> _ensureRendererScrollReady(
    InAppWebViewController controller,
  ) async {
    if (!mounted || !sameWebViewController(controller, webViewController)) {
      return false;
    }
    if (scrollReady) {
      return true;
    }
    var initialization = rendererScrollInitialization;
    if (initialization == null) {
      initialization = _initializeRendererScroll(controller);
      rendererScrollInitialization = initialization;
    }
    try {
      await initialization;
    } finally {
      if (identical(rendererScrollInitialization, initialization)) {
        rendererScrollInitialization = null;
      }
    }
    if (!mounted || !sameWebViewController(controller, webViewController)) {
      return false;
    }
    scrollReady = true;
    return true;
  }

  Future<void> _initializeRendererScroll(
    InAppWebViewController controller,
  ) async {
    rendererScrollAvailable = false;
    if (!Platform.isWindows) {
      return;
    }
    try {
      final installed = await controller.evaluateJavascript(
        source: '''
${buildPremiumKineticScrollEngineScript(config: physicsConfig)}
${buildHtmlPreviewScrollbarAutoHideScript()}
typeof globalThis.$premiumKineticJavaScriptObjectName === 'object';
''',
        contentWorld: htmlPreviewScrollContentWorld,
      );
      if (!mounted || !sameWebViewController(controller, webViewController)) {
        return;
      }
      rendererScrollAvailable = installed == true;
      if (!rendererScrollAvailable) {
        Log.warn('HTML preview kinetic engine did not initialize');
      }
    } on PlatformException catch (error, stackTrace) {
      Log.error(
        'Failed to initialize HTML preview kinetic scrolling',
        error,
        stackTrace,
      );
    }
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) {
      return;
    }
    _queueRendererCommand(
      smoothScrollingEnabled
          ? buildPremiumKineticWheelCommand(
              event.scrollDelta,
              kind: event.kind,
              position: _localPosition(event),
            )
          : buildPremiumKineticPanCommand(
              event.scrollDelta,
              position: _localPosition(event),
            ),
      fallbackDelta: event.scrollDelta,
    );
  }

  void _handlePointerPanZoomStart(PointerPanZoomStartEvent event) {
    trackpadVelocityTracker =
        MacOSScrollViewFlingVelocityTracker(PointerDeviceKind.trackpad)
          ..addPosition(event.timeStamp, Offset.zero);
    if (smoothScrollingEnabled) {
      _queueRendererCommand(
        buildPremiumKineticBeginPanCommand(position: _localPosition(event)),
      );
    }
  }

  void _handlePointerPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    trackpadVelocityTracker ??=
        MacOSScrollViewFlingVelocityTracker(PointerDeviceKind.trackpad);
    trackpadVelocityTracker!.addPosition(event.timeStamp, event.localPan);
    final delta = -event.localPanDelta;
    _queueRendererCommand(
      buildPremiumKineticPanCommand(
        delta,
        position: _localPosition(event),
      ),
      fallbackDelta: delta,
    );
  }

  void _handlePointerPanZoomEnd(PointerPanZoomEndEvent event) {
    final tracker = trackpadVelocityTracker;
    trackpadVelocityTracker = null;
    if (!smoothScrollingEnabled || tracker == null) {
      return;
    }
    _queueRendererCommand(
      buildPremiumKineticReleaseCommand(
        -tracker.getVelocity().pixelsPerSecond,
      ),
    );
  }

  Offset _localPosition(PointerEvent event) {
    final renderObject = webViewViewportKey.currentContext?.findRenderObject();
    return renderObject is RenderBox
        ? renderObject.globalToLocal(event.position)
        : event.localPosition;
  }

  void _queueRendererCommand(
    String source, {
    Offset fallbackDelta = Offset.zero,
  }) {
    pendingScrollCommands.add(
      _PendingWebViewScrollCommand(
        source: source,
        fallbackDelta: fallbackDelta,
      ),
    );
    _scheduleScroll();
  }

  void _scheduleScroll() {
    if (!scrollOperationInFlight) {
      unawaited(_flushScroll());
    }
  }

  Future<void> _flushScroll() async {
    final controller = webViewController;
    if (!canStartHtmlPreviewScrollFlush(
      scrollOperationInFlight: scrollOperationInFlight,
      hasController: controller != null,
      hasPendingCommands: pendingScrollCommands.isNotEmpty,
    )) {
      return;
    }
    scrollOperationInFlight = true;
    try {
      if (!await _ensureRendererScrollReady(controller!)) {
        return;
      }
      while (mounted &&
          sameWebViewController(controller, webViewController) &&
          pendingScrollCommands.isNotEmpty) {
        final commands = List<_PendingWebViewScrollCommand>.of(
          pendingScrollCommands,
        );
        pendingScrollCommands.clear();
        if (Platform.isWindows && rendererScrollAvailable) {
          try {
            final executed = await controller.evaluateJavascript(
              source: '''
${commands.map((command) => command.source).join('\n')}
true;
''',
              contentWorld: htmlPreviewScrollContentWorld,
            );
            if (executed == true) {
              continue;
            }
            rendererScrollAvailable = false;
            Log.warn(
              'HTML preview kinetic command failed; using direct scrolling',
            );
          } on PlatformException catch (error, stackTrace) {
            rendererScrollAvailable = false;
            Log.error(
              'HTML preview kinetic scrolling failed; using direct scrolling',
              error,
              stackTrace,
            );
          }
        }
        final fallbackDelta = commands.fold(
          Offset.zero,
          (sum, command) => sum + command.fallbackDelta,
        );
        if (fallbackDelta != Offset.zero) {
          await _scrollDirectly(controller, fallbackDelta);
        }
      }
    } on PlatformException catch (error, stackTrace) {
      pendingScrollCommands.clear();
      Log.error('Failed to scroll HTML preview', error, stackTrace);
    } finally {
      scrollOperationInFlight = false;
      if (mounted && pendingScrollCommands.isNotEmpty) {
        _scheduleScroll();
      }
    }
  }

  Future<void> _scrollDirectly(
    InAppWebViewController controller,
    Offset delta,
  ) {
    if (Platform.isWindows) {
      return controller.evaluateJavascript(
        source: buildWebViewDirectScrollScript(delta),
      );
    }
    return controller.scrollBy(
      x: delta.dx.round(),
      y: delta.dy.round(),
    );
  }
}

@visibleForTesting
bool canStartHtmlPreviewScrollFlush({
  required bool scrollOperationInFlight,
  required bool hasController,
  required bool hasPendingCommands,
}) =>
    !scrollOperationInFlight && hasController && hasPendingCommands;

class _PendingWebViewScrollCommand {
  const _PendingWebViewScrollCommand({
    required this.source,
    required this.fallbackDelta,
  });

  final String source;
  final Offset fallbackDelta;
}

/// Moves a page without the kinetic engine.
///
/// A site that leaves the document itself unscrollable and moves one big pane
/// instead cannot be scrolled by `window` alone, so the largest scrollable
/// element stands in for it.
String buildWebViewDirectScrollScript(Offset delta) => '''
(function () {
  const dx = ${delta.dx};
  const dy = ${delta.dy};
  const root = document.scrollingElement || document.documentElement;
  if (root && (root.scrollHeight - root.clientHeight > 1 ||
      root.scrollWidth - root.clientWidth > 1)) {
    window.scrollBy(dx, dy);
    return true;
  }
  let best = null;
  let bestArea = 0;
  for (const element of (document.body ? document.body.querySelectorAll('*') : [])) {
    if (element.scrollHeight - element.clientHeight <= 1 &&
        element.scrollWidth - element.clientWidth <= 1) {
      continue;
    }
    const style = getComputedStyle(element);
    if (!['auto', 'scroll'].includes(style.overflowY) &&
        !['auto', 'scroll'].includes(style.overflowX)) {
      continue;
    }
    const rect = element.getBoundingClientRect();
    const area = rect.width * rect.height;
    if (area > bestArea) {
      bestArea = area;
      best = element;
    }
  }
  (best || window).scrollBy(dx, dy);
  return true;
})();
''';

class _PreviewError extends StatelessWidget {
  const _PreviewError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 32),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
