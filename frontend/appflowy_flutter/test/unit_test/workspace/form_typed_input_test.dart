import 'package:appflowy/plugins/database/application/field/property_style.dart';
import 'package:appflowy/plugins/database/widgets/cell/desktop_grid/location_picker_card.dart';
import 'package:appflowy/plugins/database/widgets/cell/property_style_cell.dart';
import 'package:appflowy/shared/maps/app_map_view.dart';
import 'package:appflowy/shared/maps/map_location.dart';
import 'package:appflowy/shared/table_views/form_field_input.dart';
import 'package:appflowy/shared/table_views/form_stage.dart';
import 'package:appflowy/shared/table_views/form_typed_field.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/table_views/form_entry_service.dart';
import 'package:appflowy/workspace/application/table_views/form_field_value.dart';
import 'package:appflowy/workspace/application/table_views/form_spec.dart';
import 'package:appflowy/workspace/presentation/widgets/date_picker/desktop_date_picker.dart';
import 'package:appflowy/workspace/presentation/widgets/date_picker/widgets/date_time_text_field.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:cross_file/cross_file.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../widget_test/test_asset_bundle.dart';
import 'form_test_backend.dart';

void main() {
  late MemoryFormBackend backend;
  late MemoryFormSource source;
  late _FilePicks picks;
  late FieldPB field;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
  });
  setUp(() {
    backend = MemoryFormBackend();
    backend.columns.removeRange(1, backend.columns.length);
    backend.rows['entry'] = {'title': 'Example'};
    picks = _FilePicks();
  });
  tearDown(() => source.dispose());

  Future<void> mount(
    WidgetTester tester,
    String appearance,
    FieldType type, {
    String name = 'Value',
    FormFieldValue? value,
    bool location = false,
    bool draft = false,
    bool editable = true,
    PropertyStyle? style,
    double width = 1100,
    double scale = 1,
    ValueChanged<String>? openRow,
  }) async {
    field = FieldPB(id: 'value', name: name, fieldType: type);
    if (type == FieldType.DateTime) {
      field.typeOptionData = DateTypeOptionPB(
        dateFormat: DateFormatPB.ISO,
        timeFormat: TimeFormatPB.TwentyFourHour,
      ).writeToBuffer();
    }
    backend.columns.add(field);
    if (location) backend.locations.add(field.id);
    if (style != null) backend.styles[field.id] = style;
    if (value != null) {
      backend.typedRows['entry'] = {field.id: value};
      backend.rows['entry']![field.id] = value.text;
    }
    if (draft) backend.rows.clear();
    source = MemoryFormSource(backend);
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        appearance,
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: FormStage(
              viewId: '',
              title: 'Examples',
              source: source,
              entryService: FormEntryService(viewId: '', backend: backend),
              inputServices: picks,
              spec: const FormSpec(),
              onSpecChanged: (_) {},
              editable: editable,
              onOpenRow: openRow,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final mode in ['light', 'dark', 'paper']) {
    testWidgets(
        '$mode: a location opens the actual map selector and saves a pin',
        (tester) async {
      await mount(
        tester,
        mode,
        FieldType.RichText,
        location: true,
        value: const FormTextValue(''),
      );
      expect(find.byType(FormTypedField), findsOneWidget);
      await tester.tap(_key('form-location-value'));
      await tester.pumpAndSettle();
      expect(find.byType(LocationPickerCard), findsOneWidget);
      await tester.tap(find.byType(AppMapView));
      // The map keeps double-click zoom; a single click resolves after it.
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(backend.writes, isEmpty);
      final text = tester
          .widget<TextField>(_key('form-location-value'))
          .controller!
          .text;
      expect(parseMapLocation(text).point, isNotNull);
      await tester.tap(_key('form-save-value'));
      await tester.pumpAndSettle();
      expect(backend.rows['entry']!['value'], text);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('$mode: native date-time editor keeps the range and reminder',
        (tester) async {
      final old = FormDateValue(
        start: DateTime(2026, 9, 20, 14, 35),
        end: DateTime(2026, 9, 21, 17, 50),
        includeTime: true,
        isRange: true,
        reminderId: 'reminder',
      );
      await mount(tester, mode, FieldType.DateTime, value: old);
      await tester.tap(_key('form-date-value'));
      await tester.pumpAndSettle();
      expect(find.byType(DesktopAppFlowyDatePicker), findsOneWidget);
      expect(find.byType(DateTimeTextField), findsNWidgets(2));
      final time = find.descendant(
        of: _key('date_time_text_field'),
        matching: _key('date_time_text_field_time'),
      );
      await tester.enterText(time, '16:45');
      // A click on Done must commit the focused field, without requiring Enter.
      await tester.tap(_key('form-date-done'));
      await tester.pumpAndSettle();
      expect(backend.typedWrites, isEmpty);
      await tester.tap(_key('form-save-value'));
      await tester.pumpAndSettle();
      final saved = backend.typedRows['entry']!['value'] as FormDateValue;
      expect(saved.start, DateTime(2026, 9, 20, 16, 45));
      expect(saved.end, old.end);
      expect(saved.isRange, isTrue);
      expect(saved.includeTime, isTrue);
      expect(saved.reminderId, 'reminder');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        '$mode: choosing files adds pending attachments and Cancel preserves originals',
        (tester) async {
      final original = FormFilesValue([
        FormFileAttachment(
          file: MediaFilePB(
            id: 'original',
            name: 'Original.pdf',
            url: 'https://example.invalid/original',
            uploadType: FileUploadTypePB.CloudFile,
          ),
        ),
      ]);
      await mount(tester, mode, FieldType.Media, value: original);
      picks.files = [XFile('C:/test/new.pdf')];
      await tester.tap(_key('form-files-value'));
      await tester.pumpAndSettle();
      expect(picks.calls, 1);
      expect(find.text('new.pdf'), findsOneWidget);
      expect(find.text('Original.pdf'), findsOneWidget);
      expect(backend.typedWrites, isEmpty);
      await tester.tap(_key('form-cancel-value'));
      await tester.pumpAndSettle();
      expect(find.text('new.pdf'), findsNothing);
      expect(backend.typedRows['entry']!['value'], same(original));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        '$mode: checkbox is available directly and its draft can be saved',
        (tester) async {
      await mount(
        tester,
        mode,
        FieldType.Checkbox,
        value: const FormTextValue('No'),
      );
      expect(_key('form-edit-value'), findsNothing);
      await tester.tap(_key('form-checkbox-value'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CheckboxListTile>(_key('form-checkbox-value')).value,
        isTrue,
      );
      expect(backend.writes, isEmpty);
      await tester.tap(_key('form-save-value'));
      await tester.pumpAndSettle();
      expect(backend.rows['entry']!['value'], 'Yes');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        '$mode: button uses its configured action instead of a text box',
        (tester) async {
      await mount(
        tester,
        mode,
        FieldType.RichText,
        value: const FormTextValue(''),
        style: const PropertyStyle(
          kind: PropertyStyleKind.button,
          settings: {
            'label': 'Mark done',
            'action': 'setValue',
            'target': 'Done',
          },
        ),
      );
      expect(find.byType(PropertyValueControl), findsOneWidget);
      await tester.tap(find.text('Mark done'));
      await tester.pumpAndSettle();
      expect(backend.writes, isEmpty);
      await tester.tap(_key('form-save-value'));
      await tester.pumpAndSettle();
      expect(backend.rows['entry']!['value'], 'Done');
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('files and a boolean can be filled before any row exists',
      (tester) async {
    await mount(tester, 'paper', FieldType.Media, draft: true);
    picks.files = [XFile('C:/test/draft.png')];
    await tester.tap(_key('form-files-value'));
    await tester.pumpAndSettle();
    expect(backend.creations, 0);
    expect(backend.typedWrites, isEmpty);
    await tester.tap(_key('form-submit'));
    await tester.pumpAndSettle();
    expect(backend.creations, 1);
    expect(
      (backend.typedWrites.single.$3 as FormFilesValue).files.single.file.name,
      'draft.png',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('file picker cancellation makes no draft and writes nothing',
      (tester) async {
    await mount(tester, 'light', FieldType.Media);
    await tester.tap(_key('form-files-value'));
    await tester.pumpAndSettle();
    expect(_key('form-save-value'), findsNothing);
    expect(backend.typedWrites, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('checklists retain completion and support task editing',
      (tester) async {
    await mount(
      tester,
      'paper',
      FieldType.Checklist,
      value: const FormChecklistValue(
        [FormChecklistTask(id: 'old', name: 'Kept', checked: true)],
      ),
    );
    await tester.tap(_key('form-add-task-value'));
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsNWidgets(2));
    final name = find.byWidgetPredicate(
      (widget) =>
          widget is TextFormField && widget.key.toString().contains('draft:'),
    );
    await tester.enterText(name, 'A new task');
    await tester.tap(_key('form-save-value'));
    await tester.pumpAndSettle();
    final saved = backend.typedWrites.single.$3 as FormChecklistValue;
    expect(saved.tasks.first.id, 'old');
    expect(saved.tasks.first.checked, isTrue);
    expect(saved.tasks.last.name, 'A new task');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('duration editor writes hours and minutes, not a clock timestamp',
      (tester) async {
    await mount(
      tester,
      'light',
      FieldType.Time,
      value: const FormTextValue('1h 15m'),
    );
    await tester.enterText(_key('form-duration-hours-value'), '2');
    await tester.pumpAndSettle();
    await tester.tap(_key('form-save-value'));
    await tester.pumpAndSettle();
    expect(backend.writes.single.$3, '2h 15m');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('open-row button calls the row opener', (tester) async {
    String? opened;
    await mount(
      tester,
      'light',
      FieldType.RichText,
      style: const PropertyStyle(
        kind: PropertyStyleKind.button,
        settings: {'label': 'Open entry'},
      ),
      openRow: (rowId) => opened = rowId,
    );
    await tester.tap(find.text('Open entry'));
    await tester.pumpAndSettle();
    expect(opened, 'entry');
    expect(backend.writes, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('new-entry date picker offers time and keeps it on submission',
      (tester) async {
    await mount(tester, 'paper', FieldType.DateTime, draft: true);
    await tester.tap(_key('form-date-value'));
    await tester.pumpAndSettle();
    final native = tester.widget<DesktopAppFlowyDatePicker>(
      find.byType(DesktopAppFlowyDatePicker),
    );
    expect(native.onIncludeTimeChanged, isNotNull);
    native.onIncludeTimeChanged!(true, DateTime(2026, 9, 20, 16, 45), null);
    await tester.pumpAndSettle();
    await tester.tap(_key('form-date-done'));
    await tester.pumpAndSettle();
    expect(backend.creations, 0);
    await tester.tap(_key('form-submit'));
    await tester.pumpAndSettle();
    final date = backend.typedWrites.single.$3 as FormDateValue;
    expect(date.includeTime, isTrue);
    expect(date.start, DateTime(2026, 9, 20, 16, 45));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'reminder fields open a date-time picker without creating on cancel',
      (tester) async {
    await mount(
      tester,
      'light',
      FieldType.RichText,
      style: const PropertyStyle(kind: PropertyStyleKind.reminder),
      value:
          FormReminderValue(at: DateTime(2026, 9, 20, 9), reminderId: 'kept'),
    );
    await tester.tap(_key('form-reminder-value'));
    await tester.pumpAndSettle();
    final native = tester.widget<DesktopAppFlowyDatePicker>(
      find.byType(DesktopAppFlowyDatePicker),
    );
    expect(native.includeTime, isTrue);
    expect(native.onIsRangeChanged, isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(backend.typedWrites, isEmpty);
    expect(_key('form-save-value'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('select controls save ids even when labels contain commas',
      (tester) async {
    await mount(
      tester,
      'light',
      FieldType.MultiSelect,
      value: const FormSelectionValue([]),
    );
    field.typeOptionData = MultiSelectTypeOptionPB(
      options: [
        SelectOptionPB(id: 'a', name: 'Design, review'),
        SelectOptionPB(id: 'b', name: 'Publish'),
      ],
    ).writeToBuffer();
    source.refresh();
    await tester.pumpAndSettle();
    await tester.tap(_key('form-option-a'));
    await tester.pumpAndSettle();
    await tester.tap(_key('form-option-b'));
    await tester.pumpAndSettle();
    await tester.tap(_key('form-save-value'));
    await tester.pumpAndSettle();
    expect(
      (backend.typedWrites.single.$3 as FormSelectionValue).ids,
      ['a', 'b'],
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('relation picker can remove old and add new linked rows',
      (tester) async {
    backend.related.addAll({'old': 'Old row', 'new': 'New row'});
    await mount(
      tester,
      'paper',
      FieldType.Relation,
      value: const FormSelectionValue(['old'], labels: {'old': 'Old row'}),
    );
    await tester.tap(find.text('Old row'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New row'));
    await tester.pumpAndSettle();
    await tester.tap(_key('form-save-value'));
    await tester.pumpAndSettle();
    expect((backend.typedWrites.single.$3 as FormSelectionValue).ids, ['new']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('counter and progress keep configured bounds and native controls',
      (tester) async {
    await mount(
      tester,
      'light',
      FieldType.RichText,
      value: const FormTextValue('3'),
      style: const PropertyStyle(
        kind: PropertyStyleKind.counter,
        settings: {'step': 2, 'maximum': 5},
      ),
    );
    await tester.tap(find.byTooltip('Increase'));
    await tester.pumpAndSettle();
    await tester.tap(_key('form-save-value'));
    await tester.pumpAndSettle();
    expect(backend.writes.single.$3, '5');
    backend.styles[field.id] = const PropertyStyle(
      kind: PropertyStyleKind.progress,
      settings: {'maximum': 10},
    );
    source.refresh();
    await tester.pumpAndSettle();
    expect(find.byType(PropertyProgressTrack), findsOneWidget);
    expect(
      tester
          .widget<PropertyProgressTrack>(find.byType(PropertyProgressTrack))
          .fraction,
      0.5,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final type in [
    FieldType.Checkbox,
    FieldType.Media,
    FieldType.DateTime,
  ]) {
    testWidgets('$type read-only native controls cannot write', (tester) async {
      await mount(tester, 'paper', type, editable: false);
      expect(_key('form-save-value'), findsNothing);
      if (type == FieldType.Media) {
        expect(
          tester.widget<TextButton>(_key('form-files-value')).onPressed,
          isNull,
        );
      } else if (type == FieldType.Checkbox) {
        expect(
          tester
              .widget<CheckboxListTile>(_key('form-checkbox-value'))
              .onChanged,
          isNull,
        );
      } else {
        expect(
          tester.widget<TextButton>(_key('form-date-value')).onPressed,
          isNull,
        );
      }
      expect(backend.writes, isEmpty);
      expect(backend.typedWrites, isEmpty);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('narrow paper form fits the file and date controls',
      (tester) async {
    await mount(tester, 'paper', FieldType.Media, width: 360, scale: 1.5);
    picks.files = [XFile('C:/test/a-long-file-name-that-should-wrap.pdf')];
    await tester.tap(_key('form-files-value'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

class _FilePicks extends FormInputServices {
  List<XFile> files = [];
  int calls = 0;
  List<String>? extensions;
  @override
  Future<List<XFile>> pickFiles(List<String>? allowed) async {
    calls++;
    extensions = allowed;
    return files;
  }
}

Finder _key(String value) => find.byKey(ValueKey(value));
ThemeData _theme(String appearance) => DesktopAppearance()
    .getThemeData(
      appearance == 'paper'
          ? AppTheme.builtins
              .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
          : AppTheme.fallback,
      appearance == 'dark' ? Brightness.dark : Brightness.light,
      'DM Sans',
      builtInCodeFontFamily,
    )
    .copyWith(platform: TargetPlatform.windows);

Widget _app(String appearance, Widget child) => EasyLocalization(
      supportedLocales: const [Locale('en', 'US')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en', 'US'),
      useFallbackTranslations: true,
      saveLocale: false,
      assetLoader: const TestBundleAssetLoader(),
      child: Builder(
        builder: (context) => MaterialApp(
          locale: const Locale('en', 'US'),
          localizationsDelegates: context.localizationDelegates,
          theme: _theme(appearance),
          themeAnimationDuration: Duration.zero,
          home: Scaffold(body: child),
        ),
      ),
    );
