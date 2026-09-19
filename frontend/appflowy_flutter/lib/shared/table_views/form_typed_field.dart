import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/application/field/property_style.dart';
import 'package:appflowy/shared/encryption/encryption.dart';
import 'package:appflowy/shared/encryption/sensitive_clipboard.dart';
import 'package:appflowy/shared/table_views/form_field_input.dart';
import 'package:appflowy/shared/table_views/form_field_tile.dart';
import 'package:appflowy/shared/table_views/table_view_style.dart';
import 'package:appflowy/workspace/application/table_views/form_entry_service.dart';
import 'package:appflowy/workspace/application/table_views/form_field_value.dart';
import 'package:appflowy/workspace/application/table_views/form_spec.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// The field's native input stays visible; changes are a cancellable draft.
/// A failed read never turns an existing structured value into an empty one.
class FormTypedField extends StatefulWidget {
  const FormTypedField({
    super.key,
    required this.field,
    required this.control,
    required this.read,
    required this.revision,
    required this.backend,
    this.save,
    this.style,
    this.menu,
    this.description = '',
    this.onEditingChanged,
    this.onOpenRow,
    this.services = const FormInputServices(),
    this.busy = false,
  });

  final FieldPB field;
  final FormControl control;
  final Future<FormFieldValue> Function() read;
  final Future<void> Function(FormFieldValue, FormFieldValue)? save;
  final int revision;
  final FormEntryBackend backend;
  final PropertyStyle? style;
  final Widget? menu;
  final String description;
  final ValueChanged<bool>? onEditingChanged;
  final VoidCallback? onOpenRow;
  final FormInputServices services;
  final bool busy;

  @override
  State<FormTypedField> createState() => _FormTypedFieldState();
}

class _FormTypedFieldState extends State<FormTypedField> {
  FormFieldValue? _stored;
  FormFieldValue? _draft;
  bool _dirty = false;
  bool _saving = false;
  bool _conflict = false;
  bool _copied = false;
  String? _error;
  int _generation = 0;
  int _inputGeneration = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(FormTypedField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision && !_saving) unawaited(_load());
    if (widget.save == null && _dirty) _cancel();
  }

  @override
  void dispose() {
    if (_dirty) widget.onEditingChanged?.call(false);
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    try {
      final value = await widget.read();
      if (!mounted || generation != _generation) return;
      if (value is FormTextValue && looksSealed(value.text)) {
        throw const FormEntryException('fieldChanged');
      }
      setState(() {
        if (_dirty) {
          _conflict = _stored?.fingerprint != value.fingerprint;
          if (_conflict) _error = LocaleKeys.form_fieldChanged.tr();
        } else {
          if (_stored?.fingerprint != value.fingerprint) _inputGeneration++;
          _stored = _draft = value;
          _error = null;
        }
      });
    } on Object {
      if (mounted && generation == _generation) {
        setState(() {
          _error = LocaleKeys.form_readValueFailed.tr();
          _conflict = _dirty;
        });
      }
    }
  }

  void _change(FormFieldValue value) {
    if (widget.save == null || widget.busy || _saving || _stored == null) {
      return;
    }
    setState(() {
      _draft = value;
      _dirty = value.fingerprint != _stored!.fingerprint;
      _copied = false;
    });
    widget.onEditingChanged?.call(_dirty);
  }

  void _cancel() {
    _draft = _stored;
    _dirty = false;
    _conflict = false;
    _error = null;
    _inputGeneration++;
    widget.onEditingChanged?.call(false);
  }

  Future<void> _save() async {
    if (_saving || widget.busy || _conflict || widget.save == null) return;
    setState(() => _saving = true);
    try {
      await widget.save!(_draft!, _stored!);
      if (!mounted) return;
      setState(_cancel);
      await _load();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = error is FormEntryException && error.code == 'fieldChanged'
              ? LocaleKeys.form_fieldChanged.tr()
              : LocaleKeys.form_saveFailed.tr();
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _copy() async {
    try {
      await SensitiveClipboard.instance.copy(_stored!.text, sensitive: false);
      if (mounted) setState(() => _copied = true);
    } on Object {
      if (mounted) setState(() => _error = LocaleKeys.form_readFailed.tr());
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = tableViewPaletteOf(context);
    return Container(
      key: ValueKey('form-field-${widget.field.id}'),
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
                  widget.field.name,
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: palette.textSecondary),
                ),
              ),
              FormIconAction(
                actionKey: 'form-copy-${widget.field.id}',
                label: _copied
                    ? LocaleKeys.form_copied.tr()
                    : LocaleKeys.form_copyField.tr(args: [widget.field.name]),
                icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
                onPressed:
                    _stored == null || _stored!.isEmpty || _dirty || _saving
                        ? null
                        : () => unawaited(_copy()),
              ),
              if (widget.menu != null) widget.menu!,
            ],
          ),
          if (widget.description.isNotEmpty)
            Text(
              widget.description,
              style: TextStyle(color: palette.textMuted, fontSize: 12),
            ),
          if (_draft != null)
            FormFieldInput(
              key: ValueKey(
                'form-typed-input-${widget.field.id}-$_inputGeneration',
              ),
              field: widget.field,
              control: widget.control,
              value: _draft!,
              style: widget.style,
              onChanged: _change,
              enabled:
                  widget.save != null && !widget.busy && !_saving && !_conflict,
              onOpenRow: widget.onOpenRow,
              services: widget.services,
              backend: widget.backend,
            )
          else if (_error == null)
            Text(LocaleKeys.tableViews_loading.tr()),
          if (_error != null) ...[
            Text(
              _error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
              ),
            ),
            if (!_dirty)
              TextButton(
                onPressed: () => unawaited(_load()),
                child: Text(LocaleKeys.tableViews_tryAgain.tr()),
              ),
          ],
          if (_dirty)
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  key: ValueKey('form-save-${widget.field.id}'),
                  onPressed: _saving || widget.busy || _conflict
                      ? null
                      : () => unawaited(_save()),
                  child: Text(
                    _saving
                        ? LocaleKeys.form_saving.tr()
                        : LocaleKeys.form_save.tr(),
                  ),
                ),
                TextButton(
                  key: ValueKey('form-cancel-${widget.field.id}'),
                  onPressed: _saving || widget.busy
                      ? null
                      : () {
                          setState(_cancel);
                          unawaited(_load());
                        },
                  child: Text(LocaleKeys.button_cancel.tr()),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
