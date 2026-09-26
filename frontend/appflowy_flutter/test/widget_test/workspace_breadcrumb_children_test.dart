import 'dart:async';
import 'dart:ui' as ui;

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/plugins/workspace_folder/workspace_folder_plugin.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/space_icon.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_item_icon.dart';
import 'package:appflowy/workspace/presentation/widgets/tab_bar_item.dart';
import 'package:appflowy/workspace/presentation/widgets/view_title_bar.dart';
import 'package:appflowy/workspace/presentation/widgets/workspace_breadcrumb_children.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart'
    hide AFRolePB;
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'vivid_icon_test_support.dart';

const _root = ValueKey('breadcrumb-workspace-root');
const _menu = ValueKey('breadcrumb-children-menu');
const _loading = ValueKey('breadcrumb-children-loading');
const _error = ValueKey('breadcrumb-children-error');
const _empty = ValueKey('breadcrumb-children-empty');
const _retry = ValueKey('breadcrumb-children-retry');
const _testTimeout = Timeout(Duration(seconds: 45));

typedef _ViewsResult = FlowyResult<List<ViewPB>, FlowyError>;
typedef _ViewResult = FlowyResult<ViewPB, FlowyError>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(prepareVividIconTestAssets);

  test(
    'root uses actual workspace children, including spaces, without mutation',
    () async {
      final fixture = _Fixture();
      try {
        final source = fixture.repository.all;
        final bytes = source.map((view) => view.writeToBuffer()).toList();
        final result = await loadWorkspaceBreadcrumbChildren(
          repository: fixture.repository,
          parentId: 'workspace-a',
          isWorkspaceRoot: true,
          isGuest: false,
        );
        final children = result.getOrThrow();
        expect(children.map((view) => view.id), ['space-a', 'inbox']);
        expect(fixture.repository.calls, ['all']);
        expect(identical(children, source), isFalse);
        expect(() => children.clear(), throwsUnsupportedError);
        expect(source.map((view) => view.writeToBuffer()).toList(), bytes);
      } finally {
        await fixture.close();
      }
    },
    timeout: _testTimeout,
  );

  test(
    'non-root listing uses getChildren and preserves a permission failure',
    () async {
      final repository = _Repository();
      final denied = FlowyError(msg: 'Not permitted');
      repository.readChildren = (_) async => _ViewsResult.failure(denied);
      final result = await loadWorkspaceBreadcrumbChildren(
        repository: repository,
        parentId: 'ancestor',
        isWorkspaceRoot: false,
        isGuest: false,
      );
      expect(result.isFailure, isTrue);
      result.fold(
        (_) => fail('A failed read must not become empty success'),
        (error) => expect(error, same(denied)),
      );
      expect(repository.calls, ['children:ancestor']);
    },
    timeout: _testTimeout,
  );

  test(
    'guest root never calls the flat-list API; allowed descendants still load',
    () async {
      final repository = _Repository();
      final child = ViewPB(id: 'readable', parentViewId: 'shared');
      repository.children['shared'] = List.unmodifiable([child]);
      final root = await loadWorkspaceBreadcrumbChildren(
        repository: repository,
        parentId: 'workspace-a',
        isWorkspaceRoot: true,
        isGuest: true,
      );
      expect(root.isFailure, isTrue);
      expect(repository.calls, isEmpty);
      final shared = await loadWorkspaceBreadcrumbChildren(
        repository: repository,
        parentId: 'shared',
        isWorkspaceRoot: false,
        isGuest: true,
      );
      expect(shared.getOrThrow().single.id, child.id);
      expect(repository.calls, ['children:shared']);
    },
    timeout: _testTimeout,
  );

  for (final appearance in vividIconTestAppearances) {
    testWidgets(
      '$appearance: tab labels keep saved and space icons',
      (tester) async {
        final fixture =
            await _pump(tester, appearance: appearance, tabLabel: true);
        try {
          expect(
            tester
                .widget<RawEmojiIconWidget>(find.byType(RawEmojiIconWidget))
                .emoji
                .emoji,
            '🌿',
          );
          final bytes = fixture.space.writeToBuffer();
          fixture.update(() => fixture.view = fixture.space);
          await tester.pumpAndSettle();
          expect(
            tester.widget<SpaceIcon>(find.byType(SpaceIcon)).space,
            same(fixture.space),
          );
          expect(fixture.space.writeToBuffer(), bytes);
          expect(fixture.repository.calls, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          await _dispose(tester, fixture);
        }
      },
      timeout: _testTimeout,
    );

    testWidgets(
      '$appearance: slash has workspace semantics and current-path tooltip',
      (tester) async {
        final fixture = await _pump(tester, appearance: appearance, width: 40);
        final semantics = tester.ensureSemantics();
        try {
          expect(find.text('/'), findsOneWidget);
          expect(find.text('My Workspace'), findsNothing);
          expect(find.byKey(_root).hitTestable(), findsOneWidget);
          expect(_disclosure('workspace-a').hitTestable(), findsOneWidget);
          expect(
            tester.getSemantics(find.byKey(_root)).getSemanticsData().label,
            'My Workspace',
          );
          expect(
            tester
                .getSemantics(find.byKey(_root))
                .getSemanticsData()
                .hasFlag(ui.SemanticsFlag.isButton),
            isTrue,
          );
          expect(
            tester
                .widget<Tooltip>(
                  find.byKey(const ValueKey('workspace-current-path')),
                )
                .message,
            'My Workspace / Research / Notes / Report.pdf',
          );
          expect(
            tester
                .widget<Tooltip>(
                  find.byKey(const ValueKey('breadcrumb-root-tooltip')),
                )
                .message,
            'My Workspace / Research / Notes / Report.pdf',
          );
          await tester.tap(find.byKey(_root));
          expect(fixture.opened.single.id, 'workspace-a');
          expect(fixture.opened.single.isWorkspaceRootFolder, isTrue);
          expect(fixture.repository.calls, isEmpty);
          fixture.workspace.replace(_workspace('workspace-a', 'Studio'));
          await tester.pumpAndSettle();
          expect(find.text('/'), findsOneWidget);
          expect(
            tester.getSemantics(find.byKey(_root)).getSemanticsData().label,
            'Studio',
          );
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
          await _dispose(tester, fixture);
        }
      },
      timeout: _testTimeout,
    );

    testWidgets(
      '$appearance: each chevron loads that ancestor, never its parent or siblings',
      (tester) async {
        final fixture = await _pump(tester, appearance: appearance);
        try {
          for (final entry in {
            'workspace-a': ['space-a', 'inbox'],
            'space-a': ['folder'],
            'folder': ['report', 'sibling'],
          }.entries) {
            fixture.repository.calls.clear();
            await _open(tester, entry.key);
            expect(_childIds(tester), entry.value);
            expect(
              fixture.repository.calls,
              [entry.key == 'workspace-a' ? 'all' : 'children:${entry.key}'],
            );
            expect(find.byType(AppMenuSurface), findsOneWidget);
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
            expect(find.byKey(_menu), findsNothing);
          }
          // Ancestor text remains navigation rather than opening its child menu.
          await tester.tap(find.widgetWithText(TextButton, 'Notes'));
          expect(fixture.opened.single.id, 'folder');
          expect(tester.takeException(), isNull);
        } finally {
          await _dispose(tester, fixture);
        }
      },
      timeout: _testTimeout,
    );

    testWidgets(
      '$appearance: real child identity and typed/custom icons survive',
      (tester) async {
        final fixture = await _pump(tester, appearance: appearance);
        try {
          final source = fixture.repository.children['folder']!;
          final bytes = source.map((view) => view.writeToBuffer()).toList();
          await _open(tester, 'folder');
          final saved = find.descendant(
            of: _child('report'),
            matching: find.byType(RawEmojiIconWidget),
          );
          expect(saved, findsOneWidget);
          expect(tester.widget<RawEmojiIconWidget>(saved).emoji.emoji, '🌿');
          final fallback = find.descendant(
            of: _child('sibling'),
            matching: find.byType(WorkspaceItemIcon),
          );
          expect(fallback, findsOneWidget);
          expect(tester.widget<WorkspaceItemIcon>(fallback).item.id, 'sibling');
          // Refresh at activation, not the stale payload displayed by the menu.
          fixture.repository.views['sibling'] =
              ViewPB.fromBuffer(fixture.sibling.writeToBuffer())
                ..name = 'Renamed notes.md';
          await tester.tap(_child('sibling'));
          await tester.pumpAndSettle();
          expect(fixture.opened.single.name, 'Renamed notes.md');
          expect(fixture.repository.calls, ['children:folder', 'view:sibling']);
          expect(source.map((view) => view.writeToBuffer()).toList(), bytes);
          expect(find.byKey(_menu), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          await _dispose(tester, fixture);
        }
      },
      timeout: _testTimeout,
    );

    testWidgets(
      '$appearance: hidden ancestors retain navigation and their own child menus',
      (tester) async {
        final fixture = await _pump(tester, appearance: appearance, width: 220);
        try {
          await tester.tap(find.byKey(const ValueKey('breadcrumb-ancestors')));
          await tester.pumpAndSettle();
          expect(_childIds(tester), ['space-a', 'folder']);
          expect(fixture.repository.calls, isEmpty);
          await tester
              .tap(find.byKey(const ValueKey('breadcrumb-browse-space-a')));
          await tester.pumpAndSettle();
          expect(_childIds(tester), ['folder']);
          expect(fixture.repository.calls, ['children:space-a']);
          await tester
              .tap(find.byKey(const ValueKey('breadcrumb-children-back')));
          await tester.pumpAndSettle();
          expect(_childIds(tester), ['space-a', 'folder']);
          await tester.tap(_child('folder'));
          await tester.pumpAndSettle();
          expect(fixture.opened.single.id, 'folder');
          expect(fixture.repository.calls.last, 'view:folder');
          expect(tester.takeException(), isNull);
        } finally {
          await _dispose(tester, fixture);
        }
      },
      timeout: _testTimeout,
    );
  }

  testWidgets(
    'loading is immediate; backend failure and thrown failure can retry to empty',
    (tester) async {
      final fixture = await _pump(tester);
      final pending = Completer<_ViewsResult>();
      fixture.repository.readChildren = (_) => pending.future;
      try {
        await _open(tester, 'folder');
        expect(find.byKey(_loading), findsOneWidget);
        expect(find.byKey(_empty), findsNothing);
        pending.complete(
          _ViewsResult.failure(FlowyError(msg: 'Permission changed')),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(_error), findsOneWidget);
        expect(find.byKey(_empty), findsNothing);
        fixture.repository.readChildren =
            (_) => Future.error(StateError('unavailable'));
        await tester.tap(find.byKey(_retry));
        await tester.pumpAndSettle();
        expect(find.byKey(_error), findsOneWidget);
        fixture.repository.readChildren = (_) async => _ViewsResult.success([]);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.byKey(_empty), findsOneWidget);
        expect(find.byKey(_error), findsNothing);
        expect(fixture.repository.calls, List.filled(3, 'children:folder'));
        expect(fixture.opened, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await _dispose(tester, fixture);
      }
    },
    timeout: _testTimeout,
  );

  testWidgets(
    'keyboard opens disclosure, browses, returns, and navigates a child',
    (tester) async {
      final fixture = await _pump(tester);
      try {
        // The glyph lives below the native button's Focus, not above it in the
        // callback-shortcut wrapper. Open without synthesizing a pointer click.
        final glyph = find.descendant(
          of: _disclosure('workspace-a'),
          matching: find.byType(DSWorkspaceGlyph),
        );
        Focus.of(tester.element(glyph)).requestFocus();
        await tester.pump();
        await _key(tester, LogicalKeyboardKey.arrowDown);
        expect(
          FocusManager.instance.primaryFocus?.debugLabel,
          'workspace_breadcrumb_children',
        );
        await _key(tester, LogicalKeyboardKey.home);
        await _key(tester, LogicalKeyboardKey.arrowRight);
        expect(_childIds(tester), ['folder']);
        await _key(tester, LogicalKeyboardKey.arrowLeft);
        expect(_childIds(tester), ['space-a', 'inbox']);
        await _key(tester, LogicalKeyboardKey.home);
        await _key(tester, LogicalKeyboardKey.arrowRight);
        await _key(tester, LogicalKeyboardKey.home);
        await _key(tester, LogicalKeyboardKey.arrowRight);
        expect(_childIds(tester), ['report', 'sibling']);
        await _key(tester, LogicalKeyboardKey.end);
        await _key(tester, LogicalKeyboardKey.enter);
        expect(fixture.opened.single.id, 'sibling');
        expect(fixture.repository.calls, [
          'all',
          'children:space-a',
          'all',
          'children:space-a',
          'children:folder',
          'view:sibling',
        ]);
        expect(tester.takeException(), isNull);
      } finally {
        await _dispose(tester, fixture);
      }
    },
    timeout: _testTimeout,
  );

  testWidgets(
    'revoked or moved child is not opened from a stale listing',
    (tester) async {
      final fixture = await _pump(tester);
      try {
        await _open(tester, 'folder');
        fixture.repository.readView =
            (_) async => _ViewResult.failure(FlowyError(msg: 'Denied'));
        await tester.tap(_child('sibling'));
        await tester.pumpAndSettle();
        expect(fixture.opened, isEmpty);
        expect(find.byKey(_error), findsOneWidget);
        await tester.tap(find.byKey(_retry));
        await tester.pumpAndSettle();
        fixture.repository.readView = (_) async => _ViewResult.success(
              ViewPB.fromBuffer(fixture.sibling.writeToBuffer())
                ..parentViewId = 'elsewhere',
            );
        await tester.tap(_child('sibling'));
        await tester.pumpAndSettle();
        expect(fixture.opened, isEmpty);
        expect(find.byKey(_error), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await _dispose(tester, fixture);
      }
    },
    timeout: _testTimeout,
  );

  testWidgets(
    'guest root fails closed and permission changes retire displayed callbacks',
    (tester) async {
      final fixture = await _pump(tester);
      try {
        await _open(tester, 'workspace-a');
        final stale = tester.widget<AppMenuRow>(_child('inbox')).onTap!;
        fixture.workspace.replace(
          _workspace('workspace-a', 'My Workspace', role: AFRolePB.Guest),
        );
        stale(); // Before the next frame as well as after the rebuild.
        await tester.pumpAndSettle();
        expect(find.byKey(_menu), findsNothing);
        expect(fixture.opened, isEmpty);
        fixture.repository.calls.clear();
        await _open(tester, 'workspace-a');
        expect(find.byKey(_error), findsOneWidget);
        expect(fixture.repository.calls, isEmpty);
        expect(tester.widget<TextButton>(find.byKey(_root)).onPressed, isNull);
        expect(tester.takeException(), isNull);
      } finally {
        await _dispose(tester, fixture);
      }
    },
    timeout: _testTimeout,
  );

  for (final change in [
    'dismiss',
    'path',
    'workspace',
    'repository',
    'dispose',
    'closed tabs',
    'closed workspace',
  ]) {
    testWidgets(
      'late children cannot reopen a menu after $change',
      (tester) async {
        final fixture = await _pump(tester);
        final oldRepository = fixture.repository;
        final pending = Completer<_ViewsResult>();
        oldRepository.readChildren = (_) => pending.future;
        try {
          await _open(tester, 'folder');
          expect(find.byKey(_loading), findsOneWidget);
          final staleTrigger =
              tester.widget<IconButton>(_disclosure('folder')).onPressed!;
          switch (change) {
            case 'dismiss':
              await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            case 'path':
              fixture.update(() => fixture.view = fixture.sibling);
            case 'workspace':
              fixture.workspace
                  .replace(_workspace('workspace-b', 'Second workspace'));
            case 'repository':
              fixture.update(() => fixture.repository = _Repository());
            case 'dispose':
              await tester.pumpWidget(const SizedBox.shrink());
            case 'closed tabs':
              final tabsClosed = fixture.tabs.close();
              expect(fixture.tabs.isClosed, isTrue);
              staleTrigger(); // Also reject activation before onDone is delivered.
              await _pumpClose(tester, tabsClosed);
            case 'closed workspace':
              final workspaceClosed = fixture.workspace.close();
              expect(fixture.workspace.isClosed, isTrue);
              staleTrigger();
              await _pumpClose(tester, workspaceClosed);
          }
          await tester.pumpAndSettle();
          if (change != 'dismiss') staleTrigger();
          pending.complete(
            _ViewsResult.success(oldRepository.children['folder']!),
          );
          await tester.pumpAndSettle();
          expect(find.byKey(_menu), findsNothing);
          expect(fixture.opened, isEmpty);
          expect(oldRepository.calls, ['children:folder']);
          expect(tester.takeException(), isNull);
        } finally {
          await _dispose(tester, fixture);
        }
      },
      timeout: _testTimeout,
    );
  }

  testWidgets(
    'fixture teardown completes active and previously closed state streams',
    (tester) async {
      for (final closeWhileMounted in [false, true]) {
        final fixture = await _pump(tester);
        final workspaceDone = expectLater(fixture.workspace.stream, emitsDone);
        final tabsDone = expectLater(fixture.tabs.stream, emitsDone);
        try {
          if (closeWhileMounted) {
            await _pumpClose(tester, fixture.workspace.close());
            await _pumpClose(tester, fixture.tabs.close());
          }
        } finally {
          await _dispose(tester, fixture);
        }
        await workspaceDone;
        await tabsDone;
        expect(fixture.workspace.isClosed, isTrue);
        expect(fixture.tabs.isClosed, isTrue);
        expect(tester.takeException(), isNull);
      }
    },
    timeout: _testTimeout,
  );

  testWidgets(
    'late activation after path rebind cannot navigate',
    (tester) async {
      final fixture = await _pump(tester);
      final pending = Completer<_ViewResult>();
      try {
        await _open(tester, 'folder');
        fixture.repository.readView = (_) => pending.future;
        await tester.tap(_child('sibling'));
        await tester.pump();
        fixture.update(() => fixture.view = fixture.sibling);
        await tester.pumpAndSettle();
        pending.complete(_ViewResult.success(fixture.sibling));
        await tester.pumpAndSettle();
        expect(fixture.opened, isEmpty);
        expect(find.byKey(_menu), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await _dispose(tester, fixture);
      }
    },
    timeout: _testTimeout,
  );

  testWidgets(
    'timeout offers retry and rejects the first request arriving late',
    (tester) async {
      final fixture = await _pump(tester);
      final pending = Completer<_ViewsResult>();
      fixture.repository.readChildren = (_) => pending.future;
      try {
        await _open(tester, 'folder');
        await tester.pump(const Duration(seconds: 16));
        expect(find.byKey(_error), findsOneWidget);
        fixture.repository.readChildren = (_) async => _ViewsResult.success([]);
        await tester.tap(find.byKey(_retry));
        await tester.pumpAndSettle();
        pending.complete(_ViewsResult.success([fixture.sibling]));
        await tester.pumpAndSettle();
        expect(find.byKey(_empty), findsOneWidget);
        expect(_child('sibling'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await _dispose(tester, fixture);
      }
    },
    timeout: _testTimeout,
  );

  testWidgets(
    'a callback from an earlier menu level cannot select a different row',
    (tester) async {
      final fixture = await _pump(tester);
      try {
        await _open(tester, 'workspace-a');
        final stale = tester.widget<AppMenuRow>(_child('space-a')).onTap!;
        await tester
            .tap(find.byKey(const ValueKey('breadcrumb-browse-space-a')));
        await tester.pumpAndSettle();
        expect(_childIds(tester), ['folder']);
        stale();
        await tester.pumpAndSettle();
        expect(fixture.opened, isEmpty);
        expect(fixture.repository.calls, ['all', 'children:space-a']);
        expect(tester.takeException(), isNull);
      } finally {
        await _dispose(tester, fixture);
      }
    },
    timeout: _testTimeout,
  );

  testWidgets(
    'default navigation uses the real space folder plugin and no latest write',
    (tester) async {
      final fixture = await _pump(tester, defaultNavigation: true);
      Plugin? openedPlugin;
      try {
        final before = fixture.space.writeToBuffer();
        await tester.tap(find.widgetWithText(TextButton, 'Research'));
        fixture.tabs.events.single.whenOrNull(
          openPlugin: (plugin, view, setLatest) {
            openedPlugin = plugin;
            expect(plugin, isA<WorkspaceFolderPlugin>());
            expect(view?.id, fixture.space.id);
            expect(setLatest, isFalse);
          },
        );
        expect(openedPlugin, isNotNull);
        expect(fixture.space.writeToBuffer(), before);
        await tester.tap(find.byKey(_root));
        expect(fixture.tabs.opened.single.$1.id, 'workspace-a');
        expect(fixture.tabs.opened.single.$2, isFalse);
        expect(fixture.repository.calls, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        // Recording the event did not init the plugin; release its constructor-
        // owned notifier, not its uninitialized late-final page blocs.
        openedPlugin?.notifier?.dispose();
        await _dispose(tester, fixture);
      }
    },
    timeout: _testTimeout,
  );

  testWidgets(
    'retiring an owned menu leaves a newer dialog intact and completes its future',
    (tester) async {
      final fixture = await _pump(tester);
      final controller = WorkspaceBreadcrumbMenuController();
      var completed = false;
      var dialogCompleted = false;
      try {
        final anchor = tester.element(_disclosure('folder'));
        unawaited(
          controller
              .show(
                context: anchor,
                parent: fixture.folder,
                workspaceId: 'workspace-a',
                isGuest: false,
                repository: fixture.repository,
                isCurrent: () => true,
                onSelected: fixture.opened.add,
              )
              .whenComplete(() => completed = true),
        );
        await tester.pumpAndSettle();
        unawaited(
          showDialog<void>(
            context: anchor,
            builder: (_) => const AlertDialog(content: Text('New dialog')),
          ).whenComplete(() => dialogCompleted = true),
        );
        await tester.pumpAndSettle();
        controller.dismiss();
        await tester.pumpAndSettle();
        expect(completed, isTrue);
        expect(dialogCompleted, isFalse);
        expect(find.text('New dialog'), findsOneWidget);
        expect(find.byKey(_menu), findsNothing);
        Navigator.of(tester.element(find.text('New dialog'))).pop();
        await tester.pumpAndSettle();
        expect(dialogCompleted, isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        controller.dispose();
        await _dispose(tester, fixture);
      }
    },
    timeout: _testTimeout,
  );
}

Finder _disclosure(String id) =>
    find.byKey(ValueKey('breadcrumb-children-$id'));
Finder _child(String id) => find.byKey(ValueKey('breadcrumb-child-$id'));

List<String> _childIds(WidgetTester tester) => tester
    .widgetList<AppMenuRow>(
      find.descendant(of: find.byKey(_menu), matching: find.byType(AppMenuRow)),
    )
    .map((row) => row.key)
    .whereType<ValueKey<String>>()
    .where((key) => key.value.startsWith('breadcrumb-child-'))
    .map((key) => key.value.substring('breadcrumb-child-'.length))
    .toList();

Future<void> _open(WidgetTester tester, String id) async {
  await tester.tap(_disclosure(id));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump();
}

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

Future<_Fixture> _pump(
  WidgetTester tester, {
  String appearance = 'paper',
  double width = 720,
  bool defaultNavigation = false,
  bool tabLabel = false,
}) async {
  final fixture = _Fixture()..width = width;
  final theme = vividIconTestTheme(appearance);
  final defaults = AppFlowyDefaultTheme();
  await tester.pumpWidget(
    vividIconTestApp(
      appearance,
      AppFlowyTheme(
        data: PremiumTheme.appFlowyTheme(
          base: appearance == 'dark' ? defaults.dark() : defaults.light(),
          palette: theme.extension<PremiumThemeExtension>()!,
          brightness: theme.brightness,
        ),
        child: MultiBlocProvider(
          providers: [
            BlocProvider<UserWorkspaceBloc>.value(value: fixture.workspace),
            BlocProvider<TabsBloc>.value(value: fixture.tabs),
          ],
          child: StatefulBuilder(
            builder: (context, update) {
              fixture.update = update;
              return SizedBox(
                width: fixture.width,
                height: 48,
                child: tabLabel
                    ? ViewTabBarItem(
                        // The real FlowyTab also changes key with the plugin id.
                        key: ValueKey(fixture.view.id),
                        view: fixture.view,
                      )
                    : WorkspaceBreadcrumbs(
                        view: fixture.view,
                        ancestors: fixture.ancestors,
                        repository: fixture.repository,
                        onNavigate:
                            defaultNavigation ? null : fixture.opened.add,
                      ),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fixture;
}

Future<void> _dispose(WidgetTester tester, _Fixture fixture) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await _pumpClose(tester, fixture.close());
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _pumpClose(WidgetTester tester, Future<void> close) async {
  var completed = false;
  Object? closeError;
  StackTrace? closeStack;
  final closed = close.then<void>(
    (_) {
      completed = true;
    },
    onError: (Object error, StackTrace stack) {
      closeError = error;
      closeStack = stack;
      completed = true;
    },
  );
  // Start close and attach its completion in the owning fake zone, THEN pump.
  // Even a completed broadcast-stream done future queues late listeners in
  // that zone. Awaiting it from runAsync blocks the pump it needs to finish.
  await tester.pump();
  expect(
    completed,
    isTrue,
    reason: 'In-memory Cubit.close() must finish after pumping its microtasks.',
  );
  await closed;
  if (closeError != null) {
    Error.throwWithStackTrace(closeError!, closeStack!);
  }
}

UserWorkspacePB _workspace(
  String id,
  String name, {
  AFRolePB role = AFRolePB.Owner,
}) =>
    UserWorkspacePB(workspaceId: id, name: name, role: role);

ViewPB _folder(String id, String parent, String name) => ViewPB(
      id: id,
      parentViewId: parent,
      name: name,
      extra: const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
    );

class _Fixture {
  _Fixture() {
    space = ViewPB(
      id: 'space-a',
      parentViewId: 'workspace-a',
      name: 'Research',
      extra: '{"is_space":true}',
    );
    folder = _folder('folder', space.id, 'Notes');
    view = ViewPB(
      id: 'report',
      parentViewId: folder.id,
      name: 'Report.pdf',
      icon: ViewIconPB(ty: ViewIconTypePB.Emoji, value: '🌿'),
    );
    sibling = ViewPB(
      id: 'sibling',
      parentViewId: folder.id,
      name: 'Notes.md',
      extra: const WorkspaceItemMetadata.file(
        contentKind: WorkspaceFileContentKind.binary,
      ).mergeIntoExtra(''),
    );
    ancestors = List.unmodifiable([space, folder, view]);
    repository.all = List.unmodifiable([
      space,
      folder,
      view,
      sibling,
      _folder('inbox', 'workspace-a', 'Inbox'),
      _folder('foreign', 'workspace-b', 'Not in this workspace'),
    ]);
    repository.children[space.id] = List.unmodifiable([folder]);
    repository.children[folder.id] = List.unmodifiable([view, sibling]);
    repository.views
        .addEntries(repository.all.map((view) => MapEntry(view.id, view)));
  }

  final workspace = _Workspace(
    UserWorkspaceState(
      currentWorkspace: _workspace('workspace-a', 'My Workspace'),
      userProfile: UserProfilePB(id: Int64(1)),
    ),
  );
  final tabs = _Tabs();
  _Repository repository = _Repository();
  final opened = <ViewPB>[];
  late ViewPB space;
  late ViewPB folder;
  late ViewPB view;
  late ViewPB sibling;
  late List<ViewPB> ancestors;
  late StateSetter update;
  double width = 720;

  Future<void> close() async {
    await workspace.close();
    tabs.state.dispose();
    await tabs.close();
  }
}

class _Workspace extends Cubit<UserWorkspaceState>
    implements UserWorkspaceBloc {
  _Workspace(super.initialState);
  void replace(UserWorkspacePB workspace) =>
      emit(state.copyWith(currentWorkspace: workspace));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Tabs extends Cubit<TabsState> implements TabsBloc {
  _Tabs()
      : super(TabsState(pageManagers: [PageManager(plugin: _SourcePlugin())]));
  final events = <TabsEvent>[];
  final opened = <(ViewPB, bool)>[];
  @override
  void add(TabsEvent event) => events.add(event);
  @override
  void openPlugin(
    ViewPB view, {
    Map<String, dynamic> arguments = const {},
    bool setLatest = true,
  }) =>
      opened.add((view, setLatest));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SourcePlugin extends Fake implements Plugin {
  @override
  void dispose() {}
}

/// Only the real repository's read boundary is faked. Any accidental create,
/// rename, move, duplicate, or delete hits Fake.noSuchMethod and fails the test.
class _Repository extends Fake implements WorkspaceItemRepository {
  List<ViewPB> all = const [];
  final children = <String, List<ViewPB>>{};
  final views = <String, ViewPB>{};
  final calls = <String>[];
  Future<_ViewsResult> Function()? readAll;
  Future<_ViewsResult> Function(String)? readChildren;
  Future<_ViewResult> Function(String)? readView;

  @override
  Future<_ViewsResult> getAllViews() {
    calls.add('all');
    return readAll?.call() ?? Future.value(_ViewsResult.success(all));
  }

  @override
  Future<_ViewsResult> getChildren(String parentViewId) {
    calls.add('children:$parentViewId');
    return readChildren?.call(parentViewId) ??
        Future.value(_ViewsResult.success(children[parentViewId] ?? []));
  }

  @override
  Future<_ViewResult> getView(String viewId) {
    calls.add('view:$viewId');
    if (readView != null) return readView!(viewId);
    final view = views[viewId];
    return Future.value(
      view == null
          ? _ViewResult.failure(FlowyError(msg: 'Not found'))
          : _ViewResult.success(view),
    );
  }
}
