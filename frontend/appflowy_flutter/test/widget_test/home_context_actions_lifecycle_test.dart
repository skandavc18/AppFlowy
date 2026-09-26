import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/application/home/home_setting_bloc.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/presentation/home/home_layout.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_design.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/workspace.pb.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

const _triggerKey = ValueKey('workspace-context-actions');
const _holdProbeKey = ValueKey('context-actions-hold-probe');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const windowChannel = MethodChannel('window_manager');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      windowChannel,
      (call) async => call.method.startsWith('is') ? false : null,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowChannel, null);
  });

  for (final secondary in [false, true]) {
    final header = secondary ? 'secondary' : 'primary';
    for (final appearance in ['light', 'dark', 'paper']) {
      testWidgets(
        '$appearance $header: same-notifier plugin replacement dismisses actions',
        (tester) async {
          final fixture = await _pumpHeader(tester, secondary, appearance);
          try {
            final source = fixture.source;
            final original = fixture.plugin;
            final trigger = _trigger(tester);
            final host = tester.state(find.byType(HomeContextActions));
            final actions = tester.widget<HomeContextActions>(
              find.byType(HomeContextActions),
            );
            expect(actions.source, same(source));
            expect(actions.actionIdentity, same(original));
            expect(_holdVisible(tester), isFalse);

            await tester.tap(find.byKey(_triggerKey));
            await tester.pumpAndSettle();
            final popup = tester.state<_ActionProbeState>(
              find.byType(_ActionProbe),
            );
            await tester.tap(find.byKey(const ValueKey('action-old')));
            expect(original.actions.activations, 1);
            expect(original.actions.page, same(source));
            expect(original.actions.tabs, same(fixture.tabs));
            expect(original.actions.settings, same(fixture.settings));

            // Even the same logical page ID may now own different blocs.
            // This is the same PageNotifier.setPlugin path used by Ctrl+N.
            final replacement = _ActionPlugin('new');
            expect(replacement.id, original.id);
            source.setPlugin(replacement, setLatest: false);
            expect(PopoverState.rootEntry.isEmpty, isTrue);
            await tester.pumpAndSettle();
            expect(fixture.source, same(source));
            expect(tester.state(find.byType(HomeContextActions)), same(host));
            expect(original.disposals, 1);
            expect(original.actions.disposed, isTrue);
            expect(popup.mounted, isFalse);
            expect(find.byType(_ActionProbe), findsNothing);

            // A callback retained by the old button must not open the new
            // page's popup either; only its current trigger may do that.
            trigger();
            await tester.pumpAndSettle();
            expect(PopoverState.rootEntry.isEmpty, isTrue);
            _trigger(tester)();
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(const ValueKey('action-new')));
            expect(replacement.actions.activations, 1);
            expect(replacement.actions.page, same(source));
            expect(replacement.actions.tabs, same(fixture.tabs));
            expect(replacement.actions.settings, same(fixture.settings));
            expect(original.actions.activations, 1);
            expect(tester.takeException(), isNull);
          } finally {
            await _unmount(tester, fixture);
          }
        },
      );

      testWidgets(
        '$appearance $header: fresh action widgets keep the same popup alive',
        (tester) async {
          final fixture = await _pumpHeader(tester, secondary, appearance);
          try {
            final original = fixture.plugin;
            _trigger(tester)();
            await tester.pumpAndSettle();
            final popup = tester.state(find.byType(_ActionProbe));
            final actionWidget = tester
                .widget<HomeContextActions>(find.byType(HomeContextActions))
                .child;
            final builds = original.actionWidgets;
            expect(_holdVisible(tester), isTrue);

            fixture.update(() => fixture.width = 360);
            await tester.pumpAndSettle();
            fixture.source.setPlugin(original, setLatest: false);
            await tester.pumpAndSettle();
            final rebuilt = tester.widget<HomeContextActions>(
              find.byType(HomeContextActions),
            );
            expect(rebuilt.compact, isTrue);
            expect(rebuilt.actionIdentity, same(original));
            expect(rebuilt.child, isNot(same(actionWidget)));
            expect(original.actionWidgets, greaterThan(builds));
            expect(PopoverState.rootEntry.isNotEmpty, isTrue);
            expect(tester.state(find.byType(_ActionProbe)), same(popup));
            expect(original.disposals, 0);
            expect(_holdVisible(tester), isTrue);
            await tester.tap(find.byKey(const ValueKey('action-old')));
            expect(original.actions.activations, 1);
            expect(original.actions.page, same(fixture.source));
            expect(original.actions.tabs, same(fixture.tabs));
            expect(original.actions.settings, same(fixture.settings));
            expect(tester.takeException(), isNull);
          } finally {
            await _unmount(tester, fixture);
          }
        },
      );
    }

    testWidgets('$header: a replaced source cancels a queued opening',
        (tester) async {
      final fixture = await _pumpHeader(tester, secondary, 'paper');
      try {
        _trigger(tester)();
        fixture.source.setPlugin(_ActionPlugin('new'), setLatest: false);
        await tester.pumpAndSettle();
        expect(PopoverState.rootEntry.isEmpty, isTrue);
        expect(find.byType(_ActionProbe), findsNothing);
        expect(_holdVisible(tester), isFalse);

        _trigger(tester)();
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('action-new')), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await _unmount(tester, fixture);
      }
    });

    testWidgets('$header: disposal before opening never acquires a hold',
        (tester) async {
      final fixture = await _pumpHeader(tester, secondary, 'paper');
      try {
        _trigger(tester)();
        fixture.source.dispose();
        await tester.pumpAndSettle();
        expect(PopoverState.rootEntry.isEmpty, isTrue);
        expect(find.byType(_ActionProbe), findsNothing);
        expect(_holdVisible(tester), isFalse);
        expect(tester.takeException(), isNull);
      } finally {
        await _unmount(tester, fixture);
      }
    });

    testWidgets('$header: disposal before first overlay build borrows nothing',
        (tester) async {
      final fixture = await _pumpHeader(tester, secondary, 'paper');
      try {
        final original = fixture.plugin;
        _trigger(tester)();
        // Opening inserts the entry after this frame; its child has not built.
        await tester.pump();
        expect(PopoverState.rootEntry.isNotEmpty, isTrue);
        expect(find.byType(_ActionProbe), findsNothing);
        fixture.source.dispose();
        await tester.pumpAndSettle();
        expect(original.actions.disposed, isTrue);
        expect(PopoverState.rootEntry.isEmpty, isTrue);
        expect(find.byType(_ActionProbe), findsNothing);
        expect(_holdVisible(tester), isFalse);
        expect(tester.takeException(), isNull);
      } finally {
        await _unmount(tester, fixture);
      }
    });

    testWidgets('$header: unmount invalidates queued and retained triggers',
        (tester) async {
      final fixture = await _pumpHeader(tester, secondary, 'paper');
      try {
        final trigger = _trigger(tester);
        trigger();
        await tester.pumpWidget(const SizedBox.shrink());
        trigger();
        await tester.pumpAndSettle();
        expect(PopoverState.rootEntry.isEmpty, isTrue);
        expect(find.byType(_ActionProbe), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await _unmount(tester, fixture);
      }
    });

    testWidgets('$header: rebinding isolates the popup from the old notifier',
        (tester) async {
      final fixture = await _pumpHeader(tester, secondary, 'paper');
      try {
        final oldSource = fixture.source;
        _trigger(tester)();
        await tester.pumpAndSettle();
        fixture.rebind(_ActionPlugin('new'));
        await tester.pumpAndSettle();
        expect(PopoverState.rootEntry.isEmpty, isTrue);
        expect(_holdVisible(tester), isFalse);
        _trigger(tester)();
        await tester.pumpAndSettle();
        final popup = tester.state(find.byType(_ActionProbe));
        oldSource.setPlugin(_ActionPlugin('retired'), setLatest: false);
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(_ActionProbe)), same(popup));
        await tester.tap(find.byKey(const ValueKey('action-new')));
        expect(fixture.plugin.actions.page, same(fixture.source));
        expect(tester.takeException(), isNull);
      } finally {
        await _unmount(tester, fixture);
      }
    });

    testWidgets('$header: leaving compact releases only the popup hold',
        (tester) async {
      final fixture = await _pumpHeader(tester, secondary, 'paper');
      try {
        final original = fixture.plugin;
        _trigger(tester)();
        await tester.pumpAndSettle();
        expect(_holdVisible(tester), isTrue);
        fixture.update(() => fixture.width = 1200);
        await tester.pumpAndSettle();
        expect(find.byKey(_triggerKey), findsNothing);
        expect(PopoverState.rootEntry.isEmpty, isTrue);
        expect(_holdVisible(tester), isFalse);
        expect(original.disposals, 0);
        expect(original.actions.disposed, isFalse);
        expect(find.byKey(const ValueKey('action-old')), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await _unmount(tester, fixture);
      }
    });

    testWidgets('$header: an ordinary close balances its toolbar hold',
        (tester) async {
      final fixture = await _pumpHeader(tester, secondary, 'paper');
      try {
        _trigger(tester)();
        await tester.pumpAndSettle();
        expect(_holdVisible(tester), isTrue);
        final popup = tester.element(find.byType(_ActionProbe));
        PopoverContainer.of(popup).close();
        await tester.pumpAndSettle();
        expect(PopoverState.rootEntry.isEmpty, isTrue);
        expect(_holdVisible(tester), isFalse);
        expect(fixture.plugin.disposals, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await _unmount(tester, fixture);
      }
    });
  }
}

VoidCallback _trigger(WidgetTester tester) =>
    tester.widget<SidebarIconButton>(find.byKey(_triggerKey)).onPressed;

bool _holdVisible(WidgetTester tester) =>
    tester
        .widget<AnimatedOpacity>(
          find.descendant(
            of: find.byKey(_holdProbeKey),
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .opacity ==
    1;

Future<_HeaderFixture> _pumpHeader(
  WidgetTester tester,
  bool secondary,
  String appearance,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 800);
  addTearDown(tester.view.reset);
  final fixture = _HeaderFixture(secondary);
  final theme = DesktopAppearance().getThemeData(
    appearance == 'paper'
        ? AppTheme.builtins
            .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
        : AppTheme.fallback,
    appearance == 'dark' ? Brightness.dark : Brightness.light,
    defaultFontFamily,
    builtInCodeFontFamily,
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: theme.copyWith(platform: TargetPlatform.windows),
      themeAnimationDuration: Duration.zero,
      home: Scaffold(
        // These providers deliberately live BELOW the root overlay. Actions
        // can read them only if HomeContextActions forwards the same instances.
        body: MultiBlocProvider(
          providers: [
            BlocProvider<TabsBloc>.value(value: fixture.tabs),
            BlocProvider<HomeSettingBloc>.value(value: fixture.settings),
          ],
          child: StatefulBuilder(
            builder: (context, update) {
              fixture.update = update;
              return ChangeNotifierProvider<PageNotifier>.value(
                value: fixture.source,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: fixture.width,
                    height: 120,
                    child: PreviewToolbarRegion(
                      child: Column(
                        children: [
                          if (secondary)
                            HomeSecondaryTopBar(
                              key: ObjectKey(fixture),
                            )
                          else
                            HomeTopBar(
                              layout: HomeLayout.fromState(
                                fixture.settings.state,
                                availableWidth: fixture.width,
                              ),
                            ),
                          const PreviewToolbar(
                            key: _holdProbeKey,
                            child: SizedBox(width: 16, height: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  if (!secondary) {
    final titleBar = find.byKey(const ValueKey('workspace-title-bar'));
    final contextBar = find.byKey(const ValueKey('workspace-context-header'));
    expect(tester.getSize(titleBar).height, 40);
    expect(tester.getSize(contextBar).height, 36);
    expect(tester.getTopLeft(contextBar).dy, tester.getBottomLeft(titleBar).dy);
  }
  return fixture;
}

Future<void> _unmount(WidgetTester tester, _HeaderFixture fixture) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  for (final manager in fixture.managers) {
    manager.dispose();
  }
}

class _HeaderFixture {
  _HeaderFixture(this.secondary) {
    _adopt(_ActionPlugin('old'));
    // The primary title row now builds the grouped navigation controls.
    when(() => tabs.isClosed).thenReturn(false);
    when(() => tabs.canGoBack).thenReturn(false);
    when(() => tabs.canGoForward).thenReturn(false);
    when(() => settings.isClosed).thenReturn(false);
    when(() => tabs.state).thenAnswer(
      (_) => TabsState(pageManagers: [manager]),
    );
    when(() => tabs.stream).thenAnswer((_) => const Stream<TabsState>.empty());
    when(() => settings.stream)
        .thenAnswer((_) => const Stream<HomeSettingState>.empty());
    when(() => settings.state).thenReturn(
      HomeSettingState(
        panelContext: null,
        workspaceSetting: WorkspaceLatestPB(workspaceId: 'action-lifetime'),
        unauthorized: false,
        menuStatus: MenuStatus.expanded,
        isNotificationPanelCollapsed: true,
        isScreenSmall: true,
        hasColappsedMenuManually: false,
        resizeOffset: 0,
        resizeStart: 0,
        resizeType: MenuResizeType.slide,
      ),
    );
  }

  final bool secondary;
  final tabs = _MockTabsBloc();
  final settings = _MockHomeSettingBloc();
  final managers = <PageManager>[];
  late PageManager manager;
  late StateSetter update;
  double width = 320;

  PageNotifier get source =>
      secondary ? manager.secondaryNotifier : manager.notifier;
  _ActionPlugin get plugin => source.plugin as _ActionPlugin;

  void _adopt(_ActionPlugin plugin) {
    manager = PageManager(
      plugin: secondary ? _ActionPlugin('primary') : plugin,
    );
    if (secondary) manager.setSecondaryPlugin(plugin);
    managers.add(manager);
  }

  void rebind(_ActionPlugin plugin) => update(() => _adopt(plugin));
}

class _MockTabsBloc extends Mock implements TabsBloc {}

class _MockHomeSettingBloc extends Mock implements HomeSettingBloc {}

class _ActionPlugin extends Plugin {
  _ActionPlugin(String tag) : actions = _ActionModel(tag);

  final _ActionModel actions;
  int disposals = 0;
  int actionWidgets = 0;

  @override
  String get id => 'same-page';
  @override
  PluginType get pluginType => PluginType.document;
  @override
  PluginWidgetBuilder get widgetBuilder => _ActionWidgets(this);
  @override
  void dispose() {
    disposals++;
    actions.dispose();
  }
}

class _ActionWidgets extends PluginWidgetBuilder {
  _ActionWidgets(this.plugin);
  final _ActionPlugin plugin;

  @override
  String get viewName => plugin.actions.tag;
  @override
  List<NavigationItem> get navigationItems => [this];
  @override
  Widget get leftBarItem => Text(viewName, overflow: TextOverflow.ellipsis);
  @override
  Widget get rightBarItem {
    plugin.actionWidgets++;
    return ChangeNotifierProvider<_ActionModel>.value(
      value: plugin.actions,
      child: const _ActionProbe(),
    );
  }

  @override
  Widget tabBarItem(String pluginId, [bool shortForm = false]) => leftBarItem;
  @override
  Widget buildWidget({
    required PluginContext context,
    required bool shrinkWrap,
    Map<String, dynamic>? data,
  }) =>
      const SizedBox.expand();
}

class _ActionModel extends ChangeNotifier {
  _ActionModel(this.tag);
  final String tag;
  bool disposed = false;
  int activations = 0;
  PageNotifier? page;
  TabsBloc? tabs;
  HomeSettingBloc? settings;

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

class _ActionProbe extends StatefulWidget {
  const _ActionProbe();

  @override
  State<_ActionProbe> createState() => _ActionProbeState();
}

class _ActionProbeState extends State<_ActionProbe> {
  @override
  Widget build(BuildContext context) {
    final model = context.watch<_ActionModel>();
    if (model.disposed) throw StateError('Built disposed plugin actions');
    return TextButton(
      key: ValueKey('action-${model.tag}'),
      onPressed: () {
        if (model.disposed) {
          throw StateError('Activated disposed plugin actions');
        }
        model.page = context.read<PageNotifier>();
        model.tabs = context.read<TabsBloc>();
        model.settings = context.read<HomeSettingBloc>();
        model.activations++;
      },
      child: Text('Action ${model.tag}'),
    );
  }
}
