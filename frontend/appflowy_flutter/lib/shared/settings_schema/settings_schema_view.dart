import 'package:appflowy/shared/settings_schema/settings_schema.dart';
import 'package:flutter/material.dart';

/// Draws a list of [SettingsField]s.
///
/// One implementation, so every declared setting looks the same wherever it is
/// shown — a block's own panel, an extension's page, a dialog.
class SettingsSchemaView extends StatelessWidget {
  const SettingsSchemaView({
    super.key,
    required this.fields,
    this.padding = EdgeInsets.zero,
  });

  final List<SettingsField> fields;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final field in fields) _SettingsRow(field: field),
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.field});

  final SettingsField field;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget labelled(Widget control, {bool inline = false}) {
      final label = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(field.label, style: theme.textTheme.bodyMedium),
          if (field.hint.isNotEmpty)
            Text(
              field.hint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      );

      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: inline
            ? Row(
                children: [
                  Expanded(child: label),
                  const SizedBox(width: 12),
                  control,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [label, const SizedBox(height: 6), control],
              ),
      );
    }

    switch (field) {
      case final SettingsGroupField group:
        return Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                group.label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              for (final child in group.fields) _SettingsRow(field: child),
            ],
          ),
        );

      case final SettingsNoteField note:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                note.warning
                    ? Icons.warning_amber_rounded
                    : Icons.info_outline_rounded,
                size: 15,
                color: note.warning
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  note.label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: note.warning
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        );

      case final SettingsTextField text:
        return labelled(
          _SettingsTextBox(
            key: ValueKey('${text.label}-${text.multiline}'),
            field: text,
          ),
        );

      case final SettingsNumberField number:
        return labelled(
          _SettingsNumberBox(key: ValueKey(number.label), field: number),
          inline: true,
        );

      case final SettingsToggleField toggle:
        return labelled(
          Switch(value: toggle.value, onChanged: toggle.onChanged),
          inline: true,
        );

      case final SettingsChoiceField choice:
        final known =
            choice.choices.any((option) => option.value == choice.value);
        return labelled(
          DropdownButton<String>(
            value: known ? choice.value : choice.choices.firstOrNull?.value,
            underline: const SizedBox.shrink(),
            isDense: true,
            items: [
              for (final option in choice.choices)
                DropdownMenuItem(
                  value: option.value,
                  child: Text(option.label),
                ),
            ],
            onChanged: (value) {
              if (value != null) {
                choice.onChanged(value);
              }
            },
          ),
          inline: true,
        );

      case final SettingsButtonField button:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: button.onPressed,
              icon: Icon(button.icon ?? Icons.play_arrow_rounded, size: 16),
              label: Text(button.label),
              style: TextButton.styleFrom(
                // ⚠️ An accent wash with accent text, never a saturated filled
                // block — a tonal button takes its container from the theme and
                // can render its own label invisible.
                foregroundColor: button.destructive
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
                backgroundColor: (button.destructive
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary)
                    .withValues(alpha: 0.12),
              ),
            ),
          ),
        );

      default:
        // A field type this renderer does not know — the dashboard's own rows,
        // or one an extension added. Its own panel draws it.
        return const SizedBox.shrink();
    }
  }
}

/// ⚠️ Owns its controller. A field whose controller is created in `build`
/// loses the caret on every keystroke.
class _SettingsTextBox extends StatefulWidget {
  const _SettingsTextBox({super.key, required this.field});

  final SettingsTextField field;

  @override
  State<_SettingsTextBox> createState() => _SettingsTextBoxState();
}

class _SettingsTextBoxState extends State<_SettingsTextBox> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.field.value);

  @override
  void didUpdateWidget(_SettingsTextBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Adopt a value changed elsewhere, but never while it is being typed.
    if (widget.field.value != _controller.text && !_focus.hasFocus) {
      _controller.text = widget.field.value;
    }
  }

  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focus,
      maxLines: widget.field.multiline ? 4 : 1,
      decoration: InputDecoration(
        isDense: true,
        border: const OutlineInputBorder(),
        hintText: widget.field.placeholder,
      ),
      onChanged: widget.field.onChanged,
    );
  }
}

class _SettingsNumberBox extends StatefulWidget {
  const _SettingsNumberBox({super.key, required this.field});

  final SettingsNumberField field;

  @override
  State<_SettingsNumberBox> createState() => _SettingsNumberBoxState();
}

class _SettingsNumberBoxState extends State<_SettingsNumberBox> {
  late final TextEditingController _controller =
      TextEditingController(text: _format(widget.field.value));
  final FocusNode _focus = FocusNode();

  static String _format(double value) =>
      value == value.roundToDouble() ? '${value.round()}' : '$value';

  @override
  void didUpdateWidget(_SettingsNumberBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && _format(widget.field.value) != _controller.text) {
      _controller.text = _format(widget.field.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit(String raw) {
    final parsed = double.tryParse(raw.trim());
    if (parsed == null) {
      return;
    }
    final field = widget.field;
    final clamped = parsed
        .clamp(field.minimum ?? double.negativeInfinity,
            field.maximum ?? double.infinity)
        .toDouble();
    field.onChanged(clamped);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          isDense: true,
          border: const OutlineInputBorder(),
          suffixText: widget.field.suffix.isEmpty ? null : widget.field.suffix,
        ),
        onChanged: _commit,
      ),
    );
  }
}
