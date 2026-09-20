import 'package:appflowy/shared/workspace_layout.dart';
import 'package:appflowy/workspace/application/edit_panel/edit_context.dart';
import 'package:appflowy/workspace/application/home/home_setting_bloc.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/presentation/home/home_layout.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/workspace.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_setting.pb.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

const _widths = [320.0, 480.0, 800.0, 1280.0, 1920.0, 2560.0];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final width in _widths) {
    for (final status in MenuStatus.values) {
      for (final panel in [false, true]) {
        test('$width $status panel=$panel initializes and bounds every extent',
            () {
          final state =
              _state(status: status, panel: panel, resizeOffset: 5000);
          final layout = HomeLayout.fromState(state, availableWidth: width);
          expect(
            layout.menuIsDrawer,
            width < WorkspaceLayout.sidebarBreakpoint,
          );
          expect(layout.menuWidth, inInclusiveRange(0, width));
          expect(layout.editPanelWidth, inInclusiveRange(0, width));
          expect(layout.notificationPanelWidth, greaterThanOrEqualTo(320));
          expect(
            layout.homePageLOffset +
                layout.notificationPanelWidth +
                layout.homePageROffset,
            width,
          );
          if (status != MenuStatus.expanded || layout.menuIsDrawer) {
            expect(layout.homePageLOffset, 0);
          }
          expect(
            state.resizeOffset,
            5000,
            reason: 'layout must not rewrite the saved resize preference',
          );
        });
      }
    }
  }

  test('temporary clamps restore the original sidebar preference', () {
    final state = _state(panel: true, resizeOffset: 200);
    expect(HomeLayout.fromState(state, availableWidth: 1920).menuWidth, 460);
    expect(HomeLayout.fromState(state, availableWidth: 1024).menuWidth, 304);
    expect(HomeLayout.fromState(state, availableWidth: 320).menuWidth, 288);
    expect(HomeLayout.fromState(state, availableWidth: 1920).menuWidth, 460);
    expect(state.resizeOffset, 200);
  });

  test('reduced motion changes animation, not the allocated widths', () {
    final state = _state();
    final ordinary = HomeLayout.fromState(state, availableWidth: 1280);
    final reduced = HomeLayout.fromState(
      state,
      availableWidth: 1280,
      disableAnimations: true,
    );
    expect(reduced.animDuration, Duration.zero);
    expect(ordinary.animDuration, isNot(Duration.zero));
    expect(reduced.menuWidth, ordinary.menuWidth);
    expect(reduced.homePageLOffset, ordinary.homePageLOffset);
    expect(reduced.homePageROffset, ordinary.homePageROffset);
  });

  test('drawer and constrained offsets snap instead of tweening past the pane',
      () {
    final state = _state(panel: true, resizeOffset: 200);
    expect(
      HomeLayout.fromState(state, availableWidth: 320).animDuration,
      Duration.zero,
    );
    expect(
      HomeLayout.fromState(state, availableWidth: 1024).animDuration,
      Duration.zero,
    );
    expect(
      HomeLayout.fromState(state, availableWidth: 1920).animDuration,
      state.resizeType.duration(),
    );
  });

  test('screen-size events share the layout threshold and never save a clamp',
      () async {
    final appearance = _MockAppearanceCubit();
    when(() => appearance.state).thenReturn(_appearance());
    final bloc = HomeSettingBloc(
      WorkspaceLatestPB(workspaceId: 'layout-test'),
      appearance,
      1280,
    );
    try {
      for (final width in [800.0, 1024.0, 320.0, 2560.0]) {
        final changed = bloc.stream.firstWhere(
          (state) =>
              state.isScreenSmall == WorkspaceLayout.sidebarIsDrawer(width),
        );
        bloc.add(HomeSettingEvent.checkScreenSize(width));
        final state = await changed;
        expect(
          HomeLayout.fromState(state, availableWidth: width).menuIsDrawer,
          state.isScreenSmall,
        );
        expect(state.resizeOffset, 200);
      }
      verifyNever(() => appearance.saveMenuOffset(any()));
      verifyNever(() => appearance.saveIsMenuCollapsed(any()));
    } finally {
      await bloc.close();
    }
  });

  testWidgets(
      'pane constraints win over screen size and DPR without remounting',
      (tester) async {
    addTearDown(tester.view.reset);
    final state = _state(resizeOffset: 200);
    final bloc = _MockHomeSettingBloc();
    when(() => bloc.state).thenReturn(state);
    when(() => bloc.stream)
        .thenAnswer((_) => const Stream<HomeSettingState>.empty());
    final controller = TextEditingController(text: 'Keep this draft');
    final focus = FocusNode();
    var width = 1280.0;
    var scale = 1.0;
    late StateSetter resize;
    late HomeLayout layout;
    try {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(2560, 1200);
      await tester.pumpWidget(
        BlocProvider<HomeSettingBloc>.value(
          value: bloc,
          child: MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  resize = setState;
                  return MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(scale),
                    ),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: width,
                        height: 400,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            layout =
                                HomeLayout(context, constraints: constraints);
                            return Stack(
                              children: [
                                Positioned(
                                  left: layout.homePageLOffset,
                                  right: layout.homePageROffset,
                                  top: 0,
                                  bottom: 0,
                                  child: TextField(
                                    controller: controller,
                                    focusNode: focus,
                                  ),
                                ),
                              ],
                            );
                          },
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
      focus.requestFocus();
      await tester.pumpAndSettle();
      controller.selection =
          const TextSelection(baseOffset: 1, extentOffset: 5);
      final fieldState = tester.state(find.byType(EditableText));
      for (final nextWidth in _widths) {
        double? baseline;
        for (final dpr in [1.0, 2.0]) {
          tester.view.devicePixelRatio = dpr;
          tester.view.physicalSize = Size(2560 * dpr, 1200 * dpr);
          for (final nextScale in [1.0, 2.0]) {
            resize(() {
              width = nextWidth;
              scale = nextScale;
            });
            await tester.pumpAndSettle();
            final rect = tester.getRect(find.byType(TextField));
            expect(rect.right, closeTo(width, 0.001));
            expect(rect.left, closeTo(layout.homePageLOffset, 0.001));
            expect(
              layout.menuIsDrawer,
              width < WorkspaceLayout.sidebarBreakpoint,
            );
            if (baseline != null) expect(rect.width, baseline);
            baseline = rect.width;
            expect(tester.state(find.byType(EditableText)), same(fieldState));
            expect(focus.hasFocus, isTrue);
            expect(controller.text, 'Keep this draft');
            expect(
              controller.selection,
              const TextSelection(baseOffset: 1, extentOffset: 5),
            );
            expect(state.resizeOffset, 200);
            expect(tester.takeException(), isNull);
          }
        }
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      focus.dispose();
    }
  });
}

HomeSettingState _state({
  MenuStatus status = MenuStatus.expanded,
  bool panel = false,
  double resizeOffset = 0,
}) =>
    HomeSettingState(
      panelContext: panel ? const _PanelContext() : null,
      workspaceSetting: WorkspaceLatestPB(workspaceId: 'layout-test'),
      unauthorized: false,
      menuStatus: status,
      isNotificationPanelCollapsed: false,
      isScreenSmall: false,
      hasColappsedMenuManually: false,
      resizeOffset: resizeOffset,
      resizeStart: 0,
      resizeType: MenuResizeType.slide,
    );

class _PanelContext extends EditPanelContext {
  const _PanelContext()
      : super(
          identifier: 'layout-test',
          title: 'Panel',
          child: const SizedBox(),
        );
}

class _MockHomeSettingBloc extends Mock implements HomeSettingBloc {}

class _MockAppearanceCubit extends Mock implements AppearanceSettingsCubit {}

AppearanceSettingsState _appearance() {
  final dates = DateTimeSettingsPB();
  return AppearanceSettingsState(
    appTheme: AppTheme.fallback,
    themeMode: ThemeMode.light,
    font: defaultFontFamily,
    layoutDirection: LayoutDirection.ltrLayout,
    textDirection: AppFlowyTextDirection.ltr,
    enableRtlToolbarItems: false,
    locale: const Locale('en', 'US'),
    isMenuCollapsed: false,
    menuOffset: 200,
    dateFormat: dates.dateFormat,
    timeFormat: dates.timeFormat,
    timezoneId: dates.timezoneId,
    documentCursorColor: null,
    documentSelectionColor: null,
    textScaleFactor: 1,
    enableKineticScrolling: true,
  );
}
