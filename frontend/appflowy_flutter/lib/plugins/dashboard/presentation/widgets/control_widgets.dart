import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_config_field.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/dashboard_widget_kit.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/search_block_component.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_action.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_variable.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_item_icon.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Controls: the things on a dashboard that DO something.
///
/// Every one of them either runs an action or writes a dashboard variable, and
/// nothing else on the dashboard has to know which — a chart bound to
/// `project` follows the project selector without either being aware of the
/// other. That indirection is what makes a dashboard behave like a small
/// application rather than a page of pictures.
void registerDashboardControlWidgets() {
  DashboardWidgetRegistry.register(_button);
  DashboardWidgetRegistry.register(_selector);
  DashboardWidgetRegistry.register(_multiSelect);
  DashboardWidgetRegistry.register(_radioGroup);
  DashboardWidgetRegistry.register(_toggle);
  DashboardWidgetRegistry.register(_checklist);
  DashboardWidgetRegistry.register(_input);
  DashboardWidgetRegistry.register(_counter);
}

const _keyLabel = 'label';
const _keyVariable = 'variable';
const _keyOptions = 'options';
const _keyValue = 'value';
const _keyStep = 'step';
const _keyMinimum = 'minimum';
const _keyMaximum = 'maximum';
const _keyPlaceholder = 'placeholder';
const _keySearchWorkspace = 'search_workspace';
const _keyItems = 'items';
const _keyDone = 'done';
const _keyStyle = 'style';

List<DashboardOption> _optionsOf(DashboardWidgetContext context) {
  // A control bound to a variable offers the variable's own choices, so the
  // list is written once and every control that uses it agrees.
  final variable = context.document.variableFor(
    context.spec.setting(_keyVariable),
  );
  if (variable != null && variable.options.isNotEmpty) {
    return variable.options;
  }
  return DashboardOption.listFromJson(context.spec.settings[_keyOptions]);
}

String _variableKey(DashboardWidgetContext context) =>
    context.spec.setting(_keyVariable);

/// Whether this control owns its own list of choices.
///
/// A control following a variable shows the variable's options, so adding one
/// here would write a list nothing reads.
bool _ownsOptions(DashboardWidgetContext context) {
  final variable = context.document.variableFor(_variableKey(context));
  return variable == null || variable.options.isEmpty;
}

/// Add a choice where the choices are read, rather than in a settings panel.
void _addOption(DashboardWidgetContext context, {String? label}) {
  final options = _optionsOf(context);
  final next = [
    ...options,
    DashboardOption(
      id: newDashboardId('option'),
      label: label?.trim().isNotEmpty ?? false
          ? label!.trim()
          : LocaleKeys.dashboard_control_newOption.tr(),
    ),
  ];
  context.setSettings({
    _keyOptions: [for (final option in next) option.toJson()],
  });
}

/// The affordance every choice widget carries: one more option, from here.
Widget _addOptionButton(DashboardWidgetContext context) => DashboardButton(
      label: LocaleKeys.dashboard_control_addOption.tr(),
      icon: Icons.add_rounded,
      palette: context.palette,
      onPressed: () => _addOption(context),
    );

bool _canAddOptions(DashboardWidgetContext context) =>
    context.isTypable && _ownsOptions(context);

/// Read the value a control holds: from dashboard state when it drives a
/// variable, otherwise from the widget's own settings.
Object? _readValue(DashboardWidgetContext context) {
  final key = _variableKey(context);
  return key.isEmpty ? context.spec.settings[_keyValue] : context.state[key];
}

void _writeValue(DashboardWidgetContext context, Object? value) {
  final key = _variableKey(context);
  if (key.isEmpty) {
    context.setSettings({_keyValue: value});
  } else {
    context.controller.setValue(key, value);
  }
}

List<DashboardConfigField> _bindingFields(
  DashboardWidgetContext context, {
  List<DashboardVariableKind> kinds = const [],
}) =>
    [
      DashboardConfigBinding(
        label: LocaleKeys.dashboard_config_controls.tr(),
        hint: LocaleKeys.dashboard_config_controlsHint.tr(),
        setting: _keyVariable,
        variableKey: context.spec.setting(_keyVariable),
        kinds: kinds,
        onChanged: (key) => context.setSettings({_keyVariable: key}),
      ),
    ];

// --------------------------------------------------------------------- button

final _button = DashboardWidgetDefinition(
  type: 'button',
  label: () => LocaleKeys.dashboard_widget_button.tr(),
  description: () => LocaleKeys.dashboard_widget_buttonHint.tr(),
  icon: Icons.smart_button_rounded,
  group: DashboardWidgetGroup.controls,
  defaultColumnSpan: 3,
  defaultRowSpan: 2,
  showsTitleByDefault: false,
  slashName: 'button',
  keywords: const ['button', 'action', 'run', 'press', 'cta', 'link'],
  builder: (context) {
    final label = context.spec.setting(
      _keyLabel,
      fallback: LocaleKeys.dashboard_widget_button.tr(),
    );
    final action = context.spec.primaryAction;
    final filled =
        context.spec.setting(_keyStyle, fallback: 'filled') == 'filled';
    return Center(
      child: _PressableSurface(
        palette: context.palette,
        strong: context.strong,
        filled: filled,
        onPressed: () => unawaited(context.run(action)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              dashboardActionIconFor(action),
              size: 16,
              color: filled ? context.palette.onAccent : context.strong,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashboardType.cardTitle(
                  context.palette,
                  color: filled ? context.palette.onAccent : context.strong,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  },
  configure: (context) => [
    DashboardConfigText(
      label: LocaleKeys.dashboard_config_label.tr(),
      value: context.spec.setting(_keyLabel),
      placeholder: LocaleKeys.dashboard_widget_button.tr(),
      onChanged: (value) => context.setSettings({_keyLabel: value}),
    ),
    DashboardConfigAction(
      label: LocaleKeys.dashboard_config_action.tr(),
      action: context.spec.primaryAction,
      onChanged: (action) =>
          context.update((spec) => spec.copyWith(actions: [action])),
    ),
    DashboardConfigChoice(
      label: LocaleKeys.dashboard_config_style.tr(),
      value: context.spec.setting(_keyStyle, fallback: 'filled'),
      choices: [
        DashboardChoice(
          value: 'filled',
          label: LocaleKeys.dashboard_style_filled.tr(),
        ),
        DashboardChoice(
          value: 'soft',
          label: LocaleKeys.dashboard_style_soft.tr(),
        ),
      ],
      onChanged: (value) => context.setSettings({_keyStyle: value}),
    ),
  ],
);

IconData dashboardActionIconFor(DashboardAction action) =>
    switch (action.kind) {
      DashboardActionKind.none => Icons.touch_app_rounded,
      DashboardActionKind.openPage => Icons.description_rounded,
      DashboardActionKind.openUrl => Icons.open_in_new_rounded,
      DashboardActionKind.createPage => Icons.note_add_rounded,
      DashboardActionKind.createRow => Icons.playlist_add_rounded,
      DashboardActionKind.setVariable => Icons.tune_rounded,
      DashboardActionKind.toggleVariable => Icons.toggle_on_rounded,
      DashboardActionKind.toggleSection => Icons.unfold_less_rounded,
      DashboardActionKind.copyText => Icons.content_copy_rounded,
      DashboardActionKind.setReminder => Icons.notifications_rounded,
      DashboardActionKind.refresh => Icons.refresh_rounded,
      DashboardActionKind.openModal => Icons.open_in_full_rounded,
    };

// ------------------------------------------------------------------- selector

final _selector = DashboardWidgetDefinition(
  type: 'selector',
  label: () => LocaleKeys.dashboard_widget_selector.tr(),
  description: () => LocaleKeys.dashboard_widget_selectorHint.tr(),
  icon: Icons.arrow_drop_down_circle_rounded,
  group: DashboardWidgetGroup.controls,
  defaultColumnSpan: 3,
  defaultRowSpan: 2,
  slashName: 'selector',
  keywords: const ['selector', 'select', 'dropdown', 'filter', 'choose'],
  builder: (context) {
    final options = _optionsOf(context);
    final selected = '${_readValue(context) ?? ''}';
    final variable =
        context.document.variableFor(context.spec.setting(_keyVariable));
    final chosen = options.where((option) => option.id == selected).firstOrNull;
    final allLabel = variable?.allLabel.isNotEmpty == true
        ? variable!.allLabel
        : LocaleKeys.dashboard_control_all.tr();

    return Center(
      child: Builder(
        builder: (buttonContext) => _FieldSurface(
          palette: context.palette,
          onTap: () async {
            final value = await showAppMenuForWidget<String>(
              context: buttonContext,
              entries: [
                if (variable?.includeAll ?? true)
                  AppMenuItem(
                    label: allLabel,
                    value: '',
                    selected: selected.isEmpty,
                  ),
                for (final option in options)
                  AppMenuItem(
                    label: option.label,
                    value: option.id,
                    selected: option.id == selected,
                  ),
                if (_canAddOptions(context)) ...[
                  const AppMenuSeparator(),
                  AppMenuItem(
                    label: LocaleKeys.dashboard_control_addOption.tr(),
                    icon: Icons.add_rounded,
                    onSelected: () => _addOption(context),
                  ),
                ],
              ],
            );
            if (value != null) {
              _writeValue(context, value.isEmpty ? null : value);
            }
          },
          child: Row(
            children: [
              Expanded(
                child: Text(
                  chosen?.label ?? allLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardType.body(context.palette),
                ),
              ),
              Icon(
                Icons.expand_more_rounded,
                size: 17,
                color: context.palette.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  },
  configure: (context) => [
    ..._bindingFields(
      context,
      kinds: const [DashboardVariableKind.option, DashboardVariableKind.period],
    ),
    if (context.spec.setting(_keyVariable).isEmpty)
      DashboardConfigOptions(
        label: LocaleKeys.dashboard_config_options.tr(),
        options: _optionsOf(context),
        onChanged: (options) => context.setSettings({
          _keyOptions: [for (final option in options) option.toJson()],
        }),
      )
    else
      DashboardConfigNote(
        label: LocaleKeys.dashboard_config_optionsFromVariable.tr(),
        icon: Icons.info_outline_rounded,
      ),
  ],
);

// --------------------------------------------------------------- multi select

final _multiSelect = DashboardWidgetDefinition(
  type: 'multi_select',
  label: () => LocaleKeys.dashboard_widget_multiSelect.tr(),
  icon: Icons.checklist_rounded,
  group: DashboardWidgetGroup.controls,
  defaultRowSpan: 2,
  keywords: const ['multi', 'select', 'tags', 'filter', 'several'],
  builder: (context) {
    final options = _optionsOf(context);
    final value = _readValue(context);
    final selected = <String>{
      if (value is List)
        for (final entry in value)
          if (entry is String) entry,
    };
    return SingleChildScrollView(
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final option in options)
            _Chip(
              label: option.label,
              palette: context.palette,
              strong: context.strong,
              selected: selected.contains(option.id),
              onTap: () {
                final next = {...selected};
                if (!next.remove(option.id)) {
                  next.add(option.id);
                }
                _writeValue(context, next.toList());
              },
            ),
          if (_canAddOptions(context)) _addOptionButton(context),
        ],
      ),
    );
  },
  configure: (context) => [
    ..._bindingFields(
      context,
      kinds: const [DashboardVariableKind.multiOption],
    ),
    if (context.spec.setting(_keyVariable).isEmpty)
      DashboardConfigOptions(
        label: LocaleKeys.dashboard_config_options.tr(),
        options: _optionsOf(context),
        onChanged: (options) => context.setSettings({
          _keyOptions: [for (final option in options) option.toJson()],
        }),
      ),
  ],
);

// ---------------------------------------------------------------- radio group

final _radioGroup = DashboardWidgetDefinition(
  type: 'radio_group',
  label: () => LocaleKeys.dashboard_widget_radioGroup.tr(),
  icon: Icons.radio_button_checked_rounded,
  group: DashboardWidgetGroup.controls,
  defaultColumnSpan: 3,
  keywords: const ['radio', 'choice', 'option', 'one of'],
  builder: (context) {
    final options = _optionsOf(context);
    final selected = '${_readValue(context) ?? ''}';
    final canAdd = _canAddOptions(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: options.length,
            itemBuilder: (_, index) {
              final option = options[index];
              final isSelected = option.id == selected;
              return _Row(
                palette: context.palette,
                onTap: () => _writeValue(context, option.id),
                child: Row(
                  children: [
                    Icon(
                      isSelected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 17,
                      color: isSelected
                          ? context.strong
                          : context.palette.textMuted,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        option.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DashboardType.body(context.palette),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        if (canAdd)
          Align(
            alignment: Alignment.centerLeft,
            child: _addOptionButton(context),
          ),
      ],
    );
  },
  configure: (context) => [
    ..._bindingFields(context, kinds: const [DashboardVariableKind.option]),
    if (context.spec.setting(_keyVariable).isEmpty)
      DashboardConfigOptions(
        label: LocaleKeys.dashboard_config_options.tr(),
        options: _optionsOf(context),
        onChanged: (options) => context.setSettings({
          _keyOptions: [for (final option in options) option.toJson()],
        }),
      ),
  ],
);

// --------------------------------------------------------------------- toggle

final _toggle = DashboardWidgetDefinition(
  type: 'toggle',
  label: () => LocaleKeys.dashboard_widget_toggle.tr(),
  description: () => LocaleKeys.dashboard_widget_toggleHint.tr(),
  icon: Icons.toggle_on_rounded,
  group: DashboardWidgetGroup.controls,
  defaultColumnSpan: 3,
  defaultRowSpan: 2,
  showsTitleByDefault: false,
  keywords: const ['toggle', 'switch', 'on off', 'show', 'hide'],
  builder: (context) {
    final on = _readValue(context) == true;
    return Center(
      child: Row(
        children: [
          Expanded(
            child: Text(
              context.spec.setting(
                _keyLabel,
                fallback: LocaleKeys.dashboard_widget_toggle.tr(),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: DashboardType.body(context.palette),
            ),
          ),
          const SizedBox(width: 10),
          Switch(
            value: on,
            activeColor: context.strong,
            onChanged: (value) => _writeValue(context, value),
          ),
        ],
      ),
    );
  },
  configure: (context) => [
    DashboardConfigText(
      label: LocaleKeys.dashboard_config_label.tr(),
      value: context.spec.setting(_keyLabel),
      onChanged: (value) => context.setSettings({_keyLabel: value}),
    ),
    ..._bindingFields(context, kinds: const [DashboardVariableKind.toggle]),
  ],
);

// ------------------------------------------------------------------ checklist

final _checklist = DashboardWidgetDefinition(
  type: 'checklist',
  label: () => LocaleKeys.dashboard_widget_checklist.tr(),
  icon: Icons.check_box_rounded,
  group: DashboardWidgetGroup.controls,
  defaultColumnSpan: 3,
  defaultRowSpan: 5,
  keywords: const ['checklist', 'todo', 'tasks', 'checkbox', 'habits'],
  builder: (context) {
    final items = [
      for (final entry in context.spec.list(_keyItems))
        if (entry is Map) Map<String, Object?>.from(entry),
    ];
    final palette = context.palette;

    void write(List<Map<String, Object?>> next) =>
        context.setSettings({_keyItems: next});

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: items.length,
            itemBuilder: (_, index) {
              final item = items[index];
              final done = item[_keyDone] == true;
              return _Row(
                palette: palette,
                onTap: () {
                  final next = [...items];
                  next[index] = {...item, _keyDone: !done};
                  write(next);
                },
                child: Row(
                  children: [
                    Icon(
                      done
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 17,
                      color: done ? context.strong : palette.textMuted,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        '${item[_keyLabel] ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DashboardType.body(palette).copyWith(
                          decoration: done ? TextDecoration.lineThrough : null,
                          color: done ? palette.textMuted : palette.textPrimary,
                        ),
                      ),
                    ),
                    DashboardIconButton(
                      icon: Icons.close_rounded,
                      palette: palette,
                      size: 20,
                      iconSize: 13,
                      onPressed: () => write([
                        for (var i = 0; i < items.length; i++)
                          if (i != index) items[i],
                      ]),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: DashboardButton(
            label: LocaleKeys.dashboard_control_addItem.tr(),
            icon: Icons.add_rounded,
            palette: palette,
            onPressed: () => write([
              ...items,
              {_keyLabel: LocaleKeys.dashboard_control_newItem.tr()},
            ]),
          ),
        ),
      ],
    );
  },
  configure: (context) => [
    DashboardConfigNote(
      label: LocaleKeys.dashboard_config_checklistHint.tr(),
      icon: Icons.info_outline_rounded,
    ),
    DashboardConfigButton(
      label: LocaleKeys.dashboard_control_clearDone.tr(),
      icon: Icons.cleaning_services_rounded,
      onPressed: () => context.setSettings({
        _keyItems: [
          for (final entry in context.spec.list(_keyItems))
            if (entry is Map && entry[_keyDone] != true)
              Map<String, Object?>.from(entry),
        ],
      }),
    ),
  ],
);

// ---------------------------------------------------------------------- input

final _input = DashboardWidgetDefinition(
  type: 'input',
  label: () => LocaleKeys.dashboard_widget_input.tr(),
  description: () => LocaleKeys.dashboard_widget_inputHint.tr(),
  icon: Icons.search_rounded,
  group: DashboardWidgetGroup.controls,
  defaultColumnSpan: 6,
  defaultRowSpan: 2,
  showsTitleByDefault: false,
  // A search bar is a bar, not a panel: it draws its own pill and nothing
  // else, so no card is printed behind it.
  paintsOwnSurface: true,
  slashName: 'input',
  keywords: const ['input', 'search', 'field', 'query', 'text box', 'filter'],
  builder: (context) => _SearchBody(context: context),
  configure: (context) => [
    DashboardConfigText(
      label: LocaleKeys.dashboard_config_placeholder.tr(),
      value: context.spec.setting(_keyPlaceholder),
      onChanged: (value) => context.setSettings({_keyPlaceholder: value}),
    ),
    DashboardConfigToggle(
      label: LocaleKeys.dashboard_config_searchWorkspace.tr(),
      value: context.spec.flag(_keySearchWorkspace, fallback: true),
      onChanged: (value) => context.setSettings({_keySearchWorkspace: value}),
    ),
    ..._bindingFields(context, kinds: const [DashboardVariableKind.text]),
  ],
);

/// A search bar that actually searches.
///
/// It writes its text into the dashboard's own state, so a chart bound to the
/// same control follows it — and, unless it is told not to, it also looks
/// through the workspace and offers what it found, because a search box that
/// finds nothing is a text field with a magnifying glass on it.
class _SearchBody extends StatefulWidget {
  const _SearchBody({required this.context});

  final DashboardWidgetContext context;

  @override
  State<_SearchBody> createState() => _SearchBodyState();
}

class _SearchBodyState extends State<_SearchBody> {
  final LayerLink _link = LayerLink();
  final OverlayPortalController _suggestions = OverlayPortalController();
  final GlobalKey _fieldKey = GlobalKey();

  List<ViewPB> _workspace = const [];
  bool _reading = false;
  String _query = '';
  bool _focused = false;

  bool get _searchesWorkspace =>
      widget.context.spec.flag(_keySearchWorkspace, fallback: true);

  List<ViewPB> get _hits => _searchesWorkspace
      ? rankWorkspaceMatches(_workspace, _query, limit: 8)
      : const [];

  @override
  void initState() {
    super.initState();
    _query = '${_readValue(widget.context) ?? ''}';
  }

  Future<void> _readWorkspace() async {
    if (_reading || _workspace.isNotEmpty || !_searchesWorkspace) {
      return;
    }
    _reading = true;
    final result = await const WorkspaceItemService().getAllViews();
    if (!mounted) {
      return;
    }
    setState(() {
      _reading = false;
      _workspace = result.fold((views) => views, (_) => const []);
    });
  }

  void _onQuery(String value) {
    setState(() => _query = value);
    unawaited(_readWorkspace());
    _reveal(show: _hits.isNotEmpty);
  }

  /// `show`/`hide` mutate, so they can never be called from `build`.
  void _reveal({required bool show}) {
    if (show == _suggestions.isShowing) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (show) {
        _suggestions.show();
      } else {
        _suggestions.hide();
      }
    });
  }

  void _open(ViewPB view) {
    _reveal(show: false);
    unawaited(
      widget.context.run(
        DashboardAction(
          kind: DashboardActionKind.openPage,
          target: view.id,
          targetName: view.name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.context.palette;
    final hint = widget.context.spec.setting(
      _keyPlaceholder,
      fallback: LocaleKeys.dashboard_control_searchHint.tr(),
    );

    final bar = CompositedTransformTarget(
      link: _link,
      child: AnimatedContainer(
        key: _fieldKey,
        duration: DashboardMetrics.hover,
        curve: DashboardMetrics.curve,
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: palette.surface,
          // The whole point of the shape: a pill, round at both ends, held up
          // by its shadow rather than ringed by a line.
          borderRadius: BorderRadius.circular(999),
          boxShadow: palette.cardShadow(raised: _focused),
        ),
        child: Row(
          children: [
            Icon(Icons.search_rounded, size: 18, color: palette.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Focus(
                onFocusChange: (has) {
                  setState(() => _focused = has);
                  if (has) {
                    unawaited(_readWorkspace());
                  } else {
                    _reveal(show: false);
                  }
                },
                child: DashboardEditableText(
                  value: '${_readValue(widget.context) ?? ''}',
                  hint: hint,
                  palette: palette,
                  commitDelay: const Duration(milliseconds: 200),
                  onChanged: (value) => _writeValue(widget.context, value),
                  onEdited: _onQuery,
                  onSubmitted: (_) {
                    final first = _hits.firstOrNull;
                    if (first != null) {
                      _open(first);
                    }
                  },
                ),
              ),
            ),
            if (_query.isNotEmpty) ...[
              const SizedBox(width: 6),
              DashboardIconButton(
                icon: Icons.close_rounded,
                palette: palette,
                size: 24,
                iconSize: 14,
                onPressed: () {
                  _writeValue(widget.context, '');
                  _onQuery('');
                },
              ),
            ],
          ],
        ),
      ),
    );

    return OverlayPortal(
      controller: _suggestions,
      overlayChildBuilder: (_) => _buildSuggestions(palette),
      child: Align(alignment: Alignment.topCenter, child: bar),
    );
  }

  Widget _buildSuggestions(DashboardPalette palette) {
    final hits = _hits;
    final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    final width = box?.size.width ?? 320;
    if (hits.isEmpty) {
      return const SizedBox.shrink();
    }
    // An overlay child is laid out at the window's size with TIGHT
    // constraints; `Align` is what hands the card loose ones back.
    return Align(
      alignment: Alignment.topLeft,
      child: CompositedTransformFollower(
        link: _link,
        targetAnchor: Alignment.bottomLeft,
        offset: const Offset(0, 8),
        // Without this the field counts the list as "outside", unfocuses on
        // pointer down and takes the row away before the tap can land — which
        // is exactly "clicking a suggestion does nothing".
        child: TextFieldTapRegion(
          child: SizedBox(
            width: width,
            child: Material(
              color: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  color: palette.raised,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: palette.cardShadow(raised: true),
                ),
                clipBehavior: Clip.antiAlias,
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final view in hits)
                      _SuggestionRow(
                        view: view,
                        palette: palette,
                        accent: widget.context.strong,
                        onChosen: () => _open(view),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One workspace object the search bar found.
class _SuggestionRow extends StatefulWidget {
  const _SuggestionRow({
    required this.view,
    required this.palette,
    required this.accent,
    required this.onChosen,
  });

  final ViewPB view;
  final DashboardPalette palette;
  final Color accent;
  final VoidCallback onChosen;

  @override
  State<_SuggestionRow> createState() => _SuggestionRowState();
}

class _SuggestionRowState extends State<_SuggestionRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Listener(
        // Chosen on pointer DOWN: a tap would move the focus first and the
        // list would be gone before it resolved.
        onPointerDown: (_) => widget.onChosen(),
        child: AnimatedContainer(
          duration: DashboardMetrics.hover,
          curve: DashboardMetrics.curve,
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: _hovered ? palette.hover : palette.hoverBase,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: widget.accent.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: WorkspaceItemIcon.fromView(
                    view: widget.view,
                    size: 15,
                    color: widget.accent,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  widget.view.name.isEmpty
                      ? LocaleKeys.menuAppHeader_defaultNewPageName.tr()
                      : widget.view.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashboardType.body(palette),
                ),
              ),
              AnimatedOpacity(
                duration: DashboardMetrics.hover,
                opacity: _hovered ? 1 : 0,
                child: Icon(
                  Icons.arrow_outward_rounded,
                  size: 15,
                  color: palette.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------- counter

final _counter = DashboardWidgetDefinition(
  type: 'counter',
  label: () => LocaleKeys.dashboard_widget_counter.tr(),
  icon: Icons.exposure_plus_1_rounded,
  group: DashboardWidgetGroup.controls,
  defaultColumnSpan: 3,
  defaultRowSpan: 3,
  slashName: 'counter',
  keywords: const ['counter', 'count', 'tally', 'increment', 'number'],
  builder: (context) {
    final value = context.spec.number(_keyValue, fallback: 0);
    final stored = context.spec.number(_keyStep, fallback: 1);
    final step = stored == 0 ? 1.0 : stored;
    final minimum = context.spec.settings[_keyMinimum];
    final maximum = context.spec.settings[_keyMaximum];

    void nudge(double delta) {
      var next = value + delta;
      if (minimum is num) {
        next = next < minimum ? minimum.toDouble() : next;
      }
      if (maximum is num) {
        next = next > maximum ? maximum.toDouble() : next;
      }
      if (next != value) {
        context.setSettings({_keyValue: next});
      }
    }

    return Row(
      children: [
        DashboardIconButton(
          icon: Icons.remove_rounded,
          palette: context.palette,
          size: 30,
          iconSize: 17,
          onPressed: () => nudge(-step),
        ),
        Expanded(
          child: DashboardFigure(
            value: formatDashboardNumber(value),
            palette: context.palette,
            alignment: CrossAxisAlignment.center,
            size: 30,
            color: context.strong,
          ),
        ),
        DashboardIconButton(
          icon: Icons.add_rounded,
          palette: context.palette,
          size: 30,
          iconSize: 17,
          onPressed: () => nudge(step),
        ),
      ],
    );
  },
  configure: (context) => [
    DashboardConfigNumber(
      label: LocaleKeys.dashboard_config_value.tr(),
      value: context.spec.number(_keyValue, fallback: 0),
      onChanged: (value) => context.setSettings({_keyValue: value}),
    ),
    DashboardConfigNumber(
      label: LocaleKeys.dashboard_config_step.tr(),
      value: context.spec.number(_keyStep, fallback: 1),
      minimum: 0.01,
      onChanged: (value) => context.setSettings({_keyStep: value}),
    ),
    DashboardConfigButton(
      label: LocaleKeys.dashboard_control_reset.tr(),
      icon: Icons.restart_alt_rounded,
      onPressed: () => context.setSettings({_keyValue: 0}),
    ),
  ],
);

// ------------------------------------------------------------------- surfaces

class _PressableSurface extends StatefulWidget {
  const _PressableSurface({
    required this.child,
    required this.palette,
    required this.strong,
    required this.filled,
    required this.onPressed,
  });

  final Widget child;
  final DashboardPalette palette;
  final Color strong;
  final bool filled;
  final VoidCallback onPressed;

  @override
  State<_PressableSurface> createState() => _PressableSurfaceState();
}

class _PressableSurfaceState extends State<_PressableSurface> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: DashboardMetrics.hover,
            curve: DashboardMetrics.curve,
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: widget.filled
                  ? (_hovered
                      ? Color.alphaBlend(
                          Colors.black.withValues(
                            alpha: widget.palette.isDark ? 0 : 0.1,
                          ),
                          widget.strong,
                        )
                      : widget.strong)
                  : widget.strong.withValues(alpha: _hovered ? 0.22 : 0.14),
              borderRadius:
                  BorderRadius.circular(DashboardMetrics.controlRadius),
            ),
            child: Center(widthFactor: 1, child: widget.child),
          ),
        ),
      );
}

class _FieldSurface extends StatelessWidget {
  const _FieldSurface({
    required this.child,
    required this.palette,
    this.onTap,
  });

  final Widget child;
  final DashboardPalette palette;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final surface = Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: palette.sunken,
        borderRadius: BorderRadius.circular(DashboardMetrics.controlRadius),
      ),
      child: Center(child: child),
    );
    if (onTap == null) {
      return surface;
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: surface),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.palette,
    required this.strong,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final DashboardPalette palette;
  final Color strong;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: DashboardMetrics.hover,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? strong.withValues(alpha: 0.18) : palette.sunken,
              borderRadius: BorderRadius.circular(DashboardMetrics.chipRadius),
            ),
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                style: DashboardType.caption(
                  palette,
                  color: selected ? strong : palette.textSecondary,
                ).copyWith(fontSize: 12.5),
              ),
            ),
          ),
        ),
      );
}

class _Row extends StatefulWidget {
  const _Row({
    required this.child,
    required this.palette,
    required this.onTap,
  });

  final Widget child;
  final DashboardPalette palette;
  final VoidCallback onTap;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: DashboardMetrics.hover,
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            margin: const EdgeInsets.only(bottom: 2),
            decoration: BoxDecoration(
              color: _hovered ? widget.palette.hover : widget.palette.hoverBase,
              borderRadius: BorderRadius.circular(8),
            ),
            child: widget.child,
          ),
        ),
      );
}
