import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/command_palette/palette_setting.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/palette_row_surface.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The choices of one setting with too many to show in its row — a theme, a
/// language, a model — searched with the palette's own box.
class PaletteOptionPicker extends StatefulWidget {
  const PaletteOptionPicker({
    super.key,
    required this.setting,
    required this.options,
    required this.selectedId,
    required this.onPicked,
    required this.onBack,
  });

  final PaletteSetting setting;

  /// The options left after the search, best first.
  final List<PaletteSettingOption> options;
  final String? selectedId;
  final ValueChanged<PaletteSettingOption> onPicked;
  final VoidCallback onBack;

  @override
  State<PaletteOptionPicker> createState() => _PaletteOptionPickerState();
}

class _PaletteOptionPickerState extends State<PaletteOptionPicker> {
  bool _hasFocus = false;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final palette = WorkspacePalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(vertical: theme.spacing.s),
          child: Row(
            children: [
              ExcludeFocus(
                child: IconButton(
                  key: const ValueKey('command-palette-picker-back'),
                  tooltip: LocaleKeys.commandPalette_setting_back.tr(),
                  onPressed: widget.onBack,
                  visualDensity: VisualDensity.compact,
                  style: WorkspaceChrome.controlStyle(context),
                  icon: WorkspaceGlyph(
                    Directionality.of(context) == TextDirection.rtl
                        ? Icons.arrow_forward_rounded
                        : Icons.arrow_back_rounded,
                    size: 16,
                    color: palette.secondaryText,
                  ),
                ),
              ),
              const HSpace(4),
              WorkspaceGlyph(
                widget.setting.icon,
                size: 16,
                color: theme.iconColorScheme.secondary,
              ),
              const HSpace(8),
              Flexible(
                child: Text(
                  widget.setting.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textStyle.body
                      .enhanced(color: theme.textColorScheme.primary),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: widget.options.isEmpty
              ? Center(
                  child: Text(
                    LocaleKeys.commandPalette_setting_noOptions.tr(),
                    style: theme.textStyle.body
                        .standard(color: theme.textColorScheme.secondary),
                  ),
                )
              : Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onFocusChange: (hasFocus) =>
                      setState(() => _hasFocus = hasFocus),
                  child: ScrollControllerBuilder(
                    builder: (context, controller) => FlowyScrollbar(
                      controller: controller,
                      thumbVisibility: false,
                      child: ListView.builder(
                        controller: controller,
                        padding: const EdgeInsets.only(right: 6, bottom: 12),
                        itemCount: widget.options.length,
                        itemBuilder: (context, index) {
                          final option = widget.options[index];
                          return _OptionCell(
                            key: ValueKey(
                              'command-palette-picker-option-${option.id}',
                            ),
                            option: option,
                            selected: option.id == widget.selectedId,
                            preselected: !_hasFocus && index == 0,
                            onPicked: () => widget.onPicked(option),
                          );
                        },
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _OptionCell extends StatefulWidget {
  const _OptionCell({
    super.key,
    required this.option,
    required this.selected,
    required this.preselected,
    required this.onPicked,
  });

  final PaletteSettingOption option;
  final bool selected;
  final bool preselected;
  final VoidCallback onPicked;

  @override
  State<_OptionCell> createState() => _OptionCellState();
}

class _OptionCellState extends State<_OptionCell> {
  final _focusNode = FocusNode(debugLabel: 'palette option');
  bool _focused = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    final palette = WorkspacePalette.of(context);
    final option = widget.option;
    return Semantics(
      button: true,
      selected: widget.selected,
      label: option.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPicked,
        child: Focus(
          focusNode: _focusNode,
          onFocusChange: (focused) => setState(() => _focused = focused),
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                    event.logicalKey == LogicalKeyboardKey.space)) {
              widget.onPicked();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
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
                      child: option.icon == null
                          ? null
                          : WorkspaceGlyph(
                              option.icon!,
                              size: 16,
                              color: theme.iconColorScheme.secondary,
                            ),
                    ),
                  ),
                  const HSpace(10),
                  Flexible(
                    child: Text(
                      option.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textStyle.body
                          .enhanced(color: theme.textColorScheme.primary),
                    ),
                  ),
                  if (option.description.isNotEmpty) ...[
                    const HSpace(8),
                    Flexible(
                      child: Text(
                        option.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textStyle.caption
                            .standard(color: theme.textColorScheme.tertiary),
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (widget.selected)
                    WorkspaceGlyph(
                      Icons.check_rounded,
                      size: 16,
                      color: palette.accent,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
