import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/maps/map_style.dart';
import 'package:appflowy/shared/maps/map_suggestions.dart';
import 'package:appflowy/plugins/database/widgets/cell/desktop_grid/location_picker_card.dart';
import 'package:appflowy/shared/table_views/table_property_view.dart';
import 'package:appflowy/shared/table_views/table_view_chrome.dart';
import 'package:appflowy/shared/table_views/table_view_style.dart';
import 'package:appflowy/workspace/application/table_views/form_spec.dart';
import 'package:appflowy/workspace/application/table_views/table_query.dart';
import 'package:appflowy/workspace/application/table_views/table_row.dart';
import 'package:appflowy/workspace/application/table_views/table_row_source.dart';
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
    this.padding = EdgeInsets.zero,
  });

  final String viewId;
  final FormSpec spec;
  final ValueChanged<FormSpec> onSpecChanged;
  final String? title;

  /// Making the row the form describes. Hands back the row it made.
  final FormSubmit? onSubmit;

  final ValueChanged<String>? onOpenRow;

  final EdgeInsets padding;

  @override
  State<FormStage> createState() => FormStageState();
}

class FormStageState extends State<FormStage> {
  late final TableRowSource _source = TableRowSource(viewId: widget.viewId);
  final ScrollController _scroll = ScrollController();
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, FocusNode> _focusNodes = {};
  final Map<String, String> _answers = {};
  final Set<String> _collapsed = {};

  List<String> _missing = const [];
  String? _addedRowId;
  bool _submitting = false;

  static const double measure = 640;

  @override
  void initState() {
    super.initState();
    _source
      ..updateSpec(const TableReadSpec())
      ..addListener(_onSourceChanged);
    unawaited(_source.load());
  }

  @override
  void dispose() {
    _source.removeListener(_onSourceChanged);
    _source.dispose();
    _scroll.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  /// Reads the table again — the host calls this when a column changes.
  void reload() => _source.invalidate();

  void _onSourceChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  TextEditingController _controllerFor(String fieldId) =>
      _controllers.putIfAbsent(
        fieldId,
        () => TextEditingController(text: _answers[fieldId] ?? ''),
      );

  FocusNode _focusFor(String fieldId) =>
      _focusNodes.putIfAbsent(fieldId, FocusNode.new);

  void _answer(String fieldId, String value) {
    _answers[fieldId] = value;
    if (_missing.contains(fieldId) && value.trim().isNotEmpty) {
      setState(() => _missing = [..._missing]..remove(fieldId));
    }
  }

  // ------------------------------------------------------------------ layout

  @override
  Widget build(BuildContext context) {
    final palette = tableViewPaletteOf(context);
    final fields = formFieldsOf(_source.fields, widget.spec);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _submit,
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): _submit,
      },
      child: Padding(
        padding: widget.padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(palette, fields),
            const SizedBox(height: TableViewMetrics.space3),
            Expanded(child: _buildBody(palette, fields)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(TableViewPalette palette, List<FieldPB> fields) =>
      TableViewHeader(
        palette: palette,
        title: widget.title?.trim().isNotEmpty == true
            ? widget.title!
            : LocaleKeys.form_name.tr(),
        subtitle: LocaleKeys.form_fieldCount
            .tr(namedArgs: {'count': '${fields.length}'}),
        columns: const [],
        query: const TableQuery(),
        onQueryChanged: (_) {},
        valuesOf: (_) => const [],
        optionsBuilder: () => _options(fields),
        allowGrouping: false,
      );

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
    if (fields.isEmpty) {
      return TableViewEmpty(
        palette: palette,
        icon: Icons.assignment_rounded,
        message: LocaleKeys.form_empty.tr(),
        detail: LocaleKeys.form_emptyDetail.tr(),
      );
    }

    final sections = formSectionsOf(_source.fields, widget.spec);
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
    final heading = widget.spec.heading.trim().isEmpty
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
              Text(
                field.name,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
              if (required) ...[
                const SizedBox(width: 6),
                Text(
                  '*',
                  style: TextStyle(fontSize: 13.5, color: palette.accent),
                ),
              ],
              const Spacer(),
              _FieldMenuButton(
                palette: palette,
                field: field,
                spec: widget.spec,
                onSpecChanged: widget.onSpecChanged,
              ),
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
          _buildControl(palette, field, missing),
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
    final control = formControlOf(
      field,
      isLocation: _source.locationColumns.contains(field.id),
    );
    return switch (control) {
      FormControl.toggle => _buildToggle(palette, field),
      FormControl.rating => _buildRating(palette, field),
      FormControl.choice => _buildChoice(palette, field, missing),
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
        controller: _controllerFor(field.id),
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
    return GestureDetector(
      onTap: () => setState(() => _answer(field.id, on ? 'No' : 'Yes')),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: TableViewMetrics.hover,
            curve: TableViewMetrics.enterCurve,
            width: 40,
            height: 23,
            padding: const EdgeInsets.all(3),
            alignment: on ? Alignment.centerRight : Alignment.centerLeft,
            decoration: BoxDecoration(
              color: on
                  ? palette.accent
                  : palette.textMuted.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Container(
              width: 17,
              height: 17,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            on ? 'Yes' : 'No',
            style: TextStyle(fontSize: 13.5, color: palette.textSecondary),
          ),
        ],
      ),
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
    final options = tableValuesOf(_source.cards, field.id);
    final chosen = _answers[field.id] ?? '';
    if (options.isEmpty) {
      return _buildText(palette, field, missing, lines: 1);
    }
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (final option in options)
          _ChoiceChip(
            palette: palette,
            label: option,
            selected: chosen == option,
            onTap: () => setState(
              () => _answer(field.id, chosen == option ? '' : option),
            ),
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
                Text(
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
    final added = _addedRowId;
    return Row(
      children: [
        TableViewAction(
          palette: palette,
          label: _submitting
              ? LocaleKeys.tableViews_loading.tr()
              : LocaleKeys.form_submit.tr(),
          icon: Icons.check_rounded,
          onTap: _submit,
        ),
        const SizedBox(width: TableViewMetrics.space3),
        TableViewAction(
          palette: palette,
          label: LocaleKeys.form_clear.tr(),
          icon: Icons.backspace_rounded,
          primary: false,
          onTap: _clear,
        ),
        const Spacer(),
        if (added != null)
          Row(
            children: [
              Icon(
                Icons.check_circle_rounded,
                size: 15,
                color: palette.swatchFor('done'),
              ),
              const SizedBox(width: 7),
              Text(
                LocaleKeys.form_added.tr(),
                style: TextStyle(fontSize: 12.5, color: palette.textMuted),
              ),
              if (widget.onOpenRow != null) ...[
                const SizedBox(width: TableViewMetrics.space3),
                TableViewAction(
                  palette: palette,
                  label: LocaleKeys.tableViews_openRow.tr(),
                  primary: false,
                  onTap: () => widget.onOpenRow!(added),
                ),
              ],
            ],
          ),
      ],
    );
  }

  void _clear() {
    setState(() {
      _answers.clear();
      _missing = const [];
      _addedRowId = null;
      for (final controller in _controllers.values) {
        controller.clear();
      }
    });
  }

  void _submit() {
    final submit = widget.onSubmit;
    if (submit == null || _submitting) {
      return;
    }
    final missing = missingRequiredFields(widget.spec, _answers);
    if (missing.isNotEmpty) {
      setState(() => _missing = missing);
      return;
    }
    final answers = {
      for (final entry in _answers.entries)
        if (entry.value.trim().isNotEmpty) entry.key: entry.value.trim(),
    };
    if (answers.isEmpty) {
      return;
    }
    setState(() => _submitting = true);
    unawaited(
      submit(answers).then((rowId) {
        if (!mounted) {
          return;
        }
        setState(() {
          _submitting = false;
          _addedRowId = rowId;
          if (rowId != null) {
            _answers.clear();
            _missing = const [];
            for (final controller in _controllers.values) {
              controller.clear();
            }
          }
        });
      }),
    );
  }

  List<AppMenuEntry> _options(List<FieldPB> fields) => [
        AppMenuHeader(LocaleKeys.form_layout.tr()),
        AppMenuItem(
          label: LocaleKeys.form_showAll.tr(),
          icon: Icons.visibility_rounded,
          enabled: widget.spec.hiddenColumns.isNotEmpty,
          onSelected: () => widget
              .onSpecChanged(widget.spec.copyWith(hiddenColumns: const [])),
        ),
        const AppMenuSeparator(),
        AppMenuItem(
          label: LocaleKeys.form_clear.tr(),
          icon: Icons.backspace_rounded,
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

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
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
  Widget build(BuildContext context) {
    final colour = palette.swatchFor(label);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: TableViewMetrics.hover,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: colour.withValues(
              alpha: selected ? (palette.isDark ? 0.4 : 0.22) : 0.1,
            ),
            borderRadius: BorderRadius.circular(TableViewMetrics.pillRadius),
            border: Border.all(
              color: selected ? colour : colour.withValues(alpha: 0),
              width: 1.2,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: palette.isDark
                  ? Color.lerp(colour, Colors.white, 0.5)
                  : Color.lerp(colour, Colors.black, 0.4),
            ),
          ),
        ),
      ),
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

/// The little menu beside a field that says how it should be asked for.
class _FieldMenuButton extends StatelessWidget {
  const _FieldMenuButton({
    required this.palette,
    required this.field,
    required this.spec,
    required this.onSpecChanged,
  });

  final TableViewPalette palette;
  final FieldPB field;
  final FormSpec spec;
  final ValueChanged<FormSpec> onSpecChanged;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) => TableViewButton(
        palette: palette,
        icon: Icons.more_horiz_rounded,
        onTap: () => unawaited(
          showAppMenuForWidget<void>(
            context: context,
            entries: [
              AppMenuItem(
                label: LocaleKeys.form_required.tr(),
                icon: Icons.priority_high_rounded,
                selected: spec.isRequired(field.id),
                onSelected: () => onSpecChanged(
                  spec.withRequired(field.id, !spec.isRequired(field.id)),
                ),
              ),
              AppMenuItem(
                label: LocaleKeys.tableViews_showEmpty.tr(),
                icon: Icons.visibility_off_rounded,
                onSelected: () =>
                    onSpecChanged(spec.withHidden(field.id, true)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
