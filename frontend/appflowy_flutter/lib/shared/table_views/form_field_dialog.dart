import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/shared/table_views/table_view_style.dart';
import 'package:appflowy/workspace/application/table_views/form_spec.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

Future<FormCustomField?> showFormFieldDialog(
  BuildContext context, {
  FormCustomField? initial,
}) =>
    showDialog<FormCustomField>(
      context: context,
      builder: (_) => _FormFieldDialog(initial: initial),
    );

class _FormFieldDialog extends StatefulWidget {
  const _FormFieldDialog({this.initial});

  final FormCustomField? initial;

  @override
  State<_FormFieldDialog> createState() => _FormFieldDialogState();
}

class _FormFieldDialogState extends State<_FormFieldDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name);
  late final _description =
      TextEditingController(text: widget.initial?.description);
  FormCustomFieldKind _kind = FormCustomFieldKind.text;
  late bool _required = widget.initial?.required ?? false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    Navigator.of(context).pop(
      FormCustomField(
        name: _name.text.trim(),
        description: _description.text.trim(),
        kind: _kind,
        required: _required,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = tableViewPaletteOf(context);
    return AlertDialog(
      backgroundColor: palette.surface,
      scrollable: true,
      title: Text(
        widget.initial == null
            ? LocaleKeys.form_addField.tr()
            : LocaleKeys.form_editField.tr(),
      ),
      content: SizedBox(
        width: 400,
        child: TextEntryShortcuts(
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  LocaleKeys.form_fieldScope.tr(),
                  style: TextStyle(fontSize: 12, color: palette.textMuted),
                ),
                const SizedBox(height: 18),
                TextFormField(
                  key: const ValueKey('form-custom-name'),
                  controller: _name,
                  autofocus: true,
                  maxLength: 128,
                  decoration: InputDecoration(
                    labelText: LocaleKeys.form_fieldName.tr(),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? LocaleKeys.form_requiredMissing.tr()
                      : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
                if (widget.initial == null) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<FormCustomFieldKind>(
                    key: const ValueKey('form-custom-type'),
                    value: _kind,
                    isExpanded: true,
                    dropdownColor: palette.surface,
                    decoration: InputDecoration(
                      labelText: LocaleKeys.form_fieldType.tr(),
                    ),
                    items: [
                      for (final kind in FormCustomFieldKind.values)
                        DropdownMenuItem(
                          value: kind,
                          child: Text(_label(kind)),
                        ),
                    ],
                    onChanged: (kind) => setState(() => _kind = kind!),
                  ),
                  if (_kind.masked)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        _kind == FormCustomFieldKind.encrypted
                            ? LocaleKeys.form_encryptionNotice.tr()
                            : LocaleKeys.form_maskHint.tr(),
                        style:
                            TextStyle(fontSize: 12, color: palette.textMuted),
                      ),
                    ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('form-custom-description'),
                  controller: _description,
                  maxLines: 3,
                  maxLength: 1000,
                  decoration: InputDecoration(
                    labelText: LocaleKeys.form_fieldDescription.tr(),
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(LocaleKeys.form_required.tr()),
                  value: _required,
                  onChanged: (value) => setState(() => _required = value!),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(LocaleKeys.button_cancel.tr()),
        ),
        TextButton(
          key: const ValueKey('form-custom-save'),
          onPressed: _submit,
          child: Text(LocaleKeys.form_save.tr()),
        ),
      ],
    );
  }

  String _label(FormCustomFieldKind kind) => switch (kind) {
        FormCustomFieldKind.text => LocaleKeys.form_textType.tr(),
        FormCustomFieldKind.hidden => LocaleKeys.form_hiddenType.tr(),
        FormCustomFieldKind.encrypted => LocaleKeys.form_encryptedType.tr(),
        FormCustomFieldKind.number => LocaleKeys.form_numberType.tr(),
        FormCustomFieldKind.link => LocaleKeys.form_urlType.tr(),
        FormCustomFieldKind.boolean => LocaleKeys.form_booleanType.tr(),
        FormCustomFieldKind.location => LocaleKeys.form_locationType.tr(),
        FormCustomFieldKind.date => LocaleKeys.form_dateType.tr(),
        FormCustomFieldKind.time => LocaleKeys.form_timeType.tr(),
        FormCustomFieldKind.files => LocaleKeys.form_filesType.tr(),
        FormCustomFieldKind.checklist => LocaleKeys.form_checklistType.tr(),
        FormCustomFieldKind.button => LocaleKeys.form_buttonType.tr(),
        FormCustomFieldKind.counter => LocaleKeys.form_counterType.tr(),
        FormCustomFieldKind.progress => LocaleKeys.form_progressType.tr(),
      };
}
