import 'dart:async';
import 'dart:ui' as ui;

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/plugins/blank/blank.dart';
import 'package:appflowy/plugins/blank/workspace_home_page.dart';
import 'package:appflowy/plugins/templates/templates_plugin.dart';
import 'package:appflowy/plugins/workspace_folder/workspace_folder_plugin.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/default_icon_style.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/command_palette/command_palette.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart'
    hide AFRolePB;
import 'package:appflowy_backend/protobuf/flowy-notification/subject.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_backend/rust_stream.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../util/home_profile_test_support.dart' show pumpHomeProfileClose;
import 'test_asset_bundle.dart';
import 'vivid_icon_test_support.dart' show vividIconTestTheme;

const _timeout = Timeout(Duration(seconds: 45));
late Map<String, dynamic> _translations;

void main() {
  final allowFontFetching = GoogleFonts.config.allowRuntimeFetching;
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    // Bundled translations only, preloaded outside the widget fake clock.
    _translations = await const TestBundleAssetLoader().load(
      'assets/translations',
      const Locale('en', 'US'),
    );
  });
  tearDownAll(() {
    GoogleFonts.config.allowRuntimeFetching = allowFontFetching;
  });

  for (final appearance in ['light', 'dark', 'paper']) {
    testWidgets(
      '$appearance: BlankPage is Home without startup side effects',
      (tester) async {
        final fixture = _Fixture();
        final semantics = tester.ensureSemantics();
        try {
          final plugin = BlankPagePlugin();
          await _pumpHome(
            tester,
            fixture,
            appearance: appearance,
            page: plugin.widgetBuilder.buildWidget(
              context: PluginContext(),
              shrinkWrap: false,
            ),
          );
          expect(plugin.id, isEmpty);
          expect(plugin.pluginType, PluginType.blank);
          expect(plugin.widgetBuilder.viewName, 'Home');
          expect(plugin.widgetBuilder.contentPadding, EdgeInsets.zero);
          expect(find.byType(WorkspaceHomePage), findsOneWidget);
          expect(find.text('Home'), findsOneWidget);
          expect(find.text('Welcome!'), findsOneWidget);
          expect(find.text('Ada Lovelace'), findsOneWidget);
          expect(find.text('Research'), findsOneWidget);
          expect(find.text('fixture-workspace'), findsNothing);
          expect(find.text('private@example.invalid'), findsNothing);
          expect(
            tester
                .getSemantics(
                  find.byKey(const ValueKey('workspace-page-title')),
                )
                .getSemanticsData()
                .hasFlag(SemanticsFlag.isHeader),
            isTrue,
          );
          for (final id in ['workspace', 'search', 'templates']) {
            _expectButton(tester, id, enabled: true);
          }
          final canvas = find.byWidgetPredicate(
            (widget) =>
                widget is WorkspaceSurface &&
                widget.kind == WorkspaceSurfaceKind.canvas,
          );
          final container = tester.widget<Container>(
            find.descendant(of: canvas, matching: find.byType(Container)).first,
          );
          final background = (container.decoration! as BoxDecoration).color!;
          expect(
            background,
            WorkspacePalette.of(tester.element(canvas)).background,
          );
          if (appearance == 'paper') {
            expect(background.r, greaterThan(background.b));
            expect(background, isNot(Colors.white));
          }
          expect(fixture.tabs.events, isEmpty);
          expect(fixture.templates.builds, 0);
          expect(fixture.notifications.hasListener, isFalse);
          expect(fixture.menu.latestOpenView?.id, 'untouched-selection');
          expect(fixture.storage.accesses, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
          await fixture.dispose(tester);
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$appearance: native buttons support hover, Tab, Enter and Space',
      (tester) async {
        final fixture = _Fixture();
        final semantics = tester.ensureSemantics();
        final mouse =
            await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
        try {
          await _pumpHome(tester, fixture, appearance: appearance);
          await mouse.addPointer(location: Offset.zero);
          await mouse.moveTo(tester.getCenter(_button('workspace')));
          await _pumpInteraction(tester);
          final context = tester.element(_button('workspace'));
          final sharedStyle = WorkspaceChrome.controlStyle(context);
          final material = tester.widget<Material>(
            find
                .descendant(
                  of: _button('workspace'),
                  matching: find.byType(Material),
                )
                .first,
          );
          expect(
            material.color,
            sharedStyle.backgroundColor!.resolve({WidgetState.hovered}),
          );
          Focus.of(tester.element(find.text('Workspace'))).requestFocus();
          await _pumpInteraction(tester);
          _expectFocused(tester, 'workspace');
          final style = tester.widget<TextButton>(_button('workspace')).style!;
          expect(
            style.side!.resolve({WidgetState.focused})!.color,
            WorkspacePalette.of(context).focus,
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await _pumpInteraction(tester);
          expect(
            _opened(fixture.tabs.events.single).view?.id,
            'fixture-workspace',
          );

          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await _pumpInteraction(tester);
          _expectFocused(tester, 'search');
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await _pumpInteraction(tester);
          expect(fixture.palette.requests, 1);

          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await _pumpInteraction(tester);
          _expectFocused(tester, 'templates');
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await _pumpInteraction(tester);
          expect(
            _opened(fixture.tabs.events.last).plugin,
            isA<TemplatesPlugin>(),
          );
          expect(fixture.storage.accesses, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          await mouse.removePointer();
          semantics.dispose();
          await fixture.dispose(tester);
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$appearance: narrow, short, 2x and RTL stay usable',
      (tester) async {
        final fixture = _Fixture();
        try {
          fixture.workspace.show(
            _workspace(name: 'A long workspace name that wraps across lines'),
            userName: 'A long display name that also needs room to wrap',
          );
          for (final (size, scale, direction) in [
            (const Size(960, 600), 1.0, ui.TextDirection.ltr),
            (const Size(320, 260), 2.0, ui.TextDirection.ltr),
            (const Size(240, 260), 2.0, ui.TextDirection.rtl),
          ]) {
            await _pumpHome(
              tester,
              fixture,
              appearance: appearance,
              size: size,
              scale: scale,
              direction: direction,
            );
            expect(tester.takeException(), isNull);
            final bounds = tester.getRect(find.byType(WorkspaceHomePage));
            for (final id in ['workspace', 'search', 'templates']) {
              final rect = tester.getRect(_button(id));
              expect(rect.width, greaterThan(0));
              expect(rect.left, greaterThanOrEqualTo(bounds.left));
              expect(rect.right, lessThanOrEqualTo(bounds.right));
            }
            final workspaceTop = tester.getTopLeft(_button('workspace')).dy;
            final searchTop = tester.getTopLeft(_button('search')).dy;
            expect(
              searchTop,
              size.width < 600 ? greaterThan(workspaceTop) : workspaceTop,
            );
          }
          await tester.ensureVisible(_button('templates'));
          await _pumpInteraction(tester);
          expect(_button('templates').hitTestable(), findsOneWidget);
          await tester.tap(_button('templates'));
          await _pumpInteraction(tester);
          expect(fixture.templates.builds, 1);
          expect(fixture.storage.accesses, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.dispose(tester);
        }
      },
      timeout: _timeout,
    );
  }

  testWidgets(
    'actions route existing destinations without persisting Home',
    (tester) async {
      final fixture = _Fixture();
      try {
        await _pumpHome(tester, fixture);
        expect(fixture.tabs.events, isEmpty);
        await tester.tap(_button('workspace'));
        await _pumpInteraction(tester);
        final opened = _opened(fixture.tabs.events.single);
        expect(opened.plugin, isA<WorkspaceFolderPlugin>());
        expect(opened.view!.id, 'fixture-workspace');
        expect(opened.view!.parentViewId, isEmpty);
        expect(opened.view!.isWorkspaceRootFolder, isTrue);
        expect(opened.view!.childViews, isEmpty);
        expect(opened.view!.name, 'Research');
        expect(opened.plugin.id, opened.view!.id);
        expect(
          (opened.plugin as WorkspaceFolderPlugin).notifier.view,
          same(opened.view),
        );
        expect(opened.setLatest, isFalse);
        expect(fixture.menu.latestOpenView, same(opened.view));
        expect(fixture.notifications.hasListener, isTrue);

        await tester.tap(_button('search'));
        await _pumpInteraction(tester);
        expect(fixture.palette.value.isOpen, isTrue);
        expect(
          fixture.palette.value.userWorkspaceBloc,
          same(fixture.workspace),
        );
        expect(fixture.palette.value.spaceBloc, isNull);
        expect(fixture.tabs.events, hasLength(1));

        await tester.tap(_button('templates'));
        await _pumpInteraction(tester);
        final templates = _opened(fixture.tabs.events.last);
        expect(templates.plugin, isA<TemplatesPlugin>());
        expect(templates.view, isNull);
        expect(templates.setLatest, isFalse);
        expect(fixture.templates.builds, 1);
        expect(fixture.menu.latestOpenView, isNull);
        expect(fixture.storage.accesses, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
    timeout: _timeout,
  );

  testWidgets(
    'a workspace/profile change is read before the next paint',
    (tester) async {
      final fixture = _Fixture();
      try {
        await _pumpHome(tester, fixture);
        fixture.workspace.show(
          _workspace(id: 'next-workspace', name: 'Writing'),
          userName: 'Grace',
        );
        // The visible button still belongs to the previous frame.
        await tester.tap(_button('workspace'));
        await _pumpInteraction(tester);
        expect(_opened(fixture.tabs.events.single).view?.id, 'next-workspace');
        expect(find.text('Writing'), findsOneWidget);
        expect(find.text('Grace'), findsOneWidget);
        expect(find.text('Research'), findsNothing);
        expect(find.text('Ada Lovelace'), findsNothing);
        fixture.workspace.show(null);
        await tester.tap(_button('workspace'));
        await _pumpInteraction(tester);
        expect(fixture.tabs.events, hasLength(1));
        expect(
          tester.widget<TextButton>(_button('workspace')).onPressed,
          isNull,
        );
        expect(fixture.storage.accesses, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
    timeout: _timeout,
  );

  for (final missing in ['shell', 'workspace', 'workspace id']) {
    testWidgets(
      'missing $missing still renders an honest Home',
      (tester) async {
        final fixture = _Fixture(registerTemplates: false);
        final semantics = tester.ensureSemantics();
        try {
          if (missing == 'workspace') fixture.workspace.show(null);
          if (missing == 'workspace id') {
            fixture.workspace.show(_workspace(id: ' '));
          }
          await _pumpHome(
            tester,
            fixture,
            withShell: missing != 'shell',
            withPalette: false,
          );
          expect(find.text('Home'), findsOneWidget);
          expect(find.text('Welcome!'), findsOneWidget);
          expect(
            find.text('Unable to find the current workspace.'),
            findsOneWidget,
          );
          _expectButton(tester, 'workspace', enabled: false);
          expect(_button('search'), findsNothing);
          expect(_button('templates'), findsNothing);
          await tester.tap(_button('workspace'));
          await _pumpInteraction(tester);
          expect(fixture.tabs.events, isEmpty);
          expect(fixture.storage.accesses, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
          await fixture.dispose(tester);
        }
      },
      timeout: _timeout,
    );
  }

  testWidgets(
    'unregistered Templates is omitted without a blank-plugin loop',
    (tester) async {
      final fixture = _Fixture(registerTemplates: false);
      try {
        await _pumpHome(tester, fixture);
        expect(_button('workspace'), findsOneWidget);
        expect(_button('search'), findsOneWidget);
        expect(_button('templates'), findsNothing);
        expect(fixture.templates.builds, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
    timeout: _timeout,
  );

  testWidgets(
    'closed tabs reject stale clicks without constructing plugins',
    (tester) async {
      final fixture = _Fixture();
      try {
        await _pumpHome(tester, fixture);
        final openWorkspace =
            tester.widget<TextButton>(_button('workspace')).onPressed!;
        final openTemplates =
            tester.widget<TextButton>(_button('templates')).onPressed!;
        await pumpHomeProfileClose(tester, fixture.tabs.close());
        openWorkspace();
        openTemplates();
        await _pumpInteraction(tester);
        expect(fixture.tabs.events, isEmpty);
        expect(fixture.notifications.hasListener, isFalse);
        expect(fixture.templates.builds, 0);
        expect(fixture.menu.latestOpenView?.id, 'untouched-selection');
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
    timeout: _timeout,
  );

  testWidgets(
    'lightweight snapshots and callbacks work without shell providers',
    (tester) async {
      final fixture = _Fixture();
      var searches = 0;
      try {
        await _pumpHome(
          tester,
          fixture,
          withShell: false,
          withPalette: false,
          page: WorkspaceHomePage(
            workspace: _workspace(id: 'injected-root', name: 'Offline fixture'),
            userName: 'Reader',
            onNavigate: fixture.tabs.events.add,
            onSearch: () => searches++,
          ),
        );
        expect(find.text('Reader'), findsOneWidget);
        expect(find.text('Offline fixture'), findsOneWidget);
        expect(fixture.notifications.hasListener, isFalse);
        await tester.tap(_button('workspace'));
        await tester.tap(_button('search'));
        await _pumpInteraction(tester);
        expect(_opened(fixture.tabs.events.single).view?.id, 'injected-root');
        expect(searches, 1);
        expect(fixture.palette.requests, 0);
        expect(fixture.storage.accesses, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
    timeout: _timeout,
  );
}

Finder _button(String id) => find.byKey(ValueKey('workspace-home-$id'));

void _expectButton(WidgetTester tester, String id, {required bool enabled}) {
  final node = tester.getSemantics(_button(id));
  final data = node.getSemanticsData();
  expect(node.attached, isTrue);
  expect(data.hasFlag(SemanticsFlag.isButton), isTrue);
  expect(data.hasFlag(SemanticsFlag.hasEnabledState), isTrue);
  expect(data.hasFlag(SemanticsFlag.isEnabled), enabled);
  expect(data.hasAction(SemanticsAction.tap), enabled);
  expect(data.label, contains(id[0].toUpperCase() + id.substring(1)));
}

void _expectFocused(WidgetTester tester, String id) => expect(
      tester
          .getSemantics(_button(id))
          .getSemanticsData()
          .hasFlag(SemanticsFlag.isFocused),
      isTrue,
    );

({Plugin plugin, ViewPB? view, bool setLatest}) _opened(TabsEvent event) =>
    event.maybeWhen(
      openPlugin: (plugin, view, setLatest) =>
          (plugin: plugin, view: view, setLatest: setLatest),
      orElse: () => throw StateError('Expected only plugin navigation'),
    );

Future<void> _pumpInteraction(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _pumpHome(
  WidgetTester tester,
  _Fixture fixture, {
  String appearance = 'paper',
  Widget page = const BlankPage(),
  Size size = const Size(960, 720),
  double scale = 1,
  ui.TextDirection direction = ui.TextDirection.ltr,
  bool withShell = true,
  bool withPalette = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  Widget child = page;
  if (withPalette) {
    child = CommandPalette(notifier: fixture.palette, child: child);
  }
  if (withShell) {
    child = MultiBlocProvider(
      providers: [
        BlocProvider<UserWorkspaceBloc>.value(value: fixture.workspace),
        BlocProvider<TabsBloc>.value(value: fixture.tabs),
      ],
      child: child,
    );
  }
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en', 'US')],
      startLocale: const Locale('en', 'US'),
      fallbackLocale: const Locale('en', 'US'),
      path: 'assets/translations',
      saveLocale: false,
      assetLoader: const _Translations(),
      child: Builder(
        builder: (context) => MaterialApp(
          locale: context.locale,
          supportedLocales: context.supportedLocales,
          localizationsDelegates: context.localizationDelegates,
          theme: vividIconTestTheme(appearance),
          themeAnimationDuration: Duration.zero,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
            ),
            child: Directionality(textDirection: direction, child: child!),
          ),
          home: Scaffold(
            body: DefaultIconStyleScope(styles: fixture.styles, child: child),
          ),
        ),
      ),
    ),
  );
  await _pumpInteraction(tester);
  await tester.pump();
}

class _Translations extends AssetLoader {
  const _Translations();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) =>
      Future.value(_translations);
}

UserWorkspacePB _workspace({
  String id = 'fixture-workspace',
  String name = 'Research',
}) =>
    UserWorkspacePB(workspaceId: id, name: name, role: AFRolePB.Owner);

class _WorkspaceBloc extends Cubit<UserWorkspaceState>
    implements UserWorkspaceBloc {
  _WorkspaceBloc() : super(_state(_workspace()));

  static UserWorkspaceState _state(
    UserWorkspacePB? workspace, [
    String name = 'Ada Lovelace',
  ]) =>
      UserWorkspaceState(
        currentWorkspace: workspace,
        userProfile: UserProfilePB(
          id: Int64(7),
          name: name,
          email: 'private@example.invalid',
        ),
      );

  void show(UserWorkspacePB? workspace, {String userName = 'Ada Lovelace'}) =>
      emit(_state(workspace, userName));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records navigation without initializing plugins or mounting backend pages.
class _TabsBloc extends Cubit<TabsState> implements TabsBloc {
  _TabsBloc() : super(TabsState(pageManagers: []));
  final events = <TabsEvent>[];
  @override
  void add(TabsEvent event) => events.add(event);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records the real CommandPalette.toggle request, not its backend-owned modal.
class _PaletteRequests extends ValueNotifier<CommandPaletteNotifierValue> {
  _PaletteRequests() : super(CommandPaletteNotifierValue());
  CommandPaletteNotifierValue? _requested;
  int requests = 0;
  @override
  CommandPaletteNotifierValue get value => _requested ?? super.value;
  @override
  set value(CommandPaletteNotifierValue next) {
    _requested = next;
    requests++;
  }
}

class _TemplatesBuilder extends TemplatesPluginBuilder {
  int builds = 0;
  @override
  Plugin build(dynamic data) {
    builds++;
    return super.build(data);
  }
}

class _NoStorage extends Fake implements KeyValueStorage {
  final accesses = <Symbol>[];
  @override
  dynamic noSuchMethod(Invocation invocation) {
    accesses.add(invocation.memberName);
    return super.noSuchMethod(invocation);
  }
}

class _Notifications extends Fake implements RustStreamReceiver {
  _Notifications(this.observable);
  @override
  final StreamController<SubscribeObject> observable;
}

class _Fixture {
  _Fixture({bool registerTemplates = true}) {
    getIt.pushNewScope();
    final sandbox = PluginSandbox();
    if (registerTemplates) {
      sandbox.registerPlugin(PluginType.templates, templates);
    }
    getIt.registerSingleton<PluginSandbox>(sandbox);
    getIt.registerSingleton<MenuSharedState>(menu);
    getIt.registerSingleton<KeyValueStorage>(storage);
    RustStreamReceiver.shared = _Notifications(notifications);
  }

  final workspace = _WorkspaceBloc();
  final tabs = _TabsBloc();
  final palette = _PaletteRequests();
  final templates = _TemplatesBuilder();
  final storage = _NoStorage();
  final menu = MenuSharedState(view: ViewPB(id: 'untouched-selection'));
  final styles = ValueNotifier(DefaultIconStyle.vivid);
  final notifications = StreamController<SubscribeObject>.broadcast();
  final previousReceiver = RustStreamReceiver.shared;

  Future<void> dispose(WidgetTester tester) async {
    try {
      await tester.pumpWidget(const SizedBox());
      // The recording tab boundary never called init(), so release only the
      // constructor-owned notifier, not the plugin's uninitialized page blocs.
      for (final event in tabs.events) {
        _opened(event).plugin.notifier?.dispose();
      }
      await pumpHomeProfileClose(tester, notifications.close());
      await pumpHomeProfileClose(tester, workspace.close());
      if (!tabs.isClosed) await pumpHomeProfileClose(tester, tabs.close());
    } finally {
      RustStreamReceiver.shared = previousReceiver;
      palette.dispose();
      styles.dispose();
      menu.notifier.dispose();
      try {
        await pumpHomeProfileClose(tester, getIt.popScope());
      } finally {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    }
  }
}
