import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:appflowy/plugins/blank/home/home_search.dart';
import 'package:appflowy/plugins/database/widgets/row/row_detail.dart';
import 'package:appflowy/shared/floating_modal.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/command_palette/command_palette_bloc.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'workspace_overlay_test_app.dart';

void main() {
  var ownsMenuState = false;
  setUpAll(() async {
    await initializeWorkspaceOverlayTests();
    if (!getIt.isRegistered<MenuSharedState>()) {
      ownsMenuState = true;
      getIt.registerSingleton<MenuSharedState>(MenuSharedState());
    }
  });
  tearDownAll(() async {
    if (ownsMenuState) await getIt.unregister<MenuSharedState>();
  });

  for (final appearance in ['light', 'dark', 'paper']) {
    testWidgets(
        '$appearance: a row page floats in over a dimmed, softly blurred window',
        (tester) async {
      var closed = 0;
      await tester.pumpWidget(
        workspaceOverlayTestApp(
          appearance: appearance,
          child: _launcher(
            (context) => showRowDetailPage(
              context: context,
              builder: (_) => const _RowPage(),
            ).then((_) => closed++),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_backdrop, findsNothing);

      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final route = ModalRoute.of(tester.element(find.text('Row page')))!;
      expect(route, isA<FloatingModalBarrier<dynamic>>());
      expect(route.transitionDuration, FloatingModal.enterDuration);
      expect(route.reverseTransitionDuration, FloatingModal.exitDuration);
      final dim = FloatingModal.barrierColor(tester.element(find.text('Open')));
      expect(route.barrierColor, dim);
      // Partway in, the window is partly blurred and the page partly arrived.
      expect(_blur(tester).enabled, isTrue);
      expect(_blur(tester).filter, isNot(_fullBlur));
      expect(_opacity(tester), inExclusiveRange(0.0, 1.0));
      expect(_transform(tester), isNot(Matrix4.identity()));

      await tester.pumpAndSettle();
      expect(_blur(tester).filter, _fullBlur);
      expect(
        tester
            .widget<ModalBarrier>(
              find.descendant(
                of: _backdrop,
                matching: find.byType(ModalBarrier),
              ),
            )
            .color,
        dim,
      );
      // At rest nothing extra is composited over the page's text.
      expect(_opacity(tester), 1.0);
      expect(_transform(tester), Matrix4.identity());
      switch (appearance) {
        case 'paper':
          expect(
            dim.withValues(alpha: 1),
            PaperTheme.scrim.withValues(alpha: 1),
          );
          expect(dim.r, greaterThan(dim.b));
          expect(dim.a, inInclusiveRange(0.1, 0.16));
        case 'dark':
          expect(dim.a, inInclusiveRange(0.2, 0.32));
        default:
          expect(dim.a, inInclusiveRange(0.1, 0.16));
      }

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      // Leaving: still drawn but fading, with the blur easing off alongside.
      expect(find.text('Row page'), findsOneWidget);
      expect(_opacity(tester), inExclusiveRange(0.0, 1.0));
      expect(_blur(tester).filter, isNot(_fullBlur));
      await tester.pumpAndSettle();
      expect(find.text('Row page'), findsNothing);
      expect(_backdrop, findsNothing);
      expect(closed, 1);

      // A click on the dimmed window still closes the page.
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(find.text('Row page'), findsNothing);
      expect(closed, 2);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('reduced motion shows the backdrop and page at rest at once',
      (tester) async {
    var closed = false;
    await tester.pumpWidget(
      workspaceOverlayTestApp(
        disableAnimations: true,
        child: _launcher(
          (context) => showRowDetailPage(
            context: context,
            builder: (_) => const _RowPage(),
          ).then((_) => closed = true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump();
    final route = ModalRoute.of(tester.element(find.text('Row page')))!;
    expect(route.transitionDuration, Duration.zero);
    expect(route.reverseTransitionDuration, Duration.zero);
    expect(_blur(tester).filter, _fullBlur);
    expect(_opacity(tester), 1.0);
    expect(_transform(tester), Matrix4.identity());

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump();
    expect(closed, isTrue);
    expect(_backdrop, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('turning motion off mid-arrival keeps the popup and its focus',
      (tester) async {
    final controller = AnimationController(
      vsync: const TestVSync(),
      duration: FloatingModal.enterDuration,
    );
    addTearDown(controller.dispose);
    final focus = FocusNode();
    addTearDown(focus.dispose);
    Widget entrance({required bool enabled}) => MaterialApp(
          home: Material(
            child: FloatingModalEntrance(
              animation: controller,
              enabled: enabled,
              child: TextField(focusNode: focus, autofocus: true),
            ),
          ),
        );

    await tester.pumpWidget(entrance(enabled: true));
    unawaited(controller.forward());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final field = tester.state(find.byType(EditableText));
    expect(focus.hasFocus, isTrue);
    expect(_opacity(tester), lessThan(1.0));

    await tester.pumpWidget(entrance(enabled: false));
    expect(tester.state(find.byType(EditableText)), same(field));
    expect(focus.hasFocus, isTrue);
    expect(_opacity(tester), 1.0);
    expect(_transform(tester), Matrix4.identity());
    await tester.pumpAndSettle();
    expect(controller.isCompleted, isTrue);
    expect(_opacity(tester), 1.0);
  });

  testWidgets(
      'the Home search panel unfolds from its bar over the same backdrop',
      (tester) async {
    final bloc = _PaletteBloc();
    final anchor = GlobalKey();
    await tester.pumpWidget(
      workspaceOverlayTestApp(
        child: BlocProvider<CommandPaletteBloc>.value(
          value: bloc,
          child: Builder(
            builder: (context) => Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 120),
                child: SizedBox(
                  key: anchor,
                  width: 480,
                  height: 44,
                  child: TextButton(
                    // Command mode keeps the panel off the search backend.
                    onPressed: () => showHomeSearch(
                      context,
                      anchorKey: anchor,
                      initialQuery: '> ',
                    ),
                    child: const Text('Open search'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open search'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final panel = find.byKey(const ValueKey('command-palette-anchored-panel'));
    expect(panel, findsOneWidget);
    final entrance = tester.widget<FloatingModalEntrance>(
      find.ancestor(of: panel, matching: find.byType(FloatingModalEntrance)),
    );
    expect(entrance.alignment, Alignment.topCenter);
    expect(entrance.offset.dy, lessThan(0));
    final route = ModalRoute.of(tester.element(panel))!;
    expect(route, isA<FloatingModalBarrier<dynamic>>());
    expect(route.transitionDuration, FloatingModal.enterDuration);
    expect(route.reverseTransitionDuration, FloatingModal.exitDuration);
    expect(
      route.barrierColor,
      FloatingModal.barrierColor(tester.element(find.text('Open search'))),
    );
    expect(_opacity(tester), inExclusiveRange(0.0, 1.0));

    await tester.pumpAndSettle();
    expect(_blur(tester).filter, _fullBlur);
    expect(_opacity(tester), 1.0);
    expect(_transform(tester), Matrix4.identity());
    // Settled exactly where the panel belongs over its bar.
    expect(
      tester.getRect(panel),
      homeSearchPanelRect(
        anchor: tester.getRect(find.byKey(anchor)),
        viewport: tester.getSize(find.byType(Scaffold)),
      ),
    );

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(_backdrop, findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await bloc.close();
  });
}

final _fullBlur = ImageFilter.blur(
  sigmaX: FloatingModal.blur,
  sigmaY: FloatingModal.blur,
);

final _backdrop = find.ancestor(
  of: find.byType(ModalBarrier),
  matching: find.byType(BackdropFilter),
);

BackdropFilter _blur(WidgetTester tester) =>
    tester.widget<BackdropFilter>(_backdrop);

double _opacity(WidgetTester tester) => tester
    .widget<Opacity>(
      find
          .descendant(
            of: find.byType(FloatingModalEntrance),
            matching: find.byType(Opacity),
          )
          .first,
    )
    .opacity;

Matrix4 _transform(WidgetTester tester) => tester
    .widget<Transform>(
      find
          .descendant(
            of: find.byType(FloatingModalEntrance),
            matching: find.byType(Transform),
          )
          .first,
    )
    .transform;

Widget _launcher(Future<void> Function(BuildContext) open) => Builder(
      builder: (context) => Center(
        child: TextButton(
          onPressed: () => open(context),
          child: const Text('Open'),
        ),
      ),
    );

class _RowPage extends StatelessWidget {
  const _RowPage();

  @override
  Widget build(BuildContext context) => const FlowyDialog(
        width: 360,
        expandHeight: false,
        child: SizedBox(height: 120, child: Center(child: Text('Row page'))),
      );
}

class _PaletteBloc extends Cubit<CommandPaletteState>
    implements CommandPaletteBloc {
  _PaletteBloc() : super(CommandPaletteState.initial().copyWith(query: '> '));

  @override
  void add(CommandPaletteEvent event) {}

  @override
  void setContentSearchEnabled(bool enabled) {}

  @override
  Future<List<ViewPB>?> reloadCachedViews() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
