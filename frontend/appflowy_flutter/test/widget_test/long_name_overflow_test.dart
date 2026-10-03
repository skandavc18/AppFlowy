import 'dart:async';
import 'dart:io';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/search/view_ancestor_cache.dart';
import 'package:appflowy/plugins/database/calendar/application/calendar_workspace.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_shell.dart';
import 'package:appflowy/plugins/database/calendar/presentation/views/month_view.dart';
import 'package:appflowy/shared/calendar/calendar_layout.dart';
import 'package:appflowy/shared/slides/slide_property_view.dart';
import 'package:appflowy/shared/slides/slide_style.dart';
import 'package:appflowy/shared/table_views/table_property_view.dart';
import 'package:appflowy/shared/table_views/table_view_style.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/action_navigation/action_navigation_bloc.dart';
import 'package:appflowy/workspace/application/command_palette/command_palette_bloc.dart';
import 'package:appflowy/workspace/application/command_palette/command_palette_filter.dart';
import 'package:appflowy/workspace/application/command_palette/palette_ai.dart';
import 'package:appflowy/workspace/application/recent/cached_recent_service.dart';
import 'package:appflowy/workspace/application/slides/slide_model.dart';
import 'package:appflowy/workspace/application/table_views/table_row.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/palette_ai_panel.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/recent_views_list.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/search_recent_view_cell.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/search_result_cell.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/search_results_list.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-search/result.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'calendar_test_support.dart';
import 'workspace_overlay_test_app.dart';

const _appearances = ['light', 'dark', 'paper'];

// Each is far wider than any row it is put in, at every width below.
final _longName =
    'Quarterly planning review with the extended leadership team ' * 4;
final _longFolder = 'Shared engineering archive for historical projects ' * 3;
final _longFile =
    '${'Final signed contract amendment for the northern region ' * 3}.pdf';
const _longModel =
    'llama3.1:70b-instruct-q4_K_M served from the workstation in the lab';

/// The home search panel is 640–1040 wide; the palette spans narrow windows
/// up to its 1120 cap. 719/720 straddle the list-and-preview breakpoint.
const _paletteWidths = [320.0, 480.0, 640.0, 719.0, 720.0, 900.0, 1040.0];

void main() {
  setUpAll(initializeCalendarTests);

  group('command palette rows with long names', () {
    late _Fixture fixture;

    setUp(() {
      fixture = _Fixture();
      // Shadow registrations only in this test's scope; never start services.
      getIt.pushNewScope();
      getIt.registerSingleton<CachedRecentService>(fixture.recents);
      getIt.registerSingleton<ViewAncestorCache>(_LongAncestorCache());
      getIt.registerSingleton<ActionNavigationBloc>(_IgnoredNavigation());
      getIt.registerSingleton<MenuSharedState>(MenuSharedState());
    });

    tearDown(() async {
      await getIt.popScope();
      await fixture.commands.close();
      fixture.recents.notifier.dispose();
    });

    for (final appearance in _appearances) {
      testWidgets('$appearance: recent rows shorten a long name and path',
          (tester) async {
        _viewport(tester);
        for (final width in _paletteWidths) {
          await _pumpPalette(
            tester,
            fixture,
            appearance,
            width,
            RecentViewsList(
              onSelected: () {},
              filter: const CommandPaletteFilter(),
              cachedViews: fixture.views,
              currentUserId: null,
            ),
          );
          expect(tester.takeException(), isNull, reason: 'at $width');
          final rows = find.byType(SearchRecentViewCell);
          expect(rows, findsNWidgets(2), reason: 'at $width');
          _expectInside(tester, rows, width);
          // The ancestors arrived and are drawn on the long row's single line.
          expect(
            find.descendant(
              of: rows.first,
              matching: find.textContaining(
                _longFolder.trim(),
                findRichText: true,
              ),
            ),
            findsOneWidget,
            reason: 'at $width',
          );
        }
        await _unmount(tester);
      });

      testWidgets(
          '$appearance: result rows and the AI follow-up fit a long name',
          (tester) async {
        _viewport(tester);
        fixture.commands.showResults('plan', fixture.items, [
          SearchSummaryPB(
            content: 'The plan lives in $_longName and was last revised '
                'after the review.',
            sources: [
              SearchSourcePB(id: fixture.alpha.id, displayName: _longName),
            ],
          ),
        ]);
        for (final width in _paletteWidths) {
          await _pumpPalette(
            tester,
            fixture,
            appearance,
            width,
            SearchResultList(
              cachedViews: fixture.views,
              resultItems: fixture.items,
              resultSummaries: fixture.commands.state.resultSummaries,
            ),
          );
          expect(tester.takeException(), isNull, reason: 'at $width');
          final rows = find.byType(SearchResultCell);
          expect(rows, findsNWidgets(2), reason: 'at $width');
          _expectInside(tester, rows, width);
          final followUp =
              find.text(LocaleKeys.commandPalette_aiAskFollowUp.tr());
          expect(followUp, findsOneWidget, reason: 'at $width');
          _expectInside(tester, followUp, width);
        }
        await _unmount(tester);
      });
    }
  });

  group('the palette AI header with a long model name', () {
    for (final appearance in _appearances) {
      testWidgets('$appearance: the model shortens beside the actions',
          (tester) async {
        _viewport(tester);
        final conversation = PaletteAIConversation(
          engine: _SilentEngine.new,
          newConversationId: () => 'conversation',
          notifyInterval: Duration.zero,
        );
        addTearDown(conversation.dispose);
        // Thinking, with a turn: both Stop and New conversation are shown.
        unawaited(conversation.ask('Plan my week'));

        // The test font draws every glyph a full em wide, so "New
        // conversation" alone is ~260px here; real faces leave the model
        // button far more room at the same palette widths.
        for (final width in [480.0, 608.0, 760.0]) {
          await tester.pumpWidget(
            workspaceOverlayTestApp(
              appearance: appearance,
              disableAnimations: true,
              child: Center(
                child: SizedBox(
                  width: width,
                  height: 480,
                  child: PaletteAIPanel(
                    conversation: conversation,
                    sources: const [],
                    modelLabel: _longModel,
                    onAsk: (_) {},
                    onRemoveSource: (_) {},
                    onOpenSource: (_) {},
                    onSetUp: () {},
                    onPickModel: () {},
                    onNewConversation: () {},
                    onSaveAsPage: (_) async {},
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
          expect(tester.takeException(), isNull, reason: 'at $width');

          final panel = tester.getRect(find.byType(PaletteAIPanel));
          final model = tester.getRect(
            find.byKey(const ValueKey('command-palette-ai-model')),
          );
          final stop = tester.getRect(
            find.byKey(const ValueKey('command-palette-ai-stop')),
          );
          final clear = tester.getRect(
            find.byKey(const ValueKey('command-palette-ai-new')),
          );
          expect(model.left, closeTo(panel.left, 0.01), reason: 'at $width');
          expect(model.right, lessThanOrEqualTo(stop.left + 0.01));
          expect(stop.right, lessThanOrEqualTo(clear.left + 0.01));
          // The actions stay flush with the trailing edge.
          expect(clear.right, closeTo(panel.right, 0.01), reason: 'at $width');
        }
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  });

  group('property chips with long values in a narrow card', () {
    for (final appearance in _appearances) {
      testWidgets('$appearance: table and slide chips shorten their text',
          (tester) async {
        _viewport(tester);
        final values = {
          TablePropertyKind.person: '$_longName, Ann',
          TablePropertyKind.relation: '$_longFolder, Notes',
          TablePropertyKind.files: _longFile,
        };
        for (final width in [140.0, 220.0]) {
          for (final entry in values.entries) {
            final table = TableProperty(
              fieldId: entry.key.name,
              name: entry.key.name,
              value: entry.value,
              kind: entry.key,
            );
            final slide = SlideProperty(
              fieldId: entry.key.name,
              name: entry.key.name,
              value: entry.value,
              kind: SlidePropertyKind.values.byName(entry.key.name),
            );
            await tester.pumpWidget(
              workspaceOverlayTestApp(
                appearance: appearance,
                child: Center(
                  child: SizedBox(
                    width: width,
                    child: Builder(
                      builder: (context) => Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TablePropertyView(
                            property: table,
                            palette: tableViewPaletteOf(context),
                          ),
                          TablePropertyView(
                            property: table,
                            palette: tableViewPaletteOf(context),
                            compact: true,
                          ),
                          SlidePropertyView(
                            property: slide,
                            palette: slidePaletteOf(context),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pump();
            expect(
              tester.takeException(),
              isNull,
              reason: '${entry.key.name} at $width',
            );
          }
        }
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  });

  group('an embedded calendar under its tab header', () {
    // The tab bar itself needs a live database, so its sizing rule is pinned
    // at the source: a fixed-height block hands its reading what is left
    // under the header instead of a second box of the block's full height.
    test('a fixed-height embed gives its reading the remaining height', () {
      String read(String path) =>
          File(path).readAsStringSync().replaceAll('\r\n', '\n');
      final view = read('lib/plugins/database/tab_bar/tab_bar_view.dart');
      final wrap = view.substring(view.indexOf('Widget wrapContent('));
      expect(
        wrap,
        contains('if (widget.embedHeight != null) {\n        return Expanded('),
      );
      expect(
        wrap,
        contains('SingleChildScrollView(primary: false, child: child)'),
      );
      expect(
        view,
        isNot(contains('widget.embedHeight ?? layout.pluginHeight')),
      );
      expect(view, contains('growsWithContent: tab.builder.growsWithContent'));
      // Only a grid or board grows with its rows; every other reading fills.
      for (final path in [
        'lib/plugins/database/grid/presentation/grid_page.dart',
        'lib/plugins/database/board/presentation/board_page.dart',
        'lib/plugins/database/grid/presentation/mobile_grid_page.dart',
      ]) {
        expect(
          read(path),
          contains('bool get growsWithContent => true;'),
          reason: path,
        );
      }
    });

    // The block frame is the stored embed height and also holds the 38px tab
    // header, so the calendar only ever gets what is left under it. 220 is
    // the block's minimum height.
    const frames = [
      Size(320, 220),
      Size(760, 220),
      Size(760, 300),
      Size(1200, 460),
      Size(1200, 630),
    ];
    for (final appearance in _appearances) {
      for (final mode in CalendarViewMode.values) {
        testWidgets('$appearance ${mode.name}: fits what the header leaves',
            (tester) async {
          _viewport(tester);
          final day = DateTime(2026, 10, 3);
          final workspace = CalendarWorkspace(
            providers: [
              CalendarFixtureProvider(
                events: [
                  calendarFixtureEvent(
                    'long-all-day',
                    DateTime(2026, 10),
                    end: DateTime(2026, 10, 5),
                    allDay: true,
                    title: _longName,
                  ),
                  for (var hour = 8; hour < 16; hour++)
                    calendarFixtureEvent(
                      'long-$hour',
                      day.add(Duration(hours: hour)),
                      end: day.add(Duration(hours: hour, minutes: 45)),
                      title: _longName,
                      location: _longFolder,
                    ),
                ],
              ),
            ],
          );
          try {
            for (final frame in frames) {
              await mountCalendarTest(
                tester,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 38),
                    Expanded(
                      child: CalendarShell(
                        workspace: workspace,
                        initialMode: mode,
                        initialDate: day,
                        now: () => DateTime(2026, 10, 3, 12),
                        embedded: true,
                        showWeekNumbers: true,
                        delegate: CalendarViewDelegate(
                          colorOf: workspace.colorFor,
                          onOpenEvent: (_) {},
                          onEventMenu: (_, __) {},
                          onCreateAt: (_, {bool hasTime = false}) {},
                          onToggleComplete: (_) {},
                        ),
                      ),
                    ),
                  ],
                ),
                appearance: appearance,
                size: frame,
              );
              expect(tester.takeException(), isNull, reason: 'in $frame');
              expect(
                tester.getSize(find.byType(CalendarShell)).height,
                frame.height - 38,
              );
            }
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            workspace.dispose();
          }
        });
      }
    }
  });
}

void _viewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1600, 1000);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpPalette(
  WidgetTester tester,
  _Fixture fixture,
  String appearance,
  double width,
  Widget pane,
) async {
  await tester.pumpWidget(
    workspaceOverlayTestApp(
      appearance: appearance,
      disableAnimations: true,
      child: BlocProvider<CommandPaletteBloc>.value(
        value: fixture.commands,
        child: Center(
          child: SizedBox(width: width, height: 460, child: pane),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Every row stays inside the pane it is drawn in.
void _expectInside(WidgetTester tester, Finder rows, double width) {
  final left = (1600 - width) / 2;
  for (final element in rows.evaluate()) {
    final rect = tester.getRect(find.byElementPredicate((e) => e == element));
    expect(rect.left, greaterThanOrEqualTo(left - 0.01), reason: 'at $width');
    expect(
      rect.right,
      lessThanOrEqualTo(left + width + 0.01),
      reason: 'at $width',
    );
  }
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

ViewPB _folder(String id, String parentId, String name) => ViewPB(
      id: id,
      parentViewId: parentId,
      name: name,
      layout: ViewLayoutPB.Document,
      extra: const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
    );

class _Fixture {
  late final root = _folder('long-root', 'long-workspace', _longFolder);
  late final nested = _folder('long-nested', root.id, _longFolder);
  late final alpha = _folder('long-alpha', nested.id, _longName);
  late final beta = _folder('long-beta', root.id, _longFile);
  late final views = <String, ViewPB>{
    for (final view in [root, nested, alpha, beta]) view.id: view,
  };
  late final items = [
    for (final view in [alpha, beta])
      SearchResultItem(
        id: view.id,
        icon: ResultIconPB(),
        content: '',
        displayName: view.name,
      ),
  ];
  late final commands = _PaletteBloc(views);
  late final recents = _RecentCache([alpha, beta]);
}

// Only UI state is supplied. Constructing CommandPaletteBloc itself starts
// native trash/search listeners, which a layout test must not do.
class _PaletteBloc extends Cubit<CommandPaletteState>
    implements CommandPaletteBloc {
  _PaletteBloc(Map<String, ViewPB> views)
      : super(CommandPaletteState.initial().copyWith(cachedViews: views));

  @override
  void add(CommandPaletteEvent event) {}

  void showResults(
    String query,
    List<SearchResultItem> items,
    List<SearchSummaryPB> summaries,
  ) =>
      emit(
        state.copyWith(
          query: query,
          combinedResponseItems: {for (final item in items) item.id: item},
          resultSummaries: summaries,
        ),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecentCache extends Fake implements CachedRecentService {
  _RecentCache(List<ViewPB> views)
      : notifier = ValueNotifier(
          [for (final view in views) SectionViewPB(item: view)],
        );

  @override
  final ValueNotifier<List<SectionViewPB>> notifier;

  @override
  Future<List<SectionViewPB>> recentViews() async => notifier.value;
}

/// Every view sits three long-named folders deep.
class _LongAncestorCache extends ViewAncestorCache {
  @override
  Future<ViewAncestor?> getAncestor(
    String viewId, {
    ValueChanged<ViewAncestor>? onRefresh,
  }) async =>
      ViewAncestor(
        ancestors: [
          for (var index = 0; index < 3; index++)
            ViewParent(id: 'ancestor-$index', name: _longFolder),
        ],
      );
}

class _IgnoredNavigation extends Fake implements ActionNavigationBloc {
  @override
  void add(ActionNavigationEvent event) {}
}

/// Thinks forever, so the header shows Stop beside New conversation.
class _SilentEngine implements PaletteAIEngine {
  @override
  String get label => _longModel;

  @override
  bool get canContinueInChat => false;

  @override
  Future<void> answer(
    PaletteAIRequest request, {
    required void Function(String delta) onDelta,
    required void Function() onDone,
    required void Function(PaletteAIFailure failure) onError,
    void Function(String note)? onNote,
  }) async {}

  @override
  Future<void> stop() async {}
}
