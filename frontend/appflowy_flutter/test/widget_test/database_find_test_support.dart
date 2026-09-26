import 'dart:async';
import 'dart:convert';

import 'package:appflowy/plugins/database/find/database_find_host.dart';
import 'package:appflowy/plugins/database/find/database_find_session.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/document_find_content.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/find_replace/find_replace_bar.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../util/native_find_test_input.dart';

const databaseFindViewId = 'current-view-guid';
const databaseFindRowId = 'visible-row-guid';
const databaseFindFieldId = 'text-field-guid';
const databaseFindCellStage =
    'cell:$databaseFindViewId:$databaseFindRowId:$databaseFindFieldId';

/// Only read I/O is replaced. The real provider parses these PB values, and
/// the real database session/host supplies matching, snippets and keyboard UI.
/// No FFI, database controllers, alternate databases or fake search engines.
class DatabaseFindReads {
  DatabaseFindReads({ViewLayoutPB layout = ViewLayoutPB.Grid}) {
    addView(databaseFindViewId, 'Needle roadmap', layout: layout);
    addView('unrelated-database-guid', 'Unrelated secret');
    views[databaseFindViewId]!
        .childViews
        .add(views['unrelated-database-guid']!);
  }

  final views = <String, ViewPB>{};
  final fields = <String, List<FieldPB>>{};
  final rows = <String, List<RowMetaPB>>{};
  final cells = <(String, String, String), CellPB?>{};
  final calls = <String>[];
  final forbiddenReads = <String>[];
  final failures = <String>{};
  final _gates = <String, Completer<void>>{};
  final _allGates = <Completer<void>>[];
  final access = ValueNotifier(0);
  final changes = StreamController<String>.broadcast(sync: true);
  final scheduler = DocumentFindReadScheduler();
  bool allowed = true;
  bool missingView = false;
  ViewPB? wrongView;
  int inFlight = 0;
  int maxInFlight = 0;

  void addView(
    String id,
    String title, {
    ViewLayoutPB layout = ViewLayoutPB.Grid,
  }) {
    views[id] = ViewPB(
      id: id,
      name: title,
      layout: layout,
      extra: '{"not_displayed":"raw_metadata_sentinel"}',
    );
    fields[id] = [
      FieldPB(
        id: databaseFindFieldId,
        name: 'Needle column',
        fieldType: FieldType.RichText,
      ),
      FieldPB(
        id: 'status-field-guid',
        name: 'Status',
        fieldType: FieldType.SingleSelect,
        typeOptionData: SingleSelectTypeOptionPB(
          options: [
            SelectOptionPB(id: 'option-guid', name: 'NEEDLE ready'),
            SelectOptionPB(
              id: 'unused-option-guid',
              name: 'unused_option_sentinel',
            ),
          ],
        ).writeToBuffer(),
      ),
      FieldPB(
        id: 'date-field-guid',
        name: 'Due',
        fieldType: FieldType.DateTime,
        typeOptionData: DateTypeOptionPB(dateFormat: DateFormatPB.DayMonthYear)
            .writeToBuffer(),
      ),
      FieldPB(
        id: 'checkbox-field-guid',
        name: 'Complete',
        fieldType: FieldType.Checkbox,
      ),
      FieldPB(
        id: 'number-field-guid',
        name: 'Cost',
        fieldType: FieldType.Number,
      ),
      FieldPB(
        id: 'relation-field-guid',
        name: 'Related',
        fieldType: FieldType.Relation,
        typeOptionData:
            RelationTypeOptionPB(databaseId: 'unrelated-database-guid')
                .writeToBuffer(),
      ),
    ];
    rows[id] = [RowMetaPB(id: databaseFindRowId)];
    setText(id, 'A needle task');
    _cell(
      id,
      'status-field-guid',
      FieldType.SingleSelect,
      SelectOptionCellDataPB(
        selectOptions: [
          SelectOptionPB(id: 'option-guid', name: 'stale_option_sentinel'),
        ],
      ).writeToBuffer(),
    );
    _cell(
      id,
      'date-field-guid',
      FieldType.DateTime,
      DateCellDataPB(
        timestamp: Int64(
          DateTime(2026, 9, 25, 12).millisecondsSinceEpoch ~/ 1000,
        ),
      ).writeToBuffer(),
    );
    _cell(
      id,
      'checkbox-field-guid',
      FieldType.Checkbox,
      CheckboxCellDataPB(isChecked: true).writeToBuffer(),
    );
    _cell(id, 'number-field-guid', FieldType.Number, utf8.encode(r'$1,250.00'));
    cells[(id, 'filtered-out-row-guid', databaseFindFieldId)] = CellPB(
      rowId: 'filtered-out-row-guid',
      fieldId: databaseFindFieldId,
      fieldType: FieldType.RichText,
      data: utf8.encode('hidden_row_sentinel'),
    );
  }

  void setText(String id, String text) =>
      _cell(id, databaseFindFieldId, FieldType.RichText, utf8.encode(text));

  void _cell(String id, String field, FieldType type, List<int> bytes) {
    cells[(id, databaseFindRowId, field)] = CellPB(
      rowId: databaseFindRowId,
      fieldId: field,
      fieldType: type,
      data: bytes,
    );
  }

  DocumentFindReadProvider provider({
    Duration deadline = const Duration(seconds: 3),
    bool sharedScheduler = false,
  }) =>
      DocumentFindReadProvider(
        scheduler: sharedScheduler ? null : scheduler,
        deadline: deadline,
        readView: (id) => _read('view:$id', () {
          final view = wrongView ?? views[id];
          return missingView || view == null
              ? null
              : ViewPB.fromBuffer(view.writeToBuffer());
        }),
        preflight: (view) => _read('preflight:${view.id}', () => allowed),
        readDocument: (id) async {
          forbiddenReads.add('document:$id');
          throw StateError('Database Find must not read documents');
        },
        readRows: (id) async {
          forbiddenReads.add('GetRowsAsText:$id');
          throw StateError('Unsafe relation-expanding export');
        },
        readFields: (id, requested) => _read('fields:$id', () {
          expectSync(
            requested,
            isEmpty,
            reason: 'Only the current view fields',
          );
          return fields[id]
              ?.map((field) => FieldPB.fromBuffer(field.writeToBuffer()))
              .toList();
        }),
        readViewRows: (id) => _read('rows:$id', () => rows[id]),
        readCell: (id, row, field) {
          final value = cells[(id, row.id, field.id)];
          // Retain the actual reply at request time for stale-completion tests.
          final snapshot =
              value == null ? null : CellPB.fromBuffer(value.writeToBuffer());
          return _read('cell:$id:${row.id}:${field.id}', () => snapshot);
        },
        accessChanges: access,
        contentChanges: changes.stream,
      );

  Future<T> _read<T>(String stage, FutureOr<T> Function() read) async {
    calls.add(stage);
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      final gate = _gates.remove(stage);
      if (gate != null) await gate.future;
      if (failures.contains(stage)) throw StateError('Private native details');
      return await read();
    } finally {
      inFlight--;
    }
  }

  Completer<void> hold(String stage) {
    final gate = Completer<void>();
    _gates[stage] = gate;
    _allGates.add(gate);
    return gate;
  }

  Object snapshot() => [
        for (final view in views.values) view.writeToBuffer().toList(),
        for (final list in fields.values)
          for (final field in list) field.writeToBuffer().toList(),
        for (final list in rows.values)
          for (final row in list) row.writeToBuffer().toList(),
        for (final cell in cells.values) cell?.writeToBuffer().toList(),
      ];

  void dispose() {
    for (final gate in _allGates) {
      if (!gate.isCompleted) gate.complete();
    }
    access.dispose();
    unawaited(changes.close());
  }
}

class DatabaseFindHarness {
  DatabaseFindHarness({ViewLayoutPB layout = ViewLayoutPB.Grid})
      : reads = DatabaseFindReads(layout: layout) {
    view = reads.views[databaseFindViewId]!;
    provider = reads.provider();
  }

  final DatabaseFindReads reads;
  late ViewPB view;
  late DocumentFindReadProvider provider;
  DocumentFindLimits limits =
      const DocumentFindLimits(maxDepth: 0, maxViews: 1);
  final bodyKey = GlobalKey<DatabaseDraftSurfaceState>();
  final navigatorKey = GlobalKey<NavigatorState>();
  final navigationFocus = FocusNode();
  final otherQueryFocus = FocusNode();
  bool active = true;
  bool hidden = false;
  bool delegated = false;
  bool nativeChild = true;
  double width = 580;
  double height = 480;
  double textScale = 1;
  String mode = 'light';

  DatabaseDraftSurfaceState get body => bodyKey.currentState!;

  Future<void> mount(WidgetTester tester) async {
    final brightness = mode == 'dark' ? Brightness.dark : Brightness.light;
    final theme = DesktopAppearance()
        .getThemeData(
          mode == 'paper'
              ? AppTheme.builtins
                  .firstWhere((t) => t.themeName == BuiltInTheme.paper)
              : AppTheme.fallback,
          brightness,
          'Ahem',
          'Ahem',
        )
        .copyWith(platform: TargetPlatform.windows);
    Widget surface = DatabaseDraftSurface(key: bodyKey);
    if (delegated && nativeChild) {
      surface = DatabaseFindHost(
        view: view,
        isActive: () => active,
        limits: limits,
        child: surface,
      );
    }
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        fallbackLocale: const Locale('en', 'US'),
        path: 'unused-database-find-translations',
        assetLoader: const _FindStrings(),
        saveLocale: false,
        child: Builder(
          builder: (context) => MaterialApp(
            navigatorKey: navigatorKey,
            localizationsDelegates: context.localizationDelegates,
            locale: const Locale('en', 'US'),
            theme: theme,
            themeAnimationDuration: Duration.zero,
            home: AppFlowyTheme(
              data: brightness == Brightness.dark
                  ? AppFlowyDefaultTheme().dark()
                  : AppFlowyDefaultTheme().light(),
              child: Scaffold(
                body: MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(textScale)),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 160,
                        child: Column(
                          children: [
                            TextButton(
                              focusNode: navigationFocus,
                              onPressed: () {},
                              child: const Text('Navigation'),
                            ),
                            TextField(
                              key: const ValueKey('otherSearchField'),
                              focusNode: otherQueryFocus,
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: SizedBox(
                            width: width,
                            height: height,
                            child: IndexedStack(
                              index: hidden ? 1 : 0,
                              children: [
                                ContextualFindScope(
                                  child: DatabaseFindHost(
                                    view: delegated
                                        ? reads
                                            .views['unrelated-database-guid']!
                                        : view,
                                    readProvider: provider,
                                    limits: limits,
                                    delegateToNativeChild: delegated,
                                    isActive: () => active,
                                    child: surface,
                                  ),
                                ),
                                const SizedBox.expand(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> open(
    WidgetTester tester, {
    bool fromTitle = false,
    bool hover = true,
  }) async {
    navigationFocus.requestFocus();
    await tester.pump();
    expect(navigationFocus.hasPrimaryFocus, isTrue);
    TestGesture? mouse;
    try {
      if (hover) {
        final bounds = tester.getRect(find.byKey(bodyKey));
        final point = fromTitle
            ? tester.getCenter(find.byKey(const ValueKey('databaseTestTitle')))
            : Offset(bounds.left + 24, bounds.bottom - 24);
        mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: point);
        await mouse.moveTo(point);
        await tester.pump();
      }
      await databaseFindKey(
        tester,
        LogicalKeyboardKey.keyF,
        PhysicalKeyboardKey.keyF,
        control: true,
      );
    } finally {
      await mouse?.removePointer();
    }
    await tester.pump();
    await tester.pump();
    expect(find.byType(FindReplaceBar), findsOneWidget);
    expect(
      find.byKey(const ValueKey('findTextField')).hitTestable(),
      findsOneWidget,
    );
  }

  Future<void> query(
    WidgetTester tester,
    String text, {
    bool finish = true,
  }) async {
    await tester.enterText(find.byKey(const ValueKey('findTextField')), text);
    await tester
        .pump(DatabaseFindSession.debounce + const Duration(milliseconds: 1));
    if (finish) {
      await databaseFindUntil(tester, () => !databaseFindBar(tester).busy);
    }
    await tester.pump();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    reads.dispose();
    navigationFocus.dispose();
    otherQueryFocus.dispose();
    await tester.pump();
    await tester.pump();
  }
}

/// Observes the real timers without changing their durations or scheduler.
/// The native binding's pumps advance wall time, unlike widget-test pumps.
class DatabaseFindQueryProbe {
  DatabaseFindQueryProbe(this.page);

  final DatabaseFindHarness page;
  final events = <Map<String, Object>>[];
  final _clock = Stopwatch();

  Future<void> query(WidgetTester tester, String text) async {
    final session = databaseFindSession(tester);
    void record(String event) => events.add({
          'event': event,
          'microseconds': _clock.elapsedMicroseconds,
          'status': session.status.name,
          'pending': page.provider.readScheduler.pendingCount,
          'inFlight': page.reads.inFlight,
          'calls': page.reads.calls.length,
        });

    _clock.start();
    record('query:start');
    await runZoned(
      () => page.query(tester, text, finish: false),
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          final name = duration == DatabaseFindSession.debounce
              ? 'debounce'
              : duration == page.provider.deadline
                  ? 'deadline'
                  : null;
          if (name == null) {
            return parent.createTimer(zone, duration, callback);
          }
          record('$name:scheduled');
          return parent.createTimer(zone, duration, () {
            record('$name:before');
            callback();
            record('$name:after');
          });
        },
      ),
    );
    record('query:returned');
  }
}

/// A real retained editor draft and scroll controller beneath the host. These
/// are deliberately NOT the provider's values: Find must not scrape widgets.
class DatabaseDraftSurface extends StatefulWidget {
  const DatabaseDraftSurface({super.key});

  @override
  State<DatabaseDraftSurface> createState() => DatabaseDraftSurfaceState();
}

class DatabaseDraftSurfaceState extends State<DatabaseDraftSurface> {
  final draft = TextEditingController(text: 'unsaved draft');
  final scroll = ScrollController();
  int edits = 0;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          const SizedBox(
            height: 44,
            child: Text(
              'Database title surface',
              key: ValueKey('databaseTestTitle'),
            ),
          ),
          Expanded(
            child: ListView(
              controller: scroll,
              children: [
                TextField(controller: draft, onChanged: (_) => edits++),
                for (var i = 0; i < 30; i++)
                  SizedBox(height: 32, child: Text('Body row $i')),
              ],
            ),
          ),
        ],
      );

  @override
  void dispose() {
    draft.dispose();
    scroll.dispose();
    super.dispose();
  }
}

class _FindStrings extends AssetLoader {
  const _FindStrings();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) =>
      Future.value({
        'findAndReplace': {
          'find': 'Find',
          'matchOfTotal': '{} of {}',
          'noResult': 'No results',
          'searching': 'Searching…',
          'invalidRegex': 'Invalid regular expression',
          'previousMatch': 'Previous match',
          'nextMatch': 'Next match',
          'close': 'Close',
        },
      });
}

void setUpDatabaseFindTests() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
  });
}

FindReplaceBar databaseFindBar(WidgetTester tester) =>
    tester.widget<FindReplaceBar>(find.byType(FindReplaceBar));

DatabaseFindSession databaseFindSession(WidgetTester tester) => tester
    .widget<ListenableBuilder>(
      find.byWidgetPredicate(
        (widget) =>
            widget is ListenableBuilder &&
            widget.listenable is DatabaseFindSession,
      ),
    )
    .listenable as DatabaseFindSession;

Future<void> databaseFindUntil(
  WidgetTester tester,
  bool Function() ready,
) async {
  for (var i = 0; i < 30 && !ready(); i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(ready(), isTrue, reason: 'Bounded wait for database read/publication');
}

Future<void> databaseFindKey(
  WidgetTester tester,
  LogicalKeyboardKey logical,
  PhysicalKeyboardKey physical, {
  bool control = false,
  bool shift = false,
}) async {
  if (control && !shift && logical == LogicalKeyboardKey.keyF) {
    await sendFindTestShortcut(tester);
    return;
  }
  if (control) {
    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.controlLeft,
      physicalKey: PhysicalKeyboardKey.controlLeft,
    );
  }
  if (shift) {
    await tester.sendKeyDownEvent(
      LogicalKeyboardKey.shiftLeft,
      physicalKey: PhysicalKeyboardKey.shiftLeft,
    );
  }
  await tester.sendKeyEvent(logical, physicalKey: physical);
  if (shift) {
    await tester.sendKeyUpEvent(
      LogicalKeyboardKey.shiftLeft,
      physicalKey: PhysicalKeyboardKey.shiftLeft,
    );
  }
  if (control) {
    await tester.sendKeyUpEvent(
      LogicalKeyboardKey.controlLeft,
      physicalKey: PhysicalKeyboardKey.controlLeft,
    );
  }
}
