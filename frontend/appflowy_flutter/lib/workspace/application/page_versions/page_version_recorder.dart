import 'dart:async';

import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/workspace/application/page_versions/page_version.dart';
import 'package:appflowy/workspace/application/page_versions/page_version_content.dart';
import 'package:appflowy/workspace/application/page_versions/page_version_service.dart';
import 'package:appflowy/workspace/application/page_versions/page_version_settings.dart';
import 'package:appflowy/workspace/application/view/view_listener.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_editor/appflowy_editor.dart'
    show EditorState, EditorTransactionValue, TransactionTime;
import 'package:flutter/foundation.dart';

/// Keeps an eye on a page that is open and remembers it once the writing has
/// settled.
///
/// Copying on every keystroke would fill the list with noise, and copying only
/// when the page closes would lose an afternoon's work to a crash. So it waits
/// for a quiet period, and takes one last copy on the way out.
class PageVersionRecorder {
  PageVersionRecorder({
    required this.viewId,
    required this.editorState,
    this.row,
  });

  final String viewId;
  final EditorState editorState;

  /// Set when the page is a row's, so the row's cells are kept beside it.
  final PageVersionRowContext? row;

  StreamSubscription<EditorTransactionValue>? _edits;
  Timer? _quiet;
  Timer? _clock;
  bool _dirty = false;
  bool _closed = false;
  bool _capturing = false;

  PageVersionPolicy get _policy => PageVersionSettings.instance.policy;

  void start() {
    if (viewId.isEmpty || _edits != null) {
      return;
    }
    unawaited(PageVersionSettings.instance.ensureLoaded());
    unawaited(_begin());
    _edits = editorState.transactionStream.listen(_onEdit);
  }

  Future<void> _begin() async {
    await PageVersionSettings.instance.ensureLoaded();
    if (_closed) {
      return;
    }
    _startClock();
    await _captureOpeningState();
  }

  /// A copy on a clock, for writing that never pauses long enough to settle.
  void _startClock() {
    _clock?.cancel();
    _clock = null;
    if (!_policy.capturesPeriodically) {
      return;
    }
    _clock = Timer.periodic(_policy.captureInterval, (_) {
      if (!_closed && _dirty) {
        unawaited(_capture());
      }
    });
  }

  /// The state a page was in when it was opened is the one somebody means by
  /// "before I started", so it is worth a copy of its own — and it is free
  /// when nothing has changed, because an identical page is never copied
  /// twice.
  Future<void> _captureOpeningState() async {
    if (_closed || !_policy.captureAutomatically || !_policy.captureOnOpen) {
      return;
    }
    // A blank page has no earlier state worth keeping; the first version is
    // taken as soon as something is written on it. A row is different: its
    // cells are worth remembering even when nothing is written on its page.
    if (editorState.document.isEmpty && row == null) {
      return;
    }
    await _capture();
  }

  void _onEdit(EditorTransactionValue value) {
    if (_closed || value.$1 != TransactionTime.after) {
      return;
    }
    if (value.$3.inMemoryUpdate) {
      return;
    }
    _dirty = true;
    _quiet?.cancel();
    _quiet = Timer(_policy.quietPeriod, () {
      _quiet = null;
      unawaited(_capture());
    });
  }

  Future<void> _capture() async {
    if (_capturing) {
      return;
    }
    _capturing = true;
    try {
      final view = await PageVersionService.instance.readView(viewId);
      if (view == null) {
        return;
      }
      final captured = await PageVersionService.instance.capture(
        view: view,
        openDocument: editorState.document,
        row: row,
      );
      if (captured != null) {
        _dirty = false;
      }
    } on Object catch (error) {
      Log.warn('The page $viewId could not be remembered: $error');
    } finally {
      _capturing = false;
    }
  }

  /// Takes a last copy of whatever is unsaved and stops watching.
  Future<void> stop() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _quiet?.cancel();
    _quiet = null;
    _clock?.cancel();
    _clock = null;
    await _edits?.cancel();
    _edits = null;
    if (!_dirty || !_policy.captureAutomatically || !_policy.captureOnClose) {
      return;
    }
    // The editor is about to be disposed, so read the document now.
    final document = editorState.document;
    final view = await PageVersionService.instance.readView(viewId);
    if (view != null) {
      unawaited(
        PageVersionService.instance.capture(
          view: view,
          openDocument: document,
          row: row,
        ),
      );
    }
  }
}

/// Remembers a table, a folder, a collection or a file while it is open.
///
/// ⚠️ These kinds have no transaction stream to listen to, so history is taken
/// at the two moments that are genuinely meaningful — opening and closing —
/// plus whenever the view record itself changes. A file edited in place is
/// caught on close, which is what "file history" has always meant.
class ViewVersionRecorder {
  ViewVersionRecorder({required this.viewId, this.row});

  final String viewId;

  /// Set when the view is a row's page, so its cells are kept beside it.
  final PageVersionRowContext? row;

  ViewListener? _viewListener;
  Timer? _quiet;
  Timer? _clock;
  bool _closed = false;
  bool _capturing = false;

  PageVersionPolicy get _policy => PageVersionSettings.instance.policy;

  void start() {
    if (viewId.isEmpty || _viewListener != null) {
      return;
    }
    _viewListener = ViewListener(viewId: viewId)
      ..start(onViewUpdated: (_) => _onChanged());
    unawaited(_begin());
  }

  Future<void> _begin() async {
    await PageVersionSettings.instance.ensureLoaded();
    if (_closed) {
      return;
    }
    if (_policy.capturesPeriodically) {
      _clock = Timer.periodic(
        _policy.captureInterval,
        (_) => unawaited(_capture()),
      );
    }
    if (_policy.captureOnOpen) {
      await _capture();
    }
  }

  void _onChanged() {
    if (_closed) {
      return;
    }
    _quiet?.cancel();
    _quiet = Timer(_policy.quietPeriod, () {
      _quiet = null;
      unawaited(_capture());
    });
  }

  Future<void> _capture() async {
    if (_capturing) {
      return;
    }
    _capturing = true;
    try {
      await PageVersionSettings.instance.ensureLoaded();
      if (!_policy.captureAutomatically) {
        return;
      }
      final view = await PageVersionService.instance.readView(viewId);
      if (view == null) {
        return;
      }
      // A written page is watched through its editor — but only when one is
      // actually open. A canvas or a dashboard has no editor at all, and used
      // to fall through this gap and never be kept.
      if (pageVersionShapeOf(view) == PageVersionShape.document &&
          openEditorFor(viewId) != null) {
        return;
      }
      await PageVersionService.instance.capture(view: view, row: row);
    } on Object catch (error) {
      Log.warn('The view $viewId could not be remembered: $error');
    } finally {
      _capturing = false;
    }
  }

  Future<void> stop() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _quiet?.cancel();
    _quiet = null;
    _clock?.cancel();
    _clock = null;
    await _viewListener?.stop();
    _viewListener = null;
    if (!_policy.captureOnClose) {
      return;
    }
    // A file or a table changes without the view record ever changing, so the
    // copy on the way out is the one that matters.
    unawaited(_capture());
  }
}

/// Whether a view is showing its versions.
///
/// The three-dot menu and the page are SIBLINGS, so an inherited widget cannot
/// join them; both sides read the same notifier, keyed by view id.
class PageVersionPanel {
  PageVersionPanel._();

  static final PageVersionPanel instance = PageVersionPanel._();

  final Map<String, ValueNotifier<bool>> _open = {};

  ValueNotifier<bool> notifierFor(String viewId) =>
      _open.putIfAbsent(viewId, () => ValueNotifier<bool>(false));

  bool isOpen(String viewId) => _open[viewId]?.value ?? false;

  void toggle(String viewId) {
    final notifier = notifierFor(viewId);
    notifier.value = !notifier.value;
  }

  void open(String viewId) => notifierFor(viewId).value = true;

  void close(String viewId) => notifierFor(viewId).value = false;
}

/// The editor of a page that is open, for the few things that need one.
///
/// `DocumentBloc` already keeps every open page in a map of its own, so this
/// is only the reading of it — a restore has to write through the live editor,
/// and the version rail is a sibling of the page, not its parent.
EditorState? openEditorFor(String viewId) =>
    DocumentBloc.findOpen(viewId)?.state.editorState;
