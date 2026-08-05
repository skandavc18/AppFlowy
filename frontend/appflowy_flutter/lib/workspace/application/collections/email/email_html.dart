import 'dart:convert';

import 'package:appflowy/workspace/application/collections/email/mime_message.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// How much inlined artwork one message may carry into the renderer.
const maxInlineEmailImageBytes = 12 * 1024 * 1024;

/// The colours a message is printed in, taken from the application's theme so
/// a mail reads like part of the app rather than a page from elsewhere.
@immutable
class EmailHtmlPalette {
  const EmailHtmlPalette({
    required this.brightness,
    required this.background,
    required this.text,
    required this.muted,
    required this.link,
    required this.rule,
    required this.quote,
    required this.scrollbar,
  });

  final Brightness brightness;
  final Color background;
  final Color text;
  final Color muted;
  final Color link;
  final Color rule;
  final Color quote;
  final Color scrollbar;
}

/// A message turned into something a renderer can show.
@immutable
class EmailHtmlDocument {
  const EmailHtmlDocument({
    required this.html,
    this.remoteReferenceCount = 0,
    this.blockedRemoteCount = 0,
    this.inlineImageCount = 0,
    this.isPlainText = false,
  });

  final String html;

  /// How many references reach out to somebody else's server, whether or not
  /// they were allowed through.
  final int remoteReferenceCount;

  /// How many remote references were held back, so the reader can be offered
  /// the choice of loading them.
  final int blockedRemoteCount;

  /// How many pictures travelled inside the message itself.
  final int inlineImageCount;

  /// Whether the message had no HTML at all and its plain text was dressed.
  final bool isPlainText;

  bool get hasRemoteContent => remoteReferenceCount > 0;

  bool get hasBlockedRemoteContent => blockedRemoteCount > 0;
}

/// Elements that never belong in a message, whatever it claims.
const _forbiddenElements = <String>{
  'script',
  'iframe',
  'frame',
  'frameset',
  'object',
  'embed',
  'applet',
  'form',
  'input',
  'button',
  'select',
  'textarea',
  'base',
  'link',
  'meta',
  'noscript',
  'template',
  'audio',
  'video',
  'source',
  'track',
  'portal',
};

/// Attributes that carry a URL and therefore have to be looked at.
const _urlAttributes = <String>{
  'src',
  'href',
  'background',
  'poster',
  'action',
  'formaction',
  'data',
  'srcset',
  'cite',
  'longdesc',
};

/// Builds the document a message is rendered from.
///
/// Two rules decide everything here. First, a message is a stranger's markup,
/// so scripts are stripped and the document is served under a policy that
/// forbids them outright — a mail client has no business running code. Second,
/// remote references are held back until the reader asks for them, because a
/// picture fetched from a sender's server tells them the message was opened,
/// when, and from where. Pictures carried inside the message have no such cost
/// and are always shown.
EmailHtmlDocument buildEmailHtmlDocument(
  MimeMessage message, {
  required EmailHtmlPalette palette,
  required bool allowRemoteContent,
  String fontFaces = '',
}) {
  final html = message.htmlBody;
  final hasHtml = html != null && html.trim().isNotEmpty;

  final body = hasHtml
      ? _sanitize(
          html,
          message: message,
          allowRemoteContent: allowRemoteContent,
        )
      : _PreparedBody(
          html: _plainTextToHtml(message.plainBody ?? ''),
        );

  return EmailHtmlDocument(
    html: _wrap(
      body.html,
      palette: palette,
      fontFaces: fontFaces,
      allowRemoteContent: allowRemoteContent,
    ),
    remoteReferenceCount: body.remote,
    blockedRemoteCount: body.blocked,
    inlineImageCount: body.inlined,
    isPlainText: !hasHtml,
  );
}

class _PreparedBody {
  const _PreparedBody({
    required this.html,
    this.remote = 0,
    this.blocked = 0,
    this.inlined = 0,
  });

  final String html;
  final int remote;
  final int blocked;
  final int inlined;
}

_PreparedBody _sanitize(
  String source, {
  required MimeMessage message,
  required bool allowRemoteContent,
}) {
  final document = html_parser.parse(source);
  final inline = _inlinePartsOf(message);
  var remote = 0;
  var blocked = 0;
  var inlined = 0;

  for (final element in document.querySelectorAll('*').toList()) {
    final tag = element.localName?.toLowerCase();
    if (tag != null && _forbiddenElements.contains(tag)) {
      element.remove();
      continue;
    }

    for (final key in element.attributes.keys.toList()) {
      final name = key is dom.AttributeName
          ? key.name.toLowerCase()
          : key.toString().toLowerCase();
      final value = element.attributes[key] ?? '';

      // An event handler is a script by another name.
      if (name.startsWith('on') ||
          name == 'srcdoc' ||
          name == 'ping' ||
          name == 'formaction' ||
          name == 'autofocus') {
        element.attributes.remove(key);
        continue;
      }

      if (!_urlAttributes.contains(name)) {
        continue;
      }

      // A message's own pictures always show: they cost nobody anything.
      final resolved = _resolveInline(value, inline);
      if (resolved != null) {
        element.attributes[key] = resolved;
        inlined += 1;
        continue;
      }

      final scheme = _schemeOf(value);
      if (scheme == 'cid') {
        // Referenced but not carried: nothing can be shown for it.
        element.attributes.remove(key);
        continue;
      }
      if (scheme == 'data') {
        continue;
      }
      if (scheme != 'http' && scheme != 'https' && scheme != 'mailto') {
        element.attributes.remove(key);
        continue;
      }

      // A link is left alone — following one is a deliberate act, and the
      // renderer hands it to the browser rather than opening it here.
      if (name == 'href') {
        continue;
      }
      remote += 1;
      if (!allowRemoteContent) {
        element.attributes.remove(key);
        blocked += 1;
        if (tag == 'img') {
          element.attributes['data-appflowy-blocked'] = '';
        }
      }
    }

    if (tag == 'img') {
      element.attributes.putIfAbsent('loading', () => 'eager');
    }
  }

  // A style sheet can fetch too, so a blocked message loses its remote urls
  // there as well.
  for (final style in document.querySelectorAll('style').toList()) {
    final cleaned = _stripRemoteUrls(style.text);
    remote += cleaned.removed;
    if (!allowRemoteContent) {
      blocked += cleaned.removed;
      style.text = cleaned.css;
    }
  }
  for (final element in document.querySelectorAll('[style]').toList()) {
    final cleaned = _stripRemoteUrls(element.attributes['style'] ?? '');
    remote += cleaned.removed;
    if (!allowRemoteContent) {
      blocked += cleaned.removed;
      element.attributes['style'] = cleaned.css;
    }
  }

  return _PreparedBody(
    html: document.body?.innerHtml ?? '',
    remote: remote,
    blocked: blocked,
    inlined: inlined,
  );
}

/// The pictures a message carries, indexed by the identifiers markup uses to
/// point at them.
Map<String, MimePart> _inlinePartsOf(MimeMessage message) {
  final parts = <String, MimePart>{};
  for (final part in message.parts) {
    if (part.isMultipart || part.content.isEmpty) {
      continue;
    }
    final id = part.headers.raw('content-id')?.trim();
    if (id != null && id.isNotEmpty) {
      parts[_stripAngles(id).toLowerCase()] = part;
    }
    final location = part.headers.raw('content-location')?.trim();
    if (location != null && location.isNotEmpty) {
      parts[location.toLowerCase()] = part;
    }
    final name = part.filename;
    if (name != null && name.isNotEmpty) {
      parts.putIfAbsent(name.toLowerCase(), () => part);
    }
  }
  return parts;
}

/// Turns a `cid:` reference into the picture itself.
String? _resolveInline(String value, Map<String, MimePart> inline) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || inline.isEmpty) {
    return null;
  }

  final key = trimmed.toLowerCase().startsWith('cid:')
      ? _stripAngles(trimmed.substring(4)).toLowerCase()
      : trimmed.toLowerCase();
  final part = inline[key];
  if (part == null || part.content.length > maxInlineEmailImageBytes) {
    return null;
  }

  final type =
      part.mediaType.isEmpty ? 'application/octet-stream' : part.mediaType;
  return 'data:$type;base64,${base64.encode(part.content)}';
}

String _stripAngles(String value) {
  var id = value.trim();
  if (id.startsWith('<')) {
    id = id.substring(1);
  }
  if (id.endsWith('>')) {
    id = id.substring(0, id.length - 1);
  }
  return id.trim();
}

String? _schemeOf(String value) {
  final trimmed = value.trim();
  final colon = trimmed.indexOf(':');
  if (colon <= 0) {
    // A bare path can only resolve against a base the document does not have.
    return trimmed.isEmpty ? null : 'relative';
  }
  return trimmed.substring(0, colon).toLowerCase();
}

class _StrippedCss {
  const _StrippedCss(this.css, this.removed);

  final String css;
  final int removed;
}

final _cssUrl = RegExp(
  r'''url\(\s*['"]?\s*(https?:)?//[^)]*\)''',
  caseSensitive: false,
);

_StrippedCss _stripRemoteUrls(String css) {
  if (css.isEmpty) {
    return const _StrippedCss('', 0);
  }
  final matches = _cssUrl.allMatches(css).length;
  if (matches == 0) {
    return _StrippedCss(css, 0);
  }
  return _StrippedCss(css.replaceAll(_cssUrl, 'none'), matches);
}

String _plainTextToHtml(String text) {
  if (text.trim().isEmpty) {
    return '';
  }
  final escaped = const HtmlEscape().convert(text);
  // Quoted replies are dimmed rather than hidden, the way a mail client does.
  final lines = escaped.split('\n').map((line) {
    final quoted = line.trimLeft().startsWith('&gt;');
    return quoted ? '<span class="af-quote">$line</span>' : line;
  }).join('\n');
  return '<pre class="af-plain">$lines</pre>';
}

String _wrap(
  String body, {
  required EmailHtmlPalette palette,
  required String fontFaces,
  required bool allowRemoteContent,
}) {
  // Nothing may load unless it is named here. Scripts have no source at all,
  // so the document cannot run code even if something slipped past the pass
  // above.
  final imageSources = allowRemoteContent ? "data: https: http:" : 'data:';
  final policy = "default-src 'none'; img-src $imageSources; "
      "style-src 'unsafe-inline'; font-src data:; "
      "form-action 'none'; base-uri 'none'; frame-src 'none'; script-src 'none'";

  return '''
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="$policy">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
$fontFaces
:root {
  color-scheme: ${palette.brightness == Brightness.dark ? 'dark' : 'light'};
  --af-muted: ${_rgba(palette.muted)};
  --af-rule: ${_rgba(palette.rule)};
}
* { box-sizing: border-box; }
html {
  background: ${_hex(palette.background)};
}
body {
  margin: 0;
  padding: 4px 2px 28px;
  color: ${_hex(palette.text)};
  background: ${_hex(palette.background)};
  font-family: "AppFlowy Sans", "Segoe UI Variable Text", "Segoe UI",
    -apple-system, BlinkMacSystemFont, Inter, "Helvetica Neue", Arial,
    sans-serif;
  font-size: 14px;
  line-height: 1.6;
  overflow-wrap: anywhere;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
  text-rendering: optimizeLegibility;
}
/* Mail is written for a fixed width and a white page; neither is true here. */
img, video, table { max-width: 100% !important; }
img { height: auto; border: 0; }
img[data-appflowy-blocked] {
  display: inline-block;
  min-width: 22px;
  min-height: 22px;
  background: var(--af-rule);
  border-radius: 4px;
}
table { border-collapse: collapse; }
a { color: ${_hex(palette.link)}; }
a:hover { text-decoration: underline; }
blockquote {
  margin: 0 0 12px;
  padding: 2px 0 2px 12px;
  color: var(--af-muted);
  border-left: 3px solid ${_hex(palette.quote)};
}
pre.af-plain {
  margin: 0;
  font-family: inherit;
  font-size: inherit;
  line-height: inherit;
  white-space: pre-wrap;
  word-break: break-word;
}
.af-quote { color: var(--af-muted); }
hr { border: 0; border-top: 1px solid var(--af-rule); }
::-webkit-scrollbar { width: 11px; height: 11px; background: transparent; }
::-webkit-scrollbar-track, ::-webkit-scrollbar-corner { background: transparent; }
::-webkit-scrollbar-thumb {
  background-color: ${_rgba(palette.scrollbar)};
  background-clip: padding-box;
  border: 3px solid transparent;
  border-radius: 999px;
}
</style>
</head>
<body>$body</body>
</html>
''';
}

String _hex(Color color) =>
    '#${_channel(color.r)}${_channel(color.g)}${_channel(color.b)}';

String _channel(double value) =>
    (value * 255).round().toRadixString(16).padLeft(2, '0');

String _rgba(Color color) => 'rgba(${(color.r * 255).round()}, '
    '${(color.g * 255).round()}, '
    '${(color.b * 255).round()}, '
    '${color.a.toStringAsFixed(3)})';
