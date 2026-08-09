import 'dart:convert';

import 'text_find.dart';

/// The name the find engine is installed under inside a rendered document.
const webViewFindObjectName = '__appFlowyFind';

/// The channel a rendered document uses to ask its host to open the find bar.
const webViewFindOpenHandlerName = 'appflowyFindOpen';

/// What a search inside a rendered document came back with.
class WebViewFindResult {
  const WebViewFindResult({
    required this.count,
    required this.index,
    this.invalid = false,
  });

  factory WebViewFindResult.fromJavaScript(Object? value) {
    final map = value is String
        ? jsonDecode(value) as Map<String, dynamic>?
        : value is Map
            ? value.cast<String, dynamic>()
            : null;
    if (map == null) {
      return const WebViewFindResult(count: 0, index: 0);
    }
    return WebViewFindResult(
      count: (map['count'] as num?)?.toInt() ?? 0,
      index: (map['index'] as num?)?.toInt() ?? 0,
      invalid: map['invalid'] == true,
    );
  }

  static const empty = WebViewFindResult(count: 0, index: 0);

  final int count;

  /// One based, for display; 0 when nothing is selected.
  final int index;
  final bool invalid;
}

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
      '$matchColor', '$currentColor', '$currentTextColor');
    return true;
  }
  var ns = {};
  ns.marks = [];
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
    for (var i = 0; i < ns.marks.length; i++) {
      var mark = ns.marks[i];
      var parent = mark.parentNode;
      if (!parent) continue;
      parent.replaceChild(document.createTextNode(mark.textContent), mark);
      parent.normalize();
    }
    ns.marks = [];
    ns.index = -1;
    return true;
  };

  ns.paint = function (scroll) {
    for (var i = 0; i < ns.marks.length; i++) {
      ns.marks[i].classList.toggle('appflowy-find-current', i === ns.index);
    }
    if (scroll && ns.index >= 0 && ns.marks[ns.index]) {
      ns.marks[ns.index].scrollIntoView({ block: 'center', inline: 'nearest' });
    }
  };

  ns.textNodes = function () {
    var walker = document.createTreeWalker(
      document.body,
      NodeFilter.SHOW_TEXT,
      {
        acceptNode: function (node) {
          if (!node.nodeValue || node.nodeValue.length === 0) {
            return NodeFilter.FILTER_REJECT;
          }
          var parent = node.parentNode;
          if (!parent) return NodeFilter.FILTER_REJECT;
          var tag = parent.nodeName;
          if (tag === 'SCRIPT' || tag === 'STYLE' || tag === 'NOSCRIPT') {
            return NodeFilter.FILTER_REJECT;
          }
          return NodeFilter.FILTER_ACCEPT;
        }
      }
    );
    var nodes = [];
    while (walker.nextNode()) nodes.push(walker.currentNode);
    return nodes;
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
    var nodes = ns.textNodes();
    for (var n = 0; n < nodes.length; n++) {
      var node = nodes[n];
      var text = node.nodeValue;
      var spans = [];
      expression.lastIndex = 0;
      var match;
      while ((match = expression.exec(text)) !== null) {
        if (match[0].length === 0) {
          expression.lastIndex++;
          continue;
        }
        spans.push([match.index, match.index + match[0].length]);
        if (ns.marks.length + spans.length > 4000) break;
      }
      if (spans.length === 0) continue;
      var fragment = document.createDocumentFragment();
      var cursor = 0;
      for (var s = 0; s < spans.length; s++) {
        var start = spans[s][0];
        var end = spans[s][1];
        if (start > cursor) {
          fragment.appendChild(
            document.createTextNode(text.slice(cursor, start)));
        }
        var mark = document.createElement('mark');
        mark.className = 'appflowy-find';
        mark.textContent = text.slice(start, end);
        fragment.appendChild(mark);
        ns.marks.push(mark);
        cursor = end;
      }
      if (cursor < text.length) {
        fragment.appendChild(document.createTextNode(text.slice(cursor)));
      }
      node.parentNode.replaceChild(fragment, node);
      if (ns.marks.length >= 4000) break;
    }
    ns.index = ns.marks.length > 0 ? 0 : -1;
    ns.paint(true);
    return { count: ns.marks.length, index: ns.index + 1 };
  };

  ns.move = function (forward) {
    if (ns.marks.length === 0) return { count: 0, index: 0 };
    if (forward) {
      ns.index = ns.index >= ns.marks.length - 1 ? 0 : ns.index + 1;
    } else {
      ns.index = ns.index <= 0 ? ns.marks.length - 1 : ns.index - 1;
    }
    ns.paint(true);
    return { count: ns.marks.length, index: ns.index + 1 };
  };

  globalThis.$webViewFindObjectName = ns;
  ns.applyColors('$matchColor', '$currentColor', '$currentTextColor');
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
    if ((event.ctrlKey || event.metaKey) && key === 'f') {
      event.preventDefault();
      if (window.flutter_inappwebview) {
        window.flutter_inappwebview.callHandler('$webViewFindOpenHandlerName');
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
