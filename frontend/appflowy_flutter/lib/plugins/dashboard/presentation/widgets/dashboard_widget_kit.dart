import 'dart:async';

import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_find.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/find_replace/surface_find.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:flutter/material.dart';

/// Live access for delayed field commits, including fields in borrowed pages
/// and enlarged widgets. Cache the controller, not a BuildContext lookup, so
/// disposal can check the latest access without walking a deactivated tree.
class DashboardEditingScope extends InheritedWidget {
  DashboardEditingScope({
    super.key,
    required this.controller,
    required super.child,
  }) : editable = controller.isEditable;

  final DashboardController controller;
  final bool editable;

  static DashboardController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<DashboardEditingScope>()
      ?.controller;

  @override
  bool updateShouldNotify(DashboardEditingScope oldWidget) =>
      controller != oldWidget.controller || editable != oldWidget.editable;
}

/// One reading of every view a dashboard points at.
///
/// A dashboard can hold a dozen widgets naming the same page; each of them
/// asking the backend separately would be a dozen round trips for one answer.
abstract final class DashboardViewCache {
  static final Map<String, ViewPB> _views = {};
  static final Map<String, Future<ViewPB?>> _inFlight = {};

  /// What is already known, without asking.
  static ViewPB? peek(String viewId) => _views[viewId];

  static Future<ViewPB?> read(String viewId) {
    if (viewId.isEmpty) {
      return Future.value();
    }
    final known = _views[viewId];
    if (known != null) {
      return Future.value(known);
    }
    final existing = _inFlight[viewId];
    if (existing != null) {
      return existing;
    }
    final request = ViewBackendService.getView(viewId).then((result) {
      final view = result.fold<ViewPB?>((view) => view, (_) => null);
      if (view != null) {
        _views[viewId] = view;
      }
      return view;
    }).whenComplete(() => _inFlight.removeWhere((key, _) => key == viewId));
    _inFlight[viewId] = request;
    return request;
  }

  /// Drop what is remembered so the next read is a fresh one.
  static void forget([String? viewId]) {
    if (viewId == null) {
      _views.clear();
    } else {
      _views.remove(viewId);
    }
  }
}

/// Resolves a view id and rebuilds when the answer arrives.
class DashboardViewBuilder extends StatefulWidget {
  const DashboardViewBuilder({
    super.key,
    required this.viewId,
    required this.builder,
    this.placeholder,
    this.revision = 0,
  });

  final String viewId;
  final Widget Function(BuildContext context, ViewPB view) builder;
  final Widget? placeholder;

  /// Bump to force a re-read — the dashboard's refresh button does.
  final int revision;

  @override
  State<DashboardViewBuilder> createState() => _DashboardViewBuilderState();
}

class _DashboardViewBuilderState extends State<DashboardViewBuilder> {
  ViewPB? _view;

  @override
  void initState() {
    super.initState();
    _view = DashboardViewCache.peek(widget.viewId);
    _resolve();
  }

  @override
  void didUpdateWidget(DashboardViewBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewId != widget.viewId ||
        oldWidget.revision != widget.revision) {
      if (oldWidget.revision != widget.revision) {
        DashboardViewCache.forget(widget.viewId);
      }
      _view = DashboardViewCache.peek(widget.viewId);
      _resolve();
    }
  }

  Future<void> _resolve() async {
    if (widget.viewId.isEmpty) {
      return;
    }
    final view = await DashboardViewCache.read(widget.viewId);
    if (mounted && view != null && view.id == widget.viewId) {
      setState(() => _view = view);
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = _view;
    if (view == null) {
      return widget.placeholder ?? const SizedBox.shrink();
    }
    return widget.builder(context, view);
  }
}

/// Text a widget owns and can be typed into in place.
///
/// The value is committed on a timer rather than per keystroke: a dashboard is
/// persisted into the view's metadata, and a transaction per character would
/// write the whole document each time.
class DashboardEditableText extends StatefulWidget {
  const DashboardEditableText({
    super.key,
    required this.value,
    required this.onChanged,
    required this.palette,
    this.style,
    this.hint = '',
    this.enabled = true,
    this.multiline = false,
    this.textAlign = TextAlign.start,
    this.commitDelay = const Duration(milliseconds: 400),
    this.onEdited,
    this.onSubmitted,
    this.findId,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final DashboardPalette palette;
  final TextStyle? style;
  final String hint;
  final bool enabled;
  final bool multiline;
  final TextAlign textAlign;
  final Duration commitDelay;

  /// Every keystroke, for a field that answers while it is being typed in.
  final ValueChanged<String>? onEdited;
  final ValueChanged<String>? onSubmitted;

  /// Only explicit dashboard content opts in, never query/configuration fields.
  final Object? findId;

  @override
  State<DashboardEditableText> createState() => _DashboardEditableTextState();
}

class _DashboardEditableTextState extends State<DashboardEditableText> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);
  final FocusNode _focus = FocusNode();
  Timer? _commit;
  bool _dirty = false;
  String? _submitted;
  DashboardController? _dashboard;
  DashboardFindController? _find;
  Object? _findId;

  bool get _canWrite => widget.enabled && (_dashboard?.isEditable ?? true);

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) {
        _flush();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dashboard = DashboardEditingScope.maybeOf(context);
    _bindFind();
    _suspendIfBlocked();
  }

  @override
  void didUpdateWidget(DashboardEditableText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.findId != oldWidget.findId) _bindFind();
    _suspendIfBlocked();
    // onChanged is a synchronous command with no acceptance result. Only the
    // supplied value acknowledges it; a rejected command must stay dirty.
    if (_dirty && widget.value == _controller.text) {
      _dirty = false;
      _submitted = null;
    } else if (widget.value != oldWidget.value) {
      _submitted = null;
    }
    // A remote value or an access change must not replace a suspended draft.
    if (!_dirty && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  void _bindFind() {
    final owner = SurfaceFindScope.maybeOf(context);
    final find = owner is DashboardFindController ? owner : null;
    if (_find == find && _findId == widget.findId) return;
    if (_findId != null) _find?.unwatchDraft(_findId!, _controller);
    _find = find;
    _findId = widget.findId;
    if (_findId != null) _find?.watchDraft(_findId!, _controller);
  }

  void _suspendIfBlocked() {
    if (_canWrite) return;
    _commit?.cancel();
    _commit = null;
    _submitted = null;
  }

  @override
  void dispose() {
    if (_findId != null) _find?.unwatchDraft(_findId!, _controller);
    _flush();
    _commit?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _flush() {
    _commit?.cancel();
    _commit = null;
    if (!_dirty || !_canWrite || _submitted == _controller.text) {
      return;
    }
    // Coalesce submit/blur/disposal before the owner's next build. A new edit
    // or explicit submission can retry a command that was not acknowledged.
    _submitted = _controller.text;
    try {
      widget.onChanged(_controller.text);
    } catch (_) {
      _submitted = null;
      rethrow;
    }
  }

  void _schedule() {
    _dirty = true;
    _submitted = null;
    _commit?.cancel();
    _commit = Timer(widget.commitDelay, _flush);
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final style = widget.style ?? DashboardType.body(palette);
    final writable = _canWrite;
    final field = TextEntryShortcuts(
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        readOnly: !writable,
        showCursor: writable ? null : false,
        style: style,
        textAlign: widget.textAlign,
        maxLines: widget.multiline ? null : 1,
        cursorColor: palette.accent,
        decoration: InputDecoration(
          isDense: true,
          isCollapsed: true,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          hoverColor: Colors.transparent,
          hintText: widget.hint,
          hintStyle: style.copyWith(color: palette.textMuted),
        ),
        onChanged: writable
            ? (value) {
                if (!_canWrite) return;
                _schedule();
                widget.onEdited?.call(value);
              }
            : null,
        onSubmitted: writable
            ? (value) {
                if (!_canWrite) return;
                _submitted = null;
                _flush();
                widget.onSubmitted?.call(value);
              }
            : null,
      ),
    );
    final id = widget.findId;
    if (id == null) return field;
    return ContextualFindRegion(
      enabled: _find != null,
      findInEditable: true,
      onFind: () => _find?.open(),
      onReplace: _canWrite ? () => _find?.open(replace: true) : null,
      debugLabel: 'Dashboard owned text',
      child: SurfaceFindTarget(
        id: id,
        includeEditable: true,
        child: field,
      ),
    );
  }
}

/// A number a widget owns and can be typed over in place.
///
/// The same bargain as [DashboardEditableText]: a figure nobody can type into
/// is a figure that has to be hunted for in a settings panel.
class DashboardEditableNumber extends StatefulWidget {
  const DashboardEditableNumber({
    super.key,
    required this.value,
    required this.onChanged,
    required this.palette,
    this.style,
    this.enabled = true,
    this.textAlign = TextAlign.start,
    this.commitDelay = const Duration(milliseconds: 400),
  });

  final double value;
  final ValueChanged<double> onChanged;
  final DashboardPalette palette;
  final TextStyle? style;
  final bool enabled;
  final TextAlign textAlign;
  final Duration commitDelay;

  @override
  State<DashboardEditableNumber> createState() =>
      _DashboardEditableNumberState();
}

class _DashboardEditableNumberState extends State<DashboardEditableNumber> {
  late final TextEditingController _controller =
      TextEditingController(text: formatDashboardNumber(widget.value));
  final FocusNode _focus = FocusNode();
  Timer? _commit;
  bool _dirty = false;
  String? _submitted;
  DashboardController? _dashboard;

  bool get _canWrite => widget.enabled && (_dashboard?.isEditable ?? true);

  double? get _parsed => double.tryParse(_controller.text.replaceAll(',', ''));

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) {
        _flush();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dashboard = DashboardEditingScope.maybeOf(context);
    _suspendIfBlocked();
  }

  @override
  void didUpdateWidget(DashboardEditableNumber oldWidget) {
    super.didUpdateWidget(oldWidget);
    _suspendIfBlocked();
    if (_dirty) {
      if (_parsed == widget.value) {
        _dirty = false;
        _submitted = null;
      } else if (widget.value != oldWidget.value) {
        _submitted = null;
      }
      // Keep the person's formatting and selection even when acknowledged.
      return;
    }
    if (widget.value != oldWidget.value) {
      _controller.text = formatDashboardNumber(widget.value);
    }
  }

  void _suspendIfBlocked() {
    if (_canWrite) return;
    _commit?.cancel();
    _commit = null;
    _submitted = null;
  }

  @override
  void dispose() {
    _flush();
    _commit?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _flush() {
    _commit?.cancel();
    _commit = null;
    if (!_dirty || !_canWrite || _submitted == _controller.text) {
      return;
    }
    final parsed = _parsed;
    // An incomplete number is still a draft, not permission to restore the
    // stored value. Non-finite values cannot be persisted as dashboard JSON.
    if (parsed == null || !parsed.isFinite) {
      return;
    }
    _submitted = _controller.text;
    try {
      widget.onChanged(parsed);
    } catch (_) {
      _submitted = null;
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? DashboardType.figure(widget.palette);
    final writable = _canWrite;
    return IntrinsicWidth(
      child: TextEntryShortcuts(
        child: TextField(
          controller: _controller,
          focusNode: _focus,
          readOnly: !writable,
          showCursor: writable ? null : false,
          style: style,
          textAlign: widget.textAlign,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          cursorColor: widget.palette.accent,
          decoration: const InputDecoration(
            isDense: true,
            isCollapsed: true,
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            hoverColor: Colors.transparent,
          ),
          onChanged: writable
              ? (_) {
                  if (!_canWrite) return;
                  _dirty = true;
                  _submitted = null;
                  _commit?.cancel();
                  _commit = Timer(widget.commitDelay, _flush);
                }
              : null,
          onSubmitted: writable
              ? (_) {
                  if (!_canWrite) return;
                  _submitted = null;
                  _flush();
                }
              : null,
        ),
      ),
    );
  }
}

/// A quiet label above a value, used by several widgets.
class DashboardFigure extends StatelessWidget {
  const DashboardFigure({
    super.key,
    required this.value,
    required this.palette,
    this.caption = '',
    this.prefix = '',
    this.suffix = '',
    this.color,
    this.size = 34,
    this.alignment = CrossAxisAlignment.start,
  });

  final String value;
  final DashboardPalette palette;
  final String caption;
  final String prefix;
  final String suffix;
  final Color? color;
  final double size;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: alignment,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: alignment == CrossAxisAlignment.center
                ? Alignment.center
                : Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                if (prefix.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 3),
                    child: Text(
                      prefix,
                      style: DashboardType.caption(palette)
                          .copyWith(fontSize: size * 0.42),
                    ),
                  ),
                Text(
                  value,
                  style: DashboardType.figure(palette, size: size)
                      .copyWith(color: color),
                ),
                if (suffix.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 3),
                    child: Text(
                      suffix,
                      style: DashboardType.caption(palette)
                          .copyWith(fontSize: size * 0.42),
                    ),
                  ),
              ],
            ),
          ),
          if (caption.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DashboardType.caption(palette),
            ),
          ],
        ],
      );
}

/// Whole numbers read as whole numbers; only a real fraction shows a point.
String formatDashboardNumber(double value, {int decimals = 2}) {
  if (value == value.roundToDouble()) {
    return value.round().toString();
  }
  return value
      .toStringAsFixed(decimals)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}
