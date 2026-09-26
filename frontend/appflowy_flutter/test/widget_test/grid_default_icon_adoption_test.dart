import 'dart:async';
import 'dart:ui' as ui;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/application/database_controller.dart';
import 'package:appflowy/plugins/database/application/field/field_controller.dart';
import 'package:appflowy/plugins/database/application/field/field_info.dart';
import 'package:appflowy/plugins/database/application/field/filter_entities.dart';
import 'package:appflowy/plugins/database/application/field/sort_entities.dart';
import 'package:appflowy/plugins/database/grid/presentation/grid_page.dart';
import 'package:appflowy/plugins/database/grid/presentation/widgets/header/column_heading_menu.dart';
import 'package:appflowy/plugins/database/grid/presentation/widgets/header/desktop_field_cell.dart';
import 'package:appflowy/plugins/database/grid/presentation/widgets/toolbar/filter_button.dart';
import 'package:appflowy/plugins/database/grid/presentation/widgets/toolbar/grid_setting_bar.dart';
import 'package:appflowy/plugins/database/grid/presentation/widgets/toolbar/sort_button.dart';
import 'package:appflowy/plugins/database/grid/presentation/widgets/toolbar/view_database_button.dart';
import 'package:appflowy/plugins/database/widgets/field/field_editor.dart';
import 'package:appflowy/plugins/database/widgets/field/property_type_picker.dart';
import 'package:appflowy/plugins/database/widgets/setting/database_settings_list.dart';
import 'package:appflowy/plugins/database/widgets/setting/setting_button.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/mention/mention_page_block.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/icon_emoji_picker/default_icon_artwork.dart';
import 'package:appflowy/shared/icon_emoji_picker/default_icons.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/vivid_icon_artwork.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/util/field_type_extension.dart';
import 'package:appflowy/workspace/application/settings/default_icon_style.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_svg/flowy_svg.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'vivid_icon_test_support.dart' show settleVividIconPictures;
import 'workspace_overlay_test_app.dart';

final _fieldNames = <FieldType, String>{
  FieldType.RichText: 'text',
  FieldType.Number: 'hash',
  FieldType.DateTime: 'calendar-blank',
  FieldType.SingleSelect: 'select',
  FieldType.MultiSelect: 'list-checks',
  FieldType.Checkbox: 'checkbox',
  FieldType.Checklist: 'list-checks',
  FieldType.URL: 'link-simple',
  FieldType.LastEditedTime: 'clock',
  FieldType.CreatedTime: 'clock',
  FieldType.Relation: 'connections',
  FieldType.Summary: 'sparkles',
  FieldType.Time: 'clock',
  FieldType.Translate: 'translate',
  FieldType.Media: 'attachment',
};

void main() {
  setUpAll(initializeWorkspaceOverlayTests);
  setUp(WorkspaceGlyphs.clearUnknownMappings);

  test(
    'logged code points retain their SDK meanings and original outlines',
    () {
      final aliases = [
        (Icons.toc_rounded, 0xf023e, 'table-of-contents'),
        (Icons.queue_music_rounded, 0xf00d0, 'music-list'),
        (Icons.apps_rounded, 0xf56d, 'squares-nine'),
        (Icons.reorder_rounded, 0xf00f3, 'reorder'),
      ];
      for (final (icon, codePoint, name) in aliases) {
        expect(icon.codePoint, codePoint);
        expect(WorkspaceGlyphs.nameForIcon(icon), name);
        final svg = defaultIconSvg(name)!;
        for (final attribute in [
          'viewBox="0 0 24 24"',
          'stroke-width="1.75"',
          'stroke-linecap="round"',
          'stroke-linejoin="round"',
        ]) {
          expect(svg, contains(attribute));
        }
        expect(WorkspaceGlyphs.vividNameFor(name), 'utility-$name');
        final vivid = vividIconSvg('utility-$name')!;
        expect(vivid, contains('<linearGradient id="utility"'));
        expect(
          vivid,
          contains(
            svg
                .substring(svg.indexOf('>') + 1, svg.lastIndexOf('</svg>'))
                .replaceAll('currentColor', 'url(#utility)'),
          ),
        );
      }
      expect(_fieldNames.keys, unorderedEquals(FieldType.values));
    },
  );

  for (final appearance in ['light', 'dark', 'paper']) {
    testWidgets(
      '$appearance: real grid toolbar and settings follow the style',
      (tester) async {
        final styles = ValueNotifier(DefaultIconStyle.monochrome);
        final controller = _Controller();
        final toggle = ToggleExtensionNotifier();
        addTearDown(styles.dispose);
        addTearDown(controller.isLoading.dispose);
        addTearDown(toggle.dispose);
        await _mount(
          tester,
          appearance,
          styles,
          Provider<ReferenceState>.value(
            value: ReferenceState(true),
            child:
                GridSettingBar(controller: controller, toggleExtension: toggle),
          ),
        );
        final bar = find.byType(GridSettingBar);
        final element = tester.element(bar);
        final rect = tester.getRect(bar);
        final buttons = {
          FilterButton: 'filter',
          SortButton: 'sort',
          ViewDatabaseButton: 'external-link',
          SettingButton: 'gear',
        };
        for (final style in DefaultIconStyle.values) {
          styles.value = style;
          await settleVividIconPictures(tester);
          for (final button in buttons.entries) {
            _expectGlyph(tester, find.byType(button.key), button.value, style);
          }
          expect(tester.element(bar), same(element));
          expect(tester.getRect(bar), rect);
          expect(toggle.isToggled, isFalse);
        }
        await tester.tap(
          find.descendant(
            of: find.byType(SettingButton),
            matching: find.byType(RawMaterialButton),
          ),
        );
        await settleVividIconPictures(tester);
        final menu = find.byType(DatabaseSettingsList);
        expect(menu, findsOneWidget);
        final menuElement = tester.element(menu);
        for (final style in DefaultIconStyle.values.reversed) {
          styles.value = style;
          await settleVividIconPictures(tester);
          _expectGlyph(tester, menu, 'list-checks', style);
          _expectGlyph(tester, menu, 'layout', style);
          expect(tester.element(menu), same(menuElement));
        }
        expect(WorkspaceGlyphs.unknownMappings, isEmpty);
        await tester.tapAt(const Offset(4, 4));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      '$appearance: field defaults change but saved artwork does not',
      (tester) async {
        final styles = ValueNotifier(DefaultIconStyle.monochrome);
        addTearDown(styles.dispose);
        final previousGroups = kIconGroups;
        kIconGroups = appFlowyDefaultIconGroups;
        addTearDown(() => kIconGroups = previousGroups);
        final saved = FieldPB(
          id: 'saved',
          name: 'Saved artwork',
          fieldType: FieldType.RichText,
          icon: '${appFlowyDefaultIconGroupPrefix}collections/book',
        );
        final bytes = saved.writeToBuffer();
        var taps = 0;
        await _mount(
          tester,
          appearance,
          styles,
          SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  children: [
                    for (final type in FieldType.values)
                      FieldIcon(
                        key: ValueKey(type.name),
                        fieldInfo: FieldInfo.initial(FieldPB(fieldType: type)),
                      ),
                  ],
                ),
                FieldCellButton(field: saved, onTap: () => taps++),
              ],
            ),
          ),
        );
        final custom = find.descendant(
          of: find.byType(FieldCellButton),
          matching: find.byType(FlowySvg),
        );
        final customElement = tester.element(custom);
        final before = tester.widget<FlowySvg>(custom);
        expect(before.svgString, defaultIconSvg('book-open'));
        for (final style in DefaultIconStyle.values) {
          styles.value = style;
          await settleVividIconPictures(tester);
          for (final entry in _fieldNames.entries) {
            _expectGlyph(
              tester,
              find.byKey(ValueKey(entry.key.name)),
              entry.value,
              style,
            );
          }
          expect(tester.element(custom), same(customElement));
          final after = tester.widget<FlowySvg>(custom);
          expect(after.svgString, before.svgString);
          expect(after.color, before.color);
          expect(after.blendMode, before.blendMode);
          expect(after.size, before.size);
          expect(saved.writeToBuffer(), bytes);
        }
        await tester.tap(find.byType(FieldCellButton));
        expect(taps, 1);
        expect(WorkspaceGlyphs.unknownMappings, isEmpty);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      '$appearance: property picker keeps its draft and keyboard action',
      (tester) async {
        final styles = ValueNotifier(DefaultIconStyle.monochrome);
        addTearDown(styles.dispose);
        PropertyTypeEntry? chosen;
        await _mount(
          tester,
          appearance,
          styles,
          SizedBox(
            width: 292,
            height: 400,
            child: PropertyTypePicker(
              selectedId: 'date',
              onSelected: (entry) => chosen = entry,
            ),
          ),
        );
        final query = find.byType(TextField);
        final label = FieldType.DateTime.i18n;
        await tester.enterText(query, label);
        await tester.pumpAndSettle();
        final controller = tester.widget<TextField>(query).controller!;
        final row = find
            .ancestor(
              of: find.byWidgetPredicate(
                (widget) => widget is Text && widget.data == label,
              ),
              matching: find.byType(GestureDetector),
            )
            .first;
        final element = tester.element(row);
        for (final style in DefaultIconStyle.values) {
          styles.value = style;
          await settleVividIconPictures(tester);
          _expectGlyph(tester, row, 'calendar-blank', style);
          expect(tester.element(row), same(element));
          expect(tester.widget<TextField>(query).controller, same(controller));
          expect(controller.text, FieldType.DateTime.i18n);
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(chosen?.id, 'date');
        expect(WorkspaceGlyphs.unknownMappings, isEmpty);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      '$appearance: property actions preserve disabled and error ink',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final styles = ValueNotifier(DefaultIconStyle.vivid);
        final primary = FieldInfo.initial(
          FieldPB(
            id: 'primary',
            name: 'Name',
            fieldType: FieldType.RichText,
            isPrimary: true,
          ),
        );
        var edits = 0;
        try {
          await _mount(
            tester,
            appearance,
            styles,
            SizedBox(
              width: 300,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FieldActionCell(
                    key: const ValueKey('disabled-delete'),
                    viewId: 'icon-test',
                    fieldInfo: primary,
                    action: FieldAction.delete,
                  ),
                  FieldActionCell(
                    key: const ValueKey('delete'),
                    viewId: 'icon-test',
                    fieldInfo: FieldInfo.initial(FieldPB(id: 'other')),
                    action: FieldAction.delete,
                  ),
                  Builder(
                    builder: (context) => TextButton(
                      onPressed: () => unawaited(
                        showColumnHeadingMenu(
                          context: context,
                          globalPosition: const Offset(30, 30),
                          viewId: 'icon-test',
                          fieldInfo: primary,
                          onEditProperty: () => edits++,
                        ),
                      ),
                      child: const Text('Column menu'),
                    ),
                  ),
                ],
              ),
            ),
          );
          final disabled = find.byKey(const ValueKey('disabled-delete'));
          final theme = Theme.of(tester.element(disabled));
          expect(
            tester
                .widget<FlowyIconTextButton>(
                  find.descendant(
                    of: disabled,
                    matching: find.byType(FlowyIconTextButton),
                  ),
                )
                .disable,
            isTrue,
          );
          await tester.tap(disabled);
          final mouse =
              await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
          await mouse.addPointer(
            location: tester.getCenter(find.byKey(const ValueKey('delete'))),
          );
          for (final style in DefaultIconStyle.values) {
            styles.value = style;
            await settleVividIconPictures(tester);
            _expectGlyph(
              tester,
              disabled,
              'trash',
              style,
              stateInk: theme.disabledColor,
            );
            _expectGlyph(
              tester,
              find.byKey(const ValueKey('delete')),
              'trash',
              style,
              stateInk: theme.colorScheme.error,
            );
          }
          await mouse.removePointer();
          await tester.tap(find.text('Column menu'));
          await settleVividIconPictures(tester);
          final typeRow = find.widgetWithText(
            AppMenuRow,
            LocaleKeys.interactive_property_type.tr(),
          );
          final data = tester.getSemantics(typeRow).getSemanticsData();
          expect(data.hasFlag(ui.SemanticsFlag.isButton), isTrue);
          expect(data.hasFlag(ui.SemanticsFlag.isEnabled), isFalse);
          expect(data.hasAction(ui.SemanticsAction.tap), isFalse);
          _expectGlyph(
            tester,
            typeRow,
            'text',
            styles.value,
            stateInk: AppMenuStyle.of(tester.element(typeRow)).iconColorFor(
              enabled: false,
              destructive: false,
              selected: false,
            ),
          );
          await tester.tap(typeRow);
          await tester.pumpAndSettle();
          expect(typeRow, findsOneWidget);
          await tester.tap(
            find.widgetWithText(
              AppMenuRow,
              LocaleKeys.grid_field_editProperty.tr(),
            ),
          );
          await tester.pumpAndSettle();
          expect(edits, 1);
          expect(find.byType(AppMenuRow), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          semantics.dispose();
          styles.dispose();
        }
      },
    );
  }
}

Future<void> _mount(
  WidgetTester tester,
  String appearance,
  ValueNotifier<DefaultIconStyle> styles,
  Widget child,
) async {
  await tester.pumpWidget(
    DefaultIconStyleScope(
      styles: styles,
      child: workspaceOverlayTestApp(
        appearance: appearance,
        child: Center(child: child),
      ),
    ),
  );
  // Localization must finish before finding controls; then decode actual SVGs.
  await settleVividIconPictures(tester);
}

void _expectGlyph(
  WidgetTester tester,
  Finder root,
  String name,
  DefaultIconStyle style, {
  Color? stateInk,
}) {
  final glyph = find.descendant(
    of: root,
    matching: find.byWidgetPredicate(
      (widget) => widget is WorkspaceGlyph && widget.name == name,
    ),
  );
  expect(glyph, findsOneWidget);
  final context = tester.element(glyph);
  final widget = tester.widget<WorkspaceGlyph>(glyph);
  if (stateInk != null) {
    expect(widget.role, WorkspaceGlyphRole.preserveInk);
  }
  final vivid = style == DefaultIconStyle.vivid && stateInk == null;
  final art = vivid
      ? vividIconSvg(WorkspaceGlyphs.vividNameFor(name)!)!
      : defaultIconSvg(name)!;
  final picture = tester.widget<SvgPicture>(
    find.descendant(of: glyph, matching: find.byType(SvgPicture)),
  );
  final loader = picture.bytesLoader as SvgStringLoader;
  expect(
    loader,
    SvgStringLoader(art, theme: loader.theme, colorMapper: loader.colorMapper),
  );
  expect(picture.width, widget.size);
  expect(picture.height, widget.size);
  expect(
    picture.colorFilter,
    vivid
        ? isNull
        : ColorFilter.mode(
            stateInk ?? workspaceGlyphInk(context),
            BlendMode.srcIn,
          ),
  );
}

class _Controller extends Fake implements DatabaseController {
  @override
  final view = ViewPB(id: 'icon-test', layout: ViewLayoutPB.Grid);
  @override
  String get viewId => view.id;
  @override
  final isLoading = ValueNotifier(false);
  @override
  final FieldController fieldController = _Fields();
  @override
  DatabaseLayoutPB get databaseLayout => DatabaseLayoutPB.Grid;
}

class _Fields extends Fake implements FieldController {
  @override
  List<FieldInfo> get fieldInfos => [];
  @override
  List<DatabaseFilter> get filters => [];
  @override
  List<DatabaseSort> get sorts => [];
  @override
  void addListener({
    OnReceiveFields? onReceiveFields,
    OnReceiveUpdateFields? onFieldsChanged,
    OnReceiveFilters? onFilters,
    OnReceiveSorts? onSorts,
    bool Function()? listenWhen,
  }) {}
  @override
  void removeListener({
    OnReceiveFields? onFieldsListener,
    OnReceiveSorts? onSortsListener,
    OnReceiveFilters? onFiltersListener,
    OnReceiveUpdateFields? onChangesetListener,
  }) {}
}
