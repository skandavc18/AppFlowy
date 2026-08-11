import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/application/field/field_info.dart';
import 'package:appflowy/plugins/database/application/field/property_style.dart';
import 'package:appflowy/plugins/database/domain/field_service.dart';
import 'package:appflowy/plugins/database/domain/location_service.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_style.dart';
import 'package:appflowy/util/field_type_extension.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/field_entities.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The groups a property type belongs to, in the order they are offered.
enum PropertyTypeGroup {
  basic,
  dateAndTime,
  selection,
  interactive,
  media,
  web,
  advanced;

  String get label => switch (this) {
        PropertyTypeGroup.basic =>
          LocaleKeys.interactive_property_sectionBasic.tr(),
        PropertyTypeGroup.dateAndTime =>
          LocaleKeys.interactive_property_sectionDate.tr(),
        PropertyTypeGroup.selection =>
          LocaleKeys.interactive_property_sectionSelection.tr(),
        PropertyTypeGroup.interactive =>
          LocaleKeys.interactive_property_sectionInteractive.tr(),
        PropertyTypeGroup.media =>
          LocaleKeys.interactive_property_sectionMedia.tr(),
        PropertyTypeGroup.web =>
          LocaleKeys.interactive_property_sectionWeb.tr(),
        PropertyTypeGroup.advanced =>
          LocaleKeys.interactive_property_sectionAdvanced.tr(),
      };
}

/// One row of the property picker.
///
/// A richer property is a stored [fieldType] plus a [style]; the picker never
/// exposes that split, so choosing "Progress" reads as choosing a type.
@immutable
class PropertyTypeEntry {
  const PropertyTypeEntry({
    required this.id,
    required this.group,
    required this.label,
    required this.description,
    required this.icon,
    required this.fieldType,
    this.style,
    this.isLocation = false,
  });

  final String id;
  final PropertyTypeGroup group;
  final String label;
  final String description;
  final IconData icon;
  final FieldType fieldType;

  /// The note written on the column after the type is switched. Null means a
  /// plain column of [fieldType].
  final PropertyStyle? style;

  /// Location is marked through its own registry rather than through a style,
  /// because the map has to be able to ask the backend which columns hold a
  /// place.
  final bool isLocation;

  PropertyStyleKind get kind => style?.kind ?? PropertyStyleKind.plain;

  bool matches(String query) {
    final needle = query.trim().toLowerCase();
    return needle.isEmpty ||
        label.toLowerCase().contains(needle) ||
        description.toLowerCase().contains(needle);
  }
}

/// Every property type the picker offers.
List<PropertyTypeEntry> propertyTypeEntries() => [
      // Basic ---------------------------------------------------------------
      PropertyTypeEntry(
        id: 'text',
        group: PropertyTypeGroup.basic,
        label: FieldType.RichText.i18n,
        description: LocaleKeys.interactive_property_textDesc.tr(),
        icon: Icons.notes_rounded,
        fieldType: FieldType.RichText,
      ),
      PropertyTypeEntry(
        id: 'number',
        group: PropertyTypeGroup.basic,
        label: FieldType.Number.i18n,
        description: LocaleKeys.interactive_property_numberDesc.tr(),
        icon: Icons.tag_rounded,
        fieldType: FieldType.Number,
      ),
      PropertyTypeEntry(
        id: 'checkbox',
        group: PropertyTypeGroup.basic,
        label: FieldType.Checkbox.i18n,
        description: LocaleKeys.interactive_property_checkboxDesc.tr(),
        icon: Icons.check_box_rounded,
        fieldType: FieldType.Checkbox,
      ),
      PropertyTypeEntry(
        id: 'checklist',
        group: PropertyTypeGroup.basic,
        label: FieldType.Checklist.i18n,
        description: LocaleKeys.interactive_property_checklistDesc.tr(),
        icon: Icons.checklist_rounded,
        fieldType: FieldType.Checklist,
      ),

      // Date & time ---------------------------------------------------------
      PropertyTypeEntry(
        id: 'date',
        group: PropertyTypeGroup.dateAndTime,
        label: FieldType.DateTime.i18n,
        description: LocaleKeys.interactive_property_dateDesc.tr(),
        icon: Icons.calendar_today_rounded,
        fieldType: FieldType.DateTime,
      ),
      PropertyTypeEntry(
        id: 'reminder',
        group: PropertyTypeGroup.dateAndTime,
        label: LocaleKeys.interactive_reminder_name.tr(),
        description: LocaleKeys.interactive_property_reminderDesc.tr(),
        icon: Icons.notifications_active_rounded,
        fieldType: FieldType.RichText,
        style: const PropertyStyle(kind: PropertyStyleKind.reminder),
      ),

      // Selection -----------------------------------------------------------
      PropertyTypeEntry(
        id: 'select',
        group: PropertyTypeGroup.selection,
        label: FieldType.SingleSelect.i18n,
        description: LocaleKeys.interactive_property_selectDesc.tr(),
        icon: Icons.arrow_drop_down_circle_rounded,
        fieldType: FieldType.SingleSelect,
      ),
      PropertyTypeEntry(
        id: 'multi_select',
        group: PropertyTypeGroup.selection,
        label: FieldType.MultiSelect.i18n,
        description: LocaleKeys.interactive_property_multiSelectDesc.tr(),
        icon: Icons.checklist_rtl_rounded,
        fieldType: FieldType.MultiSelect,
      ),

      // Interactive ---------------------------------------------------------
      PropertyTypeEntry(
        id: 'progress',
        group: PropertyTypeGroup.interactive,
        label: LocaleKeys.interactive_progress_name.tr(),
        description: LocaleKeys.interactive_property_progressDesc.tr(),
        icon: Icons.speed_rounded,
        fieldType: FieldType.RichText,
        style: const PropertyStyle(kind: PropertyStyleKind.progress),
      ),
      PropertyTypeEntry(
        id: 'counter',
        group: PropertyTypeGroup.interactive,
        label: LocaleKeys.interactive_counter_name.tr(),
        description: LocaleKeys.interactive_property_counterDesc.tr(),
        icon: Icons.exposure_plus_1_rounded,
        fieldType: FieldType.RichText,
        style: const PropertyStyle(kind: PropertyStyleKind.counter),
      ),
      PropertyTypeEntry(
        id: 'button',
        group: PropertyTypeGroup.interactive,
        label: LocaleKeys.interactive_button_name.tr(),
        description: LocaleKeys.interactive_property_buttonDesc.tr(),
        icon: Icons.smart_button_rounded,
        fieldType: FieldType.RichText,
        style: const PropertyStyle(kind: PropertyStyleKind.button),
      ),

      // Media ---------------------------------------------------------------
      for (final media in PropertyMediaKind.values)
        PropertyTypeEntry(
          id: 'media_${media.name}',
          group: PropertyTypeGroup.media,
          label: propertyMediaLabel(media),
          description: propertyMediaDescription(media),
          icon: propertyMediaIcon(media),
          fieldType: FieldType.Media,
          style: media == PropertyMediaKind.files
              ? null
              : PropertyStyle(
                  kind: PropertyStyleKind.media,
                  settings: {'media': media.name},
                ),
        ),

      // Web -----------------------------------------------------------------
      PropertyTypeEntry(
        id: 'url',
        group: PropertyTypeGroup.web,
        label: FieldType.URL.i18n,
        description: LocaleKeys.interactive_property_urlDesc.tr(),
        icon: Icons.link_rounded,
        fieldType: FieldType.URL,
      ),
      PropertyTypeEntry(
        id: 'bookmark',
        group: PropertyTypeGroup.web,
        label: LocaleKeys.interactive_property_bookmark.tr(),
        description: LocaleKeys.interactive_property_bookmarkDesc.tr(),
        icon: Icons.bookmark_rounded,
        fieldType: FieldType.URL,
        style: const PropertyStyle(kind: PropertyStyleKind.link),
      ),

      // Advanced ------------------------------------------------------------
      PropertyTypeEntry(
        id: 'location',
        group: PropertyTypeGroup.advanced,
        label: LocaleKeys.map_locationField.tr(),
        description: LocaleKeys.interactive_property_locationDesc.tr(),
        icon: Icons.place_rounded,
        fieldType: FieldType.RichText,
        isLocation: true,
      ),
      PropertyTypeEntry(
        id: 'relation',
        group: PropertyTypeGroup.advanced,
        label: FieldType.Relation.i18n,
        description: LocaleKeys.interactive_property_relationDesc.tr(),
        icon: Icons.hub_rounded,
        fieldType: FieldType.Relation,
      ),
      PropertyTypeEntry(
        id: 'created',
        group: PropertyTypeGroup.advanced,
        label: FieldType.CreatedTime.i18n,
        description: LocaleKeys.interactive_property_createdDesc.tr(),
        icon: Icons.schedule_rounded,
        fieldType: FieldType.CreatedTime,
      ),
      PropertyTypeEntry(
        id: 'edited',
        group: PropertyTypeGroup.advanced,
        label: FieldType.LastEditedTime.i18n,
        description: LocaleKeys.interactive_property_editedDesc.tr(),
        icon: Icons.history_rounded,
        fieldType: FieldType.LastEditedTime,
      ),
      PropertyTypeEntry(
        id: 'summary',
        group: PropertyTypeGroup.advanced,
        label: FieldType.Summary.i18n,
        description: LocaleKeys.interactive_property_summaryDesc.tr(),
        icon: Icons.auto_awesome_rounded,
        fieldType: FieldType.Summary,
      ),
      PropertyTypeEntry(
        id: 'translate',
        group: PropertyTypeGroup.advanced,
        label: FieldType.Translate.i18n,
        description: LocaleKeys.interactive_property_translateDesc.tr(),
        icon: Icons.translate_rounded,
        fieldType: FieldType.Translate,
      ),
    ];

String propertyMediaLabel(PropertyMediaKind kind) => switch (kind) {
      // The generic attachment column keeps the name the rest of the
      // application already uses for it.
      PropertyMediaKind.files => FieldType.Media.i18n,
      PropertyMediaKind.photo => LocaleKeys.interactive_property_photo.tr(),
      PropertyMediaKind.video => LocaleKeys.interactive_property_video.tr(),
      PropertyMediaKind.audio => LocaleKeys.interactive_property_audio.tr(),
      PropertyMediaKind.pdf => LocaleKeys.interactive_property_pdf.tr(),
    };

String propertyMediaDescription(PropertyMediaKind kind) => switch (kind) {
      PropertyMediaKind.files => LocaleKeys.interactive_property_filesDesc.tr(),
      PropertyMediaKind.photo => LocaleKeys.interactive_property_photoDesc.tr(),
      PropertyMediaKind.video => LocaleKeys.interactive_property_videoDesc.tr(),
      PropertyMediaKind.audio => LocaleKeys.interactive_property_audioDesc.tr(),
      PropertyMediaKind.pdf => LocaleKeys.interactive_property_pdfDesc.tr(),
    };

IconData propertyMediaIcon(PropertyMediaKind kind) => switch (kind) {
      PropertyMediaKind.files => Icons.attach_file_rounded,
      PropertyMediaKind.photo => Icons.photo_rounded,
      PropertyMediaKind.video => Icons.movie_rounded,
      PropertyMediaKind.audio => Icons.graphic_eq_rounded,
      PropertyMediaKind.pdf => Icons.picture_as_pdf_rounded,
    };

/// What a column of [fieldType] wearing [style] is called and drawn with.
PropertyTypeEntry? propertyTypeEntryFor({
  required FieldType fieldType,
  PropertyStyle? style,
  bool isLocation = false,
}) {
  final entries = propertyTypeEntries();
  if (isLocation) {
    return entries.firstWhere((entry) => entry.isLocation);
  }
  final kind = style?.kind ?? PropertyStyleKind.plain;
  for (final entry in entries) {
    if (entry.fieldType != fieldType || entry.kind != kind) {
      continue;
    }
    if (kind == PropertyStyleKind.media) {
      final wanted = entry.style?.mediaKind;
      if (wanted != style?.mediaKind) {
        continue;
      }
    }
    return entry;
  }
  return null;
}

/// Turns a column into the chosen property type.
///
/// The stored type is switched first and awaited, because it rewrites the
/// column's options — the note that says how to draw it has to land after
/// that, not beside it.
Future<void> applyPropertyType({
  required String viewId,
  required FieldInfo fieldInfo,
  required PropertyTypeEntry chosen,
  PropertyTypeEntry? previous,
  bool wasLocation = false,
}) async {
  final fieldId = fieldInfo.id;
  final current = fieldInfo.fieldType;
  final name = fieldInfo.name;

  // A column nobody has named still says what it is, so it should say the new
  // thing rather than keep announcing itself as Text.
  final unnamed =
      name.isEmpty || name == previous?.label || name == current.i18n;

  if (current != chosen.fieldType) {
    await FieldBackendService.updateFieldType(
      viewId: viewId,
      fieldId: fieldId,
      fieldType: chosen.fieldType,
      fieldName: unnamed ? chosen.label : null,
    );
  } else if (unnamed && name != chosen.label) {
    await FieldBackendService(viewId: viewId, fieldId: fieldId)
        .updateField(name: chosen.label);
  }

  if (wasLocation != chosen.isLocation) {
    await LocationFieldRegistry.instance.setLocation(
      viewId: viewId,
      fieldId: fieldId,
      enabled: chosen.isLocation,
    );
  }

  // Alignment belongs to the column, not to the type it happens to wear.
  final align = PropertyStyleRegistry.instance.styleFor(viewId, fieldId)?.align;
  var style = chosen.style;
  if (align != null) {
    style = (style ?? const PropertyStyle(kind: PropertyStyleKind.plain))
        .withSetting('align', align.name);
  }
  await PropertyStyleRegistry.instance.setStyle(
    viewId: viewId,
    fieldId: fieldId,
    style: style,
  );
}

/// The picker itself: grouped, searchable and described.
class PropertyTypePicker extends StatefulWidget {
  const PropertyTypePicker({
    super.key,
    required this.onSelected,
    this.selectedId,
  });

  final ValueChanged<PropertyTypeEntry> onSelected;
  final String? selectedId;

  @override
  State<PropertyTypePicker> createState() => _PropertyTypePickerState();
}

class _PropertyTypePickerState extends State<PropertyTypePicker> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'property type picker');
  int _highlighted = 0;

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<PropertyTypeEntry> get _matches => propertyTypeEntries()
      .where((entry) => entry.matches(_query.text))
      .toList();

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final matches = _matches;
    if (matches.isEmpty) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        setState(() => _highlighted = (_highlighted + 1) % matches.length);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        setState(
          () => _highlighted =
              (_highlighted - 1 + matches.length) % matches.length,
        );
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        widget.onSelected(matches[_highlighted.clamp(0, matches.length - 1)]);
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final palette = interactivePaletteOf(context);
    final matches = _matches;

    PropertyTypeGroup? previous;
    final rows = <Widget>[];
    for (var i = 0; i < matches.length; i++) {
      final entry = matches[i];
      if (entry.group != previous) {
        previous = entry.group;
        rows.add(
          Padding(
            padding: EdgeInsets.fromLTRB(10, rows.isEmpty ? 4 : 12, 10, 4),
            child: Text(
              entry.group.label,
              style: InteractiveType.label(palette).copyWith(fontSize: 10.5),
            ),
          ),
        );
      }
      rows.add(
        _PropertyRow(
          entry: entry,
          palette: palette,
          selected: entry.id == widget.selectedId,
          highlighted: i == _highlighted,
          onTap: () => widget.onSelected(entry),
        ),
      );
    }

    return SizedBox(
      width: 292,
      child: Focus(
        focusNode: _focus,
        onKeyEvent: _onKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
              child: InteractiveFieldSurface(
                focused: false,
                palette: palette,
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 9),
                child: Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                      size: 15,
                      color: palette.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _query,
                        autofocus: true,
                        onChanged: (_) => setState(() => _highlighted = 0),
                        style: InteractiveType.body(palette)
                            .copyWith(fontSize: 13),
                        cursorColor: palette.accent,
                        decoration: InputDecoration(
                          isCollapsed: true,
                          border: InputBorder.none,
                          filled: false,
                          hintText: LocaleKeys.interactive_property_search.tr(),
                          hintStyle: InteractiveType.caption(palette),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 2),
            Flexible(
              child: matches.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 22),
                      child: Text(
                        LocaleKeys.interactive_selector_noMatches.tr(),
                        textAlign: TextAlign.center,
                        style: InteractiveType.caption(palette),
                      ),
                    )
                  : ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                      children: rows,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PropertyRow extends StatefulWidget {
  const _PropertyRow({
    required this.entry,
    required this.palette,
    required this.selected,
    required this.highlighted,
    required this.onTap,
  });

  final PropertyTypeEntry entry;
  final InteractivePalette palette;
  final bool selected;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  State<_PropertyRow> createState() => _PropertyRowState();
}

class _PropertyRowState extends State<_PropertyRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final active = _hovered || widget.highlighted;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: InteractiveMetrics.hover,
          curve: InteractiveMetrics.curve,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: widget.selected
                ? palette.accent.withValues(alpha: palette.isDark ? 0.18 : 0.10)
                : active
                    ? palette.hover
                    : palette.hoverBase,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: palette.accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  widget.entry.icon,
                  size: 15,
                  color: palette.accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.entry.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: InteractiveType.strong(palette, size: 13),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      widget.entry.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: InteractiveType.caption(palette)
                          .copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
              if (widget.selected)
                Icon(Icons.check_rounded, size: 16, color: palette.accent),
            ],
          ),
        ),
      ),
    );
  }
}
