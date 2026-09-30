import 'dart:convert';

import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// The CSS family the bundled interface face is registered under.
const officeUiFontFamily = 'AppFlowy UI';

const _bundledUiFaces = {
  'DM Sans': 'assets/google_fonts/DM_Sans/DMSans-Variable.ttf',
  'Inter': 'assets/google_fonts/Inter/Inter-Variable.ttf',
};

/// The app's interface typeface, restated for ONLYOFFICE's own chrome.
@immutable
class OfficeEditorTypography {
  const OfficeEditorTypography({required this.family, this.fontFace = ''});

  /// The family chosen in Appearance settings.
  final String family;

  /// `@font-face` for [officeUiFontFamily], or empty when unavailable.
  final String fontFace;

  bool get isBundled => _bundledUiFaces.containsKey(family);

  @override
  bool operator ==(Object other) =>
      other is OfficeEditorTypography &&
      other.family == family &&
      other.fontFace == fontFace;

  @override
  int get hashCode => Object.hash(family, fontFace);
}

final _typography = <String, OfficeEditorTypography>{};

/// Reads the variable face once per family. A family the app downloads at
/// runtime keeps the bundled face as its fallback.
Future<OfficeEditorTypography> loadOfficeEditorTypography(
  String family, {
  AssetBundle? bundle,
}) async {
  final resolved = resolveFontFamily(family);
  final cached = bundle == null ? _typography[resolved] : null;
  if (cached != null) return cached;
  final typography = await _readTypography(resolved, bundle ?? rootBundle);
  if (bundle == null && typography.fontFace.isNotEmpty) {
    _typography[resolved] = typography;
  }
  return typography;
}

Future<OfficeEditorTypography> _readTypography(
  String family,
  AssetBundle bundle,
) async {
  final asset =
      _bundledUiFaces[family] ?? _bundledUiFaces[preferredFontFamily]!;
  try {
    final bytes = await bundle.load(asset);
    final data = base64Encode(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    // Clamping the weight range renders unstyled text at the app's regular
    // weight while bold stays bold.
    return OfficeEditorTypography(
      family: family,
      fontFace: '@font-face{font-family:"$officeUiFontFamily";'
          'font-style:normal;'
          'font-weight:${defaultFontWeightValue.round()} 1000;'
          'font-display:block;'
          'src:url(data:font/ttf;base64,$data) format("truetype");}',
    );
  } catch (_) {
    return OfficeEditorTypography(family: family);
  }
}

String _cssFamily(String family) =>
    family.replaceAll(RegExp('[^A-Za-z0-9 _-]'), '').trim();

/// Interface font, smoother text and macOS-like scroll bars for the editor UI.
@visibleForTesting
String officeEditorChromeCss(OfficeEditorTypography typography) {
  final requested = _cssFamily(typography.family);
  // An installed copy of a downloaded family wins over the bundled fallback.
  final stack = [
    if (!typography.isBundled && requested.isNotEmpty) '"$requested"',
    if (typography.fontFace.isNotEmpty) '"$officeUiFontFamily"',
    '"Segoe UI"',
    'system-ui',
    'sans-serif',
  ].join(', ');
  return '''
${typography.fontFace}
:root, body, body[class] {
  --font-family-base-custom: $stack !important;
  --font-family-base: $stack !important;
}
body {
  letter-spacing: ${defaultLetterSpacing}em;
  font-kerning: normal;
  text-rendering: optimizeLegibility;
}
.ps-container .ps-scrollbar-y-rail,
.ps-container .ps-scrollbar-x-rail {
  background-color: transparent !important;
  border-radius: 999px !important;
}
.ps-container .ps-scrollbar-y-rail { width: 10px !important; right: 1px !important; }
.ps-container .ps-scrollbar-x-rail { height: 10px !important; bottom: 1px !important; }
.ps-container .ps-scrollbar-y,
.ps-container .ps-scrollbar-y-rail .ps-scrollbar-y.always-visible-y,
.ps-container .ps-scrollbar-x,
.ps-container .ps-scrollbar-x-rail .ps-scrollbar-x.always-visible-x {
  border: 0 !important;
  border-radius: 999px !important;
  background-color: var(--canvas-scroll-thumb) !important;
  background-image: none !important;
  box-shadow: none !important;
}
.ps-container .ps-scrollbar-y,
.ps-container .ps-scrollbar-y-rail .ps-scrollbar-y.always-visible-y {
  width: 6px !important;
  right: 2px !important;
  transition: width .12s ease, right .12s ease, background-color .12s ease !important;
}
.ps-container .ps-scrollbar-x,
.ps-container .ps-scrollbar-x-rail .ps-scrollbar-x.always-visible-x {
  height: 6px !important;
  bottom: 2px !important;
  transition: height .12s ease, bottom .12s ease, background-color .12s ease !important;
}
.ps-container .ps-scrollbar-y-rail:hover .ps-scrollbar-y,
.ps-container .ps-scrollbar-y-rail.hover .ps-scrollbar-y,
.ps-container .ps-scrollbar-y-rail.in-scrolling .ps-scrollbar-y {
  width: 8px !important;
  right: 1px !important;
  background-color: var(--canvas-scroll-thumb-hover) !important;
}
.ps-container .ps-scrollbar-x-rail:hover .ps-scrollbar-x,
.ps-container .ps-scrollbar-x-rail.hover .ps-scrollbar-x,
.ps-container .ps-scrollbar-x-rail.in-scrolling .ps-scrollbar-x {
  height: 8px !important;
  bottom: 1px !important;
  background-color: var(--canvas-scroll-thumb-hover) !important;
}
.ps-container .ps-scrollbar-y-rail.in-scrolling .ps-scrollbar-y,
.ps-container .ps-scrollbar-x-rail.in-scrolling .ps-scrollbar-x {
  background-color: var(--canvas-scroll-thumb-pressed) !important;
}
.ps-container .ps-scrollbar-y div,
.ps-container .ps-scrollbar-x div { display: none !important; }
::-webkit-scrollbar { width: 10px; height: 10px; background: transparent; }
::-webkit-scrollbar-track, ::-webkit-scrollbar-corner { background: transparent; }
::-webkit-scrollbar-button { display: none; }
::-webkit-scrollbar-thumb {
  background-color: var(--canvas-scroll-thumb);
  border: 2px solid transparent;
  border-radius: 999px;
  background-clip: padding-box;
}
::-webkit-scrollbar-thumb:hover { background-color: var(--canvas-scroll-thumb-hover); }
::-webkit-scrollbar-thumb:active { background-color: var(--canvas-scroll-thumb-pressed); }
''';
}

/// Runs in the editor frame before ONLYOFFICE: installs [officeEditorChromeCss],
/// defaults document text to ONLYOFFICE's smooth, unhinted rendering, and
/// repaints its canvas scroll bars as thin rounded thumbs without arrows.
@visibleForTesting
String buildOfficeEditorChromeScript({
  required String documentServerOrigin,
  required OfficeEditorTypography typography,
}) =>
    '''
(() => {
  if (window.location.origin !== ${jsonEncode(Uri.parse(documentServerOrigin).origin)}) return;
  if (!/\\/apps\\/(documenteditor|spreadsheeteditor|presentationeditor)\\/main\\//.test(window.location.pathname)) return;
  if (window.__appflowyOfficeChrome) return;
  window.__appflowyOfficeChrome = true;

  // '1' is ONLYOFFICE's "as OS X" rendering; an explicit choice is kept.
  try {
    for (const key of ['de-settings-fontrender', 'sse-settings-fontrender', 'pe-settings-fontrender']) {
      if (window.localStorage.getItem(key) === null) window.localStorage.setItem(key, '1');
    }
  } catch (_) {}

  const css = ${jsonEncode(officeEditorChromeCss(typography))};
  const install = () => {
    const parent = document.head || document.documentElement;
    if (!parent) return false;
    const style = document.createElement('style');
    style.id = 'appflowy-office-chrome';
    style.textContent = css;
    parent.appendChild(style);
    return true;
  };
  if (!install()) {
    const retry = () => {
      if (install()) document.removeEventListener('readystatechange', retry);
    };
    document.addEventListener('readystatechange', retry);
  }

  const drawThumb = (bar) => {
    const context = bar.context;
    if (!context) return;
    const settings = bar.settings || {};
    const browser = window.AscCommon && window.AscCommon.AscBrowser;
    const ratio = (browser && browser.retinaPixelRatio) || window.devicePixelRatio || 1;
    const vertical = !!settings.isVerticalScroll;
    const width = bar.canvasW;
    const height = bar.canvasH;
    context.clearRect(0, 0, width, height);
    if (settings.scrollBackgroundColor) {
      context.fillStyle = settings.scrollBackgroundColor;
      context.fillRect(0, 0, width, height);
    }
    if (vertical ? !bar.maxScrollY : !bar.maxScrollX) return;
    const state = bar.animState | 0;
    const pressed = !!bar.scrollerMouseDown || state === 3;
    const near = pressed || state !== 0;
    const cross = vertical ? width : height;
    const thickness = Math.max(2, Math.min(Math.round((near ? 8 : 6) * ratio), cross - 2));
    const across = Math.round((cross - thickness) / 2);
    const pad = Math.round(2 * ratio);
    const length = vertical ? height : width;
    const from = Math.max(pad, vertical ? bar.scroller.y : bar.scroller.x);
    const to = Math.min(length - pad,
      vertical ? bar.scroller.y + bar.scroller.h : bar.scroller.x + bar.scroller.w);
    if (!(to - from > thickness)) return;
    const x = vertical ? across : from;
    const y = vertical ? from : across;
    const w = vertical ? thickness : to - from;
    const h = vertical ? to - from : thickness;
    const radius = thickness / 2;
    context.beginPath();
    if (typeof context.roundRect === 'function') {
      context.roundRect(x, y, w, h, radius);
    } else {
      context.moveTo(x + radius, y);
      context.arcTo(x + w, y, x + w, y + h, radius);
      context.arcTo(x + w, y + h, x, y + h, radius);
      context.arcTo(x, y + h, x, y, radius);
      context.arcTo(x, y, x + w, y, radius);
      context.closePath();
    }
    context.fillStyle = (pressed ? settings.scrollerActiveColor
      : near ? settings.scrollerHoverColor
        : settings.scrollerColor) || 'rgba(128, 128, 128, 0.5)';
    context.fill();
  };

  const modernize = () => {
    const common = window.AscCommon;
    const bar = common && common.ScrollObject;
    const proto = bar && bar.prototype;
    if (!proto) return false;
    if (proto.__appflowyModern) return true;
    proto.__appflowyModern = true;
    if (typeof proto._drawScroll !== 'function' || typeof proto._init !== 'function' ||
        typeof proto.Repos !== 'function') {
      return true;
    }
    const init = proto._init;
    proto._init = function () {
      if (this.settings) this.settings.showArrows = false;
      return init.apply(this, arguments);
    };
    const repos = proto.Repos;
    proto.Repos = function (settings) {
      if (settings && typeof settings === 'object') settings.showArrows = false;
      if (this.settings) this.settings.showArrows = false;
      return repos.apply(this, arguments);
    };
    proto._drawScroll = function () {
      try {
        drawThumb(this);
      } catch (_) {}
    };
    return true;
  };
  if (!modernize()) {
    const started = Date.now();
    const poll = setInterval(() => {
      if (modernize() || Date.now() - started > 60000) clearInterval(poll);
    }, 16);
  }
})();
''';

/// Injected into every document-server frame; only editor frames act on it.
UserScript buildOfficeEditorChromeUserScript({
  required String documentServerUrl,
  required OfficeEditorTypography typography,
}) {
  final origin = Uri.parse(documentServerUrl).origin;
  return UserScript(
    source: buildOfficeEditorChromeScript(
      documentServerOrigin: origin,
      typography: typography,
    ),
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    forMainFrameOnly: false,
    allowedOriginRules: {origin},
  );
}
