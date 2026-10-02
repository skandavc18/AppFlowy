import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';

import 'readable_article.dart';

/// The most captured HTML Reader parses, in UTF-8 bytes. The page script
/// stops well short of it; this only bounds a page that does not.
const bookmarkReaderCaptureLimit = 2 * 1024 * 1024;

/// How long one step may take: an answer from the page, a snapshot read.
const bookmarkReaderDeadline = Duration(seconds: 5);

/// How long Reader waits for a page that is still loading to be readable.
const bookmarkReaderPageDeadline = Duration(seconds: 20);

/// How often a page that is not readable yet is asked again.
const bookmarkReaderRetryInterval = Duration(milliseconds: 250);

/// Captures at least this long are parsed off the UI isolate.
const _backgroundParseLength = 64 * 1024;

/// Why a capture came back empty.
enum BookmarkReaderFailure {
  /// Nothing readable, or the page did not answer in time.
  unavailable,

  /// A sign-in, subscription or consent prompt covers the page.
  gated,

  /// The page went somewhere else while Reader waited for it.
  navigated,
}

enum BookmarkReadingMode {
  live,
  reader,
  offline,

  /// As the site shows the link embedded: a pin's card, a video's player, a
  /// sheet's preview. Only for a link a site extension knows.
  embed,
}

/// String keys work before generated locale constants/assets are refreshed.
abstract final class BookmarkReaderStrings {
  static String _text(String name, String fallback) {
    final key = 'collections.bookmark.$name';
    final translated = key.tr();
    return translated == key ? fallback : translated;
  }

  static String get reader => _text('reader', 'Reader');
  static String siteView(String site) =>
      _text('siteView', 'As {} shows it').replaceFirst('{}', site);
  static String get unavailable => _text('readerUnavailable',
      'Reader is unavailable for this page. Open Live to continue.');
  static String get gated => _text(
      'readerGated',
      'A sign-in, subscription or consent prompt covers this page. '
          'Answer it in Live, then open Reader again.');
  static String get preparing => _text('readerPreparing', 'Reading the page…');
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
  BookmarkReadingSession({
    this.pageDeadline = bookmarkReaderPageDeadline,
    this.retryInterval = bookmarkReaderRetryInterval,
  });

  /// How long [capture] waits for a page that is still loading.
  final Duration pageDeadline;

  /// How often [capture] asks such a page again.
  final Duration retryInterval;

  Object? _owner;
  Future<dynamic> Function(String)? _evaluate;
  String? _url;
  int _generation = 0;
  bool _ready = false;
  bool _disposed = false;
  Future<BookmarkReaderCapture?>? _pending;
  BookmarkReaderFailure? _failure;
  final _sleepers = <Completer<void>>[];
  Timer? _retry;

  String? get url => _url;
  int get generation => _generation;

  /// Whether the page has finished loading.
  bool get ready => !_disposed && _ready && _evaluate != null;

  /// Whether a web page is on its way that [capture] can ask for its text. It
  /// may still be loading: a capture waits for it to be readable.
  bool get canRead => !_disposed && _evaluate != null && _webUrl(_url);

  /// Why the last capture came back empty.
  BookmarkReaderFailure? get lastFailure => _failure;

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
    _wakeSleepers();
    notifyListeners();
  }

  void navigationFinished(String? url) {
    if (_disposed || url != _url) return;
    _ready = _webUrl(url);
    _wakeSleepers();
    notifyListeners();
  }

  void historyChanged(String? url) {
    if (_disposed || url == _url) return;
    final wasReady = _ready;
    navigationStarted(url);
    if (wasReady) navigationFinished(url);
  }

  bool isCurrent(BookmarkReaderCapture capture) =>
      canRead && capture.generation == _generation && capture.url == _url;

  /// Reads the visible article of the page being shown. A page still loading,
  /// or still showing the document it is leaving, is asked again until it can
  /// be read or [pageDeadline] passes; navigating meanwhile ends the wait.
  Future<BookmarkReaderCapture?> capture() {
    if (!canRead) {
      _failure = BookmarkReaderFailure.unavailable;
      return Future.value();
    }
    return _pending ??= _capture(_generation, _url!, _evaluate!);
  }

  Future<BookmarkReaderCapture?> _capture(
    int generation,
    String url,
    Future<dynamic> Function(String) evaluate,
  ) async {
    _failure = null;
    // Counted as well as timed: a fake clock in tests never runs the watch.
    var retries = pageDeadline.inMicroseconds ~/
        math.max(1, retryInterval.inMicroseconds);
    final waited = Stopwatch()..start();
    bool current() => !_disposed && generation == _generation;
    BookmarkReaderCapture? fail(BookmarkReaderFailure failure) {
      _failure = current() ? failure : BookmarkReaderFailure.navigated;
      return null;
    }

    try {
      while (true) {
        Object? value;
        // The page could not answer. While it loads, the document being
        // replaced may fail to; a loaded page that fails cannot be read.
        var answered = true;
        try {
          value = await Future<dynamic>.sync(
            () => evaluate(bookmarkVisibleArticleScript),
          ).timeout(bookmarkReaderDeadline);
        } on Object {
          answered = false;
        }
        if (!current()) return fail(BookmarkReaderFailure.navigated);
        final reading = answered
            ? _PageReading.of(value, url, loaded: _ready)
            : _ready
                ? const _PageReading(_PageState.unreadable)
                : const _PageReading(_PageState.notYet);
        switch (reading.state) {
          case _PageState.gated:
            return fail(BookmarkReaderFailure.gated);
          case _PageState.unreadable:
            return fail(BookmarkReaderFailure.unavailable);
          case _PageState.notYet:
            if (retries-- <= 0 || waited.elapsed >= pageDeadline) {
              return fail(BookmarkReaderFailure.unavailable);
            }
            await _sleep();
            if (!current()) return fail(BookmarkReaderFailure.navigated);
          case _PageState.readable:
            final article = await _parse(reading.html!, url);
            if (!current()) return fail(BookmarkReaderFailure.navigated);
            if (article.isEmpty) return fail(BookmarkReaderFailure.unavailable);
            return BookmarkReaderCapture(
              url: url,
              generation: generation,
              article: article,
            );
        }
      }
    } on Object {
      return fail(BookmarkReaderFailure.unavailable);
    } finally {
      if (!_disposed && generation == _generation) _pending = null;
    }
  }

  /// Waits one retry interval, or less when the page moves on.
  Future<void> _sleep() {
    final sleeper = Completer<void>();
    _sleepers.add(sleeper);
    _retry ??= Timer(retryInterval, _wakeSleepers);
    return sleeper.future;
  }

  void _wakeSleepers() {
    _retry?.cancel();
    _retry = null;
    final sleepers = List.of(_sleepers);
    _sleepers.clear();
    for (final sleeper in sleepers) {
      if (!sleeper.isCompleted) sleeper.complete();
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
    _wakeSleepers();
    super.dispose();
  }
}

enum _PageState { notYet, readable, gated, unreadable }

/// What the page said when asked for its article.
class _PageReading {
  const _PageReading(this.state, [this.html]);

  /// [url] is the address being read. A different one means the page is
  /// still showing the document it is leaving. A page that has [loaded] and
  /// still has no web document never will.
  factory _PageReading.of(Object? value, String url, {required bool loaded}) {
    // No web document yet: the blank page a view starts on.
    if (value == null) {
      return _PageReading(loaded ? _PageState.unreadable : _PageState.notYet);
    }
    if (value is! String || value.length > bookmarkReaderCaptureLimit * 2) {
      return const _PageReading(_PageState.unreadable);
    }
    final Object? data;
    try {
      data = jsonDecode(value);
    } on FormatException {
      return const _PageReading(_PageState.unreadable);
    }
    if (data is! Map || data['url'] is! String) {
      return const _PageReading(_PageState.unreadable);
    }
    if (data['url'] != url || data['loading'] == true) {
      return const _PageReading(_PageState.notYet);
    }
    if (data['gate'] == true) return const _PageReading(_PageState.gated);
    final html = data['html'];
    if (html is! String ||
        utf8.encode(html).length > bookmarkReaderCaptureLimit) {
      return const _PageReading(_PageState.unreadable);
    }
    return _PageReading(_PageState.readable, html);
  }

  final _PageState state;
  final String? html;
}

/// A long article is parsed off the UI isolate, so reading it never stalls
/// the popup.
Future<ReadableArticle> _parse(String html, String url) async {
  if (html.length < _backgroundParseLength) {
    return parseReadableArticle(html, baseUrl: Uri.parse(url));
  }
  return compute(_parseInBackground, (html, url));
}

ReadableArticle _parseInBackground((String, String) page) =>
    parseReadableArticle(page.$1, baseUrl: Uri.parse(page.$2));

/// Walk rendered content WITHOUT mutating the live DOM or reading storage,
/// form values, scripts, JSON-LD, attributes carrying credentials, or frames.
/// Only what is on screen is read: hidden, screen-reader-only, blurred and
/// clipped-away text (a teaser's concealed rest) is skipped, and a visible
/// paywall or a prompt covering the page stops the capture as a gate.
/// A page still loading answers `loading`; a huge one is cut short, not lost.
/// Text-only output intentionally has no image/link resource URLs.
const bookmarkVisibleArticleScript = r'''
(() => {
  if (!/^https?:$/.test(location.protocol) || !document.body) return null;
  const url = location.href;
  if (document.readyState === 'loading') {
    return JSON.stringify({url, loading: true});
  }
  const start = performance.now();
  const viewWidth = window.innerWidth || 0, viewHeight = window.innerHeight || 0;
  const viewArea = Math.max(1, viewWidth * viewHeight);
  let nodes = 0, size = 0, truncated = false, gated = false;
  const escape = s => s.replace(/[&<>"']/g, c =>
    ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const xhtml = 'http://www.w3.org/1999/xhtml';
  const denied = new Set(['SCRIPT','STYLE','NOSCRIPT','TEMPLATE','IFRAME',
    'FRAME','OBJECT','EMBED','FORM','INPUT','TEXTAREA','SELECT','BUTTON',
    'CANVAS','VIDEO','AUDIO']);
  // Kept by name, so paragraphs stay whole and the parser can drop navigation.
  // Links keep no address: they only tell a list of links from prose.
  const kept = new Set(['P','H1','H2','H3','H4','H5','H6','UL','OL','LI',
    'BLOCKQUOTE','PRE','CODE','STRONG','EM','B','I','U','S','SMALL','SUB',
    'SUP','MARK','Q','CITE','ABBR','TIME','KBD','SAMP','VAR','DEL','INS','A',
    'ARTICLE','MAIN','SECTION','HEADER','FOOTER','NAV','ASIDE','FIGURE',
    'FIGCAPTION','TABLE','CAPTION','THEAD','TBODY','TFOOT','TR','TH','TD',
    'DL','DT','DD']);
  const gate = /(^|[\s_-])(paywall|access-gate|subscription-wall|regwall)([\s_-]|$)/i;
  // A landmark role says what a plain element is for, as its tag would.
  const landmarks = new Map([['navigation', 'nav'], ['complementary', 'aside'],
    ['contentinfo', 'footer'], ['banner', 'header'], ['main', 'main']]);
  // One generic word for the parser's scoring; the names themselves stay here.
  const furniture = /(?:^|[\s_-])(ad|ads|advert|advertisement|banner|bibliography|breadcrumb|byline|citations|comment|comments|cookie|disqus|footer|header|hidden|masthead|menu|modal|nav|navbar|newsletter|paywall|popup|promo|references|reflist|related|share|sharing|sidebar|signup|social|sponsor|subscribe|toolbar|widget)(?=[\s_-]|$)/i;
  const content = /(?:^|[\s_-])(article|body|content|entry|main|markdown|post|prose|story|text)(?=[\s_-]|$)/i;
  const clipped = value => value === 'hidden' || value === 'clip';
  const scrolls = value => value === 'auto' || value === 'scroll' || value === 'overlay';
  const covers = rect => {
    const width = Math.min(rect.right, viewWidth) - Math.max(rect.left, 0);
    const height = Math.min(rect.bottom, viewHeight) - Math.max(rect.top, 0);
    return width > 0 && height > 0 && width * height >= viewArea * 0.3;
  };
  function walk(node, depth, clip) {
    if (truncated || gated) return '';
    if (++nodes > 60000 || performance.now() - start > 400) {
      truncated = true;
      return '';
    }
    if (node.nodeType === Node.TEXT_NODE) {
      const text = escape(node.textContent || '');
      if ((size += text.length) > 500000) {
        truncated = true;
        return '';
      }
      return text;
    }
    if (node.nodeType !== Node.ELEMENT_NODE || depth > 160 ||
        node.namespaceURI !== xhtml || denied.has(node.tagName) ||
        node.isContentEditable) return '';
    const style = getComputedStyle(node);
    if (node.hidden || node.getAttribute('aria-hidden') === 'true' ||
        style.display === 'none' || style.visibility !== 'visible' ||
        Number(style.opacity) === 0 || style.contentVisibility === 'hidden') return '';
    const contents = style.display === 'contents';
    if (!contents && !node.getClientRects().length) return '';
    const rect = contents ? null : node.getBoundingClientRect();
    const marker = (typeof node.className === 'string' ? node.className : '') +
      ' ' + node.id;
    const prompt = node.tagName === 'DIALOG' ||
      node.getAttribute('aria-modal') === 'true' ||
      /^(alert)?dialog$/i.test(node.getAttribute('role') || '');
    if (gate.test(marker) || (prompt && rect && covers(rect))) {
      gated = true;
      return '';
    }
    // A small prompt beside the page, a screen-reader-only label and blurred
    // text are not what the page shows.
    if (prompt || (style.clip !== 'auto' && style.clip !== '') ||
        style.filter.includes('blur(')) return '';
    if (rect && (clipped(style.overflowX) || clipped(style.overflowY)) &&
        (rect.width < 2 || rect.height < 2)) return '';
    if (rect && style.position !== 'fixed' &&
        (rect.right <= clip.left || rect.left >= clip.right ||
         rect.bottom <= clip.top || rect.top >= clip.bottom)) return '';
    // What this element clips away is concealed; what it scrolls is not.
    let inner = clip;
    if (rect && node !== document.body && node !== document.documentElement) {
      const x = style.overflowX, y = style.overflowY;
      if (clipped(x) || clipped(y) || scrolls(x) || scrolls(y)) {
        inner = {
          left: clipped(x) ? Math.max(clip.left, rect.left) :
            scrolls(x) ? -Infinity : clip.left,
          right: clipped(x) ? Math.min(clip.right, rect.right) :
            scrolls(x) ? Infinity : clip.right,
          top: clipped(y) ? Math.max(clip.top, rect.top) :
            scrolls(y) ? -Infinity : clip.top,
          bottom: clipped(y) ? Math.min(clip.bottom, rect.bottom) :
            scrolls(y) ? Infinity : clip.bottom,
        };
      }
    }
    let inside = '';
    if (node.tagName === 'DETAILS' && !node.open) {
      for (const child of node.children) {
        if (child.tagName === 'SUMMARY') inside += walk(child, depth + 1, inner);
      }
    } else {
      for (const child of node.childNodes) inside += walk(child, depth + 1, inner);
    }
    if (node.tagName === 'BR' || node.tagName === 'HR') {
      return '<' + node.tagName.toLowerCase() + '>';
    }
    const landmark = landmarks.get((node.getAttribute('role') || '').toLowerCase());
    const tag = landmark || (kept.has(node.tagName) ? node.tagName.toLowerCase() :
      style.display.startsWith('inline') ? 'span' : 'div');
    const roles = [marker.match(content), marker.match(furniture)]
      .map(match => match && match[1].toLowerCase()).filter(Boolean).join(' ');
    const open = roles ? '<' + tag + ' class="' + roles + '">' : '<' + tag + '>';
    if ((size += open.length + tag.length + 3) > 500000) truncated = true;
    return open + inside + '</' + tag + '>';
  }
  try {
    const body = walk(document.body, 0,
      {left: -Infinity, top: -Infinity, right: Infinity, bottom: Infinity});
    if (gated) return JSON.stringify({url, gate: true});
    const html = '<html><head><title>' + escape(document.title.slice(0, 500)) +
      '</title></head><body>' + body + '</body></html>';
    return JSON.stringify({url, html, truncated});
  } catch (_) {
    return JSON.stringify({url, error: true});
  }
})()
''';
