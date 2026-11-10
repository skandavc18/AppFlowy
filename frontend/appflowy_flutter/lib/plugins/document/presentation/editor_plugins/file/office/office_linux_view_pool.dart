import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/workspace_item/blank_file_content.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_kind.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_linux_webview/appflowy_linux_webview.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'office_embedded_host.dart';
import 'office_embedded_page.dart';

typedef OfficeLinuxViewFactory = Future<LinuxWebViewController> Function({
  required Uri url,
  required List<String> userScripts,
});

/// The Linux office editor's web views, kept between documents.
///
/// A [LinuxWebViewController] runs its page in a web process of its own.
/// Starting that process, then fetching, compiling and warming up the editor
/// in it, is most of the time a document takes to open. A view that showed
/// an earlier document still has all of that and opens the next one in a
/// fraction of the time. Views wait on [EmbeddedOfficeHost.idleUrl] between
/// documents, and one can be warmed up before the first document (see
/// [warmUp]).
class OfficeLinuxViewPool {
  OfficeLinuxViewPool({
    OfficeLinuxViewFactory? create,
    this.capacity = 1,
    this.idleTimeout = const Duration(minutes: 20),
  }) : _create = create ?? _createView;

  static final OfficeLinuxViewPool instance = OfficeLinuxViewPool();

  static Future<LinuxWebViewController> _createView({
    required Uri url,
    required List<String> userScripts,
  }) =>
      LinuxWebViewController.create(url: url, userScripts: userScripts);

  /// How long a document that is opening waits for the view a closing one is
  /// handing back: far less than starting a view takes.
  static const _handOver = Duration(milliseconds: 500);

  /// How long a warm-up waits for the editor to draw its blank document.
  static const _warmUpLimit = Duration(seconds: 60);

  final OfficeLinuxViewFactory _create;

  /// Views kept waiting. One already makes the next document quick.
  final int capacity;

  /// How long an unused view keeps its memory.
  final Duration idleTimeout;

  final _idle = <LinuxWebViewController>[];
  final _returning = <Future<void>>{};
  // Views showing a document now; see [warmUp].
  final _showing = <LinuxWebViewController>{};
  Timer? _expiry;
  _WarmUp? _warmUp;

  @visibleForTesting
  int get idleCount => _idle.length;

  @visibleForTesting
  bool get isWarmingUp => _warmUp != null;

  bool get _isShowing {
    _showing.removeWhere((view) => view.isDisposed);
    return _showing.isNotEmpty;
  }

  /// A view showing [url], with [userScripts] running in its frames.
  Future<LinuxWebViewController> acquire({
    required Uri url,
    required List<String> userScripts,
  }) async {
    final view = await _acquire(url, userScripts);
    _showing.add(view);
    return view;
  }

  Future<LinuxWebViewController> _acquire(
    Uri url,
    List<String> userScripts,
  ) async {
    final warmUp = _warmUp;
    if (_idle.isEmpty && warmUp != null) {
      // Whatever the warm-up has loaded so far is worth having.
      _warmUp = null;
      final view = await warmUp.take();
      if (view != null && !view.isDisposed) {
        return _show(view, url, userScripts);
      }
    }
    if (_idle.isEmpty && _returning.isNotEmpty) {
      await Future.any([
        Future.wait(_returning.toList()),
        Future<void>.delayed(_handOver),
      ]);
    }
    while (_idle.isNotEmpty) {
      final view = _idle.removeLast();
      if (_idle.isEmpty) {
        _expiry?.cancel();
        _expiry = null;
      }
      if (!view.isDisposed) {
        return _show(view, url, userScripts);
      }
    }
    return _create(url: url, userScripts: userScripts);
  }

  Future<LinuxWebViewController> _show(
    LinuxWebViewController view,
    Uri url,
    List<String> userScripts,
  ) async {
    await view.setUserScripts(userScripts);
    await view.load(url);
    return view;
  }

  /// Takes [view] back once its document has closed. It waits on [idleUrl]
  /// for the next document, unless enough views wait already.
  Future<void> release(LinuxWebViewController view, {required Uri idleUrl}) {
    _showing.remove(view);
    final parked = _park(view, idleUrl);
    _returning.add(parked);
    return parked.whenComplete(() => _returning.remove(parked));
  }

  Future<void> _park(LinuxWebViewController view, Uri idleUrl) async {
    if (view.isDisposed) {
      return;
    }
    if (_idle.length >= capacity) {
      await view.dispose();
      return;
    }
    await view.setUserScripts(const []);
    await view.load(idleUrl);
    if (view.isDisposed) {
      return;
    }
    if (_idle.length >= capacity) {
      await view.dispose();
      return;
    }
    _idle.add(view);
    _expiry?.cancel();
    _expiry = Timer(idleTimeout, _expire);
  }

  void _expire() {
    _expiry = null;
    final views = _idle.toList();
    _idle.clear();
    for (final view in views) {
      unawaited(view.dispose());
    }
  }

  /// Opens a blank document of the kind this device last edited (see
  /// [OfficeEditorUsage]) in a view nobody sees, then keeps that view for the
  /// first real document, so it opens as quickly as later ones do. Does
  /// nothing on a device that has never opened one, once a view is ready, or
  /// while a document is open: loading a second editor then would slow the
  /// one in use, and its view comes back for the next document anyway.
  Future<void> warmUp({required EmbeddedOfficeHost host}) async {
    if (_idle.isNotEmpty || _warmUp != null || _isShowing) {
      return;
    }
    final usage = await OfficeEditorUsage.recall();
    if (usage == null || _idle.isNotEmpty || _warmUp != null || _isShowing) {
      return;
    }
    final warmUp = _warmUp = _WarmUp();
    try {
      await warmUp.run(this, host, usage);
    } catch (error) {
      Log.warn('Unable to warm up the office editor: $error');
    } finally {
      if (identical(_warmUp, warmUp)) {
        _warmUp = null;
      }
    }
  }

  @visibleForTesting
  Future<void> dispose() async {
    _expiry?.cancel();
    _expiry = null;
    await _warmUp?.take();
    _warmUp = null;
    final views = _idle.toList();
    _idle.clear();
    await Future.wait(views.map((view) => view.dispose()));
  }
}

/// One warm-up: a hidden blank document in a view of its own. A document that
/// opens meanwhile takes the view over at once.
class _WarmUp {
  final _created = Completer<void>();
  final _done = Completer<void>();
  LinuxWebViewController? _view;
  EmbeddedOfficeSession? _session;
  bool _taken = false;

  /// The warm-up's view, once it exists, for a document that is opening; null
  /// if it never started. The warm-up stops.
  Future<LinuxWebViewController?> take() async {
    _taken = true;
    _session?.close();
    if (!_done.isCompleted) {
      _done.complete();
    }
    await _created.future;
    return _view;
  }

  Future<void> run(
    OfficeLinuxViewPool pool,
    EmbeddedOfficeHost host,
    OfficeEditorUsage usage,
  ) async {
    Directory? folder;
    try {
      folder = await Directory.systemTemp.createTemp('appflowy_office_warm_');
      final name = 'Untitled.${usage.kind.fileExtension}';
      final file = File(p.join(folder.path, name));
      await file.writeAsBytes(blankFileContent(usage.kind), flush: true);
      if (_taken) {
        return;
      }
      final session = _session = await host.open(
        file: file,
        fileName: name,
        editable: true,
        theme: usage.theme,
        relayScroll: true,
      );
      if (_taken) {
        session.close();
        return;
      }
      final view = _view = await pool._create(
        url: session.pageUrl,
        userScripts: const [],
      );
      _created.complete();
      if (_taken) {
        // The document that took it over loads its own page now.
        return;
      }
      void settle() {
        if ((session.loaded.value ||
                session.status.value.phase == EmbeddedOfficePhase.failed) &&
            !_done.isCompleted) {
          _done.complete();
        }
      }

      session.loaded.addListener(settle);
      session.status.addListener(settle);
      settle();
      await _done.future.timeout(
        OfficeLinuxViewPool._warmUpLimit,
        onTimeout: () {},
      );
      session.loaded.removeListener(settle);
      session.status.removeListener(settle);
      if (_taken) {
        return;
      }
      session.close();
      _taken = true;
      await pool.release(view, idleUrl: host.idleUrl);
    } finally {
      if (!_created.isCompleted) {
        _created.complete();
      }
      unawaited(
        folder?.delete(recursive: true).catchError((_) => folder!),
      );
    }
  }
}

/// What this device last opened in the office editor, so that after a
/// restart the editor can be warmed up for it (see
/// [OfficeLinuxViewPool.warmUp]). Kept on this device only: it describes
/// what runs here, not the person's settings.
@immutable
class OfficeEditorUsage {
  const OfficeEditorUsage({required this.kind, required this.theme});

  static const _key = 'office_editor.last_document';

  final WorkspaceFileKind kind;

  /// The editor's look when it was last used. A warm-up page is never shown,
  /// so a theme changed since makes no difference.
  final OfficeEmbeddedTheme theme;

  static const _warmable = {
    WorkspaceFileKind.word,
    WorkspaceFileKind.excel,
    WorkspaceFileKind.powerpoint,
  };

  static Future<void> remember(
    String fileName,
    OfficeEmbeddedTheme theme,
  ) async {
    final kind = WorkspaceFileKind.fromName(fileName);
    if (kind == null ||
        !_warmable.contains(kind) ||
        !getIt.isRegistered<KeyValueStorage>()) {
      return;
    }
    try {
      await getIt<KeyValueStorage>().set(
        _key,
        jsonEncode({'kind': kind.name, 'theme': theme.toJson()}),
      );
    } catch (error) {
      Log.warn('Unable to remember the office document kind: $error');
    }
  }

  static Future<OfficeEditorUsage?> recall() async {
    if (!getIt.isRegistered<KeyValueStorage>()) {
      return null;
    }
    try {
      final stored = await getIt<KeyValueStorage>().get(_key);
      if (stored == null) {
        return null;
      }
      final json = jsonDecode(stored);
      if (json is! Map) {
        return null;
      }
      final kind = WorkspaceFileKind.values
          .where((kind) => kind.name == json['kind'])
          .firstOrNull;
      final theme = OfficeEmbeddedTheme.fromJson(json['theme']);
      if (kind == null || !_warmable.contains(kind) || theme == null) {
        return null;
      }
      return OfficeEditorUsage(kind: kind, theme: theme);
    } catch (_) {
      return null;
    }
  }
}
