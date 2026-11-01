import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'office_editor_scroll.dart';
import 'office_editor_skin.dart';

/// How long the page waits after the first unsaved edit before saving.
const _autosaveDelay = Duration(milliseconds: 1200);
const _retryDelay = Duration(seconds: 5);

/// AppFlowy's palette as the bundled editor stores it before it boots.
@immutable
class OfficeEmbeddedTheme {
  const OfficeEmbeddedTheme({
    required this.isDark,
    required this.themeId,
    required this.storedTheme,
    required this.background,
  });

  factory OfficeEmbeddedTheme.fromSkin(OfficeEditorSkin skin) =>
      OfficeEmbeddedTheme(
        isDark: skin.isDark,
        themeId: skin.baseThemeId,
        storedTheme: officeStoredUiThemeJson(skin),
        background: officeCssColor(skin.desk),
      );

  final bool isDark;

  /// ONLYOFFICE's base interface theme, e.g. `theme-white`.
  final String themeId;

  /// The `ui-theme` record repainting that theme with AppFlowy's colours.
  final String storedTheme;

  /// CSS colour behind the editor while it loads.
  final String background;

  Map<String, Object?> toJson() => {
        'dark': isDark,
        'id': themeId,
        'stored': storedTheme,
        'background': background,
      };

  @override
  bool operator ==(Object other) =>
      other is OfficeEmbeddedTheme &&
      other.isDark == isDark &&
      other.themeId == themeId &&
      other.storedTheme == storedTheme &&
      other.background == background;

  @override
  int get hashCode => Object.hash(isDark, themeId, storedTheme, background);
}

/// Loaded first in the editor page (`editor.html`).
///
/// - AppFlowy's host already sends the isolation headers the editor's
///   service worker exists to add, and waiting for that worker would hold
///   the first open for 15 seconds and reload the editor on updates.
/// - Scroll messages between the ONLYOFFICE frame and AppFlowy's page are
///   relayed across this extra frame level.
/// - The editor configuration takes AppFlowy's chrome options, as it does
///   with a document server: AppFlowy shows the file name itself.
const officeEmbeddedShimScript = '''
(function () {
  'use strict';
  try { delete Navigator.prototype.serviceWorker; } catch (e) {}

  window.addEventListener('message', function (event) {
    var data = event.data;
    if (event.origin !== location.origin || !data || data.appflowyOfficeScroll !== 1) return;
    if (event.source === window.parent) {
      var frames = document.getElementsByTagName('iframe');
      for (var i = 0; i < frames.length; i++) {
        try { frames[i].contentWindow.postMessage(data, location.origin); } catch (e) {}
      }
    } else if (window.parent !== window) {
      window.parent.postMessage(data, location.origin);
    }
  });

  var overrides = { compactHeader: true, toolbarHideFileName: true, suggestFeature: false };
  function customize(config) {
    if (!config || typeof config !== 'object') return;
    var editorConfig = config.editorConfig = config.editorConfig || {};
    var customization = editorConfig.customization = editorConfig.customization || {};
    for (var key in overrides) customization[key] = overrides[key];
    customization.features = Object.assign({}, customization.features, { featuresTips: false });
  }
  function wrap(DocEditor) {
    if (typeof DocEditor !== 'function') return DocEditor;
    var Wrapped = function (placeholder, config) {
      try { customize(config); } catch (e) {}
      return new DocEditor(placeholder, config);
    };
    for (var key in DocEditor) {
      if (Object.prototype.hasOwnProperty.call(DocEditor, key)) Wrapped[key] = DocEditor[key];
    }
    return Wrapped;
  }
  function instrument(api) {
    if (!api || typeof api !== 'object' || api.__appflowy) return api;
    var wrapped = wrap(api.DocEditor);
    Object.defineProperty(api, 'DocEditor', {
      configurable: true,
      enumerable: true,
      get: function () { return wrapped; },
      set: function (value) { wrapped = wrap(value); }
    });
    Object.defineProperty(api, '__appflowy', { value: true });
    return api;
  }
  var current;
  try {
    Object.defineProperty(window, 'DocsAPI', {
      configurable: true,
      enumerable: true,
      get: function () { return current; },
      set: function (value) { current = instrument(value); }
    });
  } catch (e) {}
})();
''';

/// Adds the shim ahead of every other script in the editor page.
String injectOfficeEmbeddedShim(String html) {
  const tag = '<script src="/__appflowy__/shim.js"></script>';
  final head =
      RegExp('<head(\\s[^>]*)?>', caseSensitive: false).firstMatch(html);
  if (head == null) {
    return '$tag$html';
  }
  return html.replaceRange(head.end, head.end, tag);
}

/// The page AppFlowy loads for one document: it boots the bundled editor in
/// a frame and drives it through the editor's postMessage API.
///
/// The page reads the file from, and saves it back to, its own session URL.
/// It saves shortly after each edit, reports progress to AppFlowy, and
/// follows the commands AppFlowy streams to it: save now, reload with a new
/// theme, or reopen after another view saved the same file.
String buildOfficeEmbeddedPage({
  required String fileName,
  required bool editable,
  required OfficeEmbeddedTheme theme,
  required String origin,
  bool relayScroll = false,
}) {
  final config = jsonEncode({
    'fileName': fileName,
    'editable': editable,
    'theme': theme.toJson(),
    'autosaveDelay': _autosaveDelay.inMilliseconds,
    'retryDelay': _retryDelay.inMilliseconds,
  });
  // `</` cannot end the inline script early.
  final safeConfig = config.replaceAll('</', r'<\/');
  final relay = relayScroll ? buildOfficeScrollRelayScript(origin) : '';
  return '''
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>${const HtmlEscape().convert(fileName)}</title>
    <style>
      html, body { margin: 0; padding: 0; height: 100%; width: 100%; overflow: hidden; background: ${theme.background}; }
      iframe { display: block; border: 0; width: 100%; height: 100%; background: transparent; }
    </style>
  </head>
  <body>
    <iframe id="appflowy-office-editor" title="Document editor" allow="clipboard-read; clipboard-write; fullscreen"></iframe>
    <script>
$relay
    </script>
    <script>
(function () {
  'use strict';
  var config = $safeConfig;
  var frame = document.getElementById('appflowy-office-editor');
  var origin = location.origin;
  // Clock-seeded so events stay ordered across reloads of this page.
  var sequence = Date.now() * 1000;
  var requestId = 0;
  var state = { opened: false, opening: false, openId: null, dirty: false, saving: false, queued: false };
  var timer = null;
  // When a save first had to wait for the mouse; see pointerBusy.
  var waitingSince = 0;

  function report(event) {
    event.seq = ++sequence;
    return fetch('events', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(event),
      keepalive: true
    }).catch(function () {});
  }
  function send(type, payload) {
    var id = 'appflowy-' + (++requestId);
    if (frame.contentWindow) frame.contentWindow.postMessage({ id: id, type: type, payload: payload || {} }, origin);
    return id;
  }
  function messageOf(error, fallback) {
    return (error && error.message) || (typeof error === 'string' && error) || fallback;
  }
  function applyTheme(theme) {
    try {
      var storage = window.localStorage;
      storage.removeItem('ui-theme-site-driven');
      storage.setItem('ui-theme-id', theme.id);
      storage.setItem('ui-theme', theme.stored);
      storage.setItem('content-theme', theme.dark ? 'dark' : 'light');
      storage.setItem('ran-theme', theme.dark ? 'dark' : 'light');
    } catch (e) {}
    document.documentElement.style.background = theme.background;
    document.body.style.background = theme.background;
  }
  function load() {
    clearTimeout(timer);
    waitingSince = 0;
    state = { opened: false, opening: false, openId: null, dirty: false, saving: false, queued: false };
    frame.src = '/editor.html?embed=1&locale=en&embedOrigin=' + encodeURIComponent(origin);
  }
  function open() {
    state.opening = true;
    fetch('document', { cache: 'no-store' }).then(function (response) {
      if (!response.ok) throw new Error('AppFlowy could not read the file (' + response.status + ').');
      return response.arrayBuffer();
    }).then(function (buffer) {
      state.openId = send('document:open-buffer', { fileName: config.fileName, buffer: buffer, readonly: !config.editable });
    }).catch(function (error) {
      state.opening = false;
      report({ type: 'open-failed', message: messageOf(error, 'The document could not be opened.') });
    });
  }
  function schedule(delay) {
    if (!config.editable) return;
    clearTimeout(timer);
    timer = setTimeout(save, delay);
  }
  // An export the editor starts mid-drag loses track of its request, so the
  // save times out minutes later. Saves wait for the button instead.
  function pointerBusy() {
    try {
      var frames = frame.contentWindow ? frame.contentWindow.frames : [];
      for (var i = 0; i < frames.length; i++) {
        var common = frames[i].AscCommon;
        var mouse = common && common.global_mouseEvent;
        if (mouse) return !!(mouse.IsLocked || mouse.IsPressed);
      }
    } catch (e) {}
    return false;
  }
  // The editor loads its file converter at the first save, and one that
  // fails to load stays broken for the life of the editor, so no save would
  // ever finish. Loading it as the document opens turns that failure into a
  // reload, made before there are edits to lose.
  var converterReloads = 0;
  function prepareConverter() {
    var converter = null;
    try {
      var frames = frame.contentWindow ? frame.contentWindow.frames : [];
      for (var i = 0; i < frames.length && !converter; i++) {
        var common = frames[i].AscCommon;
        if (common && common.x2t && typeof common.x2t.initialize === 'function') converter = common.x2t;
      }
    } catch (e) {}
    if (!converter) return;
    Promise.resolve(converter.initialize()).catch(function () {
      if (!state.dirty && !state.saving && converterReloads < 2) {
        converterReloads++;
        load();
        return;
      }
      report({
        type: 'save-failed',
        message: 'The editor could not load its file converter, so changes cannot be saved. Copy any changes, then reopen the document.'
      });
    });
  }
  function save() {
    clearTimeout(timer);
    timer = null;
    if (!config.editable || !state.opened || (!state.dirty && !state.saving)) {
      report({ type: 'clean' });
      return;
    }
    if (state.saving) {
      state.queued = true;
      return;
    }
    if (pointerBusy()) {
      waitingSince = waitingSince || Date.now();
      // A button the editor never saw released must not stop saving.
      if (Date.now() - waitingSince < 15000) {
        timer = setTimeout(save, 250);
        return;
      }
    }
    waitingSince = 0;
    state.saving = true;
    report({ type: 'saving' });
    send('document:save', {});
  }
  function upload(file, stillDirty) {
    return file.arrayBuffer().then(function (bytes) {
      return fetch('document', {
        method: 'PUT',
        body: bytes,
        headers: {
          'Content-Type': 'application/octet-stream',
          'X-AppFlowy-Dirty': stillDirty ? 'true' : 'false',
          'X-AppFlowy-Seq': String(++sequence)
        }
      });
    }).then(function (response) {
      if (!response.ok) throw new Error('AppFlowy could not write the file (' + response.status + ').');
    });
  }

  window.addEventListener('message', function (event) {
    if (event.origin !== origin || event.source !== frame.contentWindow) return;
    var data = event.data || {};
    var type = data.type;
    var payload = data.payload || {};
    if (typeof type !== 'string' || type.indexOf('document:') !== 0) return;
    switch (type) {
      case 'document:ready':
        open();
        break;
      case 'document:opened':
        state.opening = false;
        state.opened = true;
        report({ type: 'opened' });
        if (config.editable) prepareConverter();
        break;
      case 'document:dirty-changed':
        state.dirty = !!payload.dirty;
        report({ type: 'dirty', dirty: state.dirty });
        // The editor reports each change of state once: an edit made while a
        // save is uploading has to be saved after it.
        if (state.dirty) {
          if (state.saving) state.queued = true;
          else schedule(config.autosaveDelay);
        }
        break;
      case 'document:saved':
        if (!config.editable || !payload.file) break;
        var stillDirty = !!payload.dirty;
        state.saving = true;
        upload(payload.file, stillDirty).then(function () {
          state.saving = false;
          state.dirty = stillDirty || state.queued;
          if (state.dirty) {
            state.queued = false;
            schedule(config.autosaveDelay);
          }
        }, function (error) {
          state.saving = false;
          state.dirty = true;
          report({ type: 'save-failed', message: messageOf(error, 'The document could not be saved.') });
          schedule(config.retryDelay);
        });
        break;
      case 'document:error':
        if (state.opening || (state.openId && data.id === state.openId && !state.opened)) {
          state.opening = false;
          report({ type: 'open-failed', message: messageOf(payload.message, 'The document could not be opened.') });
        } else if (state.saving) {
          state.saving = false;
          report({ type: 'save-failed', message: messageOf(payload.message, 'The document could not be saved.') });
          schedule(config.retryDelay);
        }
        break;
    }
  });

  var commands = new EventSource('commands');
  commands.onmessage = function (event) {
    var command;
    try { command = JSON.parse(event.data); } catch (e) { return; }
    if (!command) return;
    if (command.type === 'save') {
      save();
    } else if (command.type === 'reload' && command.theme) {
      applyTheme(command.theme);
      load();
    } else if (command.type === 'external-change') {
      if (state.opened && !state.dirty && !state.saving) open();
    }
  };

  window.addEventListener('pagehide', function () {
    if (state.dirty && !state.saving) save();
  });

  applyTheme(config.theme);
  load();
})();
    </script>
  </body>
</html>
''';
}
