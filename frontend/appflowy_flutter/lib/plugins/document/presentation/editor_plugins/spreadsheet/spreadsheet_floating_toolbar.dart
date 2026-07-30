import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_chrome_style.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'spreadsheet_controller.dart';
import 'spreadsheet_menus.dart';
import 'spreadsheet_model.dart';
import 'spreadsheet_theme.dart';

/// The formatting toolbar that floats over the selection, matching the one the
/// editor raises for selected text: same height, radius, elevation and icon
/// colour, so formatting a cell feels like formatting a paragraph.
class SpreadsheetFloatingToolbar extends StatelessWidget {
  const SpreadsheetFloatingToolbar({
    super.key,
    required this.controller,
    this.onMenuVisibilityChanged,
  });

  final SpreadsheetController controller;

  /// Raised while one of the toolbar's popups is open, so the host can keep
  /// the bar on screen even though the popup took keyboard focus.
  final ValueChanged<bool>? onMenuVisibilityChanged;

  Future<void> _withMenu(Future<void> Function() open) async {
    onMenuVisibilityChanged?.call(true);
    try {
      await open();
    } finally {
      onMenuVisibilityChanged?.call(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = SpreadsheetPalette.of(context);
    final iconColor = EditorChromeStyle.iconColor(context);

    return Material(
      color: Colors.transparent,
      child: Container(
        height: SpreadsheetMetrics.floatingToolbarHeight,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: palette.floating,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: palette.shadow,
              blurRadius: 24,
              spreadRadius: -6,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: palette.shadow.withValues(alpha: palette.shadow.a * 0.5),
              blurRadius: 4,
              spreadRadius: -1,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Button(
              icon: Icons.format_bold_rounded,
              tooltip: LocaleKeys.spreadsheet_format_bold.tr(),
              iconColor: iconColor,
              palette: palette,
              active: controller.selectionHas((style) => style.bold),
              onPressed: controller.toggleBold,
            ),
            _Button(
              icon: Icons.format_italic_rounded,
              tooltip: LocaleKeys.spreadsheet_format_italic.tr(),
              iconColor: iconColor,
              palette: palette,
              active: controller.selectionHas((style) => style.italic),
              onPressed: controller.toggleItalic,
            ),
            _Button(
              icon: Icons.format_underline_rounded,
              tooltip: LocaleKeys.spreadsheet_format_underline.tr(),
              iconColor: iconColor,
              palette: palette,
              active: controller.selectionHas((style) => style.underline),
              onPressed: controller.toggleUnderline,
            ),
            _Button(
              icon: Icons.format_strikethrough_rounded,
              tooltip: LocaleKeys.spreadsheet_format_strikethrough.tr(),
              iconColor: iconColor,
              palette: palette,
              active: controller.selectionHas((style) => style.strikethrough),
              onPressed: controller.toggleStrikethrough,
            ),
            _Divider(palette: palette),
            _AnchoredButton(
              icon: _alignIcon(),
              tooltip: LocaleKeys.spreadsheet_format_align.tr(),
              iconColor: iconColor,
              palette: palette,
              onOpen: (position) => _openAlign(context, position),
            ),
            _AnchoredButton(
              icon: Icons.tag_rounded,
              tooltip: LocaleKeys.spreadsheet_format_numberFormat.tr(),
              iconColor: iconColor,
              palette: palette,
              onOpen: (position) => _openNumberFormat(context, position),
            ),
            _AnchoredButton(
              icon: Icons.palette_rounded,
              tooltip: LocaleKeys.spreadsheet_format_textColor.tr(),
              iconColor: iconColor,
              palette: palette,
              onOpen: (position) => _openColors(context, position),
            ),
            _Divider(palette: palette),
            _AnchoredButton(
              icon: Icons.more_horiz_rounded,
              tooltip: LocaleKeys.spreadsheet_toolbar_more.tr(),
              iconColor: iconColor,
              palette: palette,
              onOpen: (position) => _openMore(context, position),
            ),
          ],
        ),
      ),
    );
  }

  IconData _alignIcon() {
    if (controller.selectionHas((style) => style.align == CellAlign.center)) {
      return Icons.format_align_center_rounded;
    }
    if (controller.selectionHas((style) => style.align == CellAlign.end)) {
      return Icons.format_align_right_rounded;
    }
    return Icons.format_align_left_rounded;
  }

  void _openAlign(BuildContext context, Offset position) {
    _withMenu(
      () => showSpreadsheetAlignMenu(
        context: context,
        controller: controller,
        position: position,
      ),
    );
  }

  void _openNumberFormat(BuildContext context, Offset position) {
    SpreadsheetMenuEntry entry(
      CellNumberFormat format,
      String label,
      IconData icon,
    ) =>
        SpreadsheetMenuEntry(
          label: label,
          icon: icon,
          selected: controller.selectionHas((style) => style.format == format),
          onSelected: () => controller.setNumberFormat(format),
        );

    _withMenu(
      () => showSpreadsheetMenu(
        context: context,
        position: position,
        width: 212,
        entries: [
          entry(
            CellNumberFormat.automatic,
            LocaleKeys.spreadsheet_format_automatic.tr(),
            Icons.auto_awesome_rounded,
          ),
          entry(
            CellNumberFormat.number,
            LocaleKeys.spreadsheet_format_number.tr(),
            Icons.numbers_rounded,
          ),
          entry(
            CellNumberFormat.currency,
            LocaleKeys.spreadsheet_format_currency.tr(),
            Icons.attach_money_rounded,
          ),
          entry(
            CellNumberFormat.percent,
            LocaleKeys.spreadsheet_format_percent.tr(),
            Icons.percent_rounded,
          ),
          entry(
            CellNumberFormat.date,
            LocaleKeys.spreadsheet_format_date.tr(),
            Icons.calendar_today_rounded,
          ),
          entry(
            CellNumberFormat.time,
            LocaleKeys.spreadsheet_format_time.tr(),
            Icons.schedule_rounded,
          ),
          entry(
            CellNumberFormat.text,
            LocaleKeys.spreadsheet_format_plainText.tr(),
            Icons.text_fields_rounded,
          ),
        ],
      ),
    );
  }

  void _openColors(BuildContext context, Offset position) {
    _withMenu(
      () => showSpreadsheetColorPanel(
        context: context,
        controller: controller,
        position: position,
      ),
    );
  }

  void _openMore(BuildContext context, Offset position) {
    _withMenu(
      () => showSpreadsheetMenu(
        context: context,
        position: position,
        width: 212,
        entries: [
          SpreadsheetMenuEntry(
            label: LocaleKeys.spreadsheet_format_allBorders.tr(),
            icon: Icons.border_all_rounded,
            onSelected: () => controller.setBorders(CellBorders.all),
          ),
          SpreadsheetMenuEntry(
            label: LocaleKeys.spreadsheet_format_noBorder.tr(),
            icon: Icons.border_clear_rounded,
            onSelected: () => controller.setBorders(CellBorders.none),
          ),
          const SpreadsheetMenuEntry.divider(),
          SpreadsheetMenuEntry(
            label: LocaleKeys.spreadsheet_menu_clear.tr(),
            icon: Icons.backspace_rounded,
            onSelected: controller.clearSelection,
          ),
          SpreadsheetMenuEntry(
            label: LocaleKeys.spreadsheet_format_clearFormatting.tr(),
            icon: Icons.format_clear_rounded,
            onSelected: () => controller.applyStyle((_) => const CellStyle()),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.palette});

  final SpreadsheetPalette palette;

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 16,
        margin: const EdgeInsets.symmetric(horizontal: 5),
        color: palette.divider,
      );
}

class _Button extends StatefulWidget {
  const _Button({
    required this.icon,
    required this.tooltip,
    required this.iconColor,
    required this.palette,
    required this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final Color iconColor;
  final SpreadsheetPalette palette;
  final VoidCallback onPressed;
  final bool active;

  @override
  State<_Button> createState() => _ButtonState();
}

class _ButtonState extends State<_Button> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: AppFlowyMotion.fast,
            curve: AppFlowyMotion.standardCurve,
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: widget.active
                  ? palette.accent.withValues(alpha: 0.13)
                  : _hovered
                      ? palette.hover
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(
              widget.icon,
              size: 17,
              color: widget.active ? palette.accent : widget.iconColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _AnchoredButton extends StatefulWidget {
  const _AnchoredButton({
    required this.icon,
    required this.tooltip,
    required this.iconColor,
    required this.palette,
    required this.onOpen,
  });

  final IconData icon;
  final String tooltip;
  final Color iconColor;
  final SpreadsheetPalette palette;
  final void Function(Offset position) onOpen;

  @override
  State<_AnchoredButton> createState() => _AnchoredButtonState();
}

class _AnchoredButtonState extends State<_AnchoredButton> {
  final GlobalKey _anchor = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: _anchor,
      child: _Button(
        icon: widget.icon,
        tooltip: widget.tooltip,
        iconColor: widget.iconColor,
        palette: widget.palette,
        onPressed: () {
          final box = _anchor.currentContext?.findRenderObject() as RenderBox?;
          if (box == null) {
            return;
          }
          widget.onOpen(box.localToGlobal(Offset(0, box.size.height + 8)));
        },
      ),
    );
  }
}
