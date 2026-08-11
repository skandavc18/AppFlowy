import 'dart:math' as math;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'interactive_style.dart';

/// One choice a selector, a radio group or a multi-select offers.
///
/// The id is what a document stores, so renaming an option never orphans the
/// values already chosen.
@immutable
class InteractiveOption {
  const InteractiveOption({
    required this.id,
    required this.label,
    this.accent = InteractiveAccent.neutral,
  });

  factory InteractiveOption.fromJson(Map<String, Object?> json) =>
      InteractiveOption(
        id: json['id'] as String? ?? '',
        label: json['label'] as String? ?? '',
        accent: InteractiveAccent.fromValue(json['color']),
      );

  final String id;
  final String label;
  final InteractiveAccent accent;

  Map<String, Object?> toJson() => {
        'id': id,
        'label': label,
        'color': accent.name,
      };

  InteractiveOption copyWith({String? label, InteractiveAccent? accent}) =>
      InteractiveOption(
        id: id,
        label: label ?? this.label,
        accent: accent ?? this.accent,
      );

  @override
  bool operator ==(Object other) =>
      other is InteractiveOption &&
      other.id == id &&
      other.label == label &&
      other.accent == accent;

  @override
  int get hashCode => Object.hash(id, label, accent);
}

/// Read an option list out of a node attribute.
///
/// A list of maps is what the editor already stores for multi-image blocks,
/// so nothing new is needed to persist these.
List<InteractiveOption> decodeInteractiveOptions(Object? raw) {
  if (raw is! List) {
    return const <InteractiveOption>[];
  }
  final options = <InteractiveOption>[];
  for (final entry in raw) {
    if (entry is Map) {
      final option = InteractiveOption.fromJson(
        entry.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (option.id.isNotEmpty) {
        options.add(option);
      }
    }
  }
  return options;
}

List<Map<String, Object?>> encodeInteractiveOptions(
  List<InteractiveOption> options,
) =>
    options.map((option) => option.toJson()).toList();

/// A stable-enough identifier for a newly created option.
String newInteractiveOptionId() =>
    'opt_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
    '_${math.Random().nextInt(0xFFFF).toRadixString(16)}';

/// The three options a freshly inserted selection block starts with, so the
/// block is usable before anybody configures it.
List<InteractiveOption> defaultInteractiveOptions() => [
      InteractiveOption(
        id: newInteractiveOptionId(),
        label: LocaleKeys.interactive_options_sample1.tr(),
        accent: InteractiveAccent.blue,
      ),
      InteractiveOption(
        id: newInteractiveOptionId(),
        label: LocaleKeys.interactive_options_sample2.tr(),
        accent: InteractiveAccent.orange,
      ),
      InteractiveOption(
        id: newInteractiveOptionId(),
        label: LocaleKeys.interactive_options_sample3.tr(),
        accent: InteractiveAccent.green,
      ),
    ];

/// Opens the floating option list under [anchor].
///
/// One popover serves the selector, the multi-select and — later — the table
/// cells, which is what keeps choosing an option the same gesture wherever it
/// is done.
Future<void> showInteractiveOptionPicker({
  required BuildContext context,
  required Rect anchor,
  required List<InteractiveOption> options,
  required Set<String> selected,
  required bool multiple,
  required ValueChanged<Set<String>> onChanged,
  ValueChanged<InteractiveOption>? onCreate,
  double width = 272,
}) {
  return Navigator.of(context, rootNavigator: true).push(
    _OptionPickerRoute(
      anchor: anchor,
      width: width,
      capturedThemes:
          InheritedTheme.capture(from: context, to: Navigator.of(context).context),
      builder: (context) => _OptionPicker(
        options: options,
        selected: selected,
        multiple: multiple,
        onChanged: onChanged,
        onCreate: onCreate,
      ),
    ),
  );
}

class _OptionPickerRoute extends PopupRoute<void> {
  _OptionPickerRoute({
    required this.anchor,
    required this.width,
    required this.builder,
    required this.capturedThemes,
  });

  final Rect anchor;
  final double width;
  final WidgetBuilder builder;
  final CapturedThemes capturedThemes;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => LocaleKeys.interactive_selector_choose.tr();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 150);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 110);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final media = MediaQuery.of(context);
    return CustomSingleChildLayout(
      delegate: _OptionPickerLayout(anchor: anchor, width: width, media: media),
      child: capturedThemes.wrap(
        FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeIn,
          ),
          child: ScaleTransition(
            alignment: anchor.center.dy > media.size.height / 2
                ? Alignment.bottomLeft
                : Alignment.topLeft,
            scale: Tween<double>(begin: 0.97, end: 1).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: builder(context),
          ),
        ),
      ),
    );
  }
}

class _OptionPickerLayout extends SingleChildLayoutDelegate {
  _OptionPickerLayout({
    required this.anchor,
    required this.width,
    required this.media,
  });

  final Rect anchor;
  final double width;
  final MediaQueryData media;

  static const double _margin = 12;
  static const double _gap = 6;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final below = constraints.maxHeight - anchor.bottom - _gap - _margin;
    final above = anchor.top - _gap - _margin;
    return BoxConstraints(
      maxWidth: width,
      minWidth: width,
      maxHeight: math.max(160, math.max(below, above)),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final opensDown = anchor.bottom + _gap + childSize.height <=
        size.height - _margin ||
        anchor.top - _gap - childSize.height < _margin;
    final dy = opensDown
        ? anchor.bottom + _gap
        : anchor.top - _gap - childSize.height;
    final dx = anchor.left.clamp(
      _margin,
      math.max(_margin, size.width - childSize.width - _margin),
    );
    return Offset(
      dx.toDouble(),
      dy.clamp(_margin, math.max(_margin, size.height - childSize.height - _margin)),
    );
  }

  @override
  bool shouldRelayout(_OptionPickerLayout oldDelegate) =>
      oldDelegate.anchor != anchor || oldDelegate.width != width;
}

class _OptionPicker extends StatefulWidget {
  const _OptionPicker({
    required this.options,
    required this.selected,
    required this.multiple,
    required this.onChanged,
    this.onCreate,
  });

  final List<InteractiveOption> options;
  final Set<String> selected;
  final bool multiple;
  final ValueChanged<Set<String>> onChanged;
  final ValueChanged<InteractiveOption>? onCreate;

  @override
  State<_OptionPicker> createState() => _OptionPickerState();
}

class _OptionPickerState extends State<_OptionPicker> {
  late Set<String> _selected = {...widget.selected};
  final TextEditingController _query = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'interactive option picker');
  final ScrollController _scroll = ScrollController();
  int _highlighted = 0;

  List<InteractiveOption> get _matches {
    final query = _query.text.trim().toLowerCase();
    if (query.isEmpty) {
      return widget.options;
    }
    return widget.options
        .where((option) => option.label.toLowerCase().contains(query))
        .toList();
  }

  bool get _canCreate {
    final query = _query.text.trim();
    if (query.isEmpty || widget.onCreate == null) {
      return false;
    }
    return !widget.options
        .any((option) => option.label.toLowerCase() == query.toLowerCase());
  }

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toggle(InteractiveOption option) {
    setState(() {
      if (widget.multiple) {
        if (!_selected.remove(option.id)) {
          _selected.add(option.id);
        }
      } else {
        _selected = {option.id};
      }
    });
    widget.onChanged({..._selected});
    if (!widget.multiple) {
      Navigator.of(context).maybePop();
    }
  }

  void _create() {
    final label = _query.text.trim();
    if (label.isEmpty) {
      return;
    }
    final option = InteractiveOption(
      id: newInteractiveOptionId(),
      label: label,
      accent: InteractiveAccent
          .values[widget.options.length % InteractiveAccent.values.length],
    );
    widget.onCreate?.call(option);
    setState(() {
      if (widget.multiple) {
        _selected.add(option.id);
      } else {
        _selected = {option.id};
      }
      _query.clear();
      _highlighted = 0;
    });
    widget.onChanged({..._selected});
    if (!widget.multiple) {
      Navigator.of(context).maybePop();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final rows = _matches.length + (_canCreate ? 1 : 0);
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        if (rows == 0) {
          return KeyEventResult.handled;
        }
        setState(() => _highlighted = (_highlighted + 1) % rows);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        if (rows == 0) {
          return KeyEventResult.handled;
        }
        setState(() => _highlighted = (_highlighted - 1 + rows) % rows);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        final matches = _matches;
        if (_highlighted < matches.length) {
          _toggle(matches[_highlighted]);
        } else if (_canCreate) {
          _create();
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        Navigator.of(context).maybePop();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final palette = interactivePaletteOf(context);
    final matches = _matches;

    return Material(
      type: MaterialType.transparency,
      child: Container(
        decoration: BoxDecoration(
          color: palette.raised,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.border.withValues(alpha: 0.34)),
          boxShadow: [
            BoxShadow(
              color:
                  Colors.black.withValues(alpha: palette.isDark ? 0.42 : 0.11),
              blurRadius: 26,
              offset: const Offset(0, 10),
              spreadRadius: -8,
            ),
          ],
        ),
        padding: const EdgeInsets.all(6),
        child: Focus(
          focusNode: _focus,
          onKeyEvent: _onKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SearchField(
                controller: _query,
                palette: palette,
                onChanged: (_) => setState(() => _highlighted = 0),
              ),
              const SizedBox(height: 6),
              Flexible(
                child: matches.isEmpty && !_canCreate
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        child: Text(
                          LocaleKeys.interactive_selector_noMatches.tr(),
                          textAlign: TextAlign.center,
                          style: InteractiveType.caption(palette),
                        ),
                      )
                    : ListView(
                        controller: _scroll,
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        children: [
                          for (var i = 0; i < matches.length; i++)
                            _OptionRow(
                              option: matches[i],
                              palette: palette,
                              multiple: widget.multiple,
                              selected: _selected.contains(matches[i].id),
                              highlighted: i == _highlighted,
                              onTap: () => _toggle(matches[i]),
                            ),
                          if (_canCreate)
                            _CreateRow(
                              label: _query.text.trim(),
                              palette: palette,
                              highlighted: _highlighted == matches.length,
                              onTap: _create,
                            ),
                        ],
                      ),
              ),
              if (widget.multiple) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: InteractiveButton(
                        label: LocaleKeys.interactive_selector_selectAll.tr(),
                        emphasis: InteractiveEmphasis.subtle,
                        dense: true,
                        expand: true,
                        palette: palette,
                        onPressed: () {
                          setState(
                            () => _selected = {
                              for (final option in widget.options) option.id,
                            },
                          );
                          widget.onChanged({..._selected});
                        },
                      ),
                    ),
                    Expanded(
                      child: InteractiveButton(
                        label: LocaleKeys.interactive_selector_clearAll.tr(),
                        emphasis: InteractiveEmphasis.subtle,
                        dense: true,
                        expand: true,
                        palette: palette,
                        onPressed: () {
                          setState(() => _selected = <String>{});
                          widget.onChanged(<String>{});
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.palette,
    required this.onChanged,
  });

  final TextEditingController controller;
  final InteractivePalette palette;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return InteractiveFieldSurface(
      focused: false,
      palette: palette,
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 15, color: palette.textMuted),
          const SizedBox(width: 7),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: true,
              onChanged: onChanged,
              style: InteractiveType.body(palette).copyWith(fontSize: 13),
              cursorColor: palette.accent,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                filled: false,
                hintText: LocaleKeys.interactive_selector_search.tr(),
                hintStyle: InteractiveType.caption(palette),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionRow extends StatefulWidget {
  const _OptionRow({
    required this.option,
    required this.palette,
    required this.multiple,
    required this.selected,
    required this.highlighted,
    required this.onTap,
  });

  final InteractiveOption option;
  final InteractivePalette palette;
  final bool multiple;
  final bool selected;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  State<_OptionRow> createState() => _OptionRowState();
}

class _OptionRowState extends State<_OptionRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final tone = widget.option.accent.resolve(palette);
    final active = _hovered || widget.highlighted;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: InteractiveMetrics.hover,
          curve: InteractiveMetrics.curve,
          height: InteractiveMetrics.rowHeight,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: active ? palette.hover : palette.hoverBase,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              if (widget.multiple)
                _Checkbox(
                  checked: widget.selected,
                  palette: palette,
                  accent: tone.strong,
                )
              else
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: tone.strong,
                    shape: BoxShape.circle,
                  ),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.option.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: InteractiveType.body(palette).copyWith(fontSize: 13),
                ),
              ),
              if (!widget.multiple && widget.selected)
                Icon(Icons.check_rounded, size: 16, color: palette.accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _Checkbox extends StatelessWidget {
  const _Checkbox({
    required this.checked,
    required this.palette,
    required this.accent,
  });

  final bool checked;
  final InteractivePalette palette;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: InteractiveMetrics.hover,
      curve: InteractiveMetrics.curve,
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: checked ? accent : Colors.transparent,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: checked ? accent : palette.border.withValues(alpha: 0.6),
          width: 1.4,
        ),
      ),
      child: checked
          ? const Icon(Icons.check_rounded, size: 11, color: Colors.white)
          : null,
    );
  }
}

class _CreateRow extends StatefulWidget {
  const _CreateRow({
    required this.label,
    required this.palette,
    required this.highlighted,
    required this.onTap,
  });

  final String label;
  final InteractivePalette palette;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  State<_CreateRow> createState() => _CreateRowState();
}

class _CreateRowState extends State<_CreateRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final active = _hovered || widget.highlighted;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: InteractiveMetrics.hover,
          curve: InteractiveMetrics.curve,
          height: InteractiveMetrics.rowHeight,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: active ? palette.hover : palette.hoverBase,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.add_rounded, size: 15, color: palette.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  LocaleKeys.interactive_selector_create.tr(args: [widget.label]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: InteractiveType.body(palette).copyWith(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
