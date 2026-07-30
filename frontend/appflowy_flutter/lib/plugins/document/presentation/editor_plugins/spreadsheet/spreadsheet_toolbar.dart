import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'spreadsheet_controller.dart';
import 'spreadsheet_formula.dart';
import 'spreadsheet_theme.dart';

/// A borderless icon button: muted at rest, a soft rounded wash on hover, the
/// accent when its state is on. The only control shape the sheet chrome uses.
class SpreadsheetToolbarButton extends StatefulWidget {
  const SpreadsheetToolbarButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.active = false,
    this.size = SpreadsheetMetrics.controlSize,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;
  final double size;

  @override
  State<SpreadsheetToolbarButton> createState() =>
      _SpreadsheetToolbarButtonState();
}

class _SpreadsheetToolbarButtonState extends State<SpreadsheetToolbarButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = SpreadsheetPalette.of(context);
    final enabled = widget.onPressed != null;
    final foreground = !enabled
        ? palette.textMuted.withValues(alpha: 0.45)
        : widget.active
            ? palette.accent
            : _hovered
                ? palette.textPrimary
                : palette.textMuted;
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: AppFlowyMotion.fast,
            curve: AppFlowyMotion.standardCurve,
            width: widget.size,
            height: widget.size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: widget.active
                  ? palette.accent.withValues(alpha: 0.11)
                  : _hovered && enabled
                      ? palette.hover
                      : Colors.transparent,
              borderRadius:
                  BorderRadius.circular(SpreadsheetMetrics.controlRadius),
            ),
            child: Icon(widget.icon, size: 15.5, color: foreground),
          ),
        ),
      ),
    );
  }
}

/// A toolbar button that reports its own screen position so menus open flush
/// under the control that summoned them.
class SpreadsheetAnchoredButton extends StatefulWidget {
  const SpreadsheetAnchoredButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onOpen,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final void Function(Offset position) onOpen;
  final bool active;

  @override
  State<SpreadsheetAnchoredButton> createState() =>
      _SpreadsheetAnchoredButtonState();
}

class _SpreadsheetAnchoredButtonState extends State<SpreadsheetAnchoredButton> {
  final GlobalKey _anchor = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: _anchor,
      child: SpreadsheetToolbarButton(
        icon: widget.icon,
        tooltip: widget.tooltip,
        active: widget.active,
        onPressed: () {
          final box = _anchor.currentContext?.findRenderObject() as RenderBox?;
          if (box == null) {
            return;
          }
          // Right-aligned controls open menus flush with their right edge.
          final origin =
              box.localToGlobal(Offset(box.size.width, box.size.height + 6));
          widget.onOpen(origin);
        },
      ),
    );
  }
}

class SpreadsheetToolbarSeparator extends StatelessWidget {
  const SpreadsheetToolbarSeparator({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = SpreadsheetPalette.of(context);
    return Container(
      width: 1,
      height: 14,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: palette.gridLine,
    );
  }
}

/// The find and replace strip, shown under the block header on demand.
class SpreadsheetFindBar extends StatefulWidget {
  const SpreadsheetFindBar({
    super.key,
    required this.controller,
    required this.onClose,
    required this.editable,
  });

  final SpreadsheetController controller;
  final VoidCallback onClose;
  final bool editable;

  @override
  State<SpreadsheetFindBar> createState() => _SpreadsheetFindBarState();
}

class _SpreadsheetFindBarState extends State<SpreadsheetFindBar> {
  final TextEditingController _find = TextEditingController();
  final TextEditingController _replace = TextEditingController();
  final FocusNode _findFocus = FocusNode(debugLabel: 'spreadsheet-find');

  @override
  void initState() {
    super.initState();
    _find.text = widget.controller.searchQuery;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _findFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _find.dispose();
    _replace.dispose();
    _findFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = SpreadsheetPalette.of(context);
    final controller = widget.controller;
    final matches = controller.searchMatches.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(0, 6, 0, 8),
      child: Row(
        children: [
          Expanded(
            child: _FindField(
              controller: _find,
              focusNode: _findFocus,
              hint: LocaleKeys.spreadsheet_find_placeholder.tr(),
              palette: palette,
              onChanged: controller.setSearch,
              onSubmitted: (_) => controller.stepSearch(1),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            matches == 0
                ? LocaleKeys.spreadsheet_find_noResults.tr()
                : LocaleKeys.spreadsheet_find_results.tr(
                    args: ['${controller.searchMatchIndex + 1}', '$matches'],
                  ),
            style: TextStyle(fontSize: 11, color: palette.textMuted),
          ),
          const SizedBox(width: 6),
          SpreadsheetToolbarButton(
            icon: Icons.keyboard_arrow_up_rounded,
            tooltip: LocaleKeys.spreadsheet_toolbar_find.tr(),
            onPressed: matches == 0 ? null : () => controller.stepSearch(-1),
          ),
          SpreadsheetToolbarButton(
            icon: Icons.keyboard_arrow_down_rounded,
            tooltip: LocaleKeys.spreadsheet_toolbar_find.tr(),
            onPressed: matches == 0 ? null : () => controller.stepSearch(1),
          ),
          if (widget.editable) ...[
            const SpreadsheetToolbarSeparator(),
            SizedBox(
              width: 148,
              child: _FindField(
                controller: _replace,
                hint: LocaleKeys.spreadsheet_find_replacePlaceholder.tr(),
                palette: palette,
              ),
            ),
            const SizedBox(width: 6),
            SpreadsheetToolbarButton(
              icon: Icons.find_replace_rounded,
              tooltip: LocaleKeys.spreadsheet_find_replace.tr(),
              onPressed: matches == 0
                  ? null
                  : () => controller.replaceCurrent(_replace.text),
            ),
            SpreadsheetToolbarButton(
              icon: Icons.done_all_rounded,
              tooltip: LocaleKeys.spreadsheet_find_replaceAll.tr(),
              onPressed: matches == 0
                  ? null
                  : () => controller.replaceAll(_replace.text),
            ),
          ],
          const SizedBox(width: 2),
          SpreadsheetToolbarButton(
            icon: Icons.close_rounded,
            tooltip: LocaleKeys.spreadsheet_toolbar_find.tr(),
            onPressed: () {
              controller.setSearch('');
              widget.onClose();
            },
          ),
        ],
      ),
    );
  }
}

class _FindField extends StatelessWidget {
  const _FindField({
    required this.controller,
    required this.hint,
    required this.palette,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final SpreadsheetPalette palette;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: palette.floating,
        borderRadius: BorderRadius.circular(8),
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        style: TextStyle(fontSize: 12, color: palette.textPrimary),
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          filled: false,
          hoverColor: Colors.transparent,
          hintText: hint,
          hintStyle: TextStyle(fontSize: 12, color: palette.placeholder),
        ),
      ),
    );
  }
}

/// The strip under the grid: dimensions on the left, live aggregates on the
/// right. Appending a row is the grid's own last row, not a control here.
class SpreadsheetFooter extends StatelessWidget {
  const SpreadsheetFooter({super.key, required this.controller});

  final SpreadsheetController controller;

  @override
  Widget build(BuildContext context) {
    final palette = SpreadsheetPalette.of(context);
    final summary = controller.selectionSummary;
    final style = TextStyle(fontSize: 11, color: palette.textMuted);

    String number(double value) =>
        formatPlainNumber((value * 1000).roundToDouble() / 1000);

    return Container(
      height: SpreadsheetMetrics.footerHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Text(
            '${controller.data.rowCount} × ${controller.data.columnCount}',
            style: style,
          ),
          if (controller.data.filters.isNotEmpty) ...[
            const SizedBox(width: 8),
            Icon(Icons.filter_alt_rounded, size: 11, color: palette.accent),
          ],
          const Spacer(),
          if (summary.cellCount > 1)
            Text(
              LocaleKeys.spreadsheet_summaryCells.tr(
                args: ['${summary.cellCount}'],
              ),
              style: style,
            ),
          if (summary.hasNumbers) ...[
            const SizedBox(width: 16),
            Text(
              LocaleKeys.spreadsheet_summarySum.tr(args: [number(summary.sum)]),
              style: style,
            ),
            const SizedBox(width: 16),
            Text(
              LocaleKeys.spreadsheet_summaryAverage.tr(
                args: [number(summary.average ?? 0)],
              ),
              style: style,
            ),
            if (summary.minimum != null) ...[
              const SizedBox(width: 16),
              Text(
                LocaleKeys.spreadsheet_summaryMin.tr(
                  args: [number(summary.minimum!)],
                ),
                style: style,
              ),
            ],
            if (summary.maximum != null) ...[
              const SizedBox(width: 16),
              Text(
                LocaleKeys.spreadsheet_summaryMax.tr(
                  args: [number(summary.maximum!)],
                ),
                style: style,
              ),
            ],
          ],
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}
