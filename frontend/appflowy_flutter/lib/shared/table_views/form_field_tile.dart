import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/shared/encryption/sensitive_clipboard.dart';
import 'package:appflowy/shared/table_views/table_view_style.dart';
import 'package:appflowy/workspace/application/table_views/form_entry_service.dart';
import 'package:appflowy/workspace/application/table_views/table_row.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// A value is absent from the widget/semantics tree while concealed, not merely
/// painted under dots. Reading and writing are supplied by the form's host.
class FormFieldTile extends StatefulWidget {
  const FormFieldTile({
    super.key,
    required this.field,
    required this.value,
    required this.onRead,
    this.masked = false,
    this.encrypted = false,
    this.description = '',
    this.onSave,
    this.onOpenEditor,
    this.onEditingChanged,
    this.menu,
  });

  final FieldPB field;
  final String value;
  final Future<String?> Function() onRead;
  final bool masked;
  final bool encrypted;
  final String description;
  final Future<void> Function(String)? onSave;
  final VoidCallback? onOpenEditor;
  final ValueChanged<bool>? onEditingChanged;
  final Widget? menu;

  @override
  State<FormFieldTile> createState() => _FormFieldTileState();
}

class _FormFieldTileState extends State<FormFieldTile> {
  final _draft = TextEditingController();
  bool _editing = false;
  bool _revealed = false;
  bool _busy = false;
  bool _copied = false;
  bool _conflict = false;
  String? _opened;
  String? _error;
  int _revision = 0;

  bool get _sensitive => widget.masked || widget.encrypted;

  @override
  void didUpdateWidget(FormFieldTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value ||
        oldWidget.masked != widget.masked ||
        oldWidget.encrypted != widget.encrypted) {
      _revision++;
      _revealed = false;
      _opened = null;
      _copied = false;
      if (_editing) {
        _conflict = true;
        _error = LocaleKeys.form_fieldChanged.tr();
      }
    }
    if (widget.onSave == null && _editing) _conceal();
  }

  @override
  void dispose() {
    if (_editing) widget.onEditingChanged?.call(false);
    _draft.clear();
    _draft.dispose();
    super.dispose();
  }

  void _conceal() {
    if (_editing) widget.onEditingChanged?.call(false);
    _revision++;
    _editing = false;
    _revealed = false;
    _opened = null;
    _error = null;
    _conflict = false;
    _draft.clear();
  }

  Future<void> _read(String action) async {
    if (_busy) return;
    final revision = _revision;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final value = await widget.onRead();
      if (!mounted || revision != _revision || value == null) return;
      if (action == 'edit' && widget.onSave == null) return;
      switch (action) {
        case 'copy':
          await SensitiveClipboard.instance.copy(value, sensitive: _sensitive);
          if (mounted && revision == _revision) setState(() => _copied = true);
        case 'edit':
          setState(() {
            _draft.text = value;
            _editing = true;
            _conflict = false;
          });
          widget.onEditingChanged?.call(true);
        default:
          setState(() {
            _opened = value;
            _revealed = true;
          });
      }
    } on Object {
      if (mounted) setState(() => _error = LocaleKeys.form_readFailed.tr());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final save = widget.onSave;
    if (_busy || _conflict || save == null) return;
    setState(() => _busy = true);
    try {
      await save(_draft.text);
      if (mounted) setState(_conceal);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = error is FormEntryException && error.code == 'invalidNumber'
              ? LocaleKeys.form_invalidNumber.tr()
              : LocaleKeys.form_saveFailed.tr();
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = tableViewPaletteOf(context);
    final field = widget.field;
    final concealed = _sensitive && !_revealed;
    return Container(
      key: ValueKey('form-field-${field.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 10, 10, 14),
      decoration: BoxDecoration(
        color: palette.raised,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  field.name,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: palette.textSecondary,
                      ),
                ),
              ),
              if (_sensitive)
                FormIconAction(
                  actionKey: 'form-reveal-${field.id}',
                  label: concealed
                      ? LocaleKeys.form_showValue.tr()
                      : LocaleKeys.form_hideValue.tr(),
                  icon: concealed
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                  onPressed: _busy || _editing
                      ? null
                      : () => concealed
                          ? unawaited(_read('reveal'))
                          : setState(_conceal),
                ),
              FormIconAction(
                actionKey: 'form-copy-${field.id}',
                label: _copied
                    ? (_sensitive
                        ? LocaleKeys.form_sensitiveCopied.tr()
                        : LocaleKeys.form_copied.tr())
                    : LocaleKeys.form_copyField.tr(args: [field.name]),
                icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
                onPressed: _busy || _editing || widget.value.isEmpty
                    ? null
                    : () => unawaited(_read('copy')),
              ),
              if (widget.onSave != null || widget.onOpenEditor != null)
                FormIconAction(
                  actionKey: 'form-edit-${field.id}',
                  label: LocaleKeys.form_editValue.tr(),
                  icon: Icons.edit_rounded,
                  onPressed: _busy || _editing
                      ? null
                      : widget.onSave != null
                          ? () => unawaited(_read('edit'))
                          : widget.onOpenEditor,
                ),
              if (widget.menu != null) widget.menu!,
            ],
          ),
          if (widget.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                widget.description,
                style: TextStyle(fontSize: 12, color: palette.textMuted),
              ),
            ),
          if (_editing) ...[
            _editor(palette),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  key: ValueKey('form-save-${field.id}'),
                  onPressed:
                      _busy || _conflict ? null : () => unawaited(_save()),
                  child: Text(LocaleKeys.form_save.tr()),
                ),
                TextButton(
                  key: ValueKey('form-cancel-${field.id}'),
                  onPressed: _busy ? null : () => setState(_conceal),
                  child: Text(LocaleKeys.button_cancel.tr()),
                ),
              ],
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 6),
              child: Text(
                concealed
                    ? '••••••••'
                    : (_opened ?? widget.value).isEmpty
                        ? LocaleKeys.form_emptyValue.tr()
                        : _opened ?? widget.value,
                key: ValueKey('form-value-${field.id}'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: palette.textPrimary,
                      height: 1.5,
                    ),
              ),
            ),
          if (_sensitive) ...[
            const SizedBox(height: 7),
            Text(
              widget.encrypted
                  ? LocaleKeys.form_encryptedValue.tr()
                  : LocaleKeys.form_hiddenValue.tr(),
              style: TextStyle(fontSize: 11, color: palette.textSecondary),
            ),
          ],
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (_copied && _sensitive)
            Text(
              LocaleKeys.form_sensitiveCopied.tr(),
              style: TextStyle(fontSize: 11, color: palette.textMuted),
            ),
        ],
      ),
    );
  }

  Widget _editor(TableViewPalette palette) {
    final field = widget.field;
    if (field.fieldType == FieldType.Checkbox) {
      final checked =
          const ['yes', 'true', '1'].contains(_draft.text.trim().toLowerCase());
      return CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(checked ? 'Yes' : 'No'),
        value: checked,
        onChanged: _busy
            ? null
            : (value) => setState(() => _draft.text = value! ? 'Yes' : 'No'),
      );
    }
    if (field.fieldType == FieldType.SingleSelect ||
        field.fieldType == FieldType.MultiSelect) {
      final options = formChoiceNames(field);
      final multiple = field.fieldType == FieldType.MultiSelect;
      final selected = multiple ? tablePartsOf(_draft.text) : [_draft.text];
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final option in options)
            FilterChip(
              label: Text(option),
              selected: selected.contains(option),
              onSelected: _busy
                  ? null
                  : (chosen) => setState(() {
                        _draft.text = multiple
                            ? (([...selected]..remove(option))
                                  ..addAll(chosen ? [option] : []))
                                .join(', ')
                            : chosen
                                ? option
                                : '';
                      }),
            ),
        ],
      );
    }
    return TextEntryShortcuts(
      child: TextField(
        key: ValueKey('form-input-${field.id}'),
        controller: _draft,
        autofocus: true,
        readOnly: _busy,
        obscureText: _sensitive,
        autocorrect: false,
        enableSuggestions: false,
        maxLines: _sensitive || field.fieldType != FieldType.RichText ? 1 : 5,
        minLines: 1,
        style: TextStyle(color: palette.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          isDense: true,
          filled: false,
          border: InputBorder.none,
          hintText: LocaleKeys.form_emptyValue.tr(),
        ),
        onSubmitted: (_) => unawaited(_save()),
      ),
    );
  }
}

List<String> formChoiceNames(FieldPB field) {
  try {
    return SingleSelectTypeOptionPB.fromBuffer(field.typeOptionData)
        .options
        .map((option) => option.name)
        .toList();
  } on Object {
    return const [];
  }
}

/// Compact, keyboard-accessible controls that keep their hit target visible.
class FormIconAction extends StatelessWidget {
  const FormIconAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.actionKey,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final String? actionKey;

  @override
  Widget build(BuildContext context) => IconButton(
        key: actionKey == null ? null : ValueKey(actionKey!),
        tooltip: label,
        onPressed: onPressed,
        icon: Icon(icon, size: 17),
        style: IconButton.styleFrom(
          foregroundColor: tableViewPaletteOf(context).textSecondary,
          minimumSize: const Size(34, 34),
          padding: const EdgeInsets.all(7),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
}
