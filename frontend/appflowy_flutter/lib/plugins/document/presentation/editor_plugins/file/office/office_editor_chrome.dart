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
html.$officeOpeningClass .asc-loadmask-body{display:none!important}
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
/// defaults document text to ONLYOFFICE's smooth, unhinted rendering,
/// repaints its canvas scroll bars as thin rounded thumbs without arrows, and
/// keeps the document editor's scrolling smooth.
///
/// With [offscreenCanvasesInMemory], the document editor's canvases that are
/// not on the page, where it draws its pictures of pages and of glyphs, are
/// drawn in memory rather than on the GPU. On WebKitGTK, which puts every
/// canvas on the GPU, ONLYOFFICE takes twice as long to draw a page there,
/// and scrolling stalls while each page coming into view is drawn. The
/// spreadsheet editor then also shifts its shapes layer on the GPU, as it
/// does everywhere but Safari, rather than through a read-back of its pixels.
String buildOfficeEditorChromeScript({
  required String documentServerOrigin,
  required OfficeEditorTypography typography,
  bool offscreenCanvasesInMemory = false,
}) =>
    '''
(() => {
  if (window.location.origin !== ${jsonEncode(Uri.parse(documentServerOrigin).origin)}) return;
  if (!/\\/apps\\/(documenteditor|spreadsheeteditor|presentationeditor)\\/main\\//.test(window.location.pathname)) return;
  if (window.__appflowyOfficeChrome) return;
  window.__appflowyOfficeChrome = true;
${offscreenCanvasesInMemory ? _offscreenCanvasesInMemory : ''}
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

  // ONLYOFFICE's desktop editors repaint the document at most every 40 ms,
  // 25 times a second, however smoothly it is scrolled: the scroll bars and
  // rulers move every frame while the page steps behind them. Its mobile
  // editors repaint on every frame, and so do these.
  const paintEveryFrame = () => {
    const common = window.AscCommon;
    const loop = common && common.PaintMessageLoop;
    const proto = loop && loop.prototype;
    if (!proto) return false;
    if (proto.__appflowyEveryFrame) return true;
    proto.__appflowyEveryFrame = true;
    const start = proto.Start;
    if (typeof start !== 'function') return true;
    proto.Start = function () {
      if (this.requestAnimationFrame) {
        this.isUseRequestAnimationFrame = true;
        this.isUseInterval = false;
      }
      return start.apply(this, arguments);
    };
    return true;
  };

  // The document editor draws each page it shows into a picture, drops the
  // picture as soon as the page leaves the view and draws the page again
  // from scratch when it comes back: a hitch of 30-45 ms on a HiDPI screen
  // each time. Pages beside the view keep their pictures, within a budget of
  // pixels. The editor still redraws a kept page before showing it if the
  // page changed or no longer has the right size.
  const keepNearbyPages = () => {
    const api = window.editor || (window.Asc && window.Asc.editor);
    const control = api && api.WordControl;
    const pages = control && control.m_oDrawingDocument;
    if (!pages || typeof pages.StopRenderingPage !== 'function') return false;
    if (pages.__appflowyKeepsNearby) return true;
    pages.__appflowyKeepsNearby = true;
    const stop = pages.StopRenderingPage;
    pages.StopRenderingPage = function (index) {
      const first = this.m_lDrawingFirst;
      const last = this.m_lDrawingEnd;
      const page = this.m_arrPages && this.m_arrPages[index];
      const cached = page && page.drawingPage && page.drawingPage.cachedImage;
      const picture = cached && cached.image;
      if (picture && !this.m_oDocumentRenderer && first >= 0 && last >= first &&
          (index < first || index > last)) {
        const distance = index < first ? first - index : index - last;
        const reach = Math.min($officeKeptPagesPerSide, Math.max(1,
          Math.floor($officeKeptPagePixels / (2 * picture.width * picture.height))));
        if (distance <= reach) return;
      }
      return stop.apply(this, arguments);
    };
    return true;
  };

  // Each patch waits for the part of ONLYOFFICE it changes to load; the page
  // pictures only exist once a document has opened.
  const pending = [[modernize, 60000], [paintEveryFrame, 60000]];
  if (/\\/apps\\/documenteditor\\/main\\//.test(window.location.pathname)) {
    pending.push([keepNearbyPages, 120000]);
  }
  const patchesStarted = Date.now();
  const applyPatches = () => {
    for (let i = pending.length - 1; i >= 0; i--) {
      const [patch, limit] = pending[i];
      let done = false;
      try {
        done = patch();
      } catch (_) {
        done = true;
      }
      if (done || Date.now() - patchesStarted > limit) pending.splice(i, 1);
    }
    return pending.length === 0;
  };
  if (!applyPatches()) {
    const poll = setInterval(() => {
      if (applyPatches()) clearInterval(poll);
    }, 16);
  }

  // The document opens without ONLYOFFICE's "loading" box over it: its own
  // skeleton already shows where the document will be. Later progress, such
  // as printing or downloading, still shows the box.
  const quietOpening = () => {
    const root = document.documentElement;
    if (!root) return false;
    root.classList.add('$officeOpeningClass');
    const opened = Date.now();
    const settle = () => {
      const api = window.editor || (window.Asc && window.Asc.editor);
      if (api && api.isDocumentLoadComplete) {
        // The box closes just after the document reports in.
        setTimeout(() => root.classList.remove('$officeOpeningClass'), 1500);
      } else if (Date.now() - opened > 120000) {
        root.classList.remove('$officeOpeningClass');
      } else {
        setTimeout(settle, 100);
      }
    };
    settle();
    return true;
  };
  if (!quietOpening()) {
    const retry = () => {
      if (quietOpening()) document.removeEventListener('readystatechange', retry);
    };
    document.addEventListener('readystatechange', retry);
  }
})();
''';

/// Before ONLYOFFICE makes a canvas: the document editor's 2D canvases that
/// are not on the page draw in memory. Those on the page stay on the GPU,
/// which then shows the in-memory pictures without copying them each frame.
///
/// ONLYOFFICE takes WebKitGTK for Safari, and on Safari the spreadsheet
/// editor moves the shapes over its cells by reading every pixel of their
/// layer back and writing it again, on each scroll step: half of what a step
/// costs. Its own way for other browsers, a GPU copy, works here.
const _offscreenCanvasesInMemory = '''

  if (/\\/apps\\/documenteditor\\/main\\//.test(window.location.pathname)) {
    const canvas = window.HTMLCanvasElement && window.HTMLCanvasElement.prototype;
    const getContext = canvas && canvas.getContext;
    if (typeof getContext === 'function') {
      canvas.getContext = function (type, options) {
        if (type === '2d' && !this.isConnected) {
          // The hint WebKit answers with a canvas in memory.
          return getContext.call(this, type, Object.assign({}, options, { willReadFrequently: true }));
        }
        return getContext.apply(this, arguments);
      };
    }
  }
  if (/\\/apps\\/spreadsheeteditor\\/main\\//.test(window.location.pathname)) {
    const gpuShift = () => {
      const context = window.Asc && window.Asc.DrawingContext;
      const proto = context && context.prototype;
      if (!proto || typeof proto.moveImageData !== 'function') return false;
      proto.moveImageDataSafari = function () {
        return this.moveImageData.apply(this, arguments);
      };
      return true;
    };
    if (!gpuShift()) {
      const started = Date.now();
      const poll = setInterval(() => {
        if (gpuShift() || Date.now() - started > 60000) clearInterval(poll);
      }, 16);
    }
  }
''';

/// While present on an editor frame's root, ONLYOFFICE's loading box stays
/// hidden.
@visibleForTesting
const officeOpeningClass = 'appflowy-office-opening';

/// The budget, in pixels, for pictures of pages the document editor keeps
/// beside the view, across both sides: about three A4 pages a side at 100%
/// zoom on a HiDPI screen, around 90 MB.
@visibleForTesting
const officeKeptPagePixels = 24000000;

/// Pages the document editor keeps on each side of the view, at most.
@visibleForTesting
const officeKeptPagesPerSide = 4;

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
