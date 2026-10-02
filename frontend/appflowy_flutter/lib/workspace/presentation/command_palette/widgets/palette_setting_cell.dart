import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/command_palette/palette_setting.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy/workspace/presentation/command_palette/palette_settings.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/command_results_list.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/palette_row_surface.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Runs a setting's change without letting a failure escape into the frame.
void runPaletteSettingChange(FutureOr<void> Function() change) {
  unawaited(
    Future.sync(change).catchError((Object error) {
      Log.warn('A setting changed from the palette failed: $error');
    }),
  );
}

/// The first, most obvious thing to do with [setting]: flip it, step it on,
/// open its list of choices, or run it.
void activatePaletteSetting(
  PaletteSetting setting, {
  required ValueChanged<PaletteSetting> onOpenPicker,
}) {
  switch (setting.control) {
    case PaletteToggle(:final value, :final onChanged):
      runPaletteSettingChange(() => onChanged(!value));
    case final PaletteChoice choice when !choice.isInline:
      onOpenPicker(setting);
    case final PaletteChoice choice:
      final next = choice.step(1);
      if (next != null) runPaletteSettingChange(() => choice.onSelected(next));
    case final PaletteStepper stepper:
      if (stepper.canIncrease) {
        runPaletteSettingChange(() => stepper.onChanged(stepper.stepped(1)));
      }
    case PaletteAction(:final run):
      runPaletteSettingChange(run);
  }
}

/// Settings as rows, either under their section headings or under one.
class PaletteSettingsList extends StatelessWidget {
  const PaletteSettingsList({
    super.key,
    required this.settings,
    required this.onOpenPicker,
    required this.onOpenSettings,
    this.grouped = true,
    this.sectionLabel,
    this.highlightFirst = false,
  });

  final List<PaletteSetting> settings;
  final ValueChanged<PaletteSetting> onOpenPicker;
  final ValueChanged<SettingsPage> onOpenSettings;
  final bool grouped;
  final String? sectionLabel;

  /// Marks the row Enter would change while the caret is still in the box.
  final bool highlightFirst;

  @override
  Widget build(BuildContext context) {
    if (settings.isEmpty) {
      return const SizedBox.shrink();
    }
    final children = <Widget>[];
    PaletteSettingSection? previous;
    for (final setting in settings) {
      if (grouped && setting.section != previous) {
        previous = setting.section;
        children.add(
          CommandPaletteSectionHeader(
            label: paletteSettingSectionLabel(setting.section),
          ),
        );
      } else if (!grouped && children.isEmpty) {
        children.add(
          CommandPaletteSectionHeader(
            label:
                sectionLabel ?? LocaleKeys.commandPalette_scope_settings.tr(),
          ),
        );
      }
      children.add(
        PaletteSettingCell(
          key: ValueKey('command-palette-setting-${setting.id}'),
          setting: setting,
          preselected: highlightFirst && identical(setting, settings.first),
          onOpenPicker: onOpenPicker,
          onOpenSettings: onOpenSettings,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}

/// The whole body of the palette while it lists settings or extensions.
class PaletteSettingsPanel extends StatefulWidget {
  const PaletteSettingsPanel({
    super.key,
    required this.settings,
    required this.onOpenPicker,
    required this.onOpenSettings,
    this.grouped = true,
    this.sectionLabel,
    this.footer,
    this.empty,
  });

  final List<PaletteSetting> settings;
  final ValueChanged<PaletteSetting> onOpenPicker;
  final ValueChanged<SettingsPage> onOpenSettings;

  /// Under their sections, or ranked under [sectionLabel] while searching.
  final bool grouped;
  final String? sectionLabel;

  /// Shown after the settings, such as the commands extensions add.
  final Widget? footer;

  /// Shown instead when nothing matches.
  final Widget? empty;

  @override
  State<PaletteSettingsPanel> createState() => _PaletteSettingsPanelState();
}

class _PaletteSettingsPanelState extends State<PaletteSettingsPanel> {
  bool _hasFocus = false;

  @override
  Widget build(BuildContext context) {
    if (widget.settings.isEmpty && widget.footer == null) {
      return widget.empty ?? const SizedBox.shrink();
    }
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) => setState(() => _hasFocus = hasFocus),
      child: ScrollControllerBuilder(
        builder: (context, controller) => FlowyScrollbar(
          controller: controller,
          thumbVisibility: false,
          child: SingleChildScrollView(
            controller: controller,
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PaletteSettingsList(
                    settings: widget.settings,
                    onOpenPicker: widget.onOpenPicker,
                    onOpenSettings: widget.onOpenSettings,
                    grouped: widget.grouped,
                    sectionLabel: widget.sectionLabel,
                    highlightFirst: !_hasFocus,
                  ),
                  if (widget.footer != null) widget.footer!,
                  const VSpace(16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One setting, changed in place: a switch, a set of choices, a stepper or a
/// button, with a way through to the page of Settings it belongs to.
class PaletteSettingCell extends StatefulWidget {
  const PaletteSettingCell({
    super.key,
    required this.setting,
    required this.onOpenPicker,
    required this.onOpenSettings,
    this.preselected = false,
  });

  final PaletteSetting setting;
  final ValueChanged<PaletteSetting> onOpenPicker;
  final ValueChanged<SettingsPage> onOpenSettings;
  final bool preselected;

  @override
  State<PaletteSettingCell> createState() => _PaletteSettingCellState();
}

class _PaletteSettingCellState extends State<PaletteSettingCell> {
  final _focusNode = FocusNode(debugLabel: 'palette setting');
  bool _focused = false;
  bool _hovered = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _activate() => activatePaletteSetting(
        widget.setting,
        onOpenPicker: widget.onOpenPicker,
      );

  /// Left and right move a value the way they would on the control itself.
  bool _nudge(int direction) {
    switch (widget.setting.control) {
      case PaletteToggle(:final value, :final onChanged):
        final wanted = direction > 0;
        if (wanted != value) runPaletteSettingChange(() => onChanged(wanted));
        return true;
      case final PaletteChoice choice when choice.isInline:
        final next = choice.step(direction);
        if (next != null) {
          runPaletteSettingChange(() => choice.onSelected(next));
        }
        return true;
      case final PaletteStepper stepper:
        if (direction > 0 ? stepper.canIncrease : stepper.canDecrease) {
          runPaletteSettingChange(
            () => stepper.onChanged(stepper.stepped(direction)),
          );
        }
        return true;
      case PaletteChoice():
      case PaletteAction():
        return false;
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (event is KeyDownEvent &&
        (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter ||
            key == LogicalKeyboardKey.space)) {
      _activate();
      return KeyEventResult.handled;
    }
    final rtl = Directionality.of(context) == TextDirection.rtl;
    if (key == LogicalKeyboardKey.arrowRight) {
      return _nudge(rtl ? -1 : 1)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      return _nudge(rtl ? 1 : -1)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final setting = widget.setting;
    final control = setting.control;
    final tapActivates = control is PaletteToggle ||
        control is PaletteAction ||
        (control is PaletteChoice && !control.isInline);
    final page = setting.settingsPage;

    return Semantics(
      container: true,
      label: setting.title,
      value: paletteSettingValueLabel(setting),
      hint: setting.description,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _focusNode.requestFocus();
            if (tapActivates) _activate();
          },
          child: Focus(
            focusNode: _focusNode,
            onFocusChange: (focused) => setState(() => _focused = focused),
            onKeyEvent: _onKey,
            child: PaletteRowSurface(
              active: _focused || widget.preselected,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: theme.spacing.l,
                  vertical: theme.spacing.m,
                ),
                child: Row(
                  children: [
                    SizedBox.square(
                      dimension: 20,
                      child: Center(
                        child: WorkspaceGlyph(
                          setting.icon,
                          color: theme.iconColorScheme.secondary,
                        ),
                      ),
                    ),
                    const HSpace(10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            setting.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textStyle.body
                                .enhanced(color: theme.textColorScheme.primary)
                                .copyWith(height: 20 / 14),
                          ),
                          if (setting.description.isNotEmpty)
                            Text(
                              setting.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textStyle.caption.standard(
                                color: theme.textColorScheme.tertiary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const HSpace(12),
                    _PaletteSettingControl(
                      setting: setting,
                      onOpenPicker: widget.onOpenPicker,
                    ),
                    if (page != null)
                      _OpenInSettingsButton(
                        visible: _hovered || _focused,
                        onTap: () => widget.onOpenSettings(page),
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

class _OpenInSettingsButton extends StatelessWidget {
  const _OpenInSettingsButton({required this.visible, required this.onTap});

  final bool visible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: WorkspaceTokens.motion(context, WorkspaceTokens.hoverDuration),
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        // The row itself takes the keyboard; its parts are for the pointer.
        child: ExcludeFocus(
          child: IconButton(
            tooltip: LocaleKeys.commandPalette_setting_openInSettings.tr(),
            onPressed: visible ? onTap : null,
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            style: WorkspaceChrome.controlStyle(context),
            icon: WorkspaceGlyph(
              Icons.open_in_new_rounded,
              size: 16,
              color: palette.secondaryText,
            ),
          ),
        ),
      ),
    );
  }
}

class _PaletteSettingControl extends StatelessWidget {
  const _PaletteSettingControl({
    required this.setting,
    required this.onOpenPicker,
  });

  final PaletteSetting setting;
  final ValueChanged<PaletteSetting> onOpenPicker;

  @override
  Widget build(BuildContext context) {
    return switch (setting.control) {
      final PaletteToggle toggle => PaletteSwitch(
          value: toggle.value,
          onChanged: (value) =>
              runPaletteSettingChange(() => toggle.onChanged(value)),
        ),
      final PaletteChoice choice when choice.isInline =>
        _PaletteSegments(choice: choice),
      final PaletteChoice choice => _PaletteValueButton(
          label: choice.selected?.label ?? '',
          icon: choice.selected?.icon,
          onTap: () => onOpenPicker(setting),
        ),
      final PaletteStepper stepper => _PaletteStepperControl(stepper: stepper),
      final PaletteAction action => _PaletteActionButton(action: action),
    };
  }
}

/// A switch drawn from the palette's own tokens, so it sits right in paper,
/// light and dark alike — the thumb is a warm surface, never pure white.
class PaletteSwitch extends StatelessWidget {
  const PaletteSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    final duration =
        WorkspaceTokens.motion(context, WorkspaceTokens.hoverDuration);
    final track = value ? palette.accent : palette.secondarySurface;
    final thumb = value
        ? palette.elevatedSurface
        : palette.secondaryText.withValues(alpha: 0.75);
    return Semantics(
      toggled: value,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: duration,
            curve: WorkspaceTokens.curve,
            width: 34,
            height: 20,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: track,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: value ? track : palette.border,
              ),
            ),
            child: AnimatedAlign(
              duration: duration,
              curve: WorkspaceTokens.curve,
              alignment: value
                  ? AlignmentDirectional.centerEnd
                  : AlignmentDirectional.centerStart,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: thumb,
                  shape: BoxShape.circle,
                  boxShadow: value
                      ? [
                          BoxShadow(
                            color: palette.shadow.withValues(alpha: 0.18),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PaletteSegments extends StatelessWidget {
  const _PaletteSegments({required this.choice});

  final PaletteChoice choice;

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    final theme = AppFlowyTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: palette.secondarySurface,
        borderRadius: BorderRadius.circular(WorkspaceTokens.controlRadius),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in choice.options)
            _Segment(
              key: ValueKey('command-palette-option-${option.id}'),
              selected: option.id == choice.selectedId,
              label: option.label,
              icon: option.icon,
              ink: option.id == choice.selectedId
                  ? palette.primaryText
                  : theme.textColorScheme.secondary,
              onTap: () =>
                  runPaletteSettingChange(() => choice.onSelected(option)),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatefulWidget {
  const _Segment({
    super.key,
    required this.selected,
    required this.label,
    required this.ink,
    required this.onTap,
    this.icon,
  });

  final bool selected;
  final String label;
  final IconData? icon;
  final Color ink;
  final VoidCallback onTap;

  @override
  State<_Segment> createState() => _SegmentState();
}

class _SegmentState extends State<_Segment> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    final theme = AppFlowyTheme.of(context);
    final hover = WorkspaceChrome.hoverColor(context);
    final fill = widget.selected
        ? palette.elevatedSurface
        : (_hovered ? hover : hover.withValues(alpha: 0));
    return Semantics(
      selected: widget.selected,
      button: true,
      label: widget.label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration:
                WorkspaceTokens.motion(context, WorkspaceTokens.hoverDuration),
            curve: WorkspaceTokens.curve,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: fill,
              borderRadius:
                  BorderRadius.circular(WorkspaceTokens.controlRadius - 2),
              boxShadow:
                  widget.selected ? palette.elevation().take(1).toList() : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  WorkspaceGlyph(widget.icon!, size: 14, color: widget.ink),
                  const SizedBox(width: 4),
                ],
                Text(
                  widget.label,
                  maxLines: 1,
                  style: (widget.selected
                          ? theme.textStyle.caption.enhanced(color: widget.ink)
                          : theme.textStyle.caption.standard(color: widget.ink))
                      .copyWith(height: 18 / 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PaletteValueButton extends StatelessWidget {
  const _PaletteValueButton({
    required this.label,
    required this.onTap,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final palette = WorkspacePalette.of(context);
    return ExcludeFocus(
      child: TextButton(
        onPressed: onTap,
        style: WorkspaceChrome.controlStyle(context).copyWith(
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          ),
          minimumSize: const WidgetStatePropertyAll(Size(0, 28)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              WorkspaceGlyph(icon!, size: 14, color: palette.secondaryText),
              const SizedBox(width: 4),
            ],
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textStyle.caption
                    .enhanced(color: theme.textColorScheme.primary),
              ),
            ),
            const SizedBox(width: 2),
            WorkspaceGlyph(
              Icons.chevron_right_rounded,
              size: 16,
              color: palette.secondaryText,
            ),
          ],
        ),
      ),
    );
  }
}

class _PaletteStepperControl extends StatelessWidget {
  const _PaletteStepperControl({required this.stepper});

  final PaletteStepper stepper;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final palette = WorkspacePalette.of(context);
    Widget button(IconData icon, int direction, bool enabled, String key) =>
        ExcludeFocus(
          child: IconButton(
            key: ValueKey(key),
            onPressed: enabled
                ? () => runPaletteSettingChange(
                      () => stepper.onChanged(stepper.stepped(direction)),
                    )
                : null,
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            style: WorkspaceChrome.controlStyle(context),
            icon: WorkspaceGlyph(
              icon,
              size: 16,
              color: enabled
                  ? palette.secondaryText
                  : palette.secondaryText.withValues(alpha: 0.35),
            ),
          ),
        );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.secondarySurface,
        borderRadius: BorderRadius.circular(WorkspaceTokens.controlRadius),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(
            Icons.remove_rounded,
            -1,
            stepper.canDecrease,
            'command-palette-stepper-down',
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44),
            child: Text(
              stepper.label(stepper.value),
              textAlign: TextAlign.center,
              style: theme.textStyle.caption
                  .enhanced(color: theme.textColorScheme.primary)
                  .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
          button(
            Icons.add_rounded,
            1,
            stepper.canIncrease,
            'command-palette-stepper-up',
          ),
        ],
      ),
    );
  }
}

class _PaletteActionButton extends StatelessWidget {
  const _PaletteActionButton({required this.action});

  final PaletteAction action;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final palette = WorkspacePalette.of(context);
    return ExcludeFocus(
      child: OutlinedButton(
        onPressed: () => runPaletteSettingChange(action.run),
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(0, 28),
          side: BorderSide(color: palette.border),
          foregroundColor: palette.primaryText,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WorkspaceTokens.controlRadius),
          ),
        ),
        child: Text(
          action.label,
          style: theme.textStyle.caption
              .enhanced(color: theme.textColorScheme.primary),
        ),
      ),
    );
  }
}
