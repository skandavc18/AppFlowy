import 'dart:async';
import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';

import 'readable_article.dart';

const bookmarkReaderCaptureLimit = 256 * 1024;
const bookmarkReaderDeadline = Duration(seconds: 5);

enum BookmarkReadingMode { live, reader, offline }

/// String keys work before generated locale constants/assets are refreshed.
abstract final class BookmarkReaderStrings {
  static String _text(String name, String fallback) {
    final key = 'collections.bookmark.$name';
    final translated = key.tr();
    return translated == key ? fallback : translated;
  }

  static String get reader => _text('reader', 'Reader');
  static String get unavailable => _text('readerUnavailable',
      'Reader is unavailable for this page. Open Live to continue.');
  static String get blockingOn =>
      _text('blockingOn', 'Ad-network blocking on — turn off and reload');
  static String get blockingOff =>
      _text('blockingOff', 'Ad-network blocking off — turn on and reload');
  static String get blockingFailed => _text(
      'blockingFailed', 'Ad-network blocking unavailable — retry or turn off');
  static String get saveFailed => _text(
      'readerSaveFailed', 'The offline copy could not be saved. Please retry.');
  static String get gesturesAuto =>
      _text('gesturesAuto', 'Automatic gestures — switch to website gestures');
  static String get gesturesSite =>
      _text('gesturesSite', 'Website gestures — switch to automatic gestures');
}

@immutable
class BookmarkReaderCapture {
  const BookmarkReaderCapture({
    required this.url,
    required this.generation,
    required this.article,
  });

  final String url;
  final int generation;
  final ReadableArticle article;
}

/// A reader-owned handle to the EXISTING browser. Never creates a second one.
/// A navigation (including same-document history) invalidates pending captures.
class BookmarkReadingSession extends ChangeNotifier {
  Object? _owner;
  Future<dynamic> Function(String)? _evaluate;
  String? _url;
  int _generation = 0;
  bool _ready = false;
  bool _disposed = false;
  Future<BookmarkReaderCapture?>? _pending;

  String? get url => _url;
  int get generation => _generation;
  bool get ready => !_disposed && _ready && _evaluate != null;

  void attach(Object owner, Future<dynamic> Function(String) evaluate) {
    if (_disposed) return;
    _owner = owner;
    _evaluate = evaluate;
    navigationStarted(null);
  }

  void detach(Object owner) {
    if (_disposed || !identical(owner, _owner)) return;
    _owner = null;
    _evaluate = null;
    navigationStarted(null);
  }

  void navigationStarted(String? url) {
    if (_disposed) return;
    _generation++;
    _url = url;
    _ready = false;
    _pending = null;
    notifyListeners();
  }

  void navigationFinished(String? url) {
    if (_disposed || url != _url) return;
    _ready = _webUrl(url);
    notifyListeners();
  }

  void historyChanged(String? url) {
    if (_disposed || url == _url) return;
    final wasReady = _ready;
    navigationStarted(url);
    if (wasReady) navigationFinished(url);
  }

  bool isCurrent(BookmarkReaderCapture capture) =>
      ready && capture.generation == _generation && capture.url == _url;

  Future<BookmarkReaderCapture?> capture() {
    if (!ready) return Future.value();
    return _pending ??= _capture(_generation, _url!, _evaluate!);
  }

  Future<BookmarkReaderCapture?> _capture(
    int generation,
    String url,
    Future<dynamic> Function(String) evaluate,
  ) async {
    try {
      final value = await Future<dynamic>.sync(
              () => evaluate(bookmarkVisibleArticleScript))
          .timeout(bookmarkReaderDeadline);
      if (!ready ||
          generation != _generation ||
          url != _url ||
          value is! String ||
          value.length > bookmarkReaderCaptureLimit * 2) {
        return null;
      }
      final data = jsonDecode(value);
      if (data is! Map || data['url'] != url || data['html'] is! String) {
        return null;
      }
      final html = data['html'] as String;
      if (utf8.encode(html).length > bookmarkReaderCaptureLimit) return null;
      final article = parseReadableArticle(html, baseUrl: Uri.parse(url));
      if (article.isEmpty) return null;
      return BookmarkReaderCapture(
          url: url, generation: generation, article: article);
    } on Object {
      return null;
    } finally {
      if (!_disposed && generation == _generation) _pending = null;
    }
  }

  static bool _webUrl(String? value) {
    final uri = Uri.tryParse(value ?? '');
    return uri != null &&
        const {'http', 'https'}.contains(uri.scheme) &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _evaluate = null;
    _owner = null;
    super.dispose();
  }
}

/// Walk rendered content WITHOUT mutating the live DOM or reading storage,
/// form values, scripts, JSON-LD, attributes carrying credentials, or frames.
/// Conservative: visible access gates/dialogs or clipped prose abort capture.
/// Text-only output intentionally has no image/link resource URLs.
const bookmarkVisibleArticleScript = r'''
(() => {
  if (!/^https?:$/.test(location.protocol) || !document.body) return null;
  const start = performance.now();
  let nodes = 0, size = 0;
  const escape = s => s.replace(/[&<>"']/g, c =>
    ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const denied = new Set(['SCRIPT','STYLE','NOSCRIPT','TEMPLATE','IFRAME',
    'OBJECT','EMBED','FORM','INPUT','TEXTAREA','SELECT','BUTTON','SVG','CANVAS']);
  const blocks = new Set(['P','H1','H2','H3','H4','H5','H6','UL','OL','LI',
    'BLOCKQUOTE','PRE','CODE','STRONG','EM','B','I','BR','HR','ARTICLE','MAIN']);
  const gate = /(^|[\s_-])(paywall|access-gate|subscription-wall|regwall)([\s_-]|$)/i;
  function walk(node, depth) {
    if (++nodes > 12000 || depth > 80 || performance.now() - start > 100) throw 0;
    if (node.nodeType === Node.TEXT_NODE) {
      const text = escape(node.textContent || '');
      size += text.length;
      if (size > 60000) throw 0;
      return text;
    }
    if (node.nodeType !== Node.ELEMENT_NODE || denied.has(node.tagName)) return '';
    const style = getComputedStyle(node);
    if (node.hidden || node.getAttribute('aria-hidden') === 'true' ||
        style.display === 'none' || style.visibility !== 'visible' ||
        Number(style.opacity) === 0 || style.contentVisibility === 'hidden') return '';
    if (node.tagName === 'DIALOG' || node.getAttribute('aria-modal') === 'true' ||
        gate.test((node.className || '') + ' ' + node.id) ||
        style.filter.includes('blur(') || style.clipPath !== 'none' ||
        (style.clip !== 'auto' && style.clip !== '')) throw 0;
    // Never expand content concealed behind a clipped subscriber teaser.
    if (['hidden','clip'].includes(style.overflowY) &&
        node.clientHeight > 0 && node.scrollHeight > node.clientHeight + 2) throw 0;
    if (node.tagName === 'DETAILS' && !node.open) return '';
    if (style.display !== 'contents' && !node.getClientRects().length) return '';
    let content = '';
    for (const child of node.childNodes) content += walk(child, depth + 1);
    const tag = blocks.has(node.tagName) ? node.tagName.toLowerCase() : 'div';
    size += tag.length * 2 + 5;
    if (size > 60000) throw 0;
    return '<' + tag + '>' + content + '</' + tag + '>';
  }
  try {
    const html = '<html><head><title>' + escape(document.title.slice(0, 500)) +
      '</title></head><body>' + walk(document.body, 0) + '</body></html>';
    return JSON.stringify({url: location.href, html});
  } catch (_) { return null; }
})()
''';
