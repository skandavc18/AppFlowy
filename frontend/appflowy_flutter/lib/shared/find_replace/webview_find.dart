import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'text_find.dart';

/// Windows may supply distinct public wrappers for one platform controller.
/// Compare that object's identity, not view IDs that can be reused.
bool sameWebViewController(
  InAppWebViewController? first,
  InAppWebViewController? second,
) =>
    first != null &&
    second != null &&
    identical(first.platform, second.platform);

/// The name the find engine is installed under inside a rendered document.
const webViewFindObjectName = '__appFlowyFind';

/// The channel a rendered document uses to ask its host to open the find bar.
const webViewFindOpenHandlerName = 'appflowyFindOpen';

const webViewFindBindingName = '__appFlowyFindOpen';

/// The standard plugin channel remains available on all supported platforms.
/// WebView2 also needs a binding in the isolated world created after load:
/// its plugin bridge is otherwise only injected on the NEXT document load.
Future<void> installWebViewFindOpenBridge(
  InAppWebViewController controller, {
  required ContentWorld contentWorld,
  required VoidCallback onFind,
  required bool Function() isCurrent,
}) async {
  controller.addJavaScriptHandler(
    handlerName: webViewFindOpenHandlerName,
    callback: (_) {
      if (isCurrent()) onFind();
      return null;
    },
  );
  if (!Platform.isWindows || !isCurrent()) return;
  await controller.addDevToolsProtocolEventListener(
    eventName: 'Runtime.bindingCalled',
    callback: (data) {
      if (isCurrent() &&
          data is Map &&
          data['name'] == webViewFindBindingName &&
          data['payload'] == webViewFindOpenHandlerName) {
        onFind();
      }
    },
  );
  if (!isCurrent()) return;
  await controller.callDevToolsProtocolMethod(
    methodName: 'Runtime.addBinding',
    parameters: {
      'name': webViewFindBindingName,
      'executionContextName': contentWorld.name,
    },
  );
}

/// What a search inside a rendered document came back with.
class WebViewFindResult {
  const WebViewFindResult({
    required this.count,
    required this.index,
    this.invalid = false,
  });

  factory WebViewFindResult.fromJavaScript(Object? value) {
    final decoded = _decodeJavaScriptValue(value);
    if (decoded == null) return empty;
    if (decoded is! Map) {
      throw const FormatException('Expected a webview find result object');
    }
    if (decoded['error'] != null || decoded['exceptionDetails'] != null) {
      throw const FormatException('Webview returned a JavaScript exception');
    }
    final invalid = decoded['invalid'];
    final count = decoded['count'] ?? (invalid == true ? 0 : null);
    final index = decoded['index'] ?? (invalid == true ? 0 : null);
    if (count is! num ||
        !count.isFinite ||
        count != count.truncate() ||
        index is! num ||
        !index.isFinite ||
        index != index.truncate() ||
        count < 0 ||
        index < 0 ||
        index > count ||
        (invalid != null && invalid is! bool)) {
      // An exception envelope or malformed bridge response is not "0 hits".
      throw const FormatException('Invalid webview find result');
    }
    return WebViewFindResult(
      count: count.toInt(),
      index: index.toInt(),
      invalid: invalid == true,
    );
  }

  static const empty = WebViewFindResult(count: 0, index: 0);

  final int count;

  /// One based, for display; 0 when nothing is selected.
  final int index;
  final bool invalid;
}

// WebView2 and the platform plugin can each JSON-encode the result. Decode
// those layers, but do not swallow JSON errors or turn arbitrary strings into
// empty results. The bound also rejects pathological nested encodings.
Object? _decodeJavaScriptValue(Object? value) {
  for (var depth = 0; value is String && depth < 8; depth++) {
    value = jsonDecode(value);
  }
  return value;
}

typedef WebViewFindEvaluator = Future<Object?> Function(String source);

/// Only the asynchronous bridge state, not a replacement search engine.
///
/// Hosts keep their controllers, focus, debounce and UI. The injected evaluator
/// executes the real commands below in the SAME content world as installation.
/// Null means not ready or superseded; a successful zero count is an object.
/// Evaluation/decoding exceptions propagate to the host's error reporting.
class WebViewFindSession {
  WebViewFindEvaluator? _evaluate;
  int _document = 0;
  int _installation = 0;
  int _request = 0;
  bool _open = false;
  bool _ready = false;
  bool _queryApplied = false;
  String _query = '';
  FindOptions _options = const FindOptions();

  bool get ready => _ready;
  bool get pending => _open && (!_ready || !_queryApplied);

  /// Call on controller creation AND each main-document load start. Retain the
  /// pending query so a load stop retries even if it was typed before readiness.
  void attach(WebViewFindEvaluator? evaluate) {
    _evaluate = evaluate;
    _document++;
    _ready = false;
    invalidatePending();
  }

  void invalidatePending() {
    _installation++;
    _request++;
    _queryApplied = false;
  }

  bool setQuery(String query, FindOptions options) {
    if (_query == query && _options == options) return false;
    _query = query;
    _options = options;
    _request++;
    _queryApplied = false;
    return true;
  }

  void open() {
    if (_open) return;
    _open = true;
    _request++;
    _queryApplied = false;
  }

  Future<WebViewFindResult?> install(String source) async {
    final evaluate = _evaluate;
    if (evaluate == null) return null;
    final document = _document;
    final installation = ++_installation;
    final value = await evaluate(source);
    if (document != _document || installation != _installation) return null;
    _ready = _decodeJavaScriptValue(value) == true;
    if (_ready && _open) return find();
    return null;
  }

  Future<WebViewFindResult?> find() =>
      _command(buildWebViewFindCommand(_query, _options));

  Future<WebViewFindResult?> move({required bool forward}) => _queryApplied
      ? _command(buildWebViewFindMoveCommand(forward: forward))
      : find();

  Future<WebViewFindResult?> _command(String source) async {
    final evaluate = _evaluate;
    if (evaluate == null || !_ready || !_open) return null;
    final document = _document;
    final request = ++_request;
    final value = await evaluate(source);
    if (document != _document || request != _request || !_open) return null;
    final decoded = _decodeJavaScriptValue(value);
    if (decoded == null) {
      // The document navigated before its load callback reached Dart. Do not
      // publish a false zero; the next installation will retry the query.
      _ready = false;
      _queryApplied = false;
      return null;
    }
    final result = WebViewFindResult.fromJavaScript(decoded);
    _queryApplied = true;
    return result;
  }

  Future<void> close() async {
    _open = false;
    _request++;
    _queryApplied = false;
    final evaluate = _evaluate;
    if (evaluate != null && _ready) {
      await evaluate(buildWebViewFindClearCommand());
    }
  }

  void dispose() {
    _open = false;
    attach(null);
  }
}

/// Keep readiness last: scrollbar/style IIFEs often evaluate to undefined.
String buildWebViewFindInstallScript({
  required String matchColor,
  required String currentColor,
  required String currentTextColor,
  Iterable<String> additionalScripts = const [],
}) =>
    '''
${buildWebViewFindEngineScript(
      matchColor: matchColor,
      currentColor: currentColor,
      currentTextColor: currentTextColor,
    )}
${additionalScripts.join('\n')}
${buildWebViewFindShortcutScript()}
document.body != null &&
  typeof globalThis.$webViewFindObjectName?.find === 'function' &&
  globalThis.__appFlowyFindShortcut === true;
''';

/// Installs the find engine in a rendered document.
///
/// The engine marks matches in the page itself rather than reporting offsets
/// back, because only the renderer knows where a word ended up after the
/// document was laid out.
String buildWebViewFindEngineScript({
  required String matchColor,
  required String currentColor,
  required String currentTextColor,
}) =>
    '''
(function () {
  if (globalThis.$webViewFindObjectName) {
    globalThis.$webViewFindObjectName.applyColors(
      ${jsonEncode(matchColor)}, ${jsonEncode(currentColor)},
      ${jsonEncode(currentTextColor)});
    return true;
  }
  var ns = {};
  ns.groups = [];
  ns.replacements = [];
  ns.index = -1;
  ns.styleNode = null;

  ns.applyColors = function (match, current, currentText) {
    if (!ns.styleNode) {
      ns.styleNode = document.createElement('style');
      document.documentElement.appendChild(ns.styleNode);
    }
    ns.styleNode.textContent =
      'mark.appflowy-find{background:' + match + ';color:inherit;' +
      'border-radius:2px;padding:0;}' +
      'mark.appflowy-find-current{background:' + current + ';color:' +
      currentText + ';}';
  };

  ns.clear = function () {
    for (var record of ns.replacements) {
      var nodes = record.nodes;
      var intact = nodes.every(function (node, i) {
        return node.parentNode === record.parent &&
          (i === 0 || nodes[i - 1].nextSibling === node);
      }) && record.marks.every(function (mark) {
        // Preserve elements/listeners a live page inserted inside a mark too.
        return Array.from(mark.childNodes).every(function (node) {
          return node.nodeType === Node.TEXT_NODE;
        });
      });
      if (intact) {
        // Restore the original text node, not innerHTML or parent.normalize():
        // inline elements, listeners and originally separate text nodes survive.
        record.original.nodeValue = nodes.map(function (node) {
          return node.textContent;
        }).join('');
        record.parent.replaceChild(record.original, nodes[0]);
        for (var i = 1; i < nodes.length; i++) nodes[i].remove();
      } else {
        // A live site changed this subtree while find was open. Unwrap only
        // our remaining marks, without restoring obsolete document contents.
        for (var mark of record.marks) {
          if (!mark.parentNode) continue;
          while (mark.firstChild) {
            mark.parentNode.insertBefore(mark.firstChild, mark);
          }
          mark.remove();
        }
      }
    }
    ns.groups = [];
    ns.replacements = [];
    ns.index = -1;
    return true;
  };

  ns.paint = function (scroll) {
    for (var i = 0; i < ns.groups.length; i++) {
      for (var mark of ns.groups[i]) {
        mark.classList.toggle('appflowy-find-current', i === ns.index);
      }
    }
    var current = ns.index >= 0 && ns.groups[ns.index].find(function (mark) {
      return mark.isConnected;
    });
    if (scroll && current) {
      current.scrollIntoView({ block: 'center', inline: 'nearest' });
    }
  };

  // Runs join formatted inline text, but never unrelated paragraphs/cells.
  // Each part maps readable (whitespace-collapsed) offsets back to real DOM
  // text. A phrase split over <b>/<a>/<span> is still one logical match.
  ns.textRuns = function () {
    var runs = [];
    var parts = [];
    var chunks = [];
    var length = 0;
    var lastSpace = false;
    var excluded = new Set([
      'SCRIPT', 'STYLE', 'NOSCRIPT', 'TEMPLATE', 'TEXTAREA', 'INPUT', 'SELECT'
    ]);
    function flush() {
      if (parts.length) runs.push({ text: chunks.join(''), parts: parts });
      parts = [];
      chunks = [];
      length = 0;
      lastSpace = false;
    }
    function append(node, start, end, text) {
      parts.push({ node: node, start: start, end: end,
        from: length, to: length + text.length });
      chunks.push(text);
      length += text.length;
      lastSpace = text.endsWith(' ');
    }
    function visit(node, whiteSpace) {
      if (node.nodeType === Node.TEXT_NODE) {
        var text = node.nodeValue;
        if (!text) return;
        if (['pre', 'pre-wrap', 'break-spaces'].includes(whiteSpace)) {
          append(node, 0, text.length, text);
          return;
        }
        var pieces = /[\\t\\n\\r\\f ]+|[^\\t\\n\\r\\f ]+/g;
        var piece;
        while ((piece = pieces.exec(text)) !== null) {
          var space = /^[\\t\\n\\r\\f ]/.test(piece[0]);
          if (space && (!length || lastSpace)) continue;
          append(node, piece.index, piece.index + piece[0].length,
            space ? ' ' : piece[0]);
        }
        return;
      }
      if (node.nodeType !== Node.ELEMENT_NODE || excluded.has(node.tagName) ||
          node.matches('[hidden], [aria-hidden="true"], ' +
            '[data-appflowy-find-ui], [data-appflowy-find-ignore], ' +
            '.appflowy-find-ui, [role="search"]')) return;
      var style = getComputedStyle(node);
      if (style.display === 'none' || style.visibility === 'hidden' ||
          style.visibility === 'collapse' || style.opacity === '0' ||
          style.contentVisibility === 'hidden') return;
      var block = node.tagName === 'BR' ||
        (style.display && style.display !== 'contents' &&
          style.display !== 'inline' && !style.display.startsWith('inline-'));
      if (block) flush();
      for (var child of node.childNodes) {
        visit(child, style.whiteSpace || whiteSpace);
      }
      if (block) flush();
    }
    if (document.body) visit(document.body, 'normal');
    flush();
    return runs;
  };

  ns.find = function (source, flags) {
    ns.clear();
    if (!source) return { count: 0, index: 0 };
    var expression;
    try {
      expression = new RegExp(source, flags);
    } catch (error) {
      return { count: 0, index: 0, invalid: true };
    }
    var byNode = new Map();
    for (var run of ns.textRuns()) {
      expression.lastIndex = 0;
      var match;
      var firstPart = 0;
      while (ns.groups.length < 4000 &&
          (match = expression.exec(run.text)) !== null) {
        if (match[0].length === 0) {
          expression.lastIndex++;
          continue;
        }
        var end = match.index + match[0].length;
        var group = [];
        ns.groups.push(group);
        while (run.parts[firstPart].to <= match.index) firstPart++;
        for (var p = firstPart; p < run.parts.length; p++) {
          var part = run.parts[p];
          if (part.from >= end) break;
          var direct = part.end - part.start === part.to - part.from;
          var startInNode = direct
            ? part.start + Math.max(0, match.index - part.from) : part.start;
          var endInNode = direct
            ? part.start + Math.min(part.to, end) - part.from : part.end;
          var spans = byNode.get(part.node) || [];
          var previous = spans[spans.length - 1];
          if (previous && previous.group === group) {
            previous.end = endInNode;
          } else {
            spans.push({ start: startInNode, end: endInNode, group: group });
          }
          byNode.set(part.node, spans);
        }
      }
      if (ns.groups.length >= 4000) break;
    }
    for (var entry of byNode) {
      var node = entry[0];
      var text = node.nodeValue;
      var fragment = document.createDocumentFragment();
      var cursor = 0;
      var marks = [];
      for (var span of entry[1]) {
        if (span.start > cursor) {
          fragment.appendChild(
            document.createTextNode(text.slice(cursor, span.start)));
        }
        var mark = document.createElement('mark');
        mark.className = 'appflowy-find';
        mark.textContent = text.slice(span.start, span.end);
        fragment.appendChild(mark);
        marks.push(mark);
        span.group.push(mark);
        cursor = span.end;
      }
      if (cursor < text.length) {
        fragment.appendChild(document.createTextNode(text.slice(cursor)));
      }
      ns.replacements.push({ original: node, parent: node.parentNode,
        nodes: Array.from(fragment.childNodes), marks: marks });
      node.parentNode.replaceChild(fragment, node);
    }
    ns.index = ns.groups.length > 0 ? 0 : -1;
    ns.paint(true);
    return { count: ns.groups.length, index: ns.index + 1 };
  };

  ns.move = function (forward) {
    if (ns.groups.length === 0) return { count: 0, index: 0 };
    if (forward) {
      ns.index = ns.index >= ns.groups.length - 1 ? 0 : ns.index + 1;
    } else {
      ns.index = ns.index <= 0 ? ns.groups.length - 1 : ns.index - 1;
    }
    ns.paint(true);
    return { count: ns.groups.length, index: ns.index + 1 };
  };

  globalThis.$webViewFindObjectName = ns;
  ns.applyColors(${jsonEncode(matchColor)}, ${jsonEncode(currentColor)},
    ${jsonEncode(currentTextColor)});
  return true;
})();
''';

/// Lets the document itself ask for the find bar.
///
/// A rendered page takes the keyboard as soon as it is clicked, so the host's
/// own shortcut would never fire once somebody has selected a word.
String buildWebViewFindShortcutScript() => '''
(function () {
  if (globalThis.__appFlowyFindShortcut) return true;
  globalThis.__appFlowyFindShortcut = true;
  document.addEventListener('keydown', function (event) {
    var key = (event.key || '').toLowerCase();
    var bridge = window.flutter_inappwebview;
    var binding = globalThis.$webViewFindBindingName;
    var canOpen = typeof binding === 'function' ||
      (bridge && typeof bridge.callHandler === 'function');
    if (event.ctrlKey !== event.metaKey && !event.altKey && !event.shiftKey &&
        key === 'f' && canOpen) {
      event.preventDefault();
      event.stopPropagation();
      if (!event.repeat) {
        if (typeof binding === 'function') {
          binding('$webViewFindOpenHandlerName');
        } else {
          bridge.callHandler('$webViewFindOpenHandlerName');
        }
      }
    }
  }, true);
  return true;
})();
''';

/// Runs a search in a rendered document.
String buildWebViewFindCommand(String query, FindOptions options) {
  final source = query.isEmpty ? '' : findPatternSource(query, options);
  final flags = options.caseSensitive ? 'gm' : 'gmi';
  return "globalThis.$webViewFindObjectName"
      "?.find(${jsonEncode(source)}, ${jsonEncode(flags)}) ?? null;";
}

/// Moves to the next or previous match in a rendered document.
String buildWebViewFindMoveCommand({required bool forward}) =>
    'globalThis.$webViewFindObjectName?.move($forward) ?? null;';

/// Takes every mark back out of a rendered document.
String buildWebViewFindClearCommand() =>
    'globalThis.$webViewFindObjectName?.clear() ?? null;';
