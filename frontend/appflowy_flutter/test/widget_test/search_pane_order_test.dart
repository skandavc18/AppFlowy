import 'dart:async';
import 'dart:ui' as ui;

import 'package:appflowy/mobile/presentation/search/view_ancestor_cache.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/action_navigation/action_navigation_bloc.dart';
import 'package:appflowy/workspace/application/action_navigation/navigation_action.dart';
import 'package:appflowy/workspace/application/command_palette/command_palette_bloc.dart';
import 'package:appflowy/workspace/application/command_palette/command_palette_filter.dart';
import 'package:appflowy/workspace/application/command_palette/palette_command.dart';
import 'package:appflowy/workspace/application/command_palette/search_result_list_bloc.dart';
import 'package:appflowy/workspace/application/recent/cached_recent_service.dart';
import 'package:appflowy/workspace/application/recent/recent_views_bloc.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/command_palette/command_palette.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/command_results_list.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/page_inspection_panel.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/recent_views_list.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/search_field.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/search_recent_view_cell.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/search_result_cell.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/search_results_list.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-search/result.pb.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_material_app.dart';

const _searchListKey = ValueKey('command-palette-search-results-panel');
const _recentListKey = ValueKey('command-palette-recent-list-panel');
const _inspectionKey = ValueKey('command-palette-inspection-panel');
const _backKey = ValueKey('command-palette-folder-browser-back');
const _openPaletteKey = ValueKey('open-test-palette');

enum _Appearance { light, dark, paper }

enum _Results { query, recent }

void main() {
  late _Fixture fixture;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
  });

  setUp(() {
    fixture = _Fixture();
    // Shadow registrations only in this test's scope; never start app services.
    getIt.pushNewScope();
    getIt.registerSingleton<CachedRecentService>(fixture.recents);
    getIt.registerSingleton<ViewAncestorCache>(_EmptyAncestorCache());
    getIt.registerSingleton<ActionNavigationBloc>(fixture.navigation);
    getIt.registerSingleton<MenuSharedState>(MenuSharedState());
  });

  tearDown(() async {
    await getIt.popScope();
    await fixture.commands.close();
    fixture.recents.notifier.dispose();
  });

  for (final appearance in _Appearance.values) {
    for (final results in _Results.values) {
      testWidgets(
        '${appearance.name} ${results.name}: list is physically left of preview',
        (tester) async {
          _prepareViewport(tester);
          fixture.commands.showResults('a', fixture.items);

          // Include the exact split threshold and the capped-list case.
          for (final (width, listWidth) in const [
            (720.0, 360.0),
            (900.0, 450.0),
            (1280.0, 520.0),
          ]) {
            await _pumpPane(tester, fixture, results, appearance, width);
            _expectSplit(tester, results, listWidth: listWidth);
            expect(
              tester
                  .widget<PageInspectionPanel>(
                    find.byType(PageInspectionPanel),
                  )
                  .view
                  .id,
              fixture.alpha.id,
            );
            expect(tester.takeException(), isNull);
          }

          expect(fixture.navigation.events, isEmpty);
          if (results == _Results.recent) {
            expect(fixture.recents.reads, 1);
          }
          await _unmount(tester);
        },
      );

      testWidgets(
        '${appearance.name} ${results.name}: narrow remains a single pane',
        (tester) async {
          _prepareViewport(tester);
          fixture.commands.showResults('a', fixture.items);

          for (final width in [320.0, 600.0, 719.0]) {
            await _pumpPane(tester, fixture, results, appearance, width);
            _expectListOnly(tester, results);
            if (results == _Results.query) {
              expect(find.byType(SearchResultCell), findsNWidgets(2));
              expect(
                tester
                    .widgetList<SearchResultCell>(
                      find.byType(SearchResultCell),
                    )
                    .every((cell) => cell.isNarrowWindow),
                isTrue,
              );
            } else {
              expect(find.byType(SearchRecentViewCell), findsNWidgets(2));
              expect(
                tester
                    .widgetList<SearchRecentViewCell>(
                      find.byType(SearchRecentViewCell),
                    )
                    .every((cell) => cell.isNarrowWindow),
                isTrue,
              );
            }
            expect(tester.takeException(), isNull);
          }

          await tester.tap(_row(results, fixture.beta.id));
          await tester.pumpAndSettle();
          if (results == _Results.query) {
            // Narrow search browses folders in-place, not in a second pane.
            expect(find.byKey(_searchListKey), findsNothing);
            expect(find.byType(PageInspectionPanel), findsOneWidget);
            expect(find.byKey(_backKey), findsOneWidget);
            expect(
              tester.getRect(find.byKey(_inspectionKey)).width,
              closeTo(719, 0.01),
            );
            await tester.tap(_child(fixture.nested.id));
            await tester.pumpAndSettle();
            expect(_child(fixture.notes.first.id), findsOneWidget);
            final browser = tester.state(find.byType(PageInspectionPanel));

            await _pumpPane(tester, fixture, results, appearance, 600);
            expect(
              tester.state(find.byType(PageInspectionPanel)),
              same(browser),
            );
            expect(_child(fixture.notes.first.id), findsOneWidget);
            expect(find.byKey(_searchListKey), findsNothing);
            expect(
              tester.getRect(find.byKey(_inspectionKey)).width,
              closeTo(600, 0.01),
            );
            expect(fixture.navigation.events, isEmpty);

            await tester.tap(find.byKey(_backKey));
            await tester.pumpAndSettle();
            _expectListOnly(tester, results);
            expect(_row(results, fixture.beta.id), findsOneWidget);
          } else {
            // Recent folders still open directly, rather than adopting the
            // search-result folder-browser interaction.
            expect(fixture.recentSelections, 1);
            _expectOpened(fixture.navigation, fixture.beta.id);
            _expectListOnly(tester, results);
          }
          await _unmount(tester);
        },
      );
    }

    testWidgets(
      '${appearance.name}: commands-only search uses the entire list width',
      (tester) async {
        _prepareViewport(tester);
        final ran = <PaletteCommand>[];
        final command = PaletteCommand(
          id: 'pane-test-command',
          title: 'Show notes',
          icon: Icons.description_rounded,
          group: PaletteCommandGroup.navigate,
          run: (_) {},
        );

        for (final width in [600.0, 900.0, 1280.0]) {
          await _pumpPane(
            tester,
            fixture,
            _Results.query,
            appearance,
            width,
            items: const [],
            commands: [command],
            onRunCommand: ran.add,
          );
          _expectListOnly(tester, _Results.query);
          expect(find.byType(SearchResultCell), findsNothing);
          expect(find.byType(PaletteCommandCell), findsOneWidget);
          // Check the rendered row as well as the outer sizing box, so an
          // empty half-width inner list cannot satisfy the contract.
          expect(
            tester.getSize(find.byType(PaletteCommandCell)).width,
            greaterThan(width * 0.9),
          );
          expect(tester.takeException(), isNull);
        }

        await tester.tap(find.byType(PaletteCommandCell));
        await tester.pump();
        expect(ran, [command]);
        expect(fixture.navigation.events, isEmpty);
        await _unmount(tester);
      },
    );

    testWidgets(
      '${appearance.name}: typed query, selection and nested preview survive wide resize',
      (tester) async {
        _prepareViewport(tester, const Size(1280, 900));
        await tester.pumpWidget(
          _app(
            fixture,
            appearance,
            CommandPaletteModal(shortcutBuilder: (child) => child),
          ),
        );
        await tester.pumpAndSettle();

        final field = find.descendant(
          of: find.byType(SearchField),
          matching: find.byType(EditableText),
        );
        await tester.enterText(field, 'a');
        expect(
          fixture.commands.events,
          contains(const CommandPaletteEvent.searchChanged(search: 'a')),
        );
        // Publish already-cached results at the bloc boundary. There is no
        // native search service, dispatch shim, or pretend backend here.
        fixture.commands.showResults('a', fixture.items);
        await tester.pumpAndSettle();
        await tester.tap(_row(_Results.query, fixture.beta.id));
        await tester.pumpAndSettle();
        await tester.tap(_child(fixture.nested.id));
        await tester.pumpAndSettle();

        final listState = tester.state(find.byType(SearchResultList));
        final resultBloc = _resultBloc(tester);
        final previewState = tester.state(find.byType(PageInspectionPanel));
        final previewScroll = _previewScroll(tester);
        previewScroll.position.jumpTo(100);
        await tester.pump();
        expect(previewScroll.position.pixels, greaterThan(0));
        final scrollOffset = previewScroll.position.pixels;
        final fieldState = tester.state<EditableTextState>(field);
        final controller = fieldState.widget.controller;
        controller.selection = const TextSelection(
          baseOffset: 0,
          extentOffset: 1,
        );
        await tester.pump();
        final editingValue = controller.value;
        final fieldFocus = fieldState.widget.focusNode;

        for (final size in [const Size(1000, 850), const Size(1440, 1000)]) {
          tester.view.physicalSize = size;
          await tester.pumpAndSettle();
          _expectSplit(tester, _Results.query);
          expect(tester.state(find.byType(SearchResultList)), same(listState));
          expect(_resultBloc(tester), same(resultBloc));
          expect(resultBloc.state.hoveredResult?.id, fixture.beta.id);
          expect(
            tester
                .widget<SearchResultCell>(
                  _row(_Results.query, fixture.beta.id),
                )
                .isHovered,
            isTrue,
          );
          expect(
            tester.state(find.byType(PageInspectionPanel)),
            same(previewState),
          );
          expect(_previewScroll(tester), same(previewScroll));
          expect(previewScroll.position.pixels, closeTo(scrollOffset, 0.01));
          expect(_child(fixture.notes.first.id), findsOneWidget);
          expect(tester.state<EditableTextState>(field), same(fieldState));
          expect(
            tester.widget<EditableText>(field).controller,
            same(controller),
          );
          expect(
            tester.widget<EditableText>(field).focusNode,
            same(fieldFocus),
          );
          expect(controller.value, editingValue);
          expect(fixture.commands.state.query, 'a');
          expect(tester.takeException(), isNull);
        }

        // Crossing the existing breakpoint deliberately removes the preview.
        // Query and selected-result state must not be removed with it.
        tester.view.physicalSize = const Size(640, 800);
        await tester.pumpAndSettle();
        _expectListOnly(tester, _Results.query);
        expect(previewState.mounted, isFalse);
        expect(tester.state(find.byType(SearchResultList)), same(listState));
        expect(_resultBloc(tester), same(resultBloc));
        expect(resultBloc.state.hoveredResult?.id, fixture.beta.id);
        expect(tester.widget<EditableText>(field).controller, same(controller));
        expect(controller.value, editingValue);

        tester.view.physicalSize = const Size(1280, 900);
        await tester.pumpAndSettle();
        _expectSplit(tester, _Results.query);
        expect(resultBloc.state.hoveredResult?.id, fixture.beta.id);
        expect(
          tester
              .widget<PageInspectionPanel>(
                find.byType(PageInspectionPanel),
              )
              .view
              .id,
          fixture.beta.id,
        );
        expect(_child(fixture.nested.id), findsOneWidget);
        expect(controller.value, editingValue);
        expect(
          fixture.commands.events,
          [const CommandPaletteEvent.searchChanged(search: 'a')],
        );
        expect(fixture.navigation.events, isEmpty);
        await _unmount(tester);
      },
    );

    testWidgets(
      '${appearance.name}: recent selection and nested preview survive wide resize',
      (tester) async {
        _prepareViewport(tester);
        await _pumpPane(tester, fixture, _Results.recent, appearance, 1000);
        final beta = _row(_Results.recent, fixture.beta.id);
        _rowFocus(tester, beta).requestFocus();
        await tester.pumpAndSettle();
        final recentBloc = tester.element(beta).read<RecentViewsBloc>();
        expect(recentBloc.state.hoveredView?.id, fixture.beta.id);
        await tester.tap(_child(fixture.nested.id));
        await tester.pumpAndSettle();
        final preview = tester.state(find.byType(PageInspectionPanel));
        final scroll = _previewScroll(tester);
        scroll.position.jumpTo(100);
        await tester.pump();
        final offset = scroll.position.pixels;
        expect(offset, greaterThan(0));

        for (final width in [900.0, 1280.0, 720.0]) {
          await _pumpPane(tester, fixture, _Results.recent, appearance, width);
          _expectSplit(tester, _Results.recent);
          expect(
            tester.element(beta).read<RecentViewsBloc>(),
            same(recentBloc),
          );
          expect(recentBloc.state.hoveredView?.id, fixture.beta.id);
          expect(tester.widget<SearchRecentViewCell>(beta).isSelected, isTrue);
          expect(tester.state(find.byType(PageInspectionPanel)), same(preview));
          expect(_previewScroll(tester), same(scroll));
          expect(scroll.position.pixels, closeTo(offset, 0.01));
          expect(_child(fixture.notes.first.id), findsOneWidget);
          expect(fixture.recents.reads, 1);
          expect(tester.takeException(), isNull);
        }

        await _pumpPane(tester, fixture, _Results.recent, appearance, 600);
        _expectListOnly(tester, _Results.recent);
        expect(preview.mounted, isFalse);
        expect(tester.element(beta).read<RecentViewsBloc>(), same(recentBloc));
        expect(recentBloc.state.hoveredView?.id, fixture.beta.id);
        await _pumpPane(tester, fixture, _Results.recent, appearance, 1000);
        _expectSplit(tester, _Results.recent);
        expect(
          tester
              .widget<PageInspectionPanel>(
                find.byType(PageInspectionPanel),
              )
              .view
              .id,
          fixture.beta.id,
        );
        expect(_child(fixture.nested.id), findsOneWidget);
        expect(fixture.recents.reads, 1);
        expect(fixture.recentSelections, 0);
        expect(fixture.navigation.events, isEmpty);
        await _unmount(tester);
      },
    );
  }

  for (final results in _Results.values) {
    testWidgets('${results.name}: Down, Up and Enter still open the chosen row',
        (tester) async {
      _prepareViewport(tester);
      // A non-folder query hit is tested narrowly so PagePreview never asks
      // for document data. Recent views use their real wide preview layout.
      final views = results == _Results.query
          ? fixture.notes.take(2).toList()
          : [fixture.alpha, fixture.beta];
      final items = views.map(_result).toList();
      fixture.commands.showResults('note', items);
      await _openPaneRoute(
        tester,
        fixture,
        results,
        results == _Results.query ? 600 : 1000,
        items: items,
      );

      final first = _row(results, views.first.id);
      final second = _row(results, views.last.id);
      await _arrowToFirstRow(tester, first);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(_rowFocus(tester, second).hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(_rowFocus(tester, first).hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(_rowFocus(tester, second).hasFocus, isTrue);
      if (results == _Results.query) {
        expect(_resultBloc(tester).state.hoveredResult?.id, views.last.id);
      } else {
        expect(
          tester.element(second).read<RecentViewsBloc>().state.hoveredView?.id,
          views.last.id,
        );
      }
      expect(fixture.navigation.events, isEmpty);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      _expectOpened(fixture.navigation, views.last.id);
      expect(find.byType(SearchField), findsNothing);
      expect(find.byKey(_openPaletteKey), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _unmount(tester);
    });
  }

  testWidgets('wide folder Enter inspects; its Open action navigates once',
      (tester) async {
    _prepareViewport(tester);
    fixture.commands.showResults('a', fixture.items);
    await _openPaneRoute(tester, fixture, _Results.query, 1000);
    await _arrowToFirstRow(tester, _row(_Results.query, fixture.alpha.id));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      _rowFocus(tester, _row(_Results.query, fixture.beta.id)).hasFocus,
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    _expectSplit(tester, _Results.query);
    expect(
      tester
          .widget<PageInspectionPanel>(find.byType(PageInspectionPanel))
          .view
          .id,
      fixture.beta.id,
    );
    expect(fixture.navigation.events, isEmpty);

    await tester.tap(find.byKey(const ValueKey('command-palette-open-action')));
    await tester.pumpAndSettle();
    _expectOpened(fixture.navigation, fixture.beta.id);
    expect(find.byType(SearchField), findsNothing);
    await _unmount(tester);
  });

  testWidgets('explicit command mode never reserves a preview column',
      (tester) async {
    _prepareViewport(tester, const Size(1280, 900));
    fixture.commands.showResults('> zoom', const []);
    await tester.pumpWidget(
      _app(
        fixture,
        _Appearance.light,
        CommandPaletteModal(shortcutBuilder: (child) => child),
      ),
    );
    await tester.pumpAndSettle();

    for (final width in [1280.0, 600.0]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpAndSettle();
      expect(find.byType(CommandPalettePanel), findsOneWidget);
      expect(find.byType(PaletteCommandCell), findsWidgets);
      expect(find.byType(PageInspectionPanel), findsNothing);
      expect(find.byType(SearchResultList), findsNothing);
      expect(find.byType(RecentViewsList), findsNothing);
      final field = tester.getRect(find.byType(SearchField));
      final commands = tester.getRect(find.byType(CommandPalettePanel));
      expect(commands.left, closeTo(field.left, 0.01));
      expect(commands.right, closeTo(field.right, 0.01));
      expect(tester.takeException(), isNull);
    }
    expect(fixture.navigation.events, isEmpty);
    await _unmount(tester);
  });
}

void _prepareViewport(
  WidgetTester tester, [
  Size size = const Size(1600, 900),
]) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _app(_Fixture fixture, _Appearance appearance, Widget child) =>
    WidgetTestApp(child: _theme(fixture, appearance, child));

Widget _theme(_Fixture fixture, _Appearance appearance, Widget child) {
  final brightness =
      appearance == _Appearance.dark ? Brightness.dark : Brightness.light;
  final appTheme = appearance == _Appearance.paper
      ? AppTheme.builtins
          .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
      : AppTheme.fallback;
  final material = DesktopAppearance().getThemeData(
    appTheme,
    brightness,
    defaultFontFamily,
    builtInCodeFontFamily,
  );
  return Theme(
    data: material,
    child: AppFlowyTheme(
      data: PremiumTheme.appFlowyTheme(
        base: brightness == Brightness.dark
            ? AppFlowyDefaultTheme().dark()
            : AppFlowyDefaultTheme().light(),
        palette: material.extension<PremiumThemeExtension>()!,
        brightness: brightness,
      ),
      child: Directionality(
        textDirection: ui.TextDirection.ltr,
        child: BlocProvider<CommandPaletteBloc>.value(
          value: fixture.commands,
          child: child,
        ),
      ),
    ),
  );
}

Widget _pane(
  _Fixture fixture,
  _Results results, {
  List<SearchResultItem>? items,
  List<PaletteCommand> commands = const [],
  ValueChanged<PaletteCommand>? onRunCommand,
  VoidCallback? onRecentSelected,
}) =>
    results == _Results.query
        ? SearchResultList(
            cachedViews: fixture.views,
            resultItems: items ?? fixture.items,
            resultSummaries: const [],
            commands: commands,
            onRunCommand: onRunCommand,
          )
        : RecentViewsList(
            onSelected: onRecentSelected ?? () => fixture.recentSelections++,
            filter: const CommandPaletteFilter(),
            cachedViews: fixture.views,
            currentUserId: null,
          );

Future<void> _pumpPane(
  WidgetTester tester,
  _Fixture fixture,
  _Results results,
  _Appearance appearance,
  double width, {
  List<SearchResultItem>? items,
  List<PaletteCommand> commands = const [],
  ValueChanged<PaletteCommand>? onRunCommand,
}) async {
  await tester.pumpWidget(
    _app(
      fixture,
      appearance,
      Center(
        child: SizedBox(
          width: width,
          height: 620,
          child: _pane(
            fixture,
            results,
            items: items,
            commands: commands,
            onRunCommand: onRunCommand,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openPaneRoute(
  WidgetTester tester,
  _Fixture fixture,
  _Results results,
  double width, {
  List<SearchResultItem>? items,
}) async {
  await tester.pumpWidget(
    _app(
      fixture,
      _Appearance.light,
      Builder(
        builder: (context) => TextButton(
          key: _openPaletteKey,
          onPressed: () {
            unawaited(
              showDialog<void>(
                context: context,
                builder: (dialogContext) => _theme(
                  fixture,
                  _Appearance.light,
                  Dialog(
                    child: SizedBox(
                      width: width,
                      height: 700,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SearchField(query: fixture.commands.state.query),
                          Expanded(
                            child: _pane(
                              fixture,
                              results,
                              items: items,
                              onRecentSelected: () {
                                fixture.recentSelections++;
                                Navigator.of(dialogContext).pop();
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
          child: const Text('Open palette'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(_openPaletteKey));
  await tester.pumpAndSettle();
}

Finder _host(_Results results) => find.byType(
      results == _Results.query ? SearchResultList : RecentViewsList,
    );

Finder _row(_Results results, String id) => find
    .descendant(
      of: _host(results),
      matching: find.byKey(ValueKey(id)),
    )
    .first;

Finder _child(String id) =>
    find.byKey(ValueKey('command-palette-folder-child-$id'));

void _expectSplit(WidgetTester tester, _Results results, {double? listWidth}) {
  final host = _host(results);
  expect(Directionality.of(tester.element(host)), ui.TextDirection.ltr);
  expect(find.byType(PageInspectionPanel), findsOneWidget);
  final bounds = tester.getRect(host);
  final list = tester.getRect(
    find.byKey(results == _Results.query ? _searchListKey : _recentListKey),
  );
  final preview = tester.getRect(find.byKey(_inspectionKey));
  expect(list.width, greaterThan(0));
  expect(preview.width, greaterThan(0));
  expect(list.height, greaterThan(0));
  expect(preview.height, greaterThan(0));
  expect(list.left, closeTo(bounds.left, 0.01));
  expect(list.right, lessThanOrEqualTo(preview.left));
  expect(preview.right, closeTo(bounds.right, 0.01));
  final rows = find.byType(
    results == _Results.query ? SearchResultCell : SearchRecentViewCell,
  );
  expect(rows, findsWidgets);
  final row = tester.getRect(rows.first);
  expect(row.left, greaterThanOrEqualTo(list.left));
  expect(row.right, lessThanOrEqualTo(list.right));
  if (listWidth != null) {
    expect(list.width, closeTo(listWidth, 0.01));
  }
}

void _expectListOnly(WidgetTester tester, _Results results) {
  expect(find.byType(PageInspectionPanel), findsNothing);
  expect(find.byKey(_inspectionKey), findsNothing);
  final bounds = tester.getRect(_host(results));
  final list = tester.getRect(
    find.byKey(results == _Results.query ? _searchListKey : _recentListKey),
  );
  expect(list.left, closeTo(bounds.left, 0.01));
  expect(list.right, closeTo(bounds.right, 0.01));
  expect(list.width, greaterThan(0));
}

SearchResultListBloc _resultBloc(WidgetTester tester) => tester
    .element(find.byType(SearchResultCell).first)
    .read<SearchResultListBloc>();

ScrollableState _previewScroll(WidgetTester tester) =>
    tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(PageInspectionPanel),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            ),
          )
          .first,
    );

FocusNode _rowFocus(WidgetTester tester, Finder row) => tester
    .widget<Focus>(
      find
          .descendant(
            of: row,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Focus &&
                  widget.onKeyEvent != null &&
                  widget.focusNode != null,
            ),
          )
          .first,
    )
    .focusNode!;

Future<void> _arrowToFirstRow(WidgetTester tester, Finder row) async {
  final field = tester.widget<EditableText>(find.byType(EditableText));
  expect(field.focusNode.hasFocus, isTrue);
  // The real Ask AI button is also traversable. Use only Down, never a direct
  // focus assignment, to reach the result through the production focus tree.
  for (var step = 0; step < 4 && !_rowFocus(tester, row).hasFocus; step++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
  }
  expect(_rowFocus(tester, row).hasFocus, isTrue);
}

void _expectOpened(_RecordingNavigation navigation, String viewId) {
  expect(navigation.events, hasLength(1));
  navigation.events.single.when(
    performAction: (action, showErrorToast, nextActions) {
      expect(action.type, ActionType.openView);
      expect(action.objectId, viewId);
      expect(showErrorToast, isTrue);
      expect(nextActions, isEmpty);
    },
  );
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

SearchResultItem _result(ViewPB view) => SearchResultItem(
      id: view.id,
      icon: ResultIconPB(),
      content: '',
      displayName: view.name,
    );

class _Fixture {
  final alpha = _folder('pane-alpha', 'pane-workspace', 'Alpha');
  final beta = _folder('pane-beta', 'pane-workspace', 'Beta');
  late final nested = _folder('pane-nested', beta.id, 'Nested');
  late final notes = List.generate(
    16,
    (index) => ViewPB(
      id: 'pane-note-$index',
      parentViewId: nested.id,
      name: 'Note ${index.toString().padLeft(2, '0')}',
      layout: ViewLayoutPB.Document,
    ),
  );
  late final views = <String, ViewPB>{
    for (final view in [alpha, beta, nested, ...notes]) view.id: view,
  };
  late final items = [alpha, beta].map(_result).toList();
  late final commands = _PaletteBloc(views);
  late final recents = _RecentCache([alpha, beta]);
  final navigation = _RecordingNavigation();
  int recentSelections = 0;
}

// Only UI state is supplied here. Constructing CommandPaletteBloc itself
// starts native trash/search listeners, which this layout suite must not do.
class _PaletteBloc extends Cubit<CommandPaletteState>
    implements CommandPaletteBloc {
  _PaletteBloc(Map<String, ViewPB> views)
      : super(CommandPaletteState.initial().copyWith(cachedViews: views));

  final events = <CommandPaletteEvent>[];

  @override
  void add(CommandPaletteEvent event) => events.add(event);

  void showResults(String query, List<SearchResultItem> items) {
    emit(
      state.copyWith(
        query: query,
        combinedResponseItems: {for (final item in items) item.id: item},
      ),
    );
  }

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
  int reads = 0;

  @override
  Future<List<SectionViewPB>> recentViews() async {
    reads++;
    return notifier.value;
  }
}

class _EmptyAncestorCache extends ViewAncestorCache {
  @override
  Future<ViewAncestor?> getAncestor(
    String viewId, {
    ValueChanged<ViewAncestor>? onRefresh,
  }) async =>
      const ViewAncestor.empty();
}

class _RecordingNavigation extends Fake implements ActionNavigationBloc {
  final events = <ActionNavigationEvent>[];

  @override
  void add(ActionNavigationEvent event) => events.add(event);
}
