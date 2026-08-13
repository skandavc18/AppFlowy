import 'dart:async';

import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_metadata.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_variable.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:flutter/foundation.dart';

/// Holds one open dashboard: what it is, what state it is in, and whether it
/// is being built or used.
///
/// Every change goes through here so there is exactly one place that knows how
/// to persist, one undo history, and one signal for the widgets to rebuild on.
class DashboardController extends ChangeNotifier {
  DashboardController({
    required this.viewId,
    required DashboardDocument document,
    DashboardMode? mode,
    this.persistDebounce = const Duration(milliseconds: 700),
    this.maxHistory = 60,
  })  : _document = document,
        _mode = mode ?? DashboardMode.edit,
        _state = DashboardStateValues.initial(document.variables);

  final String viewId;
  final Duration persistDebounce;
  final int maxHistory;

  DashboardDocument _document;
  DashboardMode _mode;
  DashboardStateValues _state;

  final List<DashboardDocument> _undo = [];
  final List<DashboardDocument> _redo = [];

  Timer? _persist;
  bool _writing = false;
  bool _dirty = false;

  /// The widget with the selection ring on it.
  String? _selected;

  /// The widget whose settings panel is open, if any.
  String? _configuring;

  /// A widget shown on its own over the dashboard.
  String? _modal;

  int _refreshToken = 0;

  DashboardDocument get document => _document;

  DashboardMode get mode => _mode;

  DashboardStateValues get state => _state;

  String? get selectedWidgetId => _selected;

  String? get configuringWidgetId => _configuring;

  String? get modalWidgetId => _modal;

  bool get isEditable => _mode.isEditable;

  bool get canUndo => _undo.isNotEmpty;

  bool get canRedo => _redo.isNotEmpty;

  /// Bumped whenever something asks every widget with a source to re-read.
  int get refreshToken => _refreshToken;

  // ---------------------------------------------------------------- document

  /// Apply [change] to the document, remembering the previous one for undo.
  ///
  /// [transient] is for a change that is still happening — a drag in flight —
  /// so a single gesture does not fill the history with sixty entries.
  void edit(
    DashboardDocument Function(DashboardDocument document) change, {
    bool transient = false,
  }) {
    final next = change(_document);
    if (next == _document) {
      return;
    }
    if (!transient) {
      _undo.add(_document);
      if (_undo.length > maxHistory) {
        _undo.removeAt(0);
      }
      _redo.clear();
    }
    _document = next;
    _adoptVariables();
    _schedulePersist();
    notifyListeners();
  }

  /// Replace the document outright — applying a template, or adopting a change
  /// that arrived from elsewhere.
  void replace(DashboardDocument document, {bool remember = true}) {
    if (document == _document) {
      return;
    }
    if (remember) {
      _undo.add(_document);
      _redo.clear();
    }
    _document = document;
    _adoptVariables();
    _schedulePersist();
    notifyListeners();
  }

  /// Adopt a document read from the backend without marking anything dirty.
  ///
  /// A write of our own is still in flight in the common case, so a stale echo
  /// must never be allowed to put the previous arrangement back.
  void adoptFromView(ViewPB view) {
    if (_writing || _dirty || view.id != viewId) {
      return;
    }
    final incoming = view.dashboard?.document;
    if (incoming == null || incoming == _document) {
      return;
    }
    _document = incoming;
    _adoptVariables();
    notifyListeners();
  }

  void undo() {
    if (_undo.isEmpty) {
      return;
    }
    _redo.add(_document);
    _document = _undo.removeLast();
    _adoptVariables();
    _schedulePersist();
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) {
      return;
    }
    _undo.add(_document);
    _document = _redo.removeLast();
    _adoptVariables();
    _schedulePersist();
    notifyListeners();
  }

  // -------------------------------------------------------------------- mode

  void setMode(DashboardMode mode) {
    if (_mode == mode) {
      return;
    }
    _mode = mode;
    if (!mode.isEditable) {
      _selected = null;
      _configuring = null;
    }
    notifyListeners();
  }

  // ------------------------------------------------------------------- state

  void setValue(String key, Object? value) {
    final next = _state.withValue(key, value);
    if (next == _state) {
      return;
    }
    _state = next;
    notifyListeners();
  }

  void toggleValue(String key) => setValue(key, !_state.flag(key));

  /// Put every variable back to the value it starts with.
  void resetState() {
    _state = DashboardStateValues.initial(_document.variables);
    notifyListeners();
  }

  /// Ask every widget that reads something to read it again.
  void refresh() {
    _refreshToken++;
    notifyListeners();
  }

  // ---------------------------------------------------------------- selection

  /// Pick a widget up. This is the ring and nothing else — the settings panel
  /// takes width off the canvas, so a plain click is not allowed to open it.
  void select(String? widgetId) {
    if (_selected == widgetId) {
      return;
    }
    _selected = widgetId;
    // An open panel follows whatever is picked up rather than going stale.
    if (_configuring != null) {
      _configuring = widgetId;
    }
    notifyListeners();
  }

  /// Open a widget's settings, entering edit mode if that is where we are not.
  ///
  /// A widget that has not been pointed at anything yet shows a "choose…"
  /// affordance, and that affordance has to work wherever it is pressed —
  /// telling somebody to go and find a mode switch first is not an answer.
  void configure(String widgetId) {
    setMode(DashboardMode.edit);
    if (_selected == widgetId && _configuring == widgetId) {
      return;
    }
    _selected = widgetId;
    _configuring = widgetId;
    notifyListeners();
  }

  /// Put the settings away, leaving the widget picked up.
  void closeSettings() {
    if (_configuring == null) {
      return;
    }
    _configuring = null;
    notifyListeners();
  }

  void openModal(String? widgetId) {
    if (_modal == widgetId) {
      return;
    }
    _modal = widgetId;
    notifyListeners();
  }

  // ------------------------------------------------------------- persistence

  void _adoptVariables() {
    // A variable that has just been added needs its starting value, and one
    // that has gone should not leave a value behind for a rule to match on.
    final keys = {for (final variable in _document.variables) variable.key};
    var next = DashboardStateValues(
      {
        for (final entry in _state.values.entries)
          if (keys.contains(entry.key)) entry.key: entry.value,
      },
    );
    for (final variable in _document.variables) {
      if (next[variable.key] == null && variable.initialValue != null) {
        next = next.withValue(variable.key, variable.initialValue);
      }
    }
    if (next != _state) {
      _state = next;
    }
  }

  void _schedulePersist() {
    _dirty = true;
    _persist?.cancel();
    _persist = Timer(persistDebounce, () {
      _persist = null;
      unawaited(_write());
    });
  }

  /// Write now rather than on the timer — closing, or handing over to another
  /// surface that is about to read the view.
  Future<void> flush() async {
    _persist?.cancel();
    _persist = null;
    if (_dirty) {
      await _write();
    }
  }

  Future<void> _write() async {
    if (viewId.isEmpty) {
      _dirty = false;
      return;
    }
    _writing = true;
    final document = _document;
    try {
      // Re-read first: the view's extra also carries the cover, the icon and
      // whatever else has been marked on it, and a stale copy would erase it.
      final current = await ViewBackendService.getView(viewId);
      final extra = current.fold((view) => view.extra, (_) => '');
      await ViewBackendService.updateView(
        viewId: viewId,
        extra: DashboardMetadata(document: document).mergeIntoExtra(extra),
      );
    } finally {
      _writing = false;
      // Anything changed while the write was in flight is still unsaved.
      _dirty = document != _document;
      if (_dirty) {
        _schedulePersist();
      }
    }
  }

  @override
  void dispose() {
    _persist?.cancel();
    _persist = null;
    if (_dirty) {
      unawaited(_write());
    }
    super.dispose();
  }
}
