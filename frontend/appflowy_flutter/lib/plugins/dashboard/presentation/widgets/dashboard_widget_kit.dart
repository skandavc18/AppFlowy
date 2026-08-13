import 'dart:async';

import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:flutter/material.dart';

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

  @override
  State<DashboardEditableText> createState() => _DashboardEditableTextState();
}

class _DashboardEditableTextState extends State<DashboardEditableText> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);
  final FocusNode _focus = FocusNode();
  Timer? _commit;
  bool _dirty = false;

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
  void didUpdateWidget(DashboardEditableText oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Never adopt an incoming value while an edit of our own is unsaved, or a
    // rebuild lands mid-write and throws away what is being typed.
    if (!_dirty && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
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
    if (!_dirty) {
      return;
    }
    _dirty = false;
    widget.onChanged(_controller.text);
  }

  void _schedule() {
    _dirty = true;
    _commit?.cancel();
    _commit = Timer(widget.commitDelay, _flush);
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final style = widget.style ?? DashboardType.body(palette);
    if (!widget.enabled) {
      final text = _controller.text.isEmpty ? widget.hint : _controller.text;
      return Text(
        text,
        textAlign: widget.textAlign,
        style: _controller.text.isEmpty
            ? style.copyWith(color: palette.textMuted)
            : style,
      );
    }
    return TextEntryShortcuts(
      child: TextField(
        controller: _controller,
        focusNode: _focus,
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
        onChanged: (value) {
          _schedule();
          widget.onEdited?.call(value);
        },
        onSubmitted: (value) {
          _flush();
          widget.onSubmitted?.call(value);
        },
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
  void didUpdateWidget(DashboardEditableNumber oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dirty && widget.value != oldWidget.value) {
      _controller.text = formatDashboardNumber(widget.value);
    }
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
    if (!_dirty) {
      return;
    }
    _dirty = false;
    final parsed = double.tryParse(_controller.text.replaceAll(',', ''));
    if (parsed == null) {
      _controller.text = formatDashboardNumber(widget.value);
      return;
    }
    widget.onChanged(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? DashboardType.figure(widget.palette);
    if (!widget.enabled) {
      return Text(
        formatDashboardNumber(widget.value),
        textAlign: widget.textAlign,
        style: style,
      );
    }
    return IntrinsicWidth(
      child: TextEntryShortcuts(
        child: TextField(
          controller: _controller,
          focusNode: _focus,
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
          onChanged: (_) {
            _dirty = true;
            _commit?.cancel();
            _commit = Timer(widget.commitDelay, _flush);
          },
          onSubmitted: (_) => _flush(),
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
