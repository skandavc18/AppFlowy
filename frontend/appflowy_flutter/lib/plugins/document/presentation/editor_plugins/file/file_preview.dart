import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/code_block/syntax_highlighter.dart';
import 'package:appflowy/shared/document_viewer/document_viewer.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/google_fonts_extension.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:linked_scroll_controller/linked_scroll_controller.dart';
import 'package:markdown/markdown.dart' as markdown;
import 'package:markdown_widget/markdown_widget.dart';
import 'package:path/path.dart' as p;

import 'archive/archive_explorer.dart';
import 'file_preview_kind.dart';
import 'pdf_preview.dart';
import 'pdf_preview_scroll_physics.dart';
import 'pdf_preview_theme.dart';
import 'sandboxed_code_runner.dart';

const maxTextPreviewBytes = 10 * 1024 * 1024;

/// How tall an embedded preview is before the reader resizes it.
///
/// Code brings its own toolbar and terminal, and an archive brings the folder
/// chrome, so both need more than a plain document preview.
double defaultFilePreviewHeight(FilePreviewKind kind) => switch (kind) {
      FilePreviewKind.code => 560,
      FilePreviewKind.archive => 560,
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
        oldWidget.metadata[filePreviewEditModeKey] !=
            widget.metadata[filePreviewEditModeKey]) {
      preview = _buildPreview();
    }
  }

  /// Whether this preview is currently showing its source for editing.
  bool get isEditingSource =>
      widget.metadata[filePreviewEditModeKey] == true &&
      widget.kind.supportsSourceEditing;

  @override
  Widget build(BuildContext context) {
    final materialTheme = Theme.of(context);
    final appFlowyTheme = AppFlowyTheme.of(context);
    final isPremiumPreview = widget.kind == FilePreviewKind.pdf;
    final pdfPalette = isPremiumPreview ? PdfPreviewPalette.of(context) : null;
    final backgroundColor = pdfPalette?.canvas ??
        EditorSurfaceStyle.previewBackgroundFor(
          materialTheme.brightness,
          appFlowyTheme.surfaceColorScheme.layer01,
          isPaper: PaperTheme.isEnabled(context),
        );
    return ViewerCard(
      color: backgroundColor,
      child: SizedBox(
        height: widget.height ?? defaultFilePreviewHeight(widget.kind),
        child: FutureBuilder<Widget>(
          future: preview,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _PreviewError(
                message: snapshot.error.toString(),
                onRetry: () => setState(() => preview = _buildPreview()),
              );
            }
            return snapshot.data ??
                const Center(child: CircularProgressIndicator());
          },
        ),
      ),
    );
  }

  Future<Widget> _buildPreview() async {
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
      FilePreviewKind.archive => ArchiveExplorer(
          key: ValueKey('${widget.file.path}_archive'),
          file: widget.file,
          name: widget.name,
          editable: widget.editable,
          embedded: false,
          toolbarTrailing: widget.toolbarTrailing,
        ),
      FilePreviewKind.csv => _buildPreviewScaffold(
          _CsvPreview(
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
      FilePreviewKind.notebook => _buildPreviewScaffold(
          _NotebookPreview(
            document: jsonDecode(await _readText(maxTextPreviewBytes))
                as Map<String, dynamic>,
          ),
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

  /// What the floating header says about this file.
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
  :root { color-scheme: ${_cssColorScheme(brightness)}; }
  * { box-sizing: border-box; }
  html { background: ${_cssColor(backgroundColor)}; }
  body {
    margin: 0;
    padding: 16px;
    color: ${_cssColor(textColor)};
    background: ${_cssColor(backgroundColor)};
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    font-size: 15px;
    line-height: 1.6;
    overflow-wrap: anywhere;
  }
  h1, h2 { border-bottom: 1px solid ${_cssColor(borderColor)}; }
  h1, h2, h3, h4, h5, h6 { line-height: 1.25; }
  a { color: ${_cssColor(linkColor)}; }
  img { max-width: 100%; height: auto; }
  pre, code {
    background: ${_cssColor(codeBackground)};
    border-radius: 6px;
    font-family: "JetBrains Mono", "Geist Mono", monospace;
  }
  code { padding: 0.15em 0.35em; }
  pre { padding: 12px; overflow-x: auto; overflow-y: hidden; }
  pre code { padding: 0; background: transparent; }
  blockquote {
    margin-left: 0;
    padding-left: 12px;
    border-left: 3px solid ${_cssColor(borderColor)};
  }
  table { border-collapse: collapse; max-width: 100%; }
  th, td { padding: 6px 12px; border: 1px solid ${_cssColor(borderColor)}; }
  hr { border: 0; border-top: 1px solid ${_cssColor(borderColor)}; }
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
@visibleForTesting
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
@visibleForTesting
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
  Widget build(BuildContext context) {
    return SandboxedCodeRunner(
      code: code,
      fileName: fileNameForCodeLanguage(language),
      displayName: widget.name,
      language: language,
      showLineNumbers: showLineNumbers,
      onLanguageChanged: (value) {
        final normalizedLanguage = normalizeCodeLanguage(value);
        setState(() => language = normalizedLanguage);
        widget.onMetadataChanged({
          ...widget.metadata,
          'code_language': normalizedLanguage,
        });
      },
      onToggleLineNumbers: () {
        setState(() => showLineNumbers = !showLineNumbers);
        widget.onMetadataChanged({
          ...widget.metadata,
          'show_code_line_numbers': showLineNumbers,
        });
      },
      editable: widget.editable,
      testCases: testCases,
      onTestCasesChanged: (cases) {
        setState(() => testCases = cases);
        widget.onMetadataChanged({
          ...widget.metadata,
          'code_test_cases': encodeCodeTestCases(cases),
        });
      },
      toolbarTrailing: widget.toolbarTrailing,
      expandEditor: true,
      framed: false,
      child: _EditableCodeFile(
        file: widget.file,
        initialCode: widget.initialCode,
        editable: widget.editable,
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
  Timer? saveTimer;

  @override
  void didUpdateWidget(covariant _EditableCodeFile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.language != widget.language) {
      controller.updateLanguage(widget.language);
    }
  }

  @override
  void dispose() {
    _flushPendingSave();
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
    return ColoredBox(
      color: surfaceColor,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showLineNumbers)
            Container(
              width: 26 + '$lineCount'.length * 9,
              decoration: BoxDecoration(
                color: surfaceColor,
                border: Border(
                  right: BorderSide(
                    color: appFlowyTheme.borderColorScheme.primary,
                  ),
                ),
              ),
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
              controller: controller,
              scrollController: codeScrollController,
              readOnly: !widget.editable,
              expands: true,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              style: codeStyle,
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.all(12),
                border: InputBorder.none,
                // The surrounding box already paints the sheet. A filled
                // field would blend Material's hover colour over it and grey
                // the whole editor out under the pointer.
                filled: false,
                hoverColor: Colors.transparent,
              ),
              onChanged: (value) {
                setState(() {});
                widget.onChanged(value);
                saveTimer?.cancel();
                saveTimer = Timer(
                  const Duration(milliseconds: 400),
                  () => widget.file.writeAsString(value, flush: true),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

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

  void updateLanguage(String value) {
    language = normalizeCodeLanguage(value);
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    return buildSyntaxHighlightedTextSpan(
      code: text,
      language: language,
      brightness: Theme.of(context).brightness,
      isPaper: PaperTheme.isEnabled(context),
      style: style,
    );
  }
}

class _TextPreview extends StatelessWidget {
  const _TextPreview({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectableText(
        text,
        style: const TextStyle(fontFamily: 'monospace', height: 1.4),
      ),
    );
  }
}

class _CsvPreview extends StatelessWidget {
  const _CsvPreview({required this.text, required this.separator});

  final String text;
  final String separator;

  @override
  Widget build(BuildContext context) {
    final rows = const LineSplitter()
        .convert(text)
        .take(1000)
        .map((line) => line.split(separator))
        .toList();
    if (rows.isEmpty) {
      return const Center(child: Text('This table is empty.'));
    }
    final width = rows.map((row) => row.length).reduce((a, b) => a > b ? a : b);
    return Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            border: TableBorder.all(color: Theme.of(context).dividerColor),
            children: [
              for (final row in rows)
                TableRow(
                  children: [
                    for (var index = 0; index < width; index++)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: SelectableText(
                          index < row.length ? row[index] : '',
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotebookPreview extends StatelessWidget {
  const _NotebookPreview({required this.document});

  final Map<String, dynamic> document;

  @override
  Widget build(BuildContext context) {
    final cells = document['cells'];
    if (cells is! List) {
      return const Center(child: Text('Invalid notebook document.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: cells.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final cell = cells[index];
        if (cell is! Map) {
          return const SizedBox.shrink();
        }
        final source = cell['source'];
        final text = source is List ? source.join() : source?.toString() ?? '';
        if (cell['cell_type'] == 'markdown') {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: MarkdownWidget(
                data: text,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
              ),
            ),
          );
        }
        final outputs = cell['outputs'];
        final outputText = outputs is List
            ? outputs
                .whereType<Map>()
                .map((output) => output['text'])
                .whereType<List>()
                .map((lines) => lines.join())
                .join()
            : '';
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SelectableText(
                  text,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                if (outputText.isNotEmpty) ...[
                  const Divider(),
                  SelectableText(
                    outputText,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
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

@visibleForTesting
final htmlPreviewScrollContentWorld =
    ContentWorld.world(name: 'appflowyDocumentScroll');

class _HtmlPreviewState extends State<_HtmlPreview> {
  InAppWebViewController? webViewController;
  final List<_PendingWebViewScrollCommand> pendingScrollCommands = [];
  final webViewViewportKey = GlobalKey();
  late String preparedHtml;
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
    webViewController = null;
    documentRevision++;
  }

  String _prepareDocument() => prepareHtmlPreviewDocument(
        widget.html,
        brightness: documentBrightness ?? Brightness.light,
        scrollbarThumbColor:
            documentScrollbarThumbColor ?? _defaultPreviewScrollbarThumbColor,
        autoHideScrollbars: Platform.isWindows,
      );

  @override
  void dispose() {
    pendingScrollCommands.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = SizedBox.expand(
      key: webViewViewportKey,
      child: InAppWebView(
        key: ValueKey(documentRevision),
        initialData: InAppWebViewInitialData(
          data: preparedHtml,
          baseUrl: WebUri(Uri.directory(widget.baseDirectory).toString()),
        ),
        onWebViewCreated: (controller) {
          webViewController = controller;
          _scheduleScroll();
        },
        onLoadStop: (controller, _) async {
          if (controller != webViewController) {
            return;
          }
          if (!await _ensureRendererScrollReady(controller)) {
            return;
          }
          _scheduleScroll();
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
          if (!scrollReady &&
              uri != null &&
              (uri.scheme == 'file' || uri.scheme == 'data')) {
            return NavigationActionPolicy.ALLOW;
          }
          return NavigationActionPolicy.CANCEL;
        },
      ),
    );
    final guardedChild = PremiumScrollExclusion(
      child: PdfEmbedScrollGuard(
        onPointerSignal: _handlePointerSignal,
        onPointerPanZoomStart: _handlePointerPanZoomStart,
        onPointerPanZoomUpdate: _handlePointerPanZoomUpdate,
        onPointerPanZoomEnd: _handlePointerPanZoomEnd,
        child: child,
      ),
    );
    return RepaintBoundary(child: guardedChild);
  }

  Future<bool> _ensureRendererScrollReady(
    InAppWebViewController controller,
  ) async {
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
    if (!mounted || controller != webViewController) {
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
          controller == webViewController &&
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

@visibleForTesting
String buildWebViewDirectScrollScript(Offset delta) =>
    'window.scrollBy(${delta.dx}, ${delta.dy});';

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
