import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/encryption/encryption.dart';
import 'package:appflowy/shared/encryption/sensitive_clipboard.dart';
import 'package:appflowy/shared/maps/map_style.dart';
import 'package:appflowy/shared/maps/map_suggestions.dart';
import 'package:appflowy/plugins/database/widgets/cell/desktop_grid/location_picker_card.dart';
import 'package:appflowy/shared/table_views/form_field_dialog.dart';
import 'package:appflowy/shared/table_views/form_field_input.dart';
import 'package:appflowy/shared/table_views/form_field_tile.dart';
import 'package:appflowy/shared/table_views/form_typed_field.dart';
import 'package:appflowy/shared/table_views/table_property_view.dart';
import 'package:appflowy/shared/table_views/table_view_chrome.dart';
import 'package:appflowy/shared/table_views/table_view_style.dart';
import 'package:appflowy/workspace/application/encryption/encrypted_column.dart';
import 'package:appflowy/workspace/application/encryption/encryption_vault.dart';
import 'package:appflowy/workspace/application/table_views/form_entry_service.dart';
import 'package:appflowy/workspace/application/table_views/form_field_value.dart';
import 'package:appflowy/workspace/application/table_views/form_spec.dart';
import 'package:appflowy/workspace/application/table_views/table_row.dart';
import 'package:appflowy/workspace/application/table_views/table_row_source.dart';
import 'package:appflowy/workspace/presentation/encryption/encryption_dialogs.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// What a filled in form asks the host to do.
typedef FormSubmit = Future<String?> Function(Map<String, String> answers);

/// A table offered as something to fill in.
///
/// This is not the row editor with a different border: it is the table asked
/// as questions, in the order and the wording the author chose, with the
/// controls a person would expect to type each answer into.
class FormStage extends StatefulWidget {
  const FormStage({
    super.key,
    required this.viewId,
    required this.spec,
    required this.onSpecChanged,
    this.title,
    this.onSubmit,
    this.onOpenRow,
    this.editable = true,
    this.source,
    this.entryService,
    this.authorize,
    this.initialRowId,
    this.inputServices = const FormInputServices(),
    this.padding = EdgeInsets.zero,
  });

  final String viewId;
  final FormSpec spec;
  final FutureOr<void> Function(FormSpec) onSpecChanged;
  final String? title;

  /// Making the row the form describes. Hands back the row it made.
  final FormSubmit? onSubmit;

  final ValueChanged<String>? onOpenRow;

  final bool editable;
  final TableRowSource? source;
  final FormEntryService? entryService;
  final Future<bool> Function(BuildContext)? authorize;
  final String? initialRowId;
  final FormInputServices inputServices;

  final EdgeInsets padding;

  @override
  State<FormStage> createState() => FormStageState();
}

class FormStageState extends State<FormStage> with WidgetsBindingObserver {
  late final TableRowSource _source =
      widget.source ?? TableRowSource(viewId: widget.viewId);
  late final FormEntryService _entries =
      widget.entryService ?? FormEntryService(viewId: widget.viewId);
  final ScrollController _scroll = ScrollController();
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, FocusNode> _focusNodes = {};
  final Map<String, String> _answers = {};
  final Map<String, FormFieldValue> _typedAnswers = {};
  int _draftGeneration = 0;
  final Set<String> _collapsed = {};
  final Set<String> _draftRevealed = {};
  final Set<String> _editingFields = {};

  List<String> _missing = const [];
  late String? _selectedRowId = widget.initialRowId;
  bool _newEntry = false;
  String _search = '';
  String? _notice;
  bool _noticeIsError = false;
  bool _submitting = false;
  bool _changingField = false;
  bool _writingCell = false;
  int _privacyEpoch = 0;

  bool get _busy => _submitting || _changingField || _writingCell;
  EncryptionVault get _vault => EncryptionVault.instance;
  EncryptedColumnRegistry get _encryption => EncryptedColumnRegistry.instance;

  static const double measure = 640;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _vault.addListener(_onVaultChanged);
    _encryption.revision.addListener(_onSourceChanged);
    if (widget.viewId.isNotEmpty) _encryption.listenable(widget.viewId);
    _collapsed.addAll(
      widget.spec.sections
          .where((section) => section.collapsed)
          .map((s) => s.id),
    );
    _source
      ..updateSpec(const TableReadSpec())
      ..addListener(_onSourceChanged);
    unawaited(_source.load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _vault.removeListener(_onVaultChanged);
    _encryption.revision.removeListener(_onSourceChanged);
    _source.removeListener(_onSourceChanged);
    if (widget.source == null) _source.dispose();
    _scroll.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(FormStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (final id in widget.spec.hiddenColumns) {
      if (!oldWidget.spec.isHidden(id)) {
        _answers.remove(id);
        _typedAnswers.remove(id);
        _controllers[id]?.clear();
        _draftRevealed.remove(id);
      }
    }
    if (!widget.editable && oldWidget.editable) _concealSecrets();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && mounted) {
      setState(_concealSecrets);
      // Switching to the destination app is how a copied value is pasted.
      // Keep its expiry timer; only an actual vault lock clears it immediately.
    }
  }

  void _onVaultChanged() {
    if (!mounted) return;
    setState(() {
      if (!_vault.isUnlocked) _concealSecrets();
    });
    if (!_vault.isUnlocked) unawaited(SensitiveClipboard.instance.clear());
  }

  void _concealSecrets() {
    _privacyEpoch++;
    _draftRevealed.clear();
    for (final field in _source.fields) {
      if (_encryption.isEncrypted(widget.viewId, field.id)) {
        _typedAnswers.remove(field.id);
        if ((_answers.remove(field.id) ?? '').isNotEmpty) {
          _notice = LocaleKeys.form_secretDraftCleared.tr();
          _noticeIsError = true;
        }
        _controllers[field.id]?.clear();
      }
    }
  }

  /// Reads the table again — the host calls this when a column changes.
  void reload() => _source.invalidate();

  void _onSourceChanged() {
    if (mounted) {
      setState(() {
        if (!_newEntry &&
            !_source.isLoading &&
            !_source.cards.any((card) => card.rowId == _selectedRowId)) {
          _selectedRowId = _source.cards.firstOrNull?.rowId;
        }
      });
    }
  }

  TextEditingController _controllerFor(String fieldId) =>
      _controllers.putIfAbsent(
        fieldId,
        () => TextEditingController(text: _answers[fieldId] ?? ''),
      );

  FocusNode _focusFor(String fieldId) =>
      _focusNodes.putIfAbsent(fieldId, FocusNode.new);

  void _answer(String fieldId, String value, {FormFieldValue? typed}) {
    if (!widget.editable || _busy) return;
    _newEntry = true;
    _answers[fieldId] = value;
    if (typed == null) {
      _typedAnswers.remove(fieldId);
    } else {
      _typedAnswers[fieldId] = typed;
    }
    if (_missing.contains(fieldId) && value.trim().isNotEmpty) {
      setState(() => _missing = [..._missing]..remove(fieldId));
    }
  }

  // ------------------------------------------------------------------ layout

  @override
  Widget build(BuildContext context) {
    final palette = tableViewPaletteOf(context);
    final fields = _selectedRowId == null
        ? formFieldsOf(_source.fields, widget.spec)
        : _source.fields.where((f) => !widget.spec.isHidden(f.id)).toList();

    return TextEntryShortcuts(
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, control: true): () =>
              unawaited(_submit()),
          const SingleActivator(LogicalKeyboardKey.enter, meta: true): () =>
              unawaited(_submit()),
        },
        child: Padding(
          padding: widget.padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(palette, fields),
              const SizedBox(height: TableViewMetrics.space3),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final body = _buildBody(palette, fields);
                    final wide = constraints.maxWidth >= 820;
                    // Keep the detail subtree at the same depth across resize:
                    // changing Row -> Column would dispose every open field draft.
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Visibility(
                          visible: wide,
                          maintainState: true,
                          child:
                              SizedBox(width: 236, child: _entryList(palette)),
                        ),
                        SizedBox(width: wide ? 24 : 0),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Visibility(
                                visible: !wide,
                                maintainState: true,
                                child: _entryPicker(palette),
                              ),
                              SizedBox(height: wide ? 0 : 8),
                              Expanded(child: body),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(TableViewPalette palette, List<FieldPB> fields) => Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Text(
            '${LocaleKeys.form_entries.tr()} · ${_source.cards.length}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: palette.textPrimary,
                ),
          ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            children: [
              if (widget.editable) ...[
                TextButton.icon(
                  key: const ValueKey('form-new-entry'),
                  onPressed: _busy ? null : () => unawaited(_chooseEntry(null)),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(LocaleKeys.form_newEntry.tr()),
                ),
                TextButton.icon(
                  key: const ValueKey('form-add-field'),
                  onPressed: _busy ? null : () => unawaited(_addField()),
                  icon: const Icon(Icons.add_box_rounded, size: 17),
                  label: Text(LocaleKeys.form_addField.tr()),
                ),
              ] else
                Text(LocaleKeys.form_readOnly.tr()),
              Builder(
                builder: (context) => FormIconAction(
                  actionKey: 'form-options',
                  label: LocaleKeys.tableViews_options.tr(),
                  icon: Icons.more_horiz_rounded,
                  onPressed: _busy
                      ? null
                      : () => unawaited(
                            showAppMenuForWidget<void>(
                              context: context,
                              entries: _options(fields),
                            ),
                          ),
                ),
              ),
            ],
          ),
        ],
      );

  String _entryName(TableRowCard card) {
    final titleId = _source.titleColumn;
    if (widget.spec.isMasked(titleId) ||
        widget.spec.isHidden(titleId) ||
        _encryption.isEncrypted(widget.viewId, titleId) ||
        looksSealed(card.title)) {
      return LocaleKeys.form_hiddenEntry.tr();
    }
    return card.title.isEmpty
        ? LocaleKeys.grid_row_titlePlaceholder.tr()
        : card.title;
  }

  Widget _entryPicker(TableViewPalette palette) => DropdownButton<String>(
        key: const ValueKey('form-entry-picker'),
        value: _source.cards.any((card) => card.rowId == _selectedRowId)
            ? _selectedRowId
            : '',
        isExpanded: true,
        menuMaxHeight: 320,
        dropdownColor: palette.surface,
        underline: const SizedBox.shrink(),
        items: [
          DropdownMenuItem(
            value: '',
            child: Text(LocaleKeys.form_newEntry.tr()),
          ),
          for (final card in _source.cards)
            DropdownMenuItem(
              value: card.rowId,
              child: Text(
                _entryName(card),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: _busy
            ? null
            : (id) => unawaited(_chooseEntry(id == '' ? null : id)),
      );

  Widget _entryList(TableViewPalette palette) {
    final cards = _source.cards
        .where(
          (card) =>
              _entryName(card).toLowerCase().contains(_search.toLowerCase()),
        )
        .toList();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('form-entry-search'),
            onChanged: (value) => setState(() => _search = value),
            decoration: InputDecoration(
              hintText: LocaleKeys.form_searchEntries.tr(),
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              border: InputBorder.none,
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: cards.isEmpty
                ? Text(
                    LocaleKeys.form_noEntries.tr(),
                    style: TextStyle(color: palette.textMuted),
                  )
                : ListView.builder(
                    itemCount: cards.length,
                    itemBuilder: (context, index) {
                      final card = cards[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: TextButton(
                          key: ValueKey('form-entry-${card.rowId}'),
                          style: TextButton.styleFrom(
                            alignment: Alignment.centerLeft,
                            foregroundColor: palette.textPrimary,
                            backgroundColor: card.rowId == _selectedRowId
                                ? palette.hover
                                : palette.hoverAtRest,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(9),
                            ),
                          ),
                          onPressed: _busy
                              ? null
                              : () => unawaited(_chooseEntry(card.rowId)),
                          child: Text(
                            _entryName(card),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _chooseEntry(String? rowId) async {
    if (_busy || rowId == _selectedRowId) return;
    if ((_selectedRowId == null && _answers.values.any((v) => v.isNotEmpty)) ||
        _editingFields.isNotEmpty) {
      final discard = await _confirm(
        LocaleKeys.form_discardDraft.tr(),
        LocaleKeys.form_discardDraftBody.tr(),
      );
      if (!discard || !mounted) return;
    }
    setState(() {
      _clearDraft();
      _selectedRowId = rowId;
      _newEntry = rowId == null;
      _editingFields.clear();
      _privacyEpoch++;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Widget _buildBody(TableViewPalette palette, List<FieldPB> fields) {
    if (_source.isLoading && _source.fields.isEmpty) {
      return TableViewEmpty(
        palette: palette,
        icon: Icons.assignment_rounded,
        message: LocaleKeys.tableViews_loading.tr(),
      );
    }
    final error = _source.error;
    if (error != null && error.isNotEmpty && _source.fields.isEmpty) {
      return TableViewEmpty(
        palette: palette,
        icon: Icons.assignment_rounded,
        message: LocaleKeys.tableViews_couldNotRead.tr(),
        detail: error,
        actionLabel: LocaleKeys.tableViews_tryAgain.tr(),
        onAction: reload,
      );
    }
    final sections = formSectionsOf(
      _source.fields,
      widget.spec,
      includeReadOnly: _selectedRowId != null,
    );
    final byId = {for (final field in _source.fields) field.id: field};

    return Scrollbar(
      controller: _scroll,
      child: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.only(bottom: TableViewMetrics.space6),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: measure),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildIntro(palette),
                for (final section in sections)
                  _buildSection(palette, section, byId),
                if (widget.spec.hiddenColumns.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const ValueKey('form-show-hidden'),
                      onPressed: !widget.editable || _busy
                          ? null
                          : () => unawaited(
                                _changeSpec(
                                  widget.spec.copyWith(hiddenColumns: const []),
                                ),
                              ),
                      icon: const Icon(Icons.visibility_rounded, size: 17),
                      label: Text(
                        '${LocaleKeys.form_hiddenFields.tr()} · ${widget.spec.hiddenColumns.length}',
                      ),
                    ),
                  ),
                if (fields.isEmpty)
                  Text(
                    LocaleKeys.form_empty.tr(),
                    style: TextStyle(color: palette.textMuted),
                  ),
                if (_notice != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      _notice!,
                      style: TextStyle(
                        color: _noticeIsError
                            ? Theme.of(context).colorScheme.error
                            : palette.textSecondary,
                      ),
                    ),
                  ),
                const SizedBox(height: TableViewMetrics.space5),
                _buildFooter(palette),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIntro(TableViewPalette palette) {
    final selected =
        _source.cards.where((card) => card.rowId == _selectedRowId);
    final heading = selected.isNotEmpty
        ? _entryName(selected.first)
        : widget.spec.heading.trim().isEmpty
            ? (widget.title ?? LocaleKeys.form_name.tr())
            : widget.spec.heading;
    return Padding(
      padding: const EdgeInsets.only(
        top: TableViewMetrics.space5,
        bottom: TableViewMetrics.space5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            heading,
            style: TextStyle(
              fontSize: 26,
              height: 1.25,
              letterSpacing: -0.6,
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
          if (widget.spec.description.isNotEmpty) ...[
            const SizedBox(height: TableViewMetrics.space2),
            Text(
              widget.spec.description,
              style: TextStyle(
                fontSize: 14,
                height: 1.55,
                color: palette.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSection(
    TableViewPalette palette,
    FormSection section,
    Map<String, FieldPB> byId,
  ) {
    final open = !_collapsed.contains(section.id);
    final named = section.title.trim().isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: TableViewMetrics.space4),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(TableViewMetrics.cardRadius),
        boxShadow: palette.cardShadow(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (named)
            _SectionHeader(
              palette: palette,
              title: section.title,
              description: section.description,
              open: open,
              onToggle: () => setState(() {
                if (open) {
                  _collapsed.add(section.id);
                } else {
                  _collapsed.remove(section.id);
                }
              }),
            ),
          AnimatedCrossFade(
            duration: TableViewMetrics.change,
            sizeCurve: TableViewMetrics.settleCurve,
            crossFadeState:
                open ? CrossFadeState.showFirst : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: EdgeInsets.fromLTRB(
                TableViewMetrics.space5,
                named ? 0 : TableViewMetrics.space5,
                TableViewMetrics.space5,
                TableViewMetrics.space5,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final fieldId in section.fieldIds)
                    if (byId[fieldId] != null)
                      _buildField(palette, byId[fieldId]!),
                ],
              ),
            ),
            secondChild: const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _buildField(TableViewPalette palette, FieldPB field) {
    final rowId = _selectedRowId;
    final style = _source.styleForField(field.id, rowId: rowId ?? '');
    final control = formControlOf(
      field,
      isLocation: _source.locationColumns.contains(field.id),
      styleKind: style?.kind.name,
    );
    if (rowId != null) {
      final stored = _source.cellValuesFor(rowId)[field.id] ?? '';
      final encrypted = _encryption.isEncrypted(widget.viewId, field.id) ||
          looksSealed(stored);
      final sensitive = encrypted || widget.spec.isMasked(field.id);
      if (!sensitive &&
          isFormFillable(field) &&
          usesTypedFormInput(field, control)) {
        return FormTypedField(
          key: ValueKey(
            '$rowId:${field.id}:${field.fieldType.value}:${control.name}',
          ),
          field: field,
          control: control,
          style: style,
          revision: _source.revision,
          backend: _entries.backend,
          services: widget.inputServices,
          busy: _busy,
          read: () => _entries.backend.readValue(widget.viewId, rowId, field),
          save: !widget.editable
              ? null
              : (value, previous) async {
                  if (_busy || !widget.editable) {
                    throw const FormEntryException('readOnly');
                  }
                  setState(() => _writingCell = true);
                  try {
                    await _entries.updateValue(
                      rowId: rowId,
                      field: field,
                      value: value,
                      previous: previous,
                    );
                    if (mounted) await _source.load();
                  } finally {
                    if (mounted) setState(() => _writingCell = false);
                  }
                },
          onEditingChanged: (editing) => editing
              ? _editingFields.add(field.id)
              : _editingFields.remove(field.id),
          onOpenRow:
              widget.onOpenRow == null ? null : () => widget.onOpenRow!(rowId),
          description: widget.spec.descriptionOf(field.id),
          menu: widget.editable ? _fieldMenu(field) : null,
        );
      }
      return FormFieldTile(
        key: ValueKey('$rowId:${field.id}:${sensitive ? _privacyEpoch : 0}'),
        field: field,
        value: stored,
        masked: widget.spec.isMasked(field.id),
        encrypted: encrypted,
        description: widget.spec.descriptionOf(field.id),
        onRead: () => _readValue(stored, encrypted),
        onEditingChanged: (editing) => editing
            ? _editingFields.add(field.id)
            : _editingFields.remove(field.id),
        onSave: widget.editable && isFormInlineEditable(field)
            ? (value) async {
                if (!widget.editable || _busy) {
                  throw const FormEntryException('readOnly');
                }
                setState(() => _writingCell = true);
                try {
                  await _entries.update(
                    rowId: rowId,
                    field: field,
                    value: value,
                    previousValue: stored,
                  );
                  if (mounted) await _source.load();
                } finally {
                  if (mounted) setState(() => _writingCell = false);
                }
              }
            : null,
        onOpenEditor: widget.editable &&
                !_busy &&
                widget.onOpenRow != null &&
                !const [
                  FieldType.CreatedTime,
                  FieldType.LastEditedTime,
                  FieldType.Summary,
                  FieldType.Translate,
                ].contains(field.fieldType)
            ? () => widget.onOpenRow!(rowId)
            : null,
        menu: widget.editable ? _fieldMenu(field) : null,
      );
    }
    final required = widget.spec.isRequired(field.id);
    final missing = _missing.contains(field.id);
    final note = widget.spec.descriptionOf(field.id);

    return Padding(
      padding: const EdgeInsets.only(bottom: TableViewMetrics.space5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  field.name,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              if (required) ...[
                const SizedBox(width: 6),
                Text(
                  '*',
                  style: TextStyle(fontSize: 13.5, color: palette.accent),
                ),
              ],
              if (_sensitive(field))
                FormIconAction(
                  actionKey: 'form-draft-reveal-${field.id}',
                  label: _draftRevealed.contains(field.id)
                      ? LocaleKeys.form_hideValue.tr()
                      : LocaleKeys.form_showValue.tr(),
                  icon: _draftRevealed.contains(field.id)
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            if (!_draftRevealed.remove(field.id)) {
                              _draftRevealed.add(field.id);
                            }
                          }),
                ),
              FormIconAction(
                actionKey: 'form-draft-copy-${field.id}',
                label: LocaleKeys.form_copyField.tr(args: [field.name]),
                icon: Icons.copy_rounded,
                onPressed: _busy ? null : () => unawaited(_copyDraft(field)),
              ),
              if (widget.editable) _fieldMenu(field),
            ],
          ),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              note,
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: palette.textMuted,
              ),
            ),
          ],
          const SizedBox(height: TableViewMetrics.space2),
          ExcludeFocus(
            excluding: !widget.editable || _busy,
            child: IgnorePointer(
              ignoring: !widget.editable || _busy,
              child: _buildControl(palette, field, missing),
            ),
          ),
          if (_sensitive(field))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _encryption.isEncrypted(widget.viewId, field.id)
                    ? LocaleKeys.form_encryptedValue.tr()
                    : LocaleKeys.form_hiddenValue.tr(),
                style: TextStyle(fontSize: 11, color: palette.textMuted),
              ),
            ),
          if (missing) ...[
            const SizedBox(height: 5),
            Text(
              LocaleKeys.form_requiredMissing.tr(),
              style: TextStyle(fontSize: 11.5, color: palette.swatchFor('due')),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildControl(
    TableViewPalette palette,
    FieldPB field,
    bool missing,
  ) {
    if (_encryption.isEncrypted(widget.viewId, field.id) &&
        !_vault.isUnlocked) {
      return TextButton.icon(
        onPressed: widget.editable && !_busy
            ? () => unawaited(ensureWorkspaceUnlocked(context))
            : null,
        icon: const Icon(Icons.lock_rounded, size: 17),
        label: Text(LocaleKeys.encryption_needsUnlocking.tr()),
      );
    }
    if (_sensitive(field)) {
      return _buildText(palette, field, missing, lines: 1);
    }
    final style = _source.styleForField(field.id);
    final control = formControlOf(
      field,
      isLocation: _source.locationColumns.contains(field.id),
      styleKind: style?.kind.name,
    );
    if (usesTypedFormInput(field, control)) {
      return FormFieldInput(
        key: ValueKey('form-draft-input-${field.id}-$_draftGeneration'),
        field: field,
        control: control,
        style: style,
        value: _typedAnswers[field.id] ?? emptyFormValue(field),
        backend: _entries.backend,
        services: widget.inputServices,
        enabled: widget.editable && !_busy,
        onChanged: (value) {
          if (!widget.editable || _busy) return;
          setState(() {
            _answer(field.id, value.text, typed: value);
          });
        },
      );
    }
    return switch (control) {
      FormControl.toggle => _buildToggle(palette, field),
      FormControl.rating => _buildRating(palette, field),
      FormControl.choice => _buildChoice(palette, field, missing),
      FormControl.tags ||
      FormControl.people when field.fieldType == FieldType.MultiSelect =>
        _buildChoice(palette, field, missing),
      FormControl.date => _buildDate(palette, field, missing),
      FormControl.place => _buildPlace(palette, field, missing),
      FormControl.relation => _buildRelation(palette, field, missing),
      FormControl.paragraph => _buildText(palette, field, missing, lines: 5),
      _ => _buildText(palette, field, missing, lines: 1, control: control),
    };
  }

  /// A place is picked from a map, never typed blind.
  Widget _buildPlace(
    TableViewPalette palette,
    FieldPB field,
    bool missing,
  ) {
    final controller = _controllerFor(field.id);
    final focus = _focusFor(field.id);
    return MapSuggestionBox(
      controller: controller,
      focusNode: focus,
      // A form has room to show the picker in place, so it opens the moment
      // the field is entered rather than waiting for something to be typed.
      openOnFocus: true,
      builder: (context, status) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FormWell(
            palette: palette,
            warn: missing,
            child: TextField(
              controller: controller,
              focusNode: focus,
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: palette.textPrimary,
              ),
              onChanged: (value) => _answer(field.id, value),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: _hintFor(FormControl.place),
                hintStyle: TextStyle(fontSize: 14, color: palette.textMuted),
                prefixIcon: _prefixFor(FormControl.place, palette),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 30, minHeight: 24),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          // A form is a tall scrolling column, so the map and the places are
          // laid out in place rather than floated over it.
          AnimatedSize(
            duration: TableViewMetrics.change,
            curve: TableViewMetrics.settleCurve,
            alignment: Alignment.topCenter,
            child: status.open
                ? Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: LocationPickerCard(
                      palette: mapPaletteOf(context),
                      status: status,
                      text: controller.text,
                      width: double.infinity,
                      onPicked: (suggestion) => _writePlace(
                        field,
                        controller,
                        focus,
                        suggestion.value,
                      ),
                      onPinned: (point) =>
                          _writePlace(field, controller, focus, point.label),
                      onFreeText: (value) =>
                          _writePlace(field, controller, focus, value),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  void _writePlace(
    FieldPB field,
    TextEditingController controller,
    FocusNode focus,
    String value,
  ) {
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _answer(field.id, value);
    focus.unfocus();
  }

  /// The rows this one belongs with, chosen from the table it points at.
  Widget _buildRelation(
    TableViewPalette palette,
    FieldPB field,
    bool missing,
  ) {
    final chosen = _chosenRelations(field.id);
    return _RelationField(
      palette: palette,
      field: field,
      warn: missing,
      chosen: chosen,
      onChanged: (ids) => setState(() => _answer(field.id, ids.join(','))),
    );
  }

  List<String> _chosenRelations(String fieldId) => (_answers[fieldId] ?? '')
      .split(',')
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toList();

  Widget _buildText(
    TableViewPalette palette,
    FieldPB field,
    bool missing, {
    required int lines,
    FormControl control = FormControl.line,
  }) {
    return _FormWell(
      palette: palette,
      warn: missing,
      child: TextField(
        key: ValueKey('form-draft-${field.id}'),
        controller: _controllerFor(field.id),
        focusNode: _focusFor(field.id),
        readOnly: !widget.editable || _busy,
        obscureText: _sensitive(field) && !_draftRevealed.contains(field.id),
        autocorrect: !_sensitive(field),
        enableSuggestions: !_sensitive(field),
        maxLines: lines,
        minLines: lines,
        keyboardType:
            control == FormControl.number ? TextInputType.number : null,
        style: TextStyle(
          fontSize: 14,
          height: 1.45,
          color: palette.textPrimary,
        ),
        onChanged: (value) => _answer(field.id, value),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          hintText: _hintFor(control),
          hintStyle: TextStyle(fontSize: 14, color: palette.textMuted),
          prefixIcon: _prefixFor(control, palette),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 30, minHeight: 24),
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }

  Widget? _prefixFor(FormControl control, TableViewPalette palette) =>
      switch (control) {
        FormControl.link =>
          Icon(Icons.link_rounded, size: 15, color: palette.textMuted),
        FormControl.place =>
          Icon(Icons.place_rounded, size: 15, color: palette.textMuted),
        FormControl.files =>
          Icon(Icons.attach_file_rounded, size: 15, color: palette.textMuted),
        FormControl.people =>
          Icon(Icons.person_rounded, size: 15, color: palette.textMuted),
        FormControl.relation =>
          Icon(Icons.hub_rounded, size: 15, color: palette.textMuted),
        _ => null,
      };

  String _hintFor(FormControl control) => switch (control) {
        FormControl.number => '0',
        FormControl.link => 'https://',
        FormControl.people => 'Ada, Grace',
        FormControl.tags => 'one, two',
        FormControl.place => 'An address or coordinates',
        FormControl.files => 'A file name or a link',
        FormControl.relation => 'The rows this belongs with',
        FormControl.paragraph => 'Write something…',
        _ => '',
      };

  Widget _buildToggle(TableViewPalette palette, FieldPB field) {
    final on = (_answers[field.id] ?? '').toLowerCase() == 'yes';
    return SwitchListTile(
      key: ValueKey('form-toggle-${field.id}'),
      value: on,
      contentPadding: EdgeInsets.zero,
      title: Text(on ? 'Yes' : 'No'),
      onChanged: !widget.editable || _busy
          ? null
          : (value) => setState(() => _answer(field.id, value ? 'Yes' : 'No')),
    );
  }

  Widget _buildRating(TableViewPalette palette, FieldPB field) {
    final marks = int.tryParse(_answers[field.id] ?? '') ?? 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => setState(
                () => _answer(field.id, i == marks ? '' : '$i'),
              ),
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  i <= marks ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 24,
                  color: i <= marks
                      ? palette.accent
                      : palette.textMuted.withValues(alpha: 0.45),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildChoice(
    TableViewPalette palette,
    FieldPB field,
    bool missing,
  ) {
    // The choices a status column already holds are the ones worth offering.
    final options = formChoiceNames(field);
    final chosen = _answers[field.id] ?? '';
    final multiple = field.fieldType == FieldType.MultiSelect;
    final selected = multiple ? tablePartsOf(chosen) : [chosen];
    if (options.isEmpty) {
      return Text(
        LocaleKeys.form_noOptions.tr(),
        style: TextStyle(color: palette.textMuted, fontSize: 12),
      );
    }
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (final option in options)
          FilterChip(
            label: Text(option),
            selected: selected.contains(option),
            onSelected: !widget.editable || _busy
                ? null
                : (include) => setState(() {
                      final next = [...selected]..remove(option);
                      if (include) next.add(option);
                      _answer(
                        field.id,
                        multiple
                            ? next.join(', ')
                            : include
                                ? option
                                : '',
                      );
                    }),
          ),
      ],
    );
  }

  Widget _buildDate(TableViewPalette palette, FieldPB field, bool missing) {
    final chosen = parseTableDate(_answers[field.id] ?? '');
    return Row(
      children: [
        Expanded(
          child: _FormWell(
            palette: palette,
            warn: missing,
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today_rounded,
                  size: 14,
                  color: palette.textMuted,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    chosen == null
                        ? 'No date yet'
                        : '${chosen.year}-${_two(chosen.month)}-${_two(chosen.day)}',
                    style: TextStyle(
                      fontSize: 14,
                      color: chosen == null
                          ? palette.textMuted
                          : palette.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: TableViewMetrics.space2),
        TableViewAction(
          palette: palette,
          label: chosen == null ? 'Pick' : 'Change',
          icon: Icons.event_rounded,
          primary: false,
          onTap: () => unawaited(_pickDate(field)),
        ),
      ],
    );
  }

  Future<void> _pickDate(FieldPB field) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: parseTableDate(_answers[field.id] ?? '') ?? now,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 10),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(
      () => _answer(
        field.id,
        '${picked.year}-${_two(picked.month)}-${_two(picked.day)}',
      ),
    );
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  Widget _buildFooter(TableViewPalette palette) {
    final rowId = _selectedRowId;
    if (rowId != null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: widget.onOpenRow == null || _busy
              ? null
              : () => widget.onOpenRow!(rowId),
          icon: const Icon(Icons.open_in_new_rounded, size: 16),
          label: Text(LocaleKeys.form_rowEditor.tr()),
        ),
      );
    }
    if (!widget.editable) return const SizedBox.shrink();
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        TextButton.icon(
          key: const ValueKey('form-submit'),
          onPressed: _busy ? null : () => unawaited(_submit()),
          icon: const Icon(Icons.check_rounded, size: 17),
          label: Text(
            _submitting
                ? LocaleKeys.form_saving.tr()
                : LocaleKeys.form_submit.tr(),
          ),
        ),
        TextButton(
          onPressed: _busy ? null : _clear,
          child: Text(LocaleKeys.form_clear.tr()),
        ),
      ],
    );
  }

  void _clear() => setState(_clearDraft);

  void _clearDraft() {
    _answers.clear();
    _typedAnswers.clear();
    _draftGeneration++;
    _missing = const [];
    _notice = null;
    _draftRevealed.clear();
    for (final controller in _controllers.values) {
      controller.clear();
    }
  }

  Future<void> _submit() async {
    if (!widget.editable || _busy || _selectedRowId != null) return;
    final fields = formFieldsOf(_source.fields, widget.spec);
    final ids = fields.map((field) => field.id).toSet();
    final missing = missingRequiredFields(widget.spec, _answers, fieldIds: ids);
    if (missing.isNotEmpty) {
      setState(() {
        _missing = missing;
        _collapsed.clear();
      });
      _focusFor(missing.first).requestFocus();
      return;
    }
    final answers = {
      for (final entry in _answers.entries)
        if (ids.contains(entry.key) && entry.value.isNotEmpty)
          entry.key: entry.value,
    };
    if (answers.isEmpty) {
      setState(() {
        _notice = LocaleKeys.form_blankDraft.tr();
        _noticeIsError = true;
      });
      return;
    }
    setState(() => _submitting = true);
    try {
      final rowId = await (widget.onSubmit?.call(answers) ??
          _entries.create(
            answers,
            typedAnswers: {
              for (final entry in _typedAnswers.entries)
                if (ids.contains(entry.key) && !entry.value.isEmpty)
                  entry.key: entry.value,
            },
          ));
      if (rowId == null) throw const FormEntryException('writeFailed');
      if (!mounted) return;
      setState(() {
        _clearDraft();
        _newEntry = false;
        _selectedRowId = rowId;
        _notice = LocaleKeys.form_added.tr();
        _noticeIsError = false;
      });
      await _source.load();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _noticeIsError = true;
        _notice = error is FormEntryException && error.partialRowId != null
            ? LocaleKeys.form_partialSave.tr()
            : error is FormEntryException && error.code == 'protectionUnknown'
                ? LocaleKeys.form_protectionUnknown.tr()
                : error is FormEntryException && error.code == 'invalidNumber'
                    ? LocaleKeys.form_invalidNumber.tr()
                    : LocaleKeys.form_saveFailed.tr();
        if (error is FormEntryException && error.partialRowId != null) {
          _selectedRowId = error.partialRowId;
          _newEntry = false;
        }
      });
      if (error is FormEntryException && error.partialRowId != null) reload();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  bool _sensitive(FieldPB field) =>
      widget.spec.isMasked(field.id) ||
      _encryption.isEncrypted(widget.viewId, field.id);

  Future<String?> _readValue(String stored, bool encrypted) async {
    if (!encrypted) return stored;
    if (!await (widget.authorize ?? confirmWorkspaceKey)(context) || !mounted) {
      return null;
    }
    if (!_vault.isUnlocked) return null;
    final value = _vault.tryOpen(stored, context: encryptedCellContext);
    if (value == null) throw const FormEntryException('readFailed');
    return value;
  }

  Future<void> _copyDraft(FieldPB field) async {
    final value = _answers[field.id] ?? '';
    if (value.isEmpty) return;
    try {
      await SensitiveClipboard.instance
          .copy(value, sensitive: _sensitive(field));
      if (mounted) {
        setState(() {
          _noticeIsError = false;
          _notice = _sensitive(field)
              ? LocaleKeys.form_sensitiveCopied.tr()
              : LocaleKeys.form_copied.tr();
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _noticeIsError = true;
          _notice = LocaleKeys.form_readFailed.tr();
        });
      }
    }
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: tableViewPaletteOf(context).surface,
          scrollable: true,
          title: Text(title),
          content: SizedBox(width: 420, child: Text(body)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(LocaleKeys.button_cancel.tr()),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(LocaleKeys.button_confirm.tr()),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _changeSpec(FormSpec spec) async {
    if (!widget.editable || _busy) return;
    // A settings change must not silently dispose an active field editor.
    if (!_canChangeFields()) return;
    await _fieldOperation(() async {
      await widget.onSpecChanged(spec);
    });
  }

  Future<void> _fieldOperation(Future<void> Function() operation) async {
    setState(() => _changingField = true);
    try {
      await operation();
      if (mounted) {
        setState(() {
          _notice = LocaleKeys.form_saved.tr();
          _noticeIsError = false;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _notice = LocaleKeys.form_fieldFailed.tr();
          _noticeIsError = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _changingField = false);
        reload();
      }
    }
  }

  Future<void> _addField() async {
    if (!_canChangeFields()) return;
    final chosen = await showFormFieldDialog(context);
    if (chosen == null || !mounted || !widget.editable || _busy) return;
    if (chosen.kind == FormCustomFieldKind.encrypted &&
        !await ensureWorkspaceUnlocked(context)) {
      return;
    }
    if (!mounted || !widget.editable) return;
    await _fieldOperation(() async {
      final field = await _entries.addField(chosen);
      if (!mounted) return;
      await widget.onSpecChanged(
        widget.spec
            .withMasked(field.id, chosen.kind.masked)
            .withRequired(field.id, chosen.required)
            .copyWith(
          descriptions: {
            ...widget.spec.descriptions,
            field.id: chosen.description,
          },
        ),
      );
      await _source.load();
    });
  }

  Future<void> _editField(FieldPB field) async {
    if (!_canChangeFields()) return;
    final chosen = await showFormFieldDialog(
      context,
      initial: FormCustomField(
        name: field.name,
        required: widget.spec.isRequired(field.id),
        description: widget.spec.descriptionOf(field.id),
      ),
    );
    if (chosen == null || !mounted || !widget.editable || _busy) return;
    await _fieldOperation(() async {
      await _entries.backend.renameField(widget.viewId, field.id, chosen.name);
      if (!mounted) return;
      await widget.onSpecChanged(
        widget.spec.withRequired(field.id, chosen.required).copyWith(
          descriptions: {
            ...widget.spec.descriptions,
            field.id: chosen.description,
          },
        ),
      );
      await _source.load();
    });
  }

  Future<void> _setEncrypted(FieldPB field, bool encrypted) async {
    if (!widget.editable || _busy) return;
    if (!_canChangeFields()) return;
    final confirmed = await _confirm(
      encrypted
          ? LocaleKeys.form_encryptField.tr()
          : LocaleKeys.form_decryptField.tr(),
      encrypted
          ? LocaleKeys.form_encryptionNotice.tr()
          : LocaleKeys.encryption_columnDecryptBody.tr(),
    );
    if (!confirmed || !mounted || !widget.editable) return;
    if (!await (encrypted
        ? ensureWorkspaceUnlocked(context)
        : confirmWorkspaceKey(context))) {
      return;
    }
    if (!mounted || !widget.editable) return;
    await _fieldOperation(() async {
      await _entries.backend.setEncrypted(widget.viewId, field.id, encrypted);
      if (!mounted) return;
      if (encrypted) {
        await widget.onSpecChanged(widget.spec.withMasked(field.id, true));
      }
      _privacyEpoch++;
      await _source.load();
    });
  }

  Widget _fieldMenu(FieldPB field) => Builder(
        builder: (context) => FormIconAction(
          actionKey: 'form-field-menu-${field.id}',
          label: LocaleKeys.form_editField.tr(),
          icon: Icons.more_horiz_rounded,
          onPressed: _busy
              ? null
              : () => unawaited(
                    showAppMenuForWidget<void>(
                      context: context,
                      entries: [
                        AppMenuItem(
                          label: LocaleKeys.form_editField.tr(),
                          icon: Icons.edit_rounded,
                          onSelected: () => unawaited(_editField(field)),
                        ),
                        AppMenuItem(
                          label: LocaleKeys.form_required.tr(),
                          icon: Icons.priority_high_rounded,
                          selected: widget.spec.isRequired(field.id),
                          enabled: isFormFillable(field),
                          onSelected: () => unawaited(
                            _changeSpec(
                              widget.spec.withRequired(
                                field.id,
                                !widget.spec.isRequired(field.id),
                              ),
                            ),
                          ),
                        ),
                        if (field.fieldType == FieldType.RichText ||
                            field.fieldType == FieldType.URL)
                          AppMenuItem(
                            label: widget.spec.isMasked(field.id)
                                ? LocaleKeys.form_unmaskField.tr()
                                : LocaleKeys.form_maskField.tr(),
                            icon: Icons.password_rounded,
                            onSelected: () => unawaited(
                              _changeSpec(
                                widget.spec.withMasked(
                                  field.id,
                                  !widget.spec.isMasked(field.id),
                                ),
                              ),
                            ),
                          ),
                        AppMenuItem(
                          label: LocaleKeys.form_hideField.tr(),
                          icon: Icons.visibility_off_rounded,
                          onSelected: () => unawaited(
                            _changeSpec(
                              widget.spec.withHidden(field.id, true),
                            ),
                          ),
                        ),
                        const AppMenuSeparator(),
                        AppMenuItem(
                          label:
                              _encryption.isEncrypted(widget.viewId, field.id)
                                  ? LocaleKeys.form_decryptField.tr()
                                  : LocaleKeys.form_encryptField.tr(),
                          icon: Icons.lock_rounded,
                          enabled: EncryptedColumnRegistry.canEncrypt(
                                field.fieldType,
                              ) &&
                              field.id != _source.titleColumn,
                          shortcut: EncryptedColumnRegistry.canEncrypt(
                            field.fieldType,
                          )
                              ? null
                              : LocaleKeys.encryption_columnTextOnly.tr(),
                          onSelected: () => unawaited(
                            _setEncrypted(
                              field,
                              !_encryption.isEncrypted(
                                widget.viewId,
                                field.id,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
        ),
      );

  bool _canChangeFields() {
    if (_editingFields.isEmpty) return true;
    setState(() {
      _notice = LocaleKeys.form_finishEditing.tr();
      _noticeIsError = true;
    });
    return false;
  }

  List<AppMenuEntry> _options(List<FieldPB> fields) => [
        AppMenuHeader(LocaleKeys.form_layout.tr()),
        AppMenuItem(
          label: LocaleKeys.form_showAll.tr(),
          icon: Icons.visibility_rounded,
          enabled: widget.editable && widget.spec.hiddenColumns.isNotEmpty,
          onSelected: () => unawaited(
            _changeSpec(widget.spec.copyWith(hiddenColumns: const [])),
          ),
        ),
        if (widget.editable)
          for (final field in _source.fields
              .where((field) => widget.spec.isHidden(field.id)))
            AppMenuItem(
              label: '${LocaleKeys.form_showField.tr()} · ${field.name}',
              icon: Icons.visibility_rounded,
              onSelected: () => unawaited(
                _changeSpec(widget.spec.withHidden(field.id, false)),
              ),
            ),
        const AppMenuSeparator(),
        AppMenuItem(
          label: LocaleKeys.form_clear.tr(),
          icon: Icons.backspace_rounded,
          enabled: widget.editable && _selectedRowId == null,
          onSelected: _clear,
        ),
        AppMenuItem(
          label: LocaleKeys.tableViews_reload.tr(),
          icon: Icons.refresh_rounded,
          onSelected: reload,
        ),
      ];
}

/// The rows of another table, offered as something to pick.
///
/// A relation is not typed: the rows already exist, so the form lists them and
/// remembers which were chosen by id.
class _RelationField extends StatefulWidget {
  const _RelationField({
    required this.palette,
    required this.field,
    required this.chosen,
    required this.onChanged,
    this.warn = false,
  });

  final TableViewPalette palette;
  final FieldPB field;
  final List<String> chosen;
  final ValueChanged<List<String>> onChanged;
  final bool warn;

  @override
  State<_RelationField> createState() => _RelationFieldState();
}

class _RelationFieldState extends State<_RelationField> {
  final PopoverController _popover = PopoverController();

  List<RelatedRowDataPB> _rows = const [];
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _popover.close();
    super.dispose();
  }

  Future<void> _load() async {
    final databaseId = _relatedDatabaseId();
    if (databaseId == null || databaseId.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    final rows = await DatabaseEventGetRelatedDatabaseRows(
      DatabaseIdPB(value: databaseId),
    ).send().fold<List<RelatedRowDataPB>>(
      (data) => data.rows,
      (error) {
        Log.warn('[Form] could not read the related rows: $error');
        return const [];
      },
    );
    if (mounted) {
      setState(() {
        _rows = rows;
        _loading = false;
      });
    }
  }

  String? _relatedDatabaseId() {
    try {
      return RelationTypeOptionPB.fromBuffer(widget.field.typeOptionData)
          .databaseId;
    } on Object catch (error) {
      Log.warn('[Form] ${widget.field.name} names no table: $error');
      return null;
    }
  }

  String _nameOf(RelatedRowDataPB row) => row.name.trim().isEmpty
      ? LocaleKeys.grid_row_titlePlaceholder.tr()
      : row.name;

  void _toggle(String rowId) {
    final chosen = [...widget.chosen];
    chosen.contains(rowId) ? chosen.remove(rowId) : chosen.add(rowId);
    widget.onChanged(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    if (_loading) {
      return _FormWell(
        palette: palette,
        warn: widget.warn,
        child: Text(
          LocaleKeys.tableViews_loading.tr(),
          style: TextStyle(fontSize: 13.5, color: palette.textMuted),
        ),
      );
    }
    if (_rows.isEmpty) {
      return _FormWell(
        palette: palette,
        warn: widget.warn,
        child: Text(
          LocaleKeys.form_relationEmpty.tr(),
          style: TextStyle(fontSize: 13.5, color: palette.textMuted),
        ),
      );
    }
    return AppFlowyPopover(
      controller: _popover,
      direction: PopoverDirection.bottomWithLeftAligned,
      constraints: const BoxConstraints(maxWidth: 380, maxHeight: 340),
      margin: EdgeInsets.zero,
      offset: const Offset(0, 6),
      triggerActions: PopoverTriggerFlags.none,
      onClose: () => setState(() => _search = ''),
      popupBuilder: (_) => _buildMenu(palette),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _popover.show,
          child: _FormWell(
            palette: palette,
            warn: widget.warn,
            child: Row(
              children: [
                Expanded(child: _buildValue(palette)),
                const SizedBox(width: 8),
                Icon(
                  Icons.expand_more_rounded,
                  size: 18,
                  color: palette.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildValue(TableViewPalette palette) {
    final chosen = [
      for (final row in _rows)
        if (widget.chosen.contains(row.rowId)) row,
    ];
    if (chosen.isEmpty) {
      return Text(
        LocaleKeys.form_relationPick.tr(),
        style: TextStyle(fontSize: 14, color: palette.textMuted),
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final row in chosen)
          TablePill(
            label: _nameOf(row),
            colour: palette.swatchFor(_nameOf(row)),
            palette: palette,
            dense: true,
          ),
      ],
    );
  }

  Widget _buildMenu(TableViewPalette palette) {
    // The list lives in an overlay, so it keeps its own state — a rebuild of
    // the field behind it would not reach the rows or their ticks.
    return StatefulBuilder(
      builder: (context, setMenuState) {
        final query = _search.trim().toLowerCase();
        final matching = query.isEmpty
            ? _rows
            : _rows
                .where((row) => _nameOf(row).toLowerCase().contains(query))
                .toList();

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: palette.raised,
            borderRadius: BorderRadius.circular(TableViewMetrics.panelRadius),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
                child: TextField(
                  autofocus: true,
                  style: TextStyle(fontSize: 13, color: palette.textPrimary),
                  onChanged: (value) => setMenuState(() => _search = value),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: palette.sunken,
                    hintText: LocaleKeys.tableViews_searchHint.tr(),
                    hintStyle:
                        TextStyle(fontSize: 13, color: palette.textMuted),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 15,
                      color: palette.textMuted,
                    ),
                    prefixIconConstraints:
                        const BoxConstraints(minWidth: 30, minHeight: 22),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(TableViewMetrics.controlRadius),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Flexible(
                child: matching.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
                        child: Text(
                          LocaleKeys.tableViews_noneMatch.tr(),
                          style: TextStyle(
                            fontSize: 13,
                            color: palette.textMuted,
                          ),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: matching.length,
                        itemBuilder: (_, index) {
                          final row = matching[index];
                          return _RelationOption(
                            palette: palette,
                            label: _nameOf(row),
                            selected: widget.chosen.contains(row.rowId),
                            onTap: () {
                              _toggle(row.rowId);
                              setMenuState(() {});
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// One row of the relation list, with a tick when it has been chosen.
class _RelationOption extends StatefulWidget {
  const _RelationOption({
    required this.palette,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final TableViewPalette palette;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_RelationOption> createState() => _RelationOptionState();
}

class _RelationOptionState extends State<_RelationOption> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: TableViewMetrics.hover,
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: _hovered ? palette.hover : palette.hoverAtRest,
            borderRadius: BorderRadius.circular(TableViewMetrics.controlRadius),
          ),
          child: Row(
            children: [
              Expanded(
                child: TablePill(
                  label: widget.label,
                  colour: palette.swatchFor(widget.label),
                  palette: palette,
                  dense: true,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                widget.selected
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                size: 16,
                color: widget.selected ? palette.accent : palette.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The framed box every typed answer sits in.
class _FormWell extends StatelessWidget {
  const _FormWell({
    required this.palette,
    required this.child,
    this.warn = false,
  });

  final TableViewPalette palette;
  final Widget child;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: TableViewMetrics.hover,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: palette.raised,
        borderRadius: BorderRadius.circular(TableViewMetrics.controlRadius),
        border: Border.all(
          color: warn
              ? palette.swatchFor('due')
              : palette.border.withValues(alpha: 0),
          width: 1.2,
        ),
      ),
      child: child,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.palette,
    required this.title,
    required this.description,
    required this.open,
    required this.onToggle,
  });

  final TableViewPalette palette;
  final String title;
  final String description;
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            TableViewMetrics.space5,
            TableViewMetrics.space4,
            TableViewMetrics.space4,
            TableViewMetrics.space3,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary,
                      ),
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.45,
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              AnimatedRotation(
                duration: TableViewMetrics.change,
                curve: TableViewMetrics.settleCurve,
                turns: open ? 0 : -0.25,
                child: Icon(
                  Icons.expand_more_rounded,
                  size: 18,
                  color: palette.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
