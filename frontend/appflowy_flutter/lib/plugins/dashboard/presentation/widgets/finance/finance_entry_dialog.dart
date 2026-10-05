import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/finance/finance_kit.dart';
import 'package:appflowy/shared/market/market_data.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

enum FinanceFieldKind { text, number, date, choice, symbol, multiline }

/// One thing a quick-add form asks for.
@immutable
class FinanceEntryField {
  const FinanceEntryField({
    required this.key,
    required this.label,
    this.kind = FinanceFieldKind.text,
    this.options = const [],
    this.hint = '',
    this.initial = '',
    this.required = false,
    this.wide = false,
    this.fills = '',
  });

  /// What the answer is filed under when the form is saved.
  final String key;
  final String label;
  final FinanceFieldKind kind;

  /// The choices a choice field offers.
  final List<String> options;
  final String hint;
  final String initial;
  final bool required;

  /// Takes the whole row rather than half of it.
  final bool wide;

  /// For a symbol field: the key of a field a picked listing's name is
  /// written into, when that field is still empty.
  final String fills;
}

/// Asks for a new row and saves it with [onSave], which says whether the
/// save worked. The dialog stays open with a message when it did not.
Future<void> showFinanceEntryDialog({
  required BuildContext context,
  required DashboardPalette palette,
  required String title,
  required IconData icon,
  required Color color,
  required List<FinanceEntryField> fields,
  required Future<bool> Function(Map<String, String> values) onSave,
}) =>
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: palette.isDark ? 0.5 : 0.28),
      builder: (_) => _FinanceEntryDialog(
        palette: palette,
        title: title,
        icon: icon,
        color: color,
        fields: fields,
        onSave: onSave,
      ),
    );

class _FinanceEntryDialog extends StatefulWidget {
  const _FinanceEntryDialog({
    required this.palette,
    required this.title,
    required this.icon,
    required this.color,
    required this.fields,
    required this.onSave,
  });

  final DashboardPalette palette;
  final String title;
  final IconData icon;
  final Color color;
  final List<FinanceEntryField> fields;
  final Future<bool> Function(Map<String, String> values) onSave;

  @override
  State<_FinanceEntryDialog> createState() => _FinanceEntryDialogState();
}

class _FinanceEntryDialogState extends State<_FinanceEntryDialog> {
  late final Map<String, TextEditingController> _controllers = {
    for (final field in widget.fields)
      field.key: TextEditingController(text: field.initial),
  };
  final Set<String> _missing = {};
  bool _saving = false;
  bool _failed = false;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    final missing = {
      for (final field in widget.fields)
        if (field.required && _controllers[field.key]!.text.trim().isEmpty)
          field.key,
    };
    setState(() {
      _missing
        ..clear()
        ..addAll(missing);
      _failed = false;
    });
    if (missing.isNotEmpty) {
      return;
    }
    setState(() => _saving = true);
    var saved = false;
    try {
      saved = await widget.onSave({
        for (final entry in _controllers.entries)
          entry.key: entry.value.text.trim(),
      });
    } on Object {
      saved = false;
    }
    if (!mounted) {
      return;
    }
    if (saved) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final colors = FinanceColors.of(palette);
    return Dialog(
      backgroundColor: palette.raised,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: palette.border.withValues(alpha: 0.5)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: TextEntryShortcuts(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    FinanceIconTile(
                      icon: widget.icon,
                      color: widget.color,
                      colors: colors,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: DashboardType.title(palette, size: 18),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Flexible(
                  child: SingleChildScrollView(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final half = (constraints.maxWidth - 12) / 2;
                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (final field in widget.fields)
                              SizedBox(
                                width: field.wide ||
                                        field.kind ==
                                            FinanceFieldKind.multiline ||
                                        field.kind == FinanceFieldKind.symbol
                                    ? constraints.maxWidth
                                    : half,
                                child: _EntryField(
                                  field: field,
                                  controller: _controllers[field.key]!,
                                  palette: palette,
                                  missing: _missing.contains(field.key),
                                  onSubmitted: () => unawaited(_save()),
                                  onPicked: (match) {
                                    final target = _controllers[field.fills];
                                    if (target != null &&
                                        target.text.trim().isEmpty) {
                                      target.text = match.name;
                                    }
                                  },
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: AnimatedOpacity(
                        opacity: _failed ? 1 : 0,
                        duration: DashboardMetrics.hover,
                        child: Text(
                          LocaleKeys.dashboard_money_saveFailed.tr(),
                          style: financeLabel(colors.loss, size: 12),
                        ),
                      ),
                    ),
                    DashboardButton(
                      label: LocaleKeys.dashboard_money_cancel.tr(),
                      palette: palette,
                      onPressed:
                          _saving ? null : () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    DashboardButton(
                      label: _saving
                          ? LocaleKeys.dashboard_money_saving.tr()
                          : LocaleKeys.dashboard_money_add.tr(),
                      palette: palette,
                      icon: Icons.add_rounded,
                      primary: true,
                      onPressed: _saving ? null : () => unawaited(_save()),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EntryField extends StatefulWidget {
  const _EntryField({
    required this.field,
    required this.controller,
    required this.palette,
    required this.missing,
    required this.onSubmitted,
    required this.onPicked,
  });

  final FinanceEntryField field;
  final TextEditingController controller;
  final DashboardPalette palette;
  final bool missing;
  final VoidCallback onSubmitted;
  final ValueChanged<MarketSymbol> onPicked;

  @override
  State<_EntryField> createState() => _EntryFieldState();
}

class _EntryFieldState extends State<_EntryField> {
  Timer? _debounce;
  List<MarketSymbol> _matches = const [];
  int _generation = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _search(String text) {
    if (widget.field.kind != FinanceFieldKind.symbol) {
      return;
    }
    _debounce?.cancel();
    final provider = MarketData.provider;
    if (provider == null || text.trim().length < 2) {
      if (_matches.isNotEmpty) {
        setState(() => _matches = const []);
      }
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 260), () async {
      final generation = ++_generation;
      final matches = await provider.search(text.trim());
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() => _matches = matches.take(6).toList());
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final field = widget.field;
    final colors = FinanceColors.of(palette);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(
        color: widget.missing
            ? colors.loss.withValues(alpha: 0.7)
            : palette.border.withValues(alpha: 0.7),
      ),
    );
    final input = TextField(
      controller: widget.controller,
      minLines: field.kind == FinanceFieldKind.multiline ? 3 : 1,
      maxLines: field.kind == FinanceFieldKind.multiline ? 6 : 1,
      keyboardType: field.kind == FinanceFieldKind.number
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : null,
      textInputAction: field.kind == FinanceFieldKind.multiline
          ? TextInputAction.newline
          : TextInputAction.done,
      onChanged: _search,
      onSubmitted: (_) {
        if (field.kind != FinanceFieldKind.multiline) {
          widget.onSubmitted();
        }
      },
      style: DashboardType.body(palette),
      cursorColor: palette.accent,
      decoration: InputDecoration(
        isDense: true,
        hintText: field.hint.isEmpty ? null : field.hint,
        hintStyle: DashboardType.body(palette, color: palette.textMuted),
        filled: true,
        fillColor: palette.isDark
            ? Colors.white.withValues(alpha: 0.04)
            : palette.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: palette.accent, width: 1.4),
        ),
        suffixIcon: field.kind == FinanceFieldKind.date
            ? IconButton(
                icon: Icon(
                  Icons.calendar_today_rounded,
                  size: 16,
                  color: palette.textSecondary,
                ),
                onPressed: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate:
                        DateTime.tryParse(widget.controller.text) ?? now,
                    firstDate: DateTime(1950),
                    lastDate: DateTime(now.year + 30),
                  );
                  if (picked != null) {
                    widget.controller.text =
                        DateFormat('yyyy-MM-dd').format(picked);
                  }
                },
              )
            : null,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                field.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: financeLabel(palette.textSecondary, size: 12),
              ),
            ),
            if (field.required)
              Text(
                ' *',
                style: financeLabel(
                  widget.missing ? colors.loss : palette.textMuted,
                  size: 12,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        input,
        if (field.kind == FinanceFieldKind.choice && field.options.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: widget.controller,
              builder: (context, value, _) => Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final option in field.options)
                    _OptionChip(
                      label: option,
                      selected: value.text.trim().toLowerCase() ==
                          option.toLowerCase(),
                      palette: palette,
                      onTap: () => widget.controller.text = option,
                    ),
                ],
              ),
            ),
          ),
        if (_matches.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: palette.border.withValues(alpha: 0.6)),
            ),
            child: Column(
              children: [
                for (final match in _matches)
                  FinanceHover(
                    onTap: () {
                      widget.controller.text = match.symbol;
                      widget.onPicked(match);
                      setState(() => _matches = const []);
                    },
                    builder: (context, hovered) => AnimatedContainer(
                      duration: DashboardMetrics.hover,
                      color: hovered ? palette.hover : palette.hoverBase,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          FinanceAvatar(
                            label: match.symbol,
                            colors: colors,
                            size: 26,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  match.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: DashboardType.body(palette),
                                ),
                                Text(
                                  [match.symbol, match.where]
                                      .where((part) => part.isNotEmpty)
                                      .join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: DashboardType.caption(palette),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.label,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final DashboardPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FinanceHover(
        onTap: onTap,
        builder: (context, hovered) => AnimatedContainer(
          duration: DashboardMetrics.hover,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: selected
                ? palette.accentSoft
                : (hovered ? palette.hover : palette.sunken),
            borderRadius: BorderRadius.circular(DashboardMetrics.pillRadius),
            border: Border.all(
              color: palette.accent.withValues(alpha: selected ? 0.5 : 0),
            ),
          ),
          child: Text(
            label,
            style: financeLabel(
              selected ? palette.accent : palette.textSecondary,
              weight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      );
}
