import 'dart:async';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/plugins/blank/blank.dart';
import 'package:appflowy/plugins/util.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_metadata.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_home_button.dart';
import 'package:appflowy/workspace/presentation/home/startup_home.dart';
import 'package:appflowy/workspace/presentation/home/tabs/flowy_tab.dart';
import 'package:appflowy/workspace/presentation/home/tabs/tabs_manager.dart';
import 'package:appflowy/workspace/presentation/home/workspace_navigation_controls.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart'
    hide AFRolePB;
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../util/home_profile_test_support.dart';
import 'vivid_icon_test_support.dart'
    show prepareVividIconTestAssets, vividIconTestTheme;

const _workspaceId = 'home-tabs-workspace';
const _sharedHomeId = 'configured-home';
const _plusKey = ValueKey('new-workspace-tab');
const _homeKey = ValueKey('workspace-navigation-home');
const _backKey = ValueKey('workspace-navigation-back');
const _forwardKey = ValueKey('workspace-navigation-forward');
const _overflowKey = ValueKey('open-tabs-menu');

// Exercise the real TabsBloc/PageManagers and production tab/navigation chrome.
// Do not mount BlankPage, HomeStack's document hosts, or a real ViewPluginNotifier:
// those own backend services. Draft assertions concern the retained manager and
// plugin-owned controller, not the full editor renderer or its persistence.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(prepareVividIconTestAssets);
  setUp(() => getIt.pushNewScope());
  tearDown(() async => getIt.popScope());

  group('new Home tab lifetime', () {
    for (final pinned in [false, true]) {
      testWidgets(
        'allocates before resolution and preserves the previous draft '
        '(pinned=$pinned)',
        (tester) => _withFixture(tester, (fixture) async {
          final page = await fixture.openPage(tester, 'previous-page');
          final previous = fixture.tabs.state.currentPageManager;
          final notifier = previous.notifier;
          final draft = page.draft
            ..value = const TextEditingValue(
              text: 'Unsaved draft stays here',
              selection: TextSelection.collapsed(offset: 7),
            );
          if (pinned) {
            fixture.tabs.add(TabsEvent.togglePin(previous.tabId));
            await _pump(tester);
          }

          final read = await fixture.beginHome(tester);
          // After dispatch, before lookup completes: the new tab already exists.
          final home = fixture.tabs.state.currentPageManager;
          final placeholder = home.plugin;
          expect(fixture.tabs.state.pages, 2);
          expect(fixture.tabs.state.currentIndex, 1);
          expect(home, isNot(same(previous)));
          expect(home.tabId, isNot(previous.tabId));
          expect(placeholder, isA<BlankPagePlugin>());
          expect(fixture.built, isEmpty);
          expect(read.result.isCompleted, isFalse);
          expect(fixture.menu.latestOpenView, isNull);
          expect(fixture.tabs.navigationHistory.current?.tabId, home.tabId);
          expect(fixture.tabs.navigationHistory.current?.viewId, isNull);
          expect(
            fixture.tabs.navigationHistory.peek(forward: false)?.viewId,
            page.id,
          );
          expect(
            fixture.tabs.navigationHistory.peek(forward: false)?.tabId,
            previous.tabId,
          );
          expect(previous.notifier, same(notifier));
          expect(previous.plugin, same(page));
          expect(previous.isPinned, pinned);
          expect(page.initializations, 1);
          expect(page.disposals, 0);

          await fixture.resolve(tester, read, _homeView());
          expect(fixture.tabs.state.currentPageManager, same(home));
          expect(home.plugin, same(fixture.built.single));
          expect(home.plugin.id, _sharedHomeId);
          expect(home.plugin, isNot(same(placeholder)));
          expect(fixture.built.single.initializations, 1);
          expect(fixture.tabs.homeViewId, _sharedHomeId);
          expect(fixture.menu.latestOpenView?.id, _sharedHomeId);
          expect(fixture.tabs.navigationHistory.current?.tabId, home.tabId);
          expect(fixture.tabs.navigationHistory.current?.viewId, _sharedHomeId);
          expect(previous.plugin, same(page));
          expect(page.draft, same(draft));
          expect(draft.text, 'Unsaved draft stays here');
          expect(draft.selection, const TextSelection.collapsed(offset: 7));
          expect(page.disposals, 0);
          expect(fixture.storage.writes, isEmpty);
        }),
        timeout: homeProfileTestTimeout,
      );
    }

    testWidgets(
      'rapid pending opens resolve their own managers out of order, even '
      'when all Home plugin IDs match',
      (tester) => _withFixture(tester, (fixture) async {
        await fixture.openPage(tester, 'previous-page');
        final previous = fixture.tabs.state.currentPageManager;
        final reads = <_HomeRead>[];
        final homes = <PageManager>[];
        for (var i = 0; i < 3; i++) {
          reads.add(await fixture.beginHome(tester));
          homes.add(fixture.tabs.state.currentPageManager);
        }
        expect(fixture.tabs.state.pages, 4);
        expect(homes.map((home) => home.tabId).toSet(), hasLength(3));
        expect(homes.map((home) => home.plugin.id).toSet(), {''});
        expect(homes.map((home) => home.plugin).toSet(), hasLength(3));
        expect(
          fixture.reads.map((read) => read.workspaceId),
          [_workspaceId, _workspaceId, _workspaceId],
        );
        expect(reads.every((read) => !read.result.isCompleted), isTrue);
        expect(fixture.built, isEmpty);
        final currentVisit = fixture.tabs.navigationHistory.current;
        expect(currentVisit?.tabId, homes[2].tabId);
        expect(currentVisit?.viewId, isNull);

        await fixture.resolve(tester, reads[1], _homeView());
        expect(homes[1].plugin.id, _sharedHomeId);
        expect(homes[0].plugin, isA<BlankPagePlugin>());
        expect(homes[2].plugin, isA<BlankPagePlugin>());
        expect(fixture.tabs.state.currentPageManager, same(homes[2]));
        expect(fixture.menu.latestOpenView, isNull);
        expect(fixture.tabs.navigationHistory.current, same(currentVisit));
        expect(
          fixture.tabs.navigationHistory.peek(forward: false)?.tabId,
          homes[1].tabId,
        );
        expect(
          fixture.tabs.navigationHistory.peek(forward: false)?.viewId,
          _sharedHomeId,
        );
        expect(reads[0].result.isCompleted, isFalse);
        expect(reads[2].result.isCompleted, isFalse);

        await fixture.resolve(tester, reads[2], _homeView());
        final selectedPlugin = homes[2].plugin;
        final selectedVisit = fixture.tabs.navigationHistory.current;
        expect(selectedVisit?.tabId, homes[2].tabId);
        expect(selectedVisit?.viewId, _sharedHomeId);
        expect(reads[0].result.isCompleted, isFalse);
        await fixture.resolve(tester, reads[0], _homeView());
        expect(fixture.tabs.state.currentPageManager, same(homes[2]));
        expect(homes[2].plugin, same(selectedPlugin));
        expect(fixture.tabs.navigationHistory.current, same(selectedVisit));
        expect(fixture.menu.latestOpenView?.id, _sharedHomeId);
        expect(
          homes.map((home) => home.plugin.id),
          [_sharedHomeId, _sharedHomeId, _sharedHomeId],
        );
        expect(homes.map((home) => home.tabId).toSet(), hasLength(3));
        expect(homes.map((home) => home.plugin).toSet(), hasLength(3));

        // Shared view IDs must not collapse visits or select the first Home.
        for (final home in homes.take(2).toList().reversed) {
          fixture.tabs.goBack();
          await _pump(tester);
          expect(fixture.tabs.state.currentPageManager, same(home));
          expect(fixture.tabs.navigationHistory.current?.tabId, home.tabId);
          expect(fixture.tabs.navigationHistory.current?.viewId, _sharedHomeId);
        }
        fixture.tabs.goBack();
        await _pump(tester);
        expect(fixture.tabs.state.currentPageManager, same(previous));
        expect(fixture.tabs.canGoBack, isFalse);
        for (final home in homes) {
          fixture.tabs.goForward();
          await _pump(tester);
          expect(fixture.tabs.state.currentPageManager, same(home));
          expect(fixture.tabs.navigationHistory.current?.tabId, home.tabId);
          expect(fixture.tabs.navigationHistory.current?.viewId, _sharedHomeId);
        }
        expect(fixture.tabs.canGoForward, isFalse);
        expect(fixture.tabs.state.pages, 4);
        expect(fixture.reads, hasLength(3));
        expect(
          fixture.built.map((plugin) => plugin.initializations),
          [1, 1, 1],
        );
        expect(fixture.built.map((plugin) => plugin.disposals), [0, 0, 0]);
      }),
      timeout: homeProfileTestTimeout,
    );

    testWidgets(
      'same-turn Home opens allocate distinct tabs while all lookups wait',
      (tester) => _withFixture(tester, (fixture) async {
        await fixture.openPage(tester, 'previous-page');
        final previous = fixture.tabs.state.currentPageManager;
        // No pump between dispatches: all three allocations are queued together.
        for (var i = 0; i < 3; i++) {
          unawaited(
            fixture.tabs.openHome(workspaceId: _workspaceId, newTab: true),
          );
        }
        await _pump(tester);
        final homes = fixture.tabs.state.pageManagers.skip(1).toList();
        expect(fixture.tabs.state.pages, 4);
        expect(fixture.tabs.state.pageManagers.first, same(previous));
        expect(homes, hasLength(3));
        expect(homes.map((home) => home.tabId).toSet(), hasLength(3));
        expect(homes.map((home) => home.plugin).toSet(), hasLength(3));
        expect(
          homes.map((home) => home.plugin),
          everyElement(isA<BlankPagePlugin>()),
        );
        expect(fixture.tabs.state.currentPageManager, same(homes[2]));
        expect(fixture.tabs.navigationHistory.current?.tabId, homes[2].tabId);
        expect(fixture.menu.latestOpenView, isNull);
        expect(
          fixture.reads.map((read) => read.workspaceId),
          [_workspaceId, _workspaceId, _workspaceId],
        );
        expect(fixture.reads.every((read) => !read.result.isCompleted), isTrue);
        expect(fixture.built, isEmpty);

        // Pending blank Homes also require exact tab lookup, not plugin.id.
        fixture.tabs.goBack();
        await _pump(tester);
        expect(fixture.tabs.state.currentPageManager, same(homes[1]));
        expect(fixture.tabs.navigationHistory.current?.tabId, homes[1].tabId);
        fixture.tabs.goForward();
        await _pump(tester);
        expect(fixture.tabs.state.currentPageManager, same(homes[2]));
        expect(fixture.tabs.navigationHistory.current?.tabId, homes[2].tabId);
        expect(fixture.tabs.canGoForward, isFalse);
        expect(fixture.tabs.state.pages, 4);
        expect(fixture.reads, hasLength(3));
        expect(fixture.reads.every((read) => !read.result.isCompleted), isTrue);
        expect(fixture.built, isEmpty);
      }),
      timeout: homeProfileTestTimeout,
    );

    for (final failure in ['missing', 'failed']) {
      testWidgets(
        '$failure Home resolution leaves the new blank tab usable',
        (tester) => _withFixture(tester, (fixture) async {
          await fixture.openPage(tester, 'previous-page');
          final previous = fixture.tabs.state.currentPageManager;
          final read = await fixture.beginHome(tester);
          final home = fixture.tabs.state.currentPageManager;
          final placeholder = home.plugin;
          if (failure == 'failed') {
            read.result.completeError(StateError('Offline Home lookup'));
            await _pump(tester);
          } else {
            await fixture.resolve(tester, read, null);
          }
          expect(fixture.tabs.state.pages, 2);
          expect(fixture.tabs.state.currentPageManager, same(home));
          expect(home.plugin, same(placeholder));
          expect(fixture.tabs.homeViewId, isNull);
          expect(fixture.menu.latestOpenView, isNull);
          expect(fixture.built, isEmpty);
          fixture.tabs.goBack();
          await _pump(tester);
          expect(fixture.tabs.state.currentPageManager, same(previous));
          fixture.tabs.goForward();
          await _pump(tester);
          expect(fixture.tabs.state.currentPageManager, same(home));
        }),
        timeout: homeProfileTestTimeout,
      );
    }

    testWidgets(
      'manual navigation queued before resolution replaces only the placeholder',
      (tester) => _withFixture(tester, (fixture) async {
        final previous = await fixture.openPage(tester, 'previous-page');
        final read = await fixture.beginHome(tester);
        final home = fixture.tabs.state.currentPageManager;
        final chosen = _TrackedPlugin(_pageView('manually-chosen-page'));
        fixture.open(chosen);
        // Do not handle the queued navigation first: the user's click must win
        // when its event and the resolver continuation are both pending.
        read.result.complete(_homeView(id: 'late-home'));
        await _pump(tester);
        expect(fixture.tabs.state.pages, 2);
        expect(fixture.tabs.state.currentPageManager, same(home));
        expect(home.plugin, same(chosen));
        expect(chosen.initializations, 1);
        expect(fixture.built, isEmpty);
        expect(fixture.tabs.navigationHistory.current?.viewId, chosen.id);
        expect(previous.disposals, 0);
      }),
      timeout: homeProfileTestTimeout,
    );

    testWidgets(
      'replacing the placeholder with a different plugin of the same ID '
      'invalidates its resolution',
      (tester) => _withFixture(tester, (fixture) async {
        await fixture.openPage(tester, 'previous-page');
        final read = await fixture.beginHome(tester);
        final home = fixture.tabs.state.currentPageManager;
        final placeholder = home.plugin;
        final replacement = _TrackedPlugin(
          _pageView(''),
          type: PluginType.blank,
        );
        fixture.open(replacement);
        await _pump(tester);
        expect(replacement.id, placeholder.id);
        expect(home.plugin, same(replacement));
        expect(home.plugin, isNot(same(placeholder)));
        await fixture.resolve(tester, read, _homeView(id: 'late-home'));
        expect(fixture.tabs.state.currentPageManager, same(home));
        expect(home.plugin, same(replacement));
        expect(replacement.disposals, 0);
        expect(fixture.built, isEmpty);
      }),
      timeout: homeProfileTestTimeout,
    );

    testWidgets(
      'a closed pending tab cannot resolve into a newer blank tab or reopen',
      (tester) => _withFixture(tester, (fixture) async {
        await fixture.openPage(tester, 'previous-page');
        final oldRead = await fixture.beginHome(tester);
        final closed = fixture.tabs.state.currentPageManager;
        fixture.tabs.add(TabsEvent.closeTab(closed.tabId));
        await _pump(tester);
        expect(fixture.tabs.state.pages, 1);
        final newRead = await fixture.beginHome(tester);
        final replacement = fixture.tabs.state.currentPageManager;
        expect(replacement.tabId, isNot(closed.tabId));
        final placeholder = replacement.plugin;

        await fixture.resolve(tester, oldRead, _homeView(id: 'obsolete-home'));
        expect(fixture.tabs.state.pages, 2);
        expect(fixture.tabs.state.pageManagers, isNot(contains(same(closed))));
        expect(fixture.tabs.state.currentPageManager, same(replacement));
        expect(replacement.plugin, same(placeholder));
        expect(fixture.built, isEmpty);
        await fixture.resolve(tester, newRead, _homeView());
        expect(fixture.built.map((plugin) => plugin.id), [_sharedHomeId]);
        expect(fixture.tabs.state.currentPageManager, same(replacement));
      }),
      timeout: homeProfileTestTimeout,
    );

    testWidgets(
      'closing TabsBloc rejects both late resolution and subsequent Home opens',
      (tester) => _withFixture(tester, (fixture) async {
        final page = await fixture.openPage(tester, 'previous-page');
        final read = await fixture.beginHome(tester);
        final managers = [...fixture.tabs.state.pageManagers];
        await pumpHomeProfileClose(tester, fixture.tabs.close());
        expect(page.disposals, 1);
        await fixture.resolve(tester, read, _homeView(id: 'late-home'));
        unawaited(
          fixture.tabs.openHome(workspaceId: _workspaceId, newTab: true),
        );
        await _pump(tester);
        expect(fixture.tabs.isClosed, isTrue);
        expect(fixture.tabs.state.pageManagers, orderedEquals(managers));
        expect(fixture.tabs.navigationHistory.current, isNull);
        expect(fixture.reads, hasLength(1));
        expect(fixture.built, isEmpty);
        expect(page.disposals, 1);
      }),
      timeout: homeProfileTestTimeout,
    );

    testWidgets(
      'workspace-switch intent invalidates a pending new Home without a UI guard',
      (tester) => _withFixture(tester, (fixture) async {
        await fixture.openPage(tester, 'previous-page');
        final read = await fixture.beginHome(tester);
        final home = fixture.tabs.state.currentPageManager;
        final placeholder = home.plugin;
        fixture.tabs.add(const TabsEvent.switchWorkspace('next-workspace'));
        await _pump(tester);
        await fixture.resolve(
          tester,
          read,
          _homeView(id: 'old-workspace-home'),
        );
        expect(fixture.tabs.state.currentPageManager, same(home));
        expect(home.plugin, same(placeholder));
        expect(fixture.tabs.navigationHistory.current, isNull);
        expect(fixture.built, isEmpty);
        expect(fixture.tabs.homeViewId, isNull);
      }),
      timeout: homeProfileTestTimeout,
    );

    testWidgets(
      'a newer workspace Home leaves an older still-open placeholder unresolved',
      (tester) => _withFixture(tester, (fixture) async {
        await fixture.openPage(tester, 'previous-page');
        final oldRead = await fixture.beginHome(tester);
        final oldHome = fixture.tabs.state.currentPageManager;
        final oldPlaceholder = oldHome.plugin;
        final newRead = await fixture.beginHome(
          tester,
          workspaceId: 'next-workspace',
        );
        final newHome = fixture.tabs.state.currentPageManager;
        await fixture.resolve(
          tester,
          newRead,
          _homeView(id: 'next-home', workspaceId: 'next-workspace'),
        );
        await fixture.resolve(tester, oldRead, _homeView(id: 'obsolete-home'));
        expect(fixture.tabs.state.pageManagers, contains(same(oldHome)));
        expect(oldHome.plugin, same(oldPlaceholder));
        expect(fixture.tabs.state.currentPageManager, same(newHome));
        expect(fixture.tabs.homeViewId, 'next-home');
        expect(fixture.menu.latestOpenView?.id, 'next-home');
        expect(fixture.built.map((plugin) => plugin.id), ['next-home']);
      }),
      timeout: homeProfileTestTimeout,
    );

    for (final invalid in ['empty workspace', 'stale caller']) {
      testWidgets(
        '$invalid cannot allocate a placeholder or start a Home read',
        (tester) => _withFixture(tester, (fixture) async {
          await fixture.openPage(tester, 'previous-page');
          final before = fixture.tabs.state;
          final visit = fixture.tabs.navigationHistory.current;
          unawaited(
            fixture.tabs.openHome(
              workspaceId: invalid == 'empty workspace' ? '' : _workspaceId,
              newTab: true,
              isCurrent: () => invalid != 'stale caller',
            ),
          );
          await _pump(tester);
          expect(fixture.tabs.state, same(before));
          expect(fixture.tabs.navigationHistory.current, same(visit));
          expect(fixture.reads, isEmpty);
          expect(fixture.built, isEmpty);
        }),
        timeout: homeProfileTestTimeout,
      );
    }
  });

  group('Home placeholder visit replacement', () {
    for (final appearance in ['light', 'dark', 'paper']) {
      testWidgets(
        '$appearance: real Back skips the resolved placeholder and Forward '
        'returns to the same Home manager',
        (tester) => _withFixture(tester, (fixture) async {
          await fixture.openPage(tester, 'previous-page');
          final previous = fixture.tabs.state.currentPageManager;
          await fixture.mount(tester, appearance: appearance);
          expect(
            tester.widget<IconButton>(find.byKey(_backKey)).onPressed,
            isNull,
          );
          await tester.tap(find.byKey(_plusKey));
          await _pump(tester);
          final home = fixture.tabs.state.currentPageManager;
          expect(home.plugin, isA<BlankPagePlugin>());
          expect(fixture.tabs.navigationHistory.current?.tabId, home.tabId);
          expect(fixture.tabs.navigationHistory.current?.viewId, isNull);
          expect(fixture.reads.single.result.isCompleted, isFalse);
          await fixture.resolve(tester, fixture.reads.single, _homeView());

          // This is one visit changing its destination, NOT an extra visit to
          // an invisible blank Home before the configured Home.
          expect(fixture.tabs.navigationHistory.current?.tabId, home.tabId);
          expect(fixture.tabs.navigationHistory.current?.viewId, _sharedHomeId);
          expect(
            fixture.tabs.navigationHistory.peek(forward: false)?.tabId,
            previous.tabId,
          );
          expect(
            fixture.tabs.navigationHistory.peek(forward: false)?.viewId,
            'previous-page',
          );
          expect(
            tester.widget<IconButton>(find.byKey(_backKey)).onPressed,
            isNotNull,
          );
          await tester.tap(find.byKey(_backKey));
          await _pump(tester);
          expect(fixture.tabs.state.currentPageManager, same(previous));
          expect(fixture.tabs.navigationHistory.current?.tabId, previous.tabId);
          expect(
            fixture.tabs.navigationHistory.current?.viewId,
            'previous-page',
          );
          expect(fixture.tabs.canGoBack, isFalse);
          expect(fixture.menu.latestOpenView?.id, 'previous-page');
          expect(
            tester.widget<IconButton>(find.byKey(_backKey)).onPressed,
            isNull,
          );
          expect(
            tester.widget<IconButton>(find.byKey(_forwardKey)).onPressed,
            isNotNull,
          );

          await tester.tap(find.byKey(_forwardKey));
          await _pump(tester);
          expect(fixture.tabs.state.currentPageManager, same(home));
          expect(fixture.tabs.navigationHistory.current?.tabId, home.tabId);
          expect(home.plugin, same(fixture.built.single));
          expect(fixture.tabs.canGoForward, isFalse);
          expect(fixture.tabs.state.pages, 2);
          expect(fixture.historyReads, isEmpty);
          expect(fixture.built.single.initializations, 1);
        }),
        timeout: homeProfileTestTimeout,
      );
    }

    testWidgets(
      'background completion updates its earlier visit, not the selected page',
      (tester) => _withFixture(tester, (fixture) async {
        await fixture.openPage(tester, 'previous-page');
        final previous = fixture.tabs.state.currentPageManager;
        final read = await fixture.beginHome(tester);
        final home = fixture.tabs.state.currentPageManager;
        await fixture.select(tester, previous);
        final selectedVisit = fixture.tabs.navigationHistory.current;
        expect(selectedVisit?.tabId, previous.tabId);
        expect(
          fixture.tabs.navigationHistory.peek(forward: false)?.tabId,
          home.tabId,
        );
        expect(
          fixture.tabs.navigationHistory.peek(forward: false)?.viewId,
          isNull,
        );
        expect(read.result.isCompleted, isFalse);
        expect(fixture.menu.latestOpenView?.id, 'previous-page');

        await fixture.resolve(tester, read, _homeView());
        expect(fixture.tabs.state.currentPageManager, same(previous));
        expect(fixture.tabs.navigationHistory.current, same(selectedVisit));
        expect(fixture.menu.latestOpenView?.id, 'previous-page');
        expect(
          fixture.tabs.navigationHistory.peek(forward: false)?.tabId,
          home.tabId,
        );
        expect(
          fixture.tabs.navigationHistory.peek(forward: false)?.viewId,
          _sharedHomeId,
        );
        fixture.tabs.goBack();
        await _pump(tester);
        expect(fixture.tabs.state.currentPageManager, same(home));
        expect(fixture.tabs.navigationHistory.current?.tabId, home.tabId);
        expect(home.plugin.id, _sharedHomeId);
        fixture.tabs.goBack();
        await _pump(tester);
        expect(fixture.tabs.state.currentPageManager, same(previous));
        expect(fixture.tabs.canGoBack, isFalse);
        expect(fixture.tabs.state.pages, 2);
      }),
      timeout: homeProfileTestTimeout,
    );

    testWidgets(
      'resolving after Back keeps the forward branch and replaces its placeholder',
      (tester) => _withFixture(tester, (fixture) async {
        await fixture.openPage(tester, 'previous-page');
        final previous = fixture.tabs.state.currentPageManager;
        final read = await fixture.beginHome(tester);
        final home = fixture.tabs.state.currentPageManager;
        fixture.tabs.goBack();
        await _pump(tester);
        expect(fixture.tabs.state.currentPageManager, same(previous));
        expect(fixture.tabs.canGoForward, isTrue);
        final selectedVisit = fixture.tabs.navigationHistory.current;
        expect(selectedVisit?.tabId, previous.tabId);
        expect(
          fixture.tabs.navigationHistory.peek(forward: true)?.tabId,
          home.tabId,
        );
        expect(
          fixture.tabs.navigationHistory.peek(forward: true)?.viewId,
          isNull,
        );
        expect(read.result.isCompleted, isFalse);

        await fixture.resolve(tester, read, _homeView());
        expect(fixture.tabs.state.currentPageManager, same(previous));
        expect(fixture.tabs.navigationHistory.current, same(selectedVisit));
        expect(fixture.tabs.navigationHistory.current?.viewId, 'previous-page');
        expect(
          fixture.tabs.navigationHistory.peek(forward: true)?.tabId,
          home.tabId,
        );
        expect(
          fixture.tabs.navigationHistory.peek(forward: true)?.viewId,
          _sharedHomeId,
        );
        expect(fixture.tabs.canGoBack, isFalse);
        expect(fixture.tabs.canGoForward, isTrue);
        fixture.tabs.goForward();
        await _pump(tester);
        expect(fixture.tabs.state.currentPageManager, same(home));
        expect(fixture.tabs.navigationHistory.current?.tabId, home.tabId);
        expect(home.plugin.id, _sharedHomeId);
        expect(fixture.tabs.canGoForward, isFalse);
        fixture.tabs.goBack();
        await _pump(tester);
        expect(fixture.tabs.state.currentPageManager, same(previous));
      }),
      timeout: homeProfileTestTimeout,
    );
  });

  group('commands address tab IDs, not shared Home plugin IDs', () {
    testWidgets(
      'closeTab removes one background Home and a stale tab ID is harmless',
      (tester) => _withFixture(tester, (fixture) async {
        await fixture.openPage(tester, 'previous-page');
        final first = await fixture.resolvedNewHome(tester);
        final target = await fixture.resolvedNewHome(tester);
        final current = await fixture.resolvedNewHome(tester);
        final closedPlugin = target.plugin as _TrackedPlugin;
        fixture.tabs.add(TabsEvent.closeTab(target.tabId));
        await _pump(tester);
        expect(fixture.tabs.state.pages, 3);
        expect(fixture.tabs.state.currentPageManager, same(current));
        expect(fixture.tabs.state.pageManagers, contains(same(first)));
        expect(fixture.tabs.state.pageManagers, isNot(contains(same(target))));
        expect(fixture.tabs.state.managerForTab(target.tabId), isNull);
        expect(closedPlugin.disposals, 1);
        expect((first.plugin as _TrackedPlugin).disposals, 0);
        expect((current.plugin as _TrackedPlugin).disposals, 0);
        final remaining = [...fixture.tabs.state.pageManagers];
        fixture.tabs.add(TabsEvent.closeTab(target.tabId));
        await _pump(tester);
        target.dispose();
        expect(fixture.tabs.state.pageManagers, orderedEquals(remaining));
        expect(closedPlugin.disposals, 1);
        expect(closedPlugin.notifier.disposals, 1);
        expect(fixture.reads, hasLength(3));
      }),
      timeout: homeProfileTestTimeout,
    );

    testWidgets(
      'closeCurrentTab closes the selected duplicate, not the first Home',
      (tester) => _withFixture(tester, (fixture) async {
        await fixture.openPage(tester, 'previous-page');
        final first = await fixture.resolvedNewHome(tester);
        final current = await fixture.resolvedNewHome(tester);
        fixture.tabs.add(const TabsEvent.closeCurrentTab());
        await _pump(tester);
        expect(fixture.tabs.state.pages, 2);
        expect(fixture.tabs.state.currentPageManager, same(first));
        expect(fixture.tabs.state.pageManagers, isNot(contains(same(current))));
        expect((first.plugin as _TrackedPlugin).disposals, 0);
        expect((current.plugin as _TrackedPlugin).disposals, 1);
      }),
      timeout: homeProfileTestTimeout,
    );

    testWidgets(
      'pin and unpin affect one duplicate and preserve manager/draft identity',
      (tester) => _withFixture(tester, (fixture) async {
        final page = await fixture.openPage(tester, 'previous-page');
        final previous = fixture.tabs.state.currentPageManager;
        final draft = page.draft..text = 'Keep this unsaved draft';
        final first = await fixture.resolvedNewHome(tester);
        final target = await fixture.resolvedNewHome(tester);
        final current = await fixture.resolvedNewHome(tester);
        final tabId = target.tabId;
        final plugin = target.plugin;
        fixture.tabs.add(TabsEvent.togglePin(tabId));
        await _pump(tester);
        expect(fixture.tabs.state.pageManagers.first, same(target));
        expect(
          fixture.tabs.state.pageManagers.where((pm) => pm.isPinned),
          [target],
        );
        expect(fixture.tabs.state.currentPageManager, same(current));
        expect(first.isPinned, isFalse);
        expect(current.isPinned, isFalse);

        await fixture.select(tester, target);
        fixture.tabs.add(TabsEvent.togglePin(tabId));
        await _pump(tester);
        expect(fixture.tabs.state.currentPageManager, same(target));
        expect(
          fixture.tabs.state.pageManagers.where((pm) => pm.isPinned),
          isEmpty,
        );
        expect(target.tabId, tabId);
        expect(target.plugin, same(plugin));
        fixture.tabs.reorderTab(
          fixture.tabs.state.pageManagers.indexOf(previous),
          fixture.tabs.state.pages,
        );
        await _pump(tester);
        await fixture.select(tester, previous);
        expect(fixture.tabs.state.currentPageManager, same(previous));
        expect(previous.plugin, same(page));
        expect(page.draft, same(draft));
        expect(draft.text, 'Keep this unsaved draft');
        expect(page.initializations, 1);
        expect(page.disposals, 0);
        expect(fixture.built.map((item) => item.initializations), [1, 1, 1]);
      }),
      timeout: homeProfileTestTimeout,
    );

    for (final currentPinned in [false, true]) {
      testWidgets(
        'closeOthers keeps the exact duplicate and pinned tabs '
        '(current pinned=$currentPinned)',
        (tester) => _withFixture(tester, (fixture) async {
          final page = await fixture.openPage(tester, 'pinned-page');
          final pinned = fixture.tabs.state.currentPageManager;
          fixture.tabs.add(TabsEvent.togglePin(pinned.tabId));
          await _pump(tester);
          final other = await fixture.resolvedNewHome(tester);
          final target = await fixture.resolvedNewHome(tester);
          final last = await fixture.resolvedNewHome(tester);
          if (currentPinned) await fixture.select(tester, pinned);
          fixture.tabs.add(TabsEvent.closeOtherTabs(target.tabId));
          await _pump(tester);
          expect(fixture.tabs.state.pageManagers, [pinned, target]);
          expect(
            fixture.tabs.state.currentPageManager,
            same(currentPinned ? pinned : target),
          );
          expect(pinned.isPinned, isTrue);
          expect(target.isPinned, isFalse);
          expect(page.disposals, 0);
          expect((target.plugin as _TrackedPlugin).disposals, 0);
          expect((other.plugin as _TrackedPlugin).disposals, 1);
          expect((last.plugin as _TrackedPlugin).disposals, 1);
          expect(fixture.reads, hasLength(3));
        }),
        timeout: homeProfileTestTimeout,
      );
    }

    for (final currentCommand in [false, true]) {
      testWidgets(
        'explicit close can remove a pinned Home '
        '(closeCurrentTab=$currentCommand)',
        (tester) => _withFixture(tester, (fixture) async {
          await fixture.openPage(tester, 'previous-page');
          final first = await fixture.resolvedNewHome(tester);
          final target = await fixture.resolvedNewHome(tester);
          fixture.tabs.add(TabsEvent.togglePin(target.tabId));
          await _pump(tester);
          expect(fixture.tabs.state.currentPageManager, same(target));
          expect(target.isPinned, isTrue);
          fixture.tabs.add(
            currentCommand
                ? const TabsEvent.closeCurrentTab()
                : TabsEvent.closeTab(target.tabId),
          );
          await _pump(tester);
          expect(fixture.tabs.state.pages, 2);
          expect(fixture.tabs.state.pageManagers, contains(same(first)));
          expect(
            fixture.tabs.state.pageManagers,
            isNot(contains(same(target))),
          );
          expect((target.plugin as _TrackedPlugin).disposals, 1);
          expect((first.plugin as _TrackedPlugin).disposals, 0);
        }),
        timeout: homeProfileTestTimeout,
      );
    }

    for (final command in ['close', 'pin', 'close others']) {
      testWidgets(
        'legacy plugin ID remains compatible with $command and targets one Home',
        (tester) => _withFixture(tester, (fixture) async {
          await fixture.openPage(tester, 'previous-page');
          final first = await fixture.resolvedNewHome(tester);
          final second = await fixture.resolvedNewHome(tester);
          expect(first.plugin.id, second.plugin.id);
          expect(fixture.tabs.state.managerForTab(_sharedHomeId), same(first));
          fixture.tabs.add(
            switch (command) {
              'close' => const TabsEvent.closeTab(_sharedHomeId),
              'pin' => const TabsEvent.togglePin(_sharedHomeId),
              _ => const TabsEvent.closeOtherTabs(_sharedHomeId),
            },
          );
          await _pump(tester);
          switch (command) {
            case 'close':
              expect(fixture.tabs.state.pages, 2);
              expect(fixture.tabs.state.currentPageManager, same(second));
              expect(
                fixture.tabs.state.pageManagers,
                isNot(contains(same(first))),
              );
              expect((first.plugin as _TrackedPlugin).disposals, 1);
              expect((second.plugin as _TrackedPlugin).disposals, 0);
            case 'pin':
              expect(fixture.tabs.state.pages, 3);
              expect(fixture.tabs.state.currentPageManager, same(second));
              expect(
                fixture.tabs.state.pageManagers.where((pm) => pm.isPinned),
                [first],
              );
            case 'close others':
              expect(fixture.tabs.state.pageManagers, [first]);
              expect(fixture.tabs.state.currentPageManager, same(first));
              expect((first.plugin as _TrackedPlugin).disposals, 0);
              expect((second.plugin as _TrackedPlugin).disposals, 1);
          }
        }),
        timeout: homeProfileTestTimeout,
      );
    }

    testWidgets(
      'an exact tab ID wins over another tab whose plugin ID happens to match',
      (tester) => _withFixture(tester, (fixture) async {
        final page = await fixture.openPage(tester, 'previous-page');
        final original = fixture.tabs.state.currentPageManager;
        final home = await fixture.resolvedNewHome(tester, id: original.tabId);
        expect(home.plugin.id, original.tabId);
        expect(
          fixture.tabs.state.managerForTab(original.tabId),
          same(original),
        );
        fixture.tabs.add(TabsEvent.closeTab(original.tabId));
        await _pump(tester);
        expect(fixture.tabs.state.pageManagers, [home]);
        expect(fixture.tabs.state.currentPageManager, same(home));
        expect(page.disposals, 1);
        expect((home.plugin as _TrackedPlugin).disposals, 0);
      }),
      timeout: homeProfileTestTimeout,
    );
  });

  group('closing the last tab', () {
    for (final currentCommand in [false, true]) {
      testWidgets(
        'without a known Home workspace returns a fresh blank and disposes '
        'both plugins once (closeCurrentTab=$currentCommand)',
        (tester) => _withFixture(tester, (fixture) async {
          final page = await fixture.openPage(tester, 'only-page');
          final old = fixture.tabs.state.currentPageManager;
          final secondary = await fixture.openSecondary(tester);
          fixture.tabs.add(TabsEvent.togglePin(old.tabId));
          await _pump(tester);
          final snapshot = fixture.tabs.state;
          fixture.tabs.add(
            currentCommand
                ? const TabsEvent.closeCurrentTab()
                : TabsEvent.closeTab(old.tabId),
          );
          await _pump(tester);
          final fallback = fixture.tabs.state.currentPageManager;
          expect(fixture.tabs.state.pages, 1);
          expect(fixture.tabs.state.currentIndex, 0);
          expect(fallback, isNot(same(old)));
          expect(fallback.tabId, isNot(old.tabId));
          expect(fallback.plugin, isA<BlankPagePlugin>());
          expect(fallback.isPinned, isFalse);
          expect(fixture.menu.latestOpenView, isNull);
          expect(fixture.reads, isEmpty);
          fixture.tabs.add(TabsEvent.closeTab(old.tabId));
          await _pump(tester);
          snapshot.dispose();
          old.dispose();
          expect(fixture.tabs.state.currentPageManager, same(fallback));
          expect(page.disposals, 1);
          expect(page.notifier.disposals, 1);
          expect(secondary.disposals, 1);
          expect(secondary.notifier.disposals, 1);
        }),
        timeout: homeProfileTestTimeout,
      );
    }

    for (final resolution in ['configured', 'missing', 'failed']) {
      testWidgets(
        'known workspace resolves its $resolution Home after the last pinned '
        'tab closes',
        (tester) => _withFixture(tester, (fixture) async {
          final initial = await fixture.beginHome(tester, newTab: false);
          await fixture.resolve(tester, initial, _homeView(id: 'initial-home'));
          final old = fixture.tabs.state.currentPageManager;
          final plugin = old.plugin as _TrackedPlugin;
          final secondary = await fixture.openSecondary(tester);
          fixture.tabs.add(TabsEvent.togglePin(old.tabId));
          await _pump(tester);
          final snapshot = fixture.tabs.state;

          fixture.tabs.add(const TabsEvent.closeCurrentTab());
          await _pump(tester);
          final fallback = fixture.tabs.state.currentPageManager;
          final placeholder = fallback.plugin;
          expect(fixture.tabs.state.pages, 1);
          expect(fallback, isNot(same(old)));
          expect(placeholder, isA<BlankPagePlugin>());
          expect(fallback.isPinned, isFalse);
          expect(fixture.menu.latestOpenView, isNull);
          expect(
            fixture.reads.map((read) => read.workspaceId),
            [_workspaceId, _workspaceId],
          );
          expect(fixture.reads.last.result.isCompleted, isFalse);
          expect(plugin.disposals, 1);
          expect(secondary.disposals, 1);
          // Old immutable snapshots share managers, so releasing one later
          // must not dispose a closed tab's resources a second time.
          snapshot.dispose();
          old.dispose();

          if (resolution == 'failed') {
            fixture.reads.last.result.completeError(StateError('Home offline'));
            await _pump(tester);
          } else {
            await fixture.resolve(
              tester,
              fixture.reads.last,
              resolution == 'configured' ? _homeView() : null,
            );
          }
          expect(fixture.tabs.state.pages, 1);
          expect(fixture.tabs.state.currentPageManager, same(fallback));
          if (resolution == 'configured') {
            expect(fallback.plugin.id, _sharedHomeId);
            expect(fixture.tabs.homeViewId, _sharedHomeId);
            expect(fixture.menu.latestOpenView?.id, _sharedHomeId);
            expect(
              fixture.built.map((item) => item.id),
              ['initial-home', _sharedHomeId],
            );
          } else {
            expect(fallback.plugin, same(placeholder));
            expect(fixture.tabs.homeViewId, isNull);
            expect(fixture.menu.latestOpenView, isNull);
            expect(fixture.built.map((item) => item.id), ['initial-home']);
          }
          expect(plugin.disposals, 1);
          expect(plugin.notifier.disposals, 1);
          expect(secondary.disposals, 1);
          expect(secondary.notifier.disposals, 1);
          expect(fixture.storage.writes, isEmpty);
        }),
        timeout: homeProfileTestTimeout,
      );
    }

    testWidgets(
      'manual navigation wins over automatic Home after closing the last tab',
      (tester) => _withFixture(tester, (fixture) async {
        final initial = await fixture.beginHome(tester, newTab: false);
        await fixture.resolve(tester, initial, _homeView(id: 'initial-home'));
        final old = fixture.tabs.state.currentPageManager;
        fixture.tabs.add(TabsEvent.closeTab(old.tabId));
        await _pump(tester);
        final fallback = fixture.tabs.state.currentPageManager;
        final chosen = _TrackedPlugin(_pageView('chosen-after-close'));
        fixture.open(chosen);
        fixture.reads.last.result.complete(_homeView(id: 'late-home'));
        await _pump(tester);
        expect(fixture.tabs.state.pages, 1);
        expect(fixture.tabs.state.currentPageManager, same(fallback));
        expect(fallback.plugin, same(chosen));
        expect(fixture.built.map((plugin) => plugin.id), ['initial-home']);
        expect((old.plugin as _TrackedPlugin).disposals, 1);
        expect(fixture.tabs.navigationHistory.current?.viewId, chosen.id);
      }),
      timeout: homeProfileTestTimeout,
    );

    testWidgets(
      'closing a last-tab fallback again rejects the first automatic Home read',
      (tester) => _withFixture(tester, (fixture) async {
        final initial = await fixture.beginHome(tester, newTab: false);
        await fixture.resolve(tester, initial, _homeView(id: 'initial-home'));
        final original = fixture.tabs.state.currentPageManager;
        fixture.tabs.add(const TabsEvent.closeCurrentTab());
        await _pump(tester);
        final oldFallback = fixture.tabs.state.currentPageManager;
        final obsolete = fixture.reads.last;
        fixture.tabs.add(TabsEvent.closeTab(oldFallback.tabId));
        await _pump(tester);
        final currentFallback = fixture.tabs.state.currentPageManager;
        expect(currentFallback, isNot(same(oldFallback)));
        expect(fixture.reads, hasLength(3));
        await fixture.resolve(tester, fixture.reads.last, _homeView());
        await fixture.resolve(tester, obsolete, _homeView(id: 'obsolete-home'));
        expect(fixture.tabs.state.pageManagers, [currentFallback]);
        expect(currentFallback.plugin.id, _sharedHomeId);
        expect(
          fixture.built.map((plugin) => plugin.id),
          ['initial-home', _sharedHomeId],
        );
        expect((original.plugin as _TrackedPlugin).disposals, 1);
      }),
      timeout: homeProfileTestTimeout,
    );
  });

  group('production Home/tab controls', () {
    testWidgets(
      'pointer plus, Enter and Space each create a tab while previous reads wait',
      (tester) => _withFixture(tester, (fixture) async {
        await fixture.openPage(tester, 'previous-page');
        await fixture.mount(tester);
        final homes = <PageManager>[];
        await tester.tap(find.byKey(_plusKey), kind: PointerDeviceKind.mouse);
        await _pump(tester);
        homes.add(fixture.tabs.state.currentPageManager);
        expect(fixture.reads, hasLength(1));
        for (final key in [
          LogicalKeyboardKey.enter,
          LogicalKeyboardKey.space,
        ]) {
          final icon = tester.widget<IconButton>(find.byKey(_plusKey)).icon;
          final glyph = find.descendant(
            of: find.byKey(_plusKey),
            matching: find.byWidget(icon),
          );
          expect(glyph, findsOneWidget);
          // The icon is inside the native button's Focus, unlike the
          // IconButton element itself. No private Focus State is needed.
          final focus = Focus.of(tester.element(glyph));
          focus.requestFocus();
          await _pump(tester);
          expect(focus.hasPrimaryFocus, isTrue);
          await tester.sendKeyEvent(key);
          await _pump(tester);
          homes.add(fixture.tabs.state.currentPageManager);
          expect(fixture.reads, hasLength(homes.length));
          expect(fixture.tabs.state.pages, homes.length + 1);
        }
        expect(homes.map((home) => home.tabId).toSet(), hasLength(3));
        expect(fixture.reads.every((read) => !read.result.isCompleted), isTrue);
        expect(fixture.built, isEmpty);
        expect(find.byType(Dialog), findsNothing);
        for (final read in fixture.reads.reversed) {
          await fixture.resolve(tester, read, _homeView());
          expect(fixture.tabs.state.currentPageManager, same(homes.last));
        }
        expect(fixture.tabs.state.pages, 4);
        expect(homes.every((home) => home.plugin.id == _sharedHomeId), isTrue);
      }),
      timeout: homeProfileTestTimeout,
    );

    for (final invalidation in [
      'workspace',
      'user',
      'unmount',
      'workspace bloc close',
    ]) {
      testWidgets(
        'plus ignores a late result after $invalidation',
        (tester) => _withFixture(tester, (fixture) async {
          await fixture.openPage(tester, 'previous-page');
          await fixture.mount(tester);
          await tester.tap(find.byKey(_plusKey));
          await _pump(tester);
          final read = fixture.reads.single;
          final home = fixture.tabs.state.currentPageManager;
          final placeholder = home.plugin;
          final visit = fixture.tabs.navigationHistory.current;
          switch (invalidation) {
            case 'workspace':
              fixture.workspace.changeWorkspace('next-workspace');
            case 'user':
              fixture.workspace.changeUser(8);
            case 'unmount':
              await tester.pumpWidget(const SizedBox.shrink());
            case 'workspace bloc close':
              await pumpHomeProfileClose(tester, fixture.workspace.close());
          }
          // For identity changes, complete before the selector's next frame.
          read.result.complete(_homeView(id: 'stale-home'));
          await tester.idle();
          expect(fixture.built, isEmpty);
          await _pump(tester);
          expect(fixture.tabs.state.currentPageManager, same(home));
          expect(home.plugin, same(placeholder));
          expect(fixture.tabs.navigationHistory.current, same(visit));
          expect(fixture.tabs.homeViewId, isNull);
          expect(fixture.menu.latestOpenView, isNull);
          expect(fixture.reads, hasLength(1));
        }),
        timeout: homeProfileTestTimeout,
      );
    }

    for (final action in ['close button', 'middle click']) {
      for (final pinned in [false, true]) {
        testWidgets(
          'real $action targets one background Home (pinned=$pinned)',
          (tester) => _withFixture(tester, (fixture) async {
            await fixture.openPage(tester, 'previous-page');
            final first = await fixture.resolvedNewHome(tester);
            final target = await fixture.resolvedNewHome(tester);
            final current = await fixture.resolvedNewHome(tester);
            if (pinned) {
              fixture.tabs.add(TabsEvent.togglePin(target.tabId));
              await _pump(tester);
            }
            await fixture.mount(tester, appearance: 'paper');
            if (action == 'middle click') {
              await tester.tap(
                _tab(target),
                kind: PointerDeviceKind.mouse,
                buttons: kMiddleMouseButton,
              );
            } else {
              final close = find.descendant(
                of: _tab(target),
                matching: find.byType(IconButton),
              );
              expect(close.hitTestable(), findsOneWidget);
              await tester.tap(close, kind: PointerDeviceKind.mouse);
            }
            await _pump(tester);
            expect(fixture.tabs.state.pages, 3);
            expect(fixture.tabs.state.currentPageManager, same(current));
            expect(fixture.tabs.state.pageManagers, contains(same(first)));
            expect(
              fixture.tabs.state.pageManagers,
              isNot(contains(same(target))),
            );
            expect((target.plugin as _TrackedPlugin).disposals, 1);
            expect((first.plugin as _TrackedPlugin).disposals, 0);
            expect((current.plugin as _TrackedPlugin).disposals, 0);
          }),
          timeout: homeProfileTestTimeout,
        );
      }
    }

    testWidgets(
      'the lone pinned tab has a working close button and resolves a fresh Home',
      (tester) => _withFixture(tester, (fixture) async {
        final initial = await fixture.beginHome(tester, newTab: false);
        await fixture.resolve(tester, initial, _homeView());
        final old = fixture.tabs.state.currentPageManager;
        final plugin = old.plugin as _TrackedPlugin;
        fixture.tabs.add(TabsEvent.togglePin(old.tabId));
        await _pump(tester);
        await fixture.mount(tester);
        expect(fixture.tabs.state.isAllPinned, isTrue);
        final close = find.descendant(
          of: _tab(old),
          matching: find.byType(IconButton),
        );
        expect(close.hitTestable(), findsOneWidget);
        await tester.tap(close);
        await _pump(tester);
        final fallback = fixture.tabs.state.currentPageManager;
        expect(fixture.tabs.state.pages, 1);
        expect(fallback.tabId, isNot(old.tabId));
        expect(fallback.plugin, isA<BlankPagePlugin>());
        expect(fallback.isPinned, isFalse);
        expect(plugin.disposals, 1);
        expect(fixture.reads, hasLength(2));
        await fixture.resolve(tester, fixture.reads.last, _homeView());
        expect(fixture.tabs.state.currentPageManager, same(fallback));
        expect(fallback.plugin.id, plugin.id);
        expect(fallback.plugin, isNot(same(plugin)));
        expect((fallback.plugin as _TrackedPlugin).initializations, 1);
        expect(plugin.disposals, 1);
      }),
      timeout: homeProfileTestTimeout,
    );

    testWidgets(
      'overflow pins the selected duplicate, protects it during close-others, '
      'and can explicitly close the last pinned tab',
      (tester) => _withFixture(tester, (fixture) async {
        final page = await fixture.openPage(tester, 'previous-page');
        final first = await fixture.resolvedNewHome(tester);
        final target = await fixture.resolvedNewHome(tester);
        // Narrow rail exposes the production overflow's tab actions.
        await fixture.mount(
          tester,
          width: 4 * HomeSizes.navigationButtonSize +
              HomeSizes.tabPaneMinWidth / 2,
        );
        expect(
          tester
              .widget<TabsOverflowButton>(find.byType(TabsOverflowButton))
              .includeTabActions,
          isTrue,
        );
        await _chooseOverflow(tester, 'Pin tab');
        expect(target.isPinned, isTrue);
        expect(first.isPinned, isFalse);
        expect(fixture.tabs.state.currentPageManager, same(target));

        fixture.tabs.add(TabsEvent.togglePin(first.tabId));
        await _pump(tester);
        await _chooseOverflow(tester, 'Unpin tab');
        expect(first.isPinned, isTrue);
        expect(target.isPinned, isFalse);
        expect(fixture.tabs.state.currentPageManager, same(target));
        // Keep the other Home first in tab order. A UI callback that mistakenly
        // sends plugin.id would now target that Home instead of this one.
        expect(fixture.tabs.state.pageManagers.first, same(first));
        await _chooseOverflow(tester, 'Close others');
        expect(fixture.tabs.state.pageManagers, [first, target]);
        expect(fixture.tabs.state.currentPageManager, same(target));
        expect(page.disposals, 1);
        expect((first.plugin as _TrackedPlugin).disposals, 0);
        expect((target.plugin as _TrackedPlugin).disposals, 0);
        await _chooseOverflow(tester, 'Close');
        expect(fixture.tabs.state.pageManagers, [first]);
        expect(fixture.tabs.state.currentPageManager, same(first));
        expect(first.isPinned, isTrue);
        expect((target.plugin as _TrackedPlugin).disposals, 1);
        expect((first.plugin as _TrackedPlugin).disposals, 0);
        await _chooseOverflow(tester, 'Close');
        final fallback = fixture.tabs.state.currentPageManager;
        expect(fallback, isNot(same(first)));
        expect(fallback.plugin, isA<BlankPagePlugin>());
        expect(fallback.isPinned, isFalse);
        expect(fixture.tabs.state.pages, 1);
        expect((first.plugin as _TrackedPlugin).disposals, 1);
        expect((target.plugin as _TrackedPlugin).disposals, 1);
        expect(fixture.reads, hasLength(3));
        await fixture.resolve(tester, fixture.reads.last, null);
        expect(fixture.tabs.state.currentPageManager, same(fallback));
      }),
      timeout: homeProfileTestTimeout,
    );

    for (final control in ['title bar', 'sidebar']) {
      testWidgets(
        '$control Home reuses an existing Home instead of behaving like plus',
        (tester) => _withFixture(tester, (fixture) async {
          final manual = await fixture.openPage(tester, 'previous-page');
          final previous = fixture.tabs.state.currentPageManager;
          manual.draft.text = 'Still unsaved';
          final first = await fixture.resolvedNewHome(tester);
          final second = await fixture.resolvedNewHome(tester);
          final originalHomePlugin = first.plugin as _TrackedPlugin;
          await fixture.select(tester, previous);
          await fixture.mount(tester, sidebarHome: true);
          final button = find.byKey(
            control == 'sidebar' ? const ValueKey('sidebar-home') : _homeKey,
          );
          for (var attempt = 0; attempt < 2; attempt++) {
            await tester.tap(button);
            await _pump(tester);
            expect(fixture.tabs.state.pages, 3);
            await fixture.resolve(tester, fixture.reads.last, _homeView());
            expect(fixture.tabs.state.currentPageManager, same(first));
            expect(first.plugin, same(originalHomePlugin));
            expect(fixture.tabs.state.pageManagers, [previous, first, second]);
            expect(manual.draft.text, 'Still unsaved');
            expect(manual.disposals, 0);
          }
          expect(originalHomePlugin.initializations, 1);
          expect(originalHomePlugin.disposals, 0);
          // Reuse must also release the unused candidate's constructor-owned
          // notifier without init/dispose of an unopened plugin's late fields.
          expect(
            fixture.built.skip(2).map((plugin) => plugin.initializations),
            [0, 0],
          );
          expect(
            fixture.built.skip(2).map((plugin) => plugin.notifier.disposals),
            [1, 1],
          );
          expect(fixture.storage.writes, isEmpty);
        }),
        timeout: homeProfileTestTimeout,
      );
    }

    testWidgets(
      'Home also reuses an existing blank fallback among duplicate blank tabs',
      (tester) => _withFixture(tester, (fixture) async {
        final page = await fixture.openPage(tester, 'previous-page');
        final previous = fixture.tabs.state.currentPageManager;
        final firstRead = await fixture.beginHome(tester);
        final first = fixture.tabs.state.currentPageManager;
        await fixture.resolve(tester, firstRead, null);
        final secondRead = await fixture.beginHome(tester);
        final second = fixture.tabs.state.currentPageManager;
        await fixture.resolve(tester, secondRead, null);
        expect(first.plugin.id, second.plugin.id);
        expect(first.tabId, isNot(second.tabId));
        await fixture.select(tester, previous);
        await fixture.mount(tester);
        await tester.tap(find.byKey(_homeKey));
        await _pump(tester);
        expect(fixture.tabs.state.currentPageManager, same(previous));
        expect(fixture.tabs.state.pages, 3);
        expect(fixture.reads, hasLength(3));
        await fixture.resolve(tester, fixture.reads.last, null);
        expect(fixture.tabs.state.currentPageManager, same(first));
        expect(fixture.tabs.state.pageManagers, [previous, first, second]);
        expect(first.plugin, isA<BlankPagePlugin>());
        expect(fixture.menu.latestOpenView, isNull);
        expect(fixture.built, isEmpty);
        expect(page.disposals, 0);
      }),
      timeout: homeProfileTestTimeout,
    );
  });

  group('startup Home policy and guards', () {
    for (final configured in [false, true]) {
      testWidgets(
        'startup opens only Home, never saved crash/pinned tabs '
        '(configured=$configured)',
        (tester) => _withFixture(tester, (fixture) async {
          final initialManager = fixture.tabs.state.currentPageManager;
          final saved = Map.of(fixture.storage.values);
          await fixture.mount(tester, startup: true);
          expect(fixture.reads.map((read) => read.workspaceId), [_workspaceId]);
          expect(fixture.tabs.state.pageManagers, [initialManager]);
          expect(fixture.built, isEmpty);
          await fixture.resolve(
            tester,
            fixture.reads.single,
            configured ? _homeView() : null,
          );
          expect(fixture.tabs.state.pageManagers, [initialManager]);
          if (configured) {
            expect(initialManager.plugin.id, _sharedHomeId);
            expect(fixture.built.map((plugin) => plugin.id), [_sharedHomeId]);
          } else {
            expect(initialManager.plugin, isA<BlankPagePlugin>());
            expect(fixture.built, isEmpty);
          }
          expect(initialManager.isPinned, isFalse);
          expect(fixture.tabs.canGoBack, isFalse);
          expect(fixture.tabs.canGoForward, isFalse);
          expect(fixture.storage.values, saved);
          expect(fixture.storage.reads, isEmpty);
          expect(fixture.storage.writes, isEmpty);
        }),
        timeout: homeProfileTestTimeout,
      );
    }

    testWidgets(
      'startup rebuilds and remounts do not replace later manual navigation',
      (tester) => _withFixture(tester, (fixture) async {
        await fixture.mount(tester, startup: true);
        await fixture.resolve(tester, fixture.reads.single, _homeView());
        final page = await fixture.openPage(tester, 'manual-after-startup');
        final manager = fixture.tabs.state.currentPageManager;
        await fixture.mount(tester, startup: true, appearance: 'dark');
        await tester.pumpWidget(const SizedBox.shrink());
        await fixture.mount(tester, startup: true, appearance: 'paper');
        expect(fixture.reads, hasLength(1));
        expect(fixture.tabs.state.currentPageManager, same(manager));
        expect(manager.plugin, same(page));
        expect(page.initializations, 1);
        expect(page.disposals, 0);
      }),
      timeout: homeProfileTestTimeout,
    );

    testWidgets(
      'a manual page queued before StartupHome mounts prevents its lookup',
      (tester) => _withFixture(tester, (fixture) async {
        final page = _TrackedPlugin(_pageView('queued-deep-link'));
        fixture.open(page);
        await fixture.mount(tester, startup: true);
        expect(fixture.tabs.state.currentPageManager.plugin, same(page));
        expect(fixture.reads, isEmpty);
        expect(fixture.built, isEmpty);
      }),
      timeout: homeProfileTestTimeout,
    );

    for (final navigation in ['manual page', 'plus']) {
      testWidgets(
        'pending startup cannot override a newer $navigation',
        (tester) => _withFixture(tester, (fixture) async {
          await fixture.mount(tester, startup: true);
          final startupRead = fixture.reads.single;
          if (navigation == 'plus') {
            await tester.tap(find.byKey(_plusKey));
            await _pump(tester);
            final home = fixture.tabs.state.currentPageManager;
            await fixture.resolve(tester, fixture.reads.last, _homeView());
            await fixture.resolve(
              tester,
              startupRead,
              _homeView(id: 'obsolete-startup-home'),
            );
            expect(fixture.tabs.state.currentPageManager, same(home));
            expect(home.plugin.id, _sharedHomeId);
            expect(fixture.built.map((plugin) => plugin.id), [_sharedHomeId]);
            expect(fixture.tabs.state.pages, 2);
          } else {
            final chosen = _TrackedPlugin(_pageView('manual-startup-page'));
            fixture.open(chosen);
            startupRead.result.complete(_homeView(id: 'obsolete-startup-home'));
            await _pump(tester);
            expect(fixture.tabs.state.currentPageManager.plugin, same(chosen));
            expect(fixture.built, isEmpty);
          }
        }),
        timeout: homeProfileTestTimeout,
      );
    }

    for (final invalidation in ['user change', 'unmount']) {
      testWidgets(
        'StartupHome rejects pending resolution after $invalidation',
        (tester) => _withFixture(tester, (fixture) async {
          await fixture.mount(tester, startup: true);
          final manager = fixture.tabs.state.currentPageManager;
          final placeholder = manager.plugin;
          if (invalidation == 'user change') {
            fixture.workspace.changeUser(8);
          } else {
            await tester.pumpWidget(const SizedBox.shrink());
          }
          fixture.reads.single.result.complete(_homeView(id: 'obsolete-home'));
          await tester.idle();
          expect(fixture.built, isEmpty);
          await _pump(tester);
          expect(fixture.tabs.state.currentPageManager, same(manager));
          expect(manager.plugin, same(placeholder));
          expect(fixture.tabs.homeViewId, isNull);
          expect(fixture.reads, hasLength(1));
        }),
        timeout: homeProfileTestTimeout,
      );
    }

    testWidgets(
      'confirmed workspace state rejects old startup before the next frame '
      'and resolves the new workspace Home',
      (tester) => _withFixture(tester, (fixture) async {
        await fixture.mount(tester, startup: true);
        final oldRead = fixture.reads.single;
        fixture.workspace.changeWorkspace('next-workspace');
        oldRead.result.complete(_homeView(id: 'obsolete-home'));
        await tester.idle();
        expect(fixture.built, isEmpty);
        await _pump(tester);
        expect(
          fixture.reads.map((read) => read.workspaceId),
          [_workspaceId, 'next-workspace'],
        );
        await fixture.resolve(
          tester,
          fixture.reads.last,
          _homeView(id: 'next-home', workspaceId: 'next-workspace'),
        );
        expect(fixture.tabs.state.currentPageManager.plugin.id, 'next-home');
        expect(fixture.built.map((plugin) => plugin.id), ['next-home']);
        expect(fixture.tabs.homeViewId, 'next-home');
      }),
      timeout: homeProfileTestTimeout,
    );

    testWidgets(
      'a deep link queued during workspace switching beats confirmed startup',
      (tester) => _withFixture(tester, (fixture) async {
        await fixture.mount(tester, startup: true);
        await fixture.resolve(tester, fixture.reads.single, _homeView());
        fixture.tabs.add(const TabsEvent.switchWorkspace('next-workspace'));
        final chosen = _TrackedPlugin(_pageView('next-workspace-deep-link'));
        fixture.open(chosen);
        fixture.workspace.changeWorkspace('next-workspace');
        await _pump(tester);
        expect(fixture.tabs.state.currentPageManager.plugin, same(chosen));
        expect(fixture.tabs.homeViewId, isNull);
        expect(fixture.reads, hasLength(1));
        expect(fixture.built.map((plugin) => plugin.id), [_sharedHomeId]);
        await fixture.mount(tester, startup: true, appearance: 'dark');
        expect(fixture.tabs.state.currentPageManager.plugin, same(chosen));
        expect(fixture.reads, hasLength(1));
      }),
      timeout: homeProfileTestTimeout,
    );
  });
}

Future<void> _withFixture(
  WidgetTester tester,
  Future<void> Function(_HomeTabsFixture) body,
) async {
  // Bloc event subscriptions must be created in this testWidgets/FakeAsync
  // zone, never in setUp or inside runAsync.
  final fixture = _HomeTabsFixture();
  try {
    await body(fixture);
    expect(tester.takeException(), isNull);
    expect(
      fixture.historyReads,
      isEmpty,
      reason: 'History should select retained pages, not load a backend view.',
    );
    expect(fixture.storage.writes, isEmpty);
  } finally {
    try {
      await fixture.dispose(tester);
    } finally {
      tester.view.reset();
    }
  }
}

/// Finite turns for asynchronous event delivery and inherited-widget rebuilds.
/// No pumpAndSettle, sleeps, or awaiting fake-zone work from runAsync.
Future<void> _pump(WidgetTester tester) async {
  for (var turn = 0; turn < 3; turn++) {
    await tester.runAsync(() async {});
    await tester.pump(const Duration(milliseconds: 1));
  }
}

Finder _tab(PageManager manager) => find.byWidgetPredicate(
      (widget) => widget is FlowyTab && identical(widget.pageManager, manager),
    );

Future<void> _chooseOverflow(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(_overflowKey));
  await _pump(tester);
  await tester.pump(const Duration(milliseconds: 250));
  final row = find.byWidgetPredicate(
    (widget) => widget is AppMenuRow && widget.label == label,
  );
  expect(row.hitTestable(), findsOneWidget);
  expect(tester.widget<AppMenuRow>(row).enabled, isTrue);
  await tester.tap(row);
  // Menu callbacks are posted after dismissal; deliver both that frame and
  // the bloc event instead of invoking a captured callback by hand.
  await _pump(tester);
  await tester.pump(const Duration(milliseconds: 250));
  await _pump(tester);
}

ViewPB _pageView(String id) => ViewPB(
      id: id,
      parentViewId: _workspaceId,
      name: id.isEmpty ? 'Replacement blank' : id,
      layout: ViewLayoutPB.Document,
    );

ViewPB _homeView({
  String id = _sharedHomeId,
  String workspaceId = _workspaceId,
}) =>
    ViewPB(
      id: id,
      parentViewId: workspaceId,
      name: 'Home',
      layout: ViewLayoutPB.Document,
      extra: DashboardMetadata.newExtra(),
    );

class _HomeTabsFixture {
  _HomeTabsFixture() {
    getIt.registerSingleton<MenuSharedState>(menu);
    getIt.registerSingleton<PluginSandbox>(PluginSandbox());
    getIt.registerSingleton<KeyValueStorage>(storage);
    workspace = _WorkspaceBloc();
    tabs = TabsBloc(
      loadHomeView: (workspaceId) {
        final read = _HomeRead(workspaceId);
        reads.add(read);
        return read.result.future;
      },
      loadHistoryView: (id) async {
        historyReads.add(id);
        throw StateError('Unexpected read of a non-retained history page: $id');
      },
      buildHistoryPlugin: (view) {
        final plugin = _TrackedPlugin(view);
        built.add(plugin);
        return plugin;
      },
    );
  }

  final menu = MenuSharedState();
  final storage = _MemoryStorage();
  final reads = <_HomeRead>[];
  final historyReads = <String>[];
  final built = <_TrackedPlugin>[];
  late final _WorkspaceBloc workspace;
  late final TabsBloc tabs;

  Future<_HomeRead> beginHome(
    WidgetTester tester, {
    bool newTab = true,
    String workspaceId = _workspaceId,
  }) async {
    final index = reads.length;
    unawaited(tabs.openHome(workspaceId: workspaceId, newTab: newTab));
    await _pump(tester);
    expect(reads, hasLength(index + 1));
    final read = reads[index];
    expect(read.workspaceId, workspaceId);
    expect(read.result.isCompleted, isFalse);
    return read;
  }

  void open(_TrackedPlugin plugin) => tabs.add(
        TabsEvent.openPlugin(
          plugin: plugin,
          view: plugin.view,
          // PageNotifier's setLatest=true dispatches a native backend write.
          // Home already uses false; explicit fixture navigation must too.
          setLatest: false,
        ),
      );

  Future<_TrackedPlugin> openPage(WidgetTester tester, String id) async {
    final plugin = _TrackedPlugin(_pageView(id));
    open(plugin);
    await _pump(tester);
    expect(tabs.state.currentPageManager.plugin, same(plugin));
    return plugin;
  }

  Future<_TrackedPlugin> openSecondary(WidgetTester tester) async {
    final plugin = _TrackedPlugin(_pageView('secondary-page'));
    tabs.add(TabsEvent.openSecondaryPlugin(plugin: plugin, view: plugin.view));
    await _pump(tester);
    expect(
      tabs.state.currentPageManager.secondaryNotifier.plugin,
      same(plugin),
    );
    expect(plugin.initializations, 1);
    return plugin;
  }

  Future<void> resolve(
    WidgetTester tester,
    _HomeRead read,
    ViewPB? view,
  ) async {
    read.result.complete(view);
    await _pump(tester);
  }

  Future<PageManager> resolvedNewHome(
    WidgetTester tester, {
    String id = _sharedHomeId,
  }) async {
    final read = await beginHome(tester);
    final manager = tabs.state.currentPageManager;
    await resolve(tester, read, _homeView(id: id));
    expect(tabs.state.currentPageManager, same(manager));
    expect(manager.plugin.id, id);
    return manager;
  }

  Future<void> select(WidgetTester tester, PageManager manager) async {
    final index = tabs.state.pageManagers.indexOf(manager);
    expect(index, greaterThanOrEqualTo(0));
    tabs.add(TabsEvent.selectTab(index));
    await _pump(tester);
    expect(tabs.state.currentPageManager, same(manager));
  }

  Future<void> mount(
    WidgetTester tester, {
    String appearance = 'light',
    bool startup = false,
    bool sidebarHome = false,
    double width = 1200,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    final chrome = SizedBox(
      width: width,
      height: 500,
      child: Column(
        children: [
          Row(
            children: [
              const WorkspaceNavigationControls(),
              Expanded(
                child: TabsManager(
                  onIndexChanged: (index) =>
                      tabs.add(TabsEvent.selectTab(index)),
                ),
              ),
            ],
          ),
          if (sidebarHome)
            const SizedBox(width: 260, child: SidebarHomeButton()),
        ],
      ),
    );
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'home-tabs-memory-only',
        fallbackLocale: const Locale('en', 'US'),
        saveLocale: false,
        assetLoader: const _HomeTabsLabels(),
        child: Builder(
          builder: (context) => MaterialApp(
            locale: const Locale('en', 'US'),
            localizationsDelegates: context.localizationDelegates,
            theme: vividIconTestTheme(appearance),
            themeAnimationDuration: Duration.zero,
            home: Scaffold(
              body: Center(
                child: MultiBlocProvider(
                  providers: [
                    BlocProvider<TabsBloc>.value(value: tabs),
                    BlocProvider<UserWorkspaceBloc>.value(value: workspace),
                  ],
                  child: startup
                      ? BlocSelector<UserWorkspaceBloc, UserWorkspaceState,
                          String>(
                          selector: (state) =>
                              state.currentWorkspace?.workspaceId ?? '',
                          builder: (context, id) =>
                              StartupHome(workspaceId: id, child: chrome),
                        )
                      : chrome,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    for (var turn = 0;
        turn < 8 && find.byKey(_homeKey).evaluate().isEmpty;
        turn++) {
      await _pump(tester);
    }
    expect(find.byKey(_homeKey), findsOneWidget);
    await _pump(tester);
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    // Unmount subscribers first. Observe close in its owning fake zone and
    // alternate bounded pumps with empty real-zone turns, using shared support.
    try {
      if (!tabs.isClosed) {
        await pumpHomeProfileClose(
          tester,
          tabs.close(),
          description: 'Dedicated Home tabs fixture',
        );
      }
    } finally {
      for (final read in reads) {
        if (!read.result.isCompleted) read.result.complete(null);
      }
      await _pump(tester);
      try {
        if (!workspace.isClosed) {
          await pumpHomeProfileClose(
            tester,
            workspace.close(),
            description: 'Dedicated Home workspace fixture',
          );
        }
      } finally {
        menu.notifier.dispose();
      }
    }
  }
}

class _HomeRead {
  _HomeRead(this.workspaceId);
  final String workspaceId;
  final result = Completer<ViewPB?>();
}

class _TrackedPlugin extends Plugin {
  _TrackedPlugin(this.view, {this.type = PluginType.document})
      : notifier = _MemoryViewNotifier(view);

  final ViewPB view;
  final PluginType type;
  @override
  final _MemoryViewNotifier notifier;
  late final _TrackedWidgets _widgets = _TrackedWidgets(this);
  TextEditingController? _draft;
  int initializations = 0;
  int disposals = 0;

  // Allocate only for plugins actually used as draft owners. Unopened duplicate
  // candidates intentionally own only their constructor-created notifier.
  TextEditingController get draft => _draft ??= TextEditingController();
  @override
  String get id => view.id;
  @override
  PluginType get pluginType => type;
  @override
  PluginWidgetBuilder get widgetBuilder => _widgets;
  @override
  void init() => initializations++;
  @override
  void dispose() {
    disposals++;
    _draft?.dispose();
    notifier.dispose();
  }
}

// Implement, do not extend: ViewPluginNotifier's constructor subscribes to Rust.
class _MemoryViewNotifier implements ViewPluginNotifier {
  _MemoryViewNotifier(this.view);
  @override
  ViewPB view;
  @override
  final isDeleted = ValueNotifier<DeletedViewPB?>(null);
  int disposals = 0;
  @override
  void dispose() {
    disposals++;
    isDeleted.dispose();
  }
}

class _TrackedWidgets extends PluginWidgetBuilder {
  _TrackedWidgets(this.plugin);
  final _TrackedPlugin plugin;
  @override
  String get viewName => plugin.view.name;
  @override
  List<NavigationItem> get navigationItems => [this];
  @override
  Widget get leftBarItem => Text(viewName);
  @override
  Widget tabBarItem(String pluginId, [bool shortForm = false]) => shortForm
      ? const Icon(Icons.description_rounded, size: 12)
      : Text(viewName, maxLines: 1, overflow: TextOverflow.ellipsis);
  @override
  Widget buildWidget({
    required PluginContext context,
    required bool shrinkWrap,
    Map<String, dynamic>? data,
  }) =>
      const SizedBox.shrink();
}

class _WorkspaceBloc extends Cubit<UserWorkspaceState>
    implements UserWorkspaceBloc {
  _WorkspaceBloc()
      : super(
          UserWorkspaceState.initial(UserProfilePB(id: Int64(7))).copyWith(
            currentWorkspace: UserWorkspacePB(
              workspaceId: _workspaceId,
              role: AFRolePB.Owner,
            ),
          ),
        );

  void changeWorkspace(String id) => emit(
        state.copyWith(
          currentWorkspace:
              UserWorkspacePB(workspaceId: id, role: AFRolePB.Owner),
        ),
      );

  void changeUser(int id) =>
      emit(state.copyWith(userProfile: UserProfilePB(id: Int64(id))));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryStorage implements KeyValueStorage {
  final values = <String, String>{
    'appflowy_home_dashboard': _sharedHomeId,
    'openedTabs':
        '{"$_workspaceId":[{"id":"crashed-collection","isPinned":true},'
            '{"id":"saved-page"}]}',
    'pinnedTabs': '["crashed-collection"]',
    'expandedViews': '{"saved-page":true}',
  };
  final reads = <String>[];
  final writes = <String>[];
  @override
  Future<String?> get(String key) async {
    reads.add(key);
    return values[key];
  }

  @override
  Future<T?> getWithFormat<T>(String key, T Function(String) formatter) async {
    final value = await get(key);
    return value == null ? null : formatter(value);
  }

  @override
  Future<void> set(String key, String value) async {
    writes.add(key);
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    writes.add(key);
    values.remove(key);
  }

  @override
  Future<void> clear() async {
    writes.add('*');
    values.clear();
  }
}

class _HomeTabsLabels extends AssetLoader {
  const _HomeTabsLabels();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) =>
      Future.value({
        // Future.value is deliberate: EasyLocalization uses Future.wait, whose
        // bookkeeping is incompatible with a synchronously invoked .then.
        'dashboard': {'home': 'Home'},
        'button': {'back': 'Back', 'next': 'Forward'},
        'sideBar': {
          'openSidebar': 'Open sidebar',
          'closeSidebar': 'Close sidebar',
        },
        'disclosureAction': {'openNewTab': 'Open in new tab'},
        'workspaceChrome': {'openTabs': 'Open tabs'},
        'menuAppHeader': {'defaultNewPageName': 'Untitled'},
        'tabMenu': {
          'close': 'Close',
          'closeOthers': 'Close others',
          'pinTab': 'Pin tab',
          'unpinTab': 'Unpin tab',
        },
      });
}
