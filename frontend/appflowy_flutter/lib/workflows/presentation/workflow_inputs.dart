import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_view_picker.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workflows/application/workflow_format.dart';
import 'package:appflowy/workflows/application/workflow_model.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'workflow_style.dart';

/// One value the data picker can drop into a field.
class WorkflowDataField {
  const WorkflowDataField({
    required this.path,
    required this.label,
    this.preview = '',
  });

  /// What goes between the braces: `trigger.title`, `step2.body.id`.
  final String path;
  final String label;
  final String preview;
}

class WorkflowDataGroup {
  const WorkflowDataGroup({
    required this.label,
    required this.glyph,
    required this.fields,
  });

  final String label;
  final String glyph;
  final List<WorkflowDataField> fields;
}

/// Everything a step can read: the trigger, each step before it, stored
/// values and the clock. Real samples come first; fields every run of that
/// kind carries fill in what has not been tested yet.
List<WorkflowDataGroup> workflowDataGroups(
  Workflow workflow, {
  String? beforeStepId,
  Map<String, Object?> storage = const {},
}) {
  WorkflowDataGroup group(
    String label,
    String glyph,
    String prefix,
    Object? sample,
    List<String> known,
  ) {
    final paths = <String>[
      ...workflowFieldPaths(sample),
      for (final field in known)
        if (!workflowFieldPaths(sample)
            .any((path) => path == field || path.startsWith('$field.')))
          field,
    ];
    return WorkflowDataGroup(
      label: label,
      glyph: glyph,
      fields: [
        for (final path in paths.take(60))
          WorkflowDataField(
            path: '$prefix.$path',
            label: path,
            preview: _preview(
              sample is Map ? _read(sample, path) : null,
            ),
          ),
      ],
    );
  }

  final groups = <WorkflowDataGroup>[
    group(
      '${LocaleKeys.workflows_fields_trigger.tr()} · '
          '${WorkflowVisuals.triggerName(workflow.trigger.kind)}',
      WorkflowVisuals.triggerGlyph(workflow.trigger.kind),
      'trigger',
      workflow.samples[Workflow.triggerSampleKey],
      workflow.trigger.kind.knownFields,
    ),
  ];
  for (var index = 0; index < workflow.steps.length; index++) {
    final step = workflow.steps[index];
    if (step.id == beforeStepId) {
      break;
    }
    groups.add(
      group(
        '${index + 2}. ${WorkflowVisuals.stepTitle(step)}',
        WorkflowVisuals.stepGlyph(step.kind),
        step.id,
        workflow.samples[step.id],
        step.kind.knownFields,
      ),
    );
  }
  if (storage.isNotEmpty) {
    groups.add(
      WorkflowDataGroup(
        label: LocaleKeys.workflows_fields_storage.tr(),
        glyph: 'database',
        fields: [
          for (final entry in storage.entries.take(60))
            WorkflowDataField(
              path: 'storage.${entry.key}',
              label: entry.key,
              preview: _preview(entry.value),
            ),
        ],
      ),
    );
  }
  groups.add(
    WorkflowDataGroup(
      label: LocaleKeys.workflows_fields_builtIn.tr(),
      glyph: 'clock',
      fields: [
        WorkflowDataField(
          path: 'now',
          label: LocaleKeys.workflows_fields_now.tr(),
        ),
        WorkflowDataField(
          path: 'today',
          label: LocaleKeys.workflows_fields_today.tr(),
        ),
        WorkflowDataField(
          path: 'time',
          label: LocaleKeys.workflows_fields_time.tr(),
        ),
        WorkflowDataField(
          path: 'workflow.name',
          label: LocaleKeys.workflows_fields_workflowName.tr(),
        ),
      ],
    ),
  );
  return groups;
}

Object? _read(Map<Object?, Object?> sample, String path) {
  Object? current = sample;
  for (final segment in path.split('.')) {
    if (current is Map) {
      current = current[segment];
    } else if (current is List) {
      final index = int.tryParse(segment);
      current =
          index == null || index >= current.length ? null : current[index];
    } else {
      return null;
    }
  }
  return current;
}

String _preview(Object? value) {
  if (value == null || value is Map || value is List) {
    return '';
  }
  final text = workflowText(value).replaceAll(RegExp(r'\s+'), ' ').trim();
  return text.length > 48 ? '${text.substring(0, 48)}…' : text;
}

/// Opens the data picker under [anchorContext]; the chosen path, or null.
Future<String?> showWorkflowDataMenu(
  BuildContext anchorContext,
  List<WorkflowDataGroup> groups,
) {
  final entries = <AppMenuEntry>[
    AppMenuHeader(LocaleKeys.workflows_fields_insertData.tr()),
    for (final group in groups)
      AppMenuItem(
        label: group.label,
        iconWidget: WorkspaceGlyph.named(group.glyph, size: 16),
        submenu: group.fields.isEmpty
            ? [
                AppMenuItem(
                  label: LocaleKeys.workflows_fields_noData.tr(),
                  enabled: false,
                ),
              ]
            : [
                for (final field in group.fields)
                  AppMenuItem(
                    label: field.label,
                    subtitle: field.preview.isEmpty ? null : field.preview,
                    value: field.path,
                  ),
              ],
      ),
  ];
  return showAppMenuForWidget<String>(
    context: anchorContext,
    entries: entries,
    width: 280,
  );
}

/// Draws `{{ ... }}` as a tinted token, so data is told apart from words.
class WorkflowTemplateController extends TextEditingController {
  WorkflowTemplateController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final source = text;
    final composing = withComposing && value.isComposingRangeValid;
    if (composing || !source.contains('{{')) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final palette = DashboardPalette.of(context);
    final token = TextStyle(
      color: palette.accent,
      backgroundColor: palette.accentSoft,
    );
    final children = <InlineSpan>[];
    var last = 0;
    for (final match in workflowTemplatePattern.allMatches(source)) {
      if (match.start > last) {
        children.add(TextSpan(text: source.substring(last, match.start)));
      }
      children.add(TextSpan(text: match.group(0), style: token));
      last = match.end;
    }
    if (last < source.length) {
      children.add(TextSpan(text: source.substring(last)));
    }
    return TextSpan(style: style, children: children);
  }
}

/// A labelled text field. Given [dataGroups], it can insert data from the
/// trigger and earlier steps at the caret.
class WorkflowTextInput extends StatefulWidget {
  const WorkflowTextInput({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.hint,
    this.dataGroups,
    this.minLines = 1,
    this.maxLines = 1,
    this.monospace = false,
    this.keyboardType,
    this.readOnly = false,
    this.trailing,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String? label;
  final String? hint;
  final List<WorkflowDataGroup>? dataGroups;
  final int minLines;
  final int maxLines;
  final bool monospace;
  final TextInputType? keyboardType;
  final bool readOnly;
  final Widget? trailing;

  @override
  State<WorkflowTextInput> createState() => _WorkflowTextInputState();
}

class _WorkflowTextInputState extends State<WorkflowTextInput> {
  late final WorkflowTemplateController _controller =
      WorkflowTemplateController(text: widget.value);
  final FocusNode _focus = FocusNode();

  @override
  void didUpdateWidget(WorkflowTextInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text && !_focus.hasFocus) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _insert(BuildContext anchor) async {
    final groups = widget.dataGroups;
    if (groups == null) {
      return;
    }
    final path = await showWorkflowDataMenu(anchor, groups);
    if (path == null || !mounted) {
      return;
    }
    final token = '{{$path}}';
    final text = _controller.text;
    final selection = _controller.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    _controller.value = TextEditingValue(
      text: text.replaceRange(start, end, token),
      selection: TextSelection.collapsed(offset: start + token.length),
    );
    widget.onChanged(_controller.text);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    final multiline = widget.maxLines > 1;
    final style = DashboardType.body(palette).copyWith(
      fontSize: 13,
      height: 1.45,
      fontFamily: widget.monospace ? 'monospace' : null,
      fontFamilyFallback: widget.monospace
          ? const ['Cascadia Code', 'Consolas', 'Menlo', 'Courier New']
          : null,
    );
    final insert = widget.dataGroups == null || widget.readOnly
        ? null
        : Builder(
            builder: (anchor) => WorkflowInsertDataButton(
              onPressed: () => unawaited(_insert(anchor)),
            ),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null || insert != null)
          WorkflowLabel(
            widget.label ?? '',
            trailing: insert,
          ),
        TextEntryShortcuts(
          child: TextField(
            controller: _controller,
            focusNode: _focus,
            readOnly: widget.readOnly,
            onChanged: widget.onChanged,
            minLines: widget.minLines,
            maxLines: widget.maxLines,
            keyboardType: widget.keyboardType ??
                (multiline ? TextInputType.multiline : TextInputType.text),
            style: style,
            cursorColor: palette.accent,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: palette.sunken,
              hoverColor: palette.hover.withValues(alpha: 0.35),
              hintText: widget.hint,
              hintStyle: style.copyWith(color: palette.textMuted),
              suffixIcon: widget.trailing,
              suffixIconConstraints:
                  const BoxConstraints(minWidth: 30, minHeight: 30),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 11,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: palette.border.withValues(alpha: 0.35),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: palette.accent, width: 1.3),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The small "{ } Insert data" control over a field.
class WorkflowInsertDataButton extends StatelessWidget {
  const WorkflowInsertDataButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    return TextButton(
      onPressed: onPressed,
      style: WorkspaceChrome.controlStyle(context).copyWith(
        minimumSize: const WidgetStatePropertyAll(Size(0, 22)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        ),
        foregroundColor: WidgetStatePropertyAll(palette.accent),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)
              ? palette.accentSoft
              : palette.accentSoft.withValues(alpha: 0),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          WorkspaceGlyph.named(
            'brackets',
            size: 13,
            color: palette.accent,
            role: WorkspaceGlyphRole.preserveInk,
          ),
          const SizedBox(width: 4),
          Text(
            LocaleKeys.workflows_fields_insertData.tr(),
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Name/value lines: headers, query parameters, body fields, columns.
class WorkflowPairsEditor extends StatelessWidget {
  const WorkflowPairsEditor({
    super.key,
    required this.pairs,
    required this.onChanged,
    this.label,
    this.keyHint,
    this.valueHint,
    this.dataGroups,
    this.fixedKeys = false,
  });

  final List<WorkflowPair> pairs;
  final ValueChanged<List<WorkflowPair>> onChanged;
  final String? label;
  final String? keyHint;
  final String? valueHint;
  final List<WorkflowDataGroup>? dataGroups;

  /// Keys are given (a table's columns); only values are edited.
  final bool fixedKeys;

  void _set(int index, WorkflowPair pair) {
    final next = [...pairs];
    next[index] = pair;
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) WorkflowLabel(label!),
        for (var index = 0; index < pairs.length; index++)
          Padding(
            key: ValueKey('pair-$index-${pairs.length}'),
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(
                  width: 128,
                  child: fixedKeys
                      ? Padding(
                          padding: const EdgeInsets.only(bottom: 10, right: 4),
                          child: Text(
                            pairs[index].key,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: DashboardType.body(palette).copyWith(
                              fontSize: 12.5,
                              color: palette.textSecondary,
                            ),
                          ),
                        )
                      : WorkflowTextInput(
                          value: pairs[index].key,
                          hint: keyHint ?? LocaleKeys.workflows_fields_key.tr(),
                          onChanged: (text) => _set(
                            index,
                            WorkflowPair(text, pairs[index].value),
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: WorkflowTextInput(
                    value: pairs[index].value,
                    hint: valueHint ?? LocaleKeys.workflows_fields_value.tr(),
                    dataGroups: dataGroups,
                    onChanged: (text) => _set(
                      index,
                      WorkflowPair(pairs[index].key, text),
                    ),
                  ),
                ),
                if (!fixedKeys) ...[
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: WorkflowIconButton(
                      glyph: 'x',
                      tooltip: LocaleKeys.workflows_fields_remove.tr(),
                      onPressed: () => onChanged([...pairs]..removeAt(index)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        if (!fixedKeys)
          Align(
            alignment: Alignment.centerLeft,
            child: WorkflowButton(
              label: LocaleKeys.workflows_fields_add.tr(),
              glyph: 'plus',
              kind: WorkflowButtonKind.quiet,
              onPressed: () =>
                  onChanged([...pairs, const WorkflowPair('', '')]),
            ),
          ),
      ],
    );
  }
}

/// One option of a [WorkflowChoice].
class WorkflowOption<T> {
  const WorkflowOption(this.value, this.label, {this.subtitle, this.glyph});

  final T value;
  final String label;
  final String? subtitle;
  final String? glyph;
}

/// A dropdown: shows the current choice and opens a menu of the rest.
class WorkflowChoice<T> extends StatelessWidget {
  const WorkflowChoice({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.label,
    this.width,
  });

  final T value;
  final List<WorkflowOption<T>> options;
  final ValueChanged<T> onChanged;
  final String? label;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    WorkflowOption<T>? current;
    for (final option in options) {
      if (option.value == value) {
        current = option;
      }
    }
    final button = Builder(
      builder: (anchor) => TextButton(
        onPressed: () async {
          final chosen = await showAppMenuForWidget<Object?>(
            context: anchor,
            placement: AppMenuPlacement.below,
            width: width == null ? 240 : (width! < 200 ? 200 : width),
            entries: [
              for (final option in options)
                AppMenuItem(
                  label: option.label,
                  subtitle: option.subtitle,
                  iconWidget: option.glyph == null
                      ? null
                      : WorkspaceGlyph.named(option.glyph!, size: 16),
                  selected: option.value == value,
                  value: _Picked<T>(option.value),
                ),
            ],
          );
          if (chosen is _Picked<T>) {
            onChanged(chosen.value);
          }
        },
        style: WorkspaceChrome.controlStyle(context).copyWith(
          minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          foregroundColor: WidgetStatePropertyAll(palette.textPrimary),
          side: WidgetStateProperty.resolveWith(
            (states) => BorderSide(
              color: states.contains(WidgetState.focused)
                  ? palette.accent
                  : palette.border.withValues(alpha: 0.35),
            ),
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.hovered)
                ? Color.alphaBlend(
                    palette.hover.withValues(alpha: 0.5),
                    palette.sunken,
                  )
                : palette.sunken,
          ),
        ),
        child: Row(
          children: [
            if (current?.glyph != null) ...[
              WorkspaceGlyph.named(current!.glyph!, size: 15),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                current?.label ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashboardType.body(palette).copyWith(fontSize: 13),
              ),
            ),
            const SizedBox(width: 6),
            WorkspaceGlyph.named(
              'caret-down',
              size: 13,
              color: palette.textMuted,
            ),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) WorkflowLabel(label!),
        if (width == null) button else SizedBox(width: width, child: button),
      ],
    );
  }
}

class _Picked<T> {
  const _Picked(this.value);

  final T value;
}

/// A checkbox with its sentence; the whole row is the target.
class WorkflowCheckRow extends StatelessWidget {
  const WorkflowCheckRow({
    super.key,
    required this.value,
    required this.label,
    required this.onChanged,
    this.hint,
  });

  final bool value;
  final String label;
  final String? hint;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    return MergeSemantics(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        hoverColor: palette.hover.withValues(alpha: 0.5),
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: Checkbox(
                  value: value,
                  onChanged: onChanged == null
                      ? null
                      : (checked) => onChanged!(checked ?? false),
                  activeColor: palette.accent,
                  checkColor: palette.onAccent,
                  side: BorderSide(color: palette.textMuted, width: 1.4),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        label,
                        style:
                            DashboardType.body(palette).copyWith(fontSize: 13),
                      ),
                    ),
                    if (hint != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        hint!,
                        style: DashboardType.caption(palette)
                            .copyWith(fontSize: 12, height: 1.35),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What kind of thing a [WorkflowViewPicker] chooses.
enum WorkflowViewKind {
  page,
  table,
  parent;

  bool accepts(ViewPB view) => switch (this) {
        WorkflowViewKind.table => view.layout == ViewLayoutPB.Grid ||
            view.layout == ViewLayoutPB.Board ||
            view.layout == ViewLayoutPB.Calendar,
        WorkflowViewKind.page => view.layout == ViewLayoutPB.Document,
        WorkflowViewKind.parent => view.layout == ViewLayoutPB.Document,
      };
}

/// Shows the chosen page or table by name, and lets it be changed.
class WorkflowViewPicker extends StatefulWidget {
  const WorkflowViewPicker({
    super.key,
    required this.viewId,
    required this.kind,
    required this.onChanged,
    this.label,
    this.emptyLabel,
    this.clearable = false,
    this.clearedLabel,
  });

  final String viewId;
  final WorkflowViewKind kind;

  /// The id and name chosen, or empty strings when cleared.
  final void Function(String id, String name) onChanged;
  final String? label;
  final String? emptyLabel;

  /// Offer a way back to nothing chosen, shown as [clearedLabel].
  final bool clearable;
  final String? clearedLabel;

  @override
  State<WorkflowViewPicker> createState() => _WorkflowViewPickerState();
}

class _WorkflowViewPickerState extends State<WorkflowViewPicker> {
  ViewPB? _view;
  bool _missing = false;
  String _loadedFor = '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(WorkflowViewPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewId != widget.viewId) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final id = widget.viewId;
    _loadedFor = id;
    if (id.isEmpty) {
      setState(() {
        _view = null;
        _missing = false;
      });
      return;
    }
    final result = await ViewBackendService.getView(id);
    if (!mounted || _loadedFor != id) {
      return;
    }
    setState(() {
      _view = result.fold((view) => view, (_) => null);
      _missing = _view == null;
    });
  }

  Future<void> _choose() async {
    final chosen = await showInteractiveViewPicker(
      context,
      selectedViewId: widget.viewId.isEmpty ? null : widget.viewId,
      filter: widget.kind.accepts,
    );
    if (chosen == null || !mounted) {
      return;
    }
    widget.onChanged(chosen.id, chosen.nameOrDefault);
  }

  @override
  Widget build(BuildContext context) {
    final palette = DashboardPalette.of(context);
    final view = _view;
    final String text;
    if (widget.viewId.isEmpty) {
      text = widget.clearable && widget.clearedLabel != null
          ? widget.clearedLabel!
          : widget.emptyLabel ?? LocaleKeys.workflows_fields_choose.tr();
    } else if (view != null) {
      text = view.nameOrDefault;
    } else if (_missing) {
      text = LocaleKeys.workflows_fields_missing.tr();
    } else {
      text = '…';
    }
    final empty = widget.viewId.isEmpty && !widget.clearable;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) WorkflowLabel(widget.label!),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => unawaited(_choose()),
                style: WorkspaceChrome.controlStyle(context).copyWith(
                  minimumSize: const WidgetStatePropertyAll(Size(0, 38)),
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                  ),
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  side: WidgetStateProperty.resolveWith(
                    (states) => BorderSide(
                      color: states.contains(WidgetState.focused)
                          ? palette.accent
                          : empty
                              ? palette.accent.withValues(alpha: 0.45)
                              : palette.border.withValues(alpha: 0.35),
                    ),
                  ),
                  backgroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.hovered)
                        ? Color.alphaBlend(
                            palette.hover.withValues(alpha: 0.5),
                            palette.sunken,
                          )
                        : palette.sunken,
                  ),
                ),
                child: Row(
                  children: [
                    if (view != null)
                      view.defaultIcon(size: const Size.square(16))
                    else
                      WorkspaceGlyph.named(
                        _missing
                            ? 'warning'
                            : widget.kind == WorkflowViewKind.table
                                ? 'table'
                                : 'file-text',
                        size: 16,
                        color: _missing
                            ? palette.strongFor(DashboardAccent.red)
                            : null,
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DashboardType.body(
                          palette,
                          color: empty ? palette.accent : null,
                        ).copyWith(fontSize: 13),
                      ),
                    ),
                    WorkspaceGlyph.named(
                      'caret-down',
                      size: 13,
                      color: palette.textMuted,
                    ),
                  ],
                ),
              ),
            ),
            if (widget.clearable && widget.viewId.isNotEmpty) ...[
              const SizedBox(width: 4),
              WorkflowIconButton(
                glyph: 'x',
                tooltip: LocaleKeys.workflows_fields_clear.tr(),
                onPressed: () => widget.onChanged('', ''),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
