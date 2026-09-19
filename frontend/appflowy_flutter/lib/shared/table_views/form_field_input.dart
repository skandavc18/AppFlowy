import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/plugins/database/application/field/property_style.dart';
import 'package:appflowy/plugins/database/widgets/cell/desktop_grid/location_picker_card.dart';
import 'package:appflowy/plugins/database/widgets/cell/property_style_cell.dart';
import 'package:appflowy/shared/maps/map_style.dart';
import 'package:appflowy/shared/maps/map_suggestions.dart';
import 'package:appflowy/shared/table_views/form_field_tile.dart';
import 'package:appflowy/shared/table_views/table_view_style.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/util/time.dart';
import 'package:appflowy/util/xfile_ext.dart';
import 'package:appflowy/workspace/application/table_views/form_entry_service.dart';
import 'package:appflowy/workspace/application/table_views/form_field_value.dart';
import 'package:appflowy/workspace/application/table_views/form_spec.dart';
import 'package:appflowy/workspace/presentation/widgets/date_picker/desktop_date_picker.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:cross_file/cross_file.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/file_picker/file_picker_service.dart' as picker;
import 'package:flowy_infra/uuid.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

/// Tests never open an OS dialog. File selection itself does not upload.
class FormInputServices {
  const FormInputServices();

  Future<List<XFile>> pickFiles(List<String>? extensions) async {
    final picked = await getIt<picker.FilePickerService>().pickFiles(
      dialogTitle: LocaleKeys.form_chooseFiles.tr(),
      allowMultiple: true,
      type: extensions == null ? picker.FileType.any : picker.FileType.custom,
      allowedExtensions: extensions,
    );
    return picked?.files.map((file) => file.xFile).toList() ?? const [];
  }
}

bool usesTypedFormInput(FieldPB field, FormControl control) =>
    const [
      FieldType.DateTime,
      FieldType.Time,
      FieldType.Media,
      FieldType.Checklist,
      FieldType.Relation,
      FieldType.Checkbox,
      FieldType.SingleSelect,
      FieldType.MultiSelect,
    ].contains(field.fieldType) ||
    const [
      FormControl.place,
      FormControl.progress,
      FormControl.counter,
      FormControl.button,
      FormControl.reminder,
      FormControl.rating,
    ].contains(control);

/// Native controls edit a draft. No backend writes happen during build, focus,
/// picker cancellation or file selection; the host decides when to save it.
class FormFieldInput extends StatefulWidget {
  const FormFieldInput({
    super.key,
    required this.field,
    required this.control,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.style,
    this.onOpenRow,
    this.backend = const FormEntryBackend(),
    this.services = const FormInputServices(),
  });

  final FieldPB field;
  final FormControl control;
  final FormFieldValue value;
  final ValueChanged<FormFieldValue> onChanged;
  final bool enabled;
  final PropertyStyle? style;
  final VoidCallback? onOpenRow;
  final FormEntryBackend backend;
  final FormInputServices services;

  @override
  State<FormFieldInput> createState() => _FormFieldInputState();
}

class _FormFieldInputState extends State<FormFieldInput> {
  late final _text = TextEditingController(text: widget.value.text);
  final _focus = FocusNode();
  bool _picking = false;
  String? _error;
  bool get _enabled => widget.enabled && !_picking;

  @override
  void didUpdateWidget(FormFieldInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_text.text != widget.value.text) _text.text = widget.value.text;
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _change(FormFieldValue value) {
    if (_enabled) widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final palette = tableViewPaletteOf(context);
    final input = switch (widget.control) {
      FormControl.place => _location(palette),
      FormControl.date => _date(),
      FormControl.reminder => _reminder(),
      FormControl.time => _duration(palette),
      FormControl.toggle => CheckboxListTile(
          key: ValueKey('form-checkbox-${widget.field.id}'),
          value: const ['yes', 'true', '1']
              .contains(widget.value.text.toLowerCase()),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: Text(widget.field.name),
          onChanged: _enabled
              ? (value) => _change(FormTextValue(value! ? 'Yes' : 'No'))
              : null,
        ),
      FormControl.files => _files(palette),
      FormControl.checklist => _checklist(),
      FormControl.choice ||
      FormControl.tags ||
      FormControl.people =>
        _choices(),
      FormControl.relation => _FormRelationInput(
          key: ValueKey('${widget.field.id}:${widget.field.typeOptionData}'),
          field: widget.field,
          value: widget.value as FormSelectionValue,
          backend: widget.backend,
          enabled: _enabled,
          onChanged: _change,
        ),
      FormControl.progress ||
      FormControl.counter ||
      FormControl.button =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PropertyValueControl(
              key: ValueKey('form-${widget.control.name}-${widget.field.id}'),
              style: widget.style!,
              value: widget.value.text,
              enabled: _enabled,
              onOpenRow: widget.onOpenRow,
              onChanged: (text) => _change(FormTextValue(text)),
            ),
            if (widget.control == FormControl.button &&
                widget.style!.buttonAction == PropertyButtonAction.openRow &&
                widget.onOpenRow == null)
              Text(
                LocaleKeys.form_saveBeforeAction.tr(),
                style: TextStyle(color: palette.textMuted, fontSize: 12),
              ),
          ],
        ),
      FormControl.rating => Wrap(
          children: [
            for (var i = 1; i <= 5; i++)
              FormIconAction(
                label: '$i / 5',
                icon: i <= (int.tryParse(widget.value.text) ?? 0)
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                onPressed: _enabled ? () => _change(FormTextValue('$i')) : null,
              ),
          ],
        ),
      _ => Text(widget.value.text),
    };
    return TextEntryShortcuts(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          input,
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    );
  }

  Widget _location(TableViewPalette palette) => MapSuggestionBox(
        controller: _text,
        focusNode: _focus,
        enabled: _enabled,
        openOnFocus: true,
        builder: (context, status) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: ValueKey('form-location-${widget.field.id}'),
              controller: _text,
              focusNode: _focus,
              readOnly: !_enabled,
              style: TextStyle(color: palette.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                prefixIcon: const Icon(Icons.place_rounded, size: 18),
                hintText: LocaleKeys.form_locationHint.tr(),
              ),
              onChanged: (text) => _change(FormTextValue(text)),
            ),
            if (status.open)
              TextFieldTapRegion(
                child: LocationPickerCard(
                  palette: mapPaletteOf(context),
                  status: status,
                  text: _text.text,
                  width: double.infinity,
                  onPicked: (suggestion) => _choosePlace(suggestion.value),
                  onPinned: (point) => _choosePlace(point.label),
                  onFreeText: _choosePlace,
                ),
              ),
          ],
        ),
      );

  void _choosePlace(String text) {
    if (!_enabled) return;
    _text.text = text;
    _change(FormTextValue(text));
    _focus.unfocus();
  }

  Widget _date() => TextButton.icon(
        key: ValueKey('form-date-${widget.field.id}'),
        icon: const Icon(Icons.calendar_month_rounded, size: 18),
        label: Text(
          widget.value.isEmpty
              ? LocaleKeys.form_chooseDate.tr()
              : widget.value.text,
        ),
        style: TextButton.styleFrom(alignment: Alignment.centerLeft),
        onPressed: _enabled ? () => unawaited(_pickDate()) : null,
      );

  Future<void> _pickDate() async {
    final value = await showDialog<FormDateValue>(
      context: context,
      builder: (_) => FormDateInputDialog(
        field: widget.field,
        value: widget.value as FormDateValue,
      ),
    );
    if (value != null && mounted) _change(value);
  }

  Widget _reminder() {
    final value = widget.value is FormReminderValue
        ? widget.value as FormReminderValue
        : FormReminderValue.fromText(widget.value.text);
    return TextButton.icon(
      key: ValueKey('form-reminder-${widget.field.id}'),
      icon: const Icon(Icons.notifications_active_rounded, size: 18),
      label: Text(value.isEmpty ? LocaleKeys.form_chooseDate.tr() : value.text),
      onPressed: !_enabled
          ? null
          : () async {
              final chosen = await showDialog<FormDateValue>(
                context: context,
                builder: (_) => FormDateInputDialog(
                  field: widget.field,
                  allowRange: false,
                  value: FormDateValue(
                    start: value.at,
                    includeTime: value.includeTime,
                  ),
                ),
              );
              if (chosen == null || !mounted || !_enabled) return;
              _change(
                FormReminderValue(
                  at: chosen.start,
                  reminderId:
                      value.reminderId.isEmpty ? uuid() : value.reminderId,
                  includeTime: chosen.includeTime,
                ),
              );
            },
    );
  }

  Widget _duration(TableViewPalette palette) {
    final minutes = parseTime(widget.value.text) ?? 0;
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        SizedBox(
          width: 108,
          child: TextFormField(
            key: ValueKey('form-duration-hours-${widget.field.id}'),
            initialValue: '${minutes ~/ 60}',
            readOnly: !_enabled,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: LocaleKeys.form_hours.tr()),
            onChanged: (value) => _change(
              FormTextValue(
                formatTime((int.tryParse(value) ?? 0) * 60 + minutes % 60),
              ),
            ),
          ),
        ),
        SizedBox(
          width: 108,
          child: DropdownButtonFormField<int>(
            key: ValueKey('form-duration-minutes-${widget.field.id}'),
            value: minutes % 60,
            dropdownColor: palette.surface,
            decoration:
                InputDecoration(labelText: LocaleKeys.form_minutes.tr()),
            items: [
              for (var minute = 0; minute < 60; minute++)
                DropdownMenuItem(value: minute, child: Text('$minute')),
            ],
            onChanged: _enabled
                ? (value) => _change(
                      FormTextValue(formatTime(minutes ~/ 60 * 60 + value!)),
                    )
                : null,
          ),
        ),
      ],
    );
  }

  Widget _choices() {
    final selected = widget.value as FormSelectionValue;
    final options =
        SingleSelectTypeOptionPB.fromBuffer(widget.field.typeOptionData)
            .options;
    final multiple = widget.field.fieldType == FieldType.MultiSelect;
    return options.isEmpty
        ? Text(LocaleKeys.form_noOptions.tr())
        : Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final option in options)
                FilterChip(
                  key: ValueKey('form-option-${option.id}'),
                  label: Text(option.name),
                  selected: selected.ids.contains(option.id),
                  onSelected: _enabled
                      ? (include) {
                          final ids = multiple
                              ? ([...selected.ids]..remove(option.id))
                              : <String>[];
                          if (include) ids.add(option.id);
                          _change(
                            FormSelectionValue(
                              ids,
                              labels: {
                                for (final option in options)
                                  option.id: option.name,
                              },
                            ),
                          );
                        }
                      : null,
                ),
            ],
          );
  }

  Widget _files(TableViewPalette palette) {
    final value = widget.value as FormFilesValue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final attachment in value.files)
          Row(
            key: ValueKey('form-file-${attachment.file.id}'),
            children: [
              const Icon(Icons.attach_file_rounded, size: 17),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  attachment.file.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (attachment.pending != null)
                Text(
                  LocaleKeys.form_pendingFile.tr(),
                  style: TextStyle(color: palette.textMuted, fontSize: 11),
                ),
              FormIconAction(
                actionKey: 'form-remove-file-${attachment.file.id}',
                label: LocaleKeys.button_remove.tr(),
                icon: Icons.close_rounded,
                onPressed: _enabled
                    ? () => _change(
                          FormFilesValue(
                            value.files
                                .where((file) => file != attachment)
                                .toList(),
                          ),
                        )
                    : null,
              ),
            ],
          ),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              key: ValueKey('form-files-${widget.field.id}'),
              onPressed: _enabled ? () => unawaited(_pickFiles()) : null,
              icon: const Icon(Icons.upload_file_rounded, size: 18),
              label: Text(
                _picking
                    ? LocaleKeys.form_saving.tr()
                    : LocaleKeys.form_chooseFiles.tr(),
              ),
            ),
            TextButton.icon(
              key: ValueKey('form-file-link-${widget.field.id}'),
              onPressed: _enabled ? () => unawaited(_addFileLink()) : null,
              icon: const Icon(Icons.link_rounded, size: 18),
              label: Text(LocaleKeys.form_attachLink.tr()),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickFiles() async {
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final picked =
          await widget.services.pickFiles(formFileExtensions(widget.style));
      if (!mounted || !widget.enabled || picked.isEmpty) return;
      final current = widget.value as FormFilesValue;
      widget.onChanged(
        FormFilesValue([
          ...current.files,
          for (final file in picked)
            FormFileAttachment(
              file: MediaFilePB(
                id: uuid(),
                name: path.posix.basename(file.name.replaceAll(r'\', '/')),
                fileType: file.fileType.toMediaFileTypePB(),
                uploadType: FileUploadTypePB.LocalFile,
              ),
              pending: file,
            ),
        ]),
      );
    } on Object {
      if (mounted) setState(() => _error = LocaleKeys.form_filePickFailed.tr());
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _addFileLink() async {
    final url = await showDialog<String>(
      context: context,
      builder: (_) => const _FileLinkDialog(),
    );
    if (!mounted || !_enabled || url == null) return;
    final uri = Uri.parse(url);
    final file = XFile(uri.path);
    final name = uri.pathSegments.isNotEmpty && uri.pathSegments.last.isNotEmpty
        ? uri.pathSegments.last
        : uri.host;
    _change(
      FormFilesValue([
        ...(widget.value as FormFilesValue).files,
        FormFileAttachment(
          file: MediaFilePB(
            id: uuid(),
            name: name,
            url: url,
            uploadType: FileUploadTypePB.NetworkFile,
            fileType: file.fileType.toMediaFileTypePB(),
          ),
        ),
      ]),
    );
  }

  Widget _checklist() {
    final value = widget.value as FormChecklistValue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final task in value.tasks)
          Row(
            key: ValueKey('form-task-${task.id}'),
            children: [
              Checkbox(
                value: task.checked,
                onChanged: _enabled
                    ? (checked) => _change(
                          FormChecklistValue([
                            for (final current in value.tasks)
                              current.id == task.id
                                  ? current.copyWith(checked: checked)
                                  : current,
                          ]),
                        )
                    : null,
              ),
              Expanded(
                child: TextFormField(
                  key: ValueKey('form-task-name-${task.id}'),
                  initialValue: task.name,
                  readOnly: !_enabled,
                  decoration: const InputDecoration(
                      border: InputBorder.none, isDense: true),
                  onChanged: (name) => _change(
                    FormChecklistValue([
                      for (final current in value.tasks)
                        current.id == task.id
                            ? current.copyWith(name: name)
                            : current,
                    ]),
                  ),
                ),
              ),
              FormIconAction(
                label: LocaleKeys.button_remove.tr(),
                icon: Icons.close_rounded,
                onPressed: _enabled
                    ? () => _change(
                          FormChecklistValue(
                            value.tasks
                                .where((current) => current.id != task.id)
                                .toList(),
                          ),
                        )
                    : null,
              ),
            ],
          ),
        TextButton.icon(
          key: ValueKey('form-add-task-${widget.field.id}'),
          onPressed: _enabled
              ? () => _change(
                    FormChecklistValue([
                      ...value.tasks,
                      FormChecklistTask(
                        id: 'draft:${uuid()}',
                        name: LocaleKeys.form_newTask.tr(),
                      ),
                    ]),
                  )
              : null,
          icon: const Icon(Icons.add_rounded, size: 17),
          label: Text(LocaleKeys.form_addTask.tr()),
        ),
      ],
    );
  }
}

List<String>? formFileExtensions(PropertyStyle? style) =>
    switch (style?.mediaKind) {
      PropertyMediaKind.photo => [
          'png',
          'jpg',
          'jpeg',
          'gif',
          'webp',
          'bmp',
          'heic',
        ],
      PropertyMediaKind.video => ['mp4', 'mov', 'mkv', 'webm', 'avi'],
      PropertyMediaKind.audio => ['mp3', 'wav', 'm4a', 'ogg', 'flac'],
      PropertyMediaKind.pdf => ['pdf'],
      _ => null,
    };

class FormDateInputDialog extends StatefulWidget {
  const FormDateInputDialog({
    super.key,
    required this.field,
    required this.value,
    this.allowRange = true,
  });
  final FieldPB field;
  final FormDateValue value;
  final bool allowRange;
  @override
  State<FormDateInputDialog> createState() => _FormDateInputDialogState();
}

class _FormDateInputDialogState extends State<FormDateInputDialog> {
  late FormDateValue _draft = widget.value;

  Future<void> _done() async {
    // Commit the focused date/time input before reading the dialog draft.
    FocusScope.of(context).unfocus();
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context, _draft);
  }

  @override
  Widget build(BuildContext context) {
    final format = widget.field.fieldType == FieldType.DateTime
        ? DateTypeOptionPB.fromBuffer(widget.field.typeOptionData)
        : DateTypeOptionPB();
    // The calendar uses LayoutBuilder. AlertDialog's IntrinsicWidth asks it
    // for intrinsic height and prevents the entire dialog from laying out.
    return Dialog(
      backgroundColor: tableViewPaletteOf(context).surface,
      child: SizedBox(
        width: 360,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.field.name,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: TextEntryShortcuts(
                    child: DesktopAppFlowyDatePicker(
                      key: const ValueKey('form-native-date-picker'),
                      dateTime: _draft.start,
                      endDateTime: _draft.end,
                      dateFormat: format.dateFormat,
                      timeFormat: format.timeFormat,
                      includeTime: _draft.includeTime,
                      isRange: _draft.isRange,
                      onDaySelected: (date) =>
                          setState(() => _draft = _draft.copyWith(start: date)),
                      onRangeSelected: (start, end) => setState(
                        () => _draft = _draft.copyWith(start: start, end: end),
                      ),
                      onIncludeTimeChanged: (include, start, end) => setState(
                        () => _draft = _draft.copyWith(
                          start: start,
                          end: end,
                          includeTime: include,
                        ),
                      ),
                      onIsRangeChanged: !widget.allowRange
                          ? null
                          : (range, start, end) => setState(
                                () => _draft = _draft.copyWith(
                                    start: start, end: end, isRange: range),
                              ),
                    ),
                  ),
                ),
              ),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(
                      context,
                      FormDateValue(reminderId: _draft.reminderId),
                    ),
                    child: Text(LocaleKeys.form_clear.tr()),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(LocaleKeys.button_cancel.tr()),
                  ),
                  TextButton(
                    key: const ValueKey('form-date-done'),
                    onPressed: () => unawaited(_done()),
                    child: Text(LocaleKeys.button_done.tr()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FileLinkDialog extends StatefulWidget {
  const _FileLinkDialog();
  @override
  State<_FileLinkDialog> createState() => _FileLinkDialogState();
}

class _FileLinkDialogState extends State<_FileLinkDialog> {
  final _text = TextEditingController();
  String? _error;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final url = _text.text.trim();
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      setState(
        () => _error = LocaleKeys.document_plugins_file_networkUrlInvalid.tr(),
      );
      return;
    }
    Navigator.pop(context, url);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: tableViewPaletteOf(context).surface,
        title: Text(LocaleKeys.form_attachLink.tr()),
        content: SizedBox(
          width: 360,
          child: TextEntryShortcuts(
            child: TextField(
              controller: _text,
              autofocus: true,
              decoration:
                  InputDecoration(hintText: 'https://', errorText: _error),
              onSubmitted: (_) => _submit(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(LocaleKeys.button_cancel.tr()),
          ),
          TextButton(
            onPressed: _submit,
            child: Text(LocaleKeys.form_save.tr()),
          ),
        ],
      );
}

class _FormRelationInput extends StatefulWidget {
  const _FormRelationInput({
    super.key,
    required this.field,
    required this.value,
    required this.backend,
    required this.enabled,
    required this.onChanged,
  });
  final FieldPB field;
  final FormSelectionValue value;
  final FormEntryBackend backend;
  final bool enabled;
  final ValueChanged<FormFieldValue> onChanged;
  @override
  State<_FormRelationInput> createState() => _FormRelationInputState();
}

class _FormRelationInputState extends State<_FormRelationInput> {
  late Future<Map<String, String>> _rows =
      widget.backend.relatedRows(widget.field);
  String _search = '';
  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, String>>(
        future: _rows,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return TextButton(
              onPressed: () => setState(() {
                _rows = widget.backend.relatedRows(widget.field);
              }),
              child: Text(LocaleKeys.tableViews_tryAgain.tr()),
            );
          }
          if (!snapshot.hasData) {
            return Text(LocaleKeys.tableViews_loading.tr());
          }
          final rows = snapshot.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: ValueKey('form-relation-${widget.field.id}'),
                readOnly: !widget.enabled,
                decoration: InputDecoration(
                  hintText: LocaleKeys.form_relationPick.tr(),
                  prefixIcon: const Icon(Icons.search_rounded),
                  border: InputBorder.none,
                ),
                onChanged: (value) =>
                    setState(() => _search = value.toLowerCase()),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final row in rows.entries.where(
                        (entry) => entry.value.toLowerCase().contains(_search),
                      ))
                        FilterChip(
                          label: Text(
                            row.value.isEmpty
                                ? LocaleKeys.grid_row_titlePlaceholder.tr()
                                : row.value,
                          ),
                          selected: widget.value.ids.contains(row.key),
                          onSelected: widget.enabled
                              ? (selected) {
                                  final ids = [...widget.value.ids]
                                    ..remove(row.key);
                                  if (selected) ids.add(row.key);
                                  widget.onChanged(
                                    FormSelectionValue(ids, labels: rows),
                                  );
                                }
                              : null,
                        ),
                    ],
                  ),
                ),
              ),
              if (rows.isEmpty) Text(LocaleKeys.form_relationEmpty.tr()),
            ],
          );
        },
      );
}
