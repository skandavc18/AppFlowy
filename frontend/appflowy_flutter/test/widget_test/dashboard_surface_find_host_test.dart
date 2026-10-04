import 'package:appflowy/plugins/dashboard/presentation/dashboard_canvas.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_card.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_find.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_page.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/find_replace/find_replace_bar.dart';
import 'package:appflowy/shared/find_replace/surface_find.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_placement.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'surface_find_test_support.dart';

const _document = DashboardDocument(
  subtitle: 'Dashboard subtitle',
  settings: DashboardSettings(showControlBar: false, reduceMotion: true),
  sections: [
    DashboardSection(
      id: 'top',
      widgets: [
        DashboardWidgetSpec(
          id: 'top-note',
          type: 'text',
          showTitle: false,
          placement: DashboardPlacement(columnSpan: 12, rowSpan: 3),
          settings: {'text': 'Saved top note'},
        ),
        DashboardWidgetSpec(
          id: 'space',
          type: 'spacer',
          showTitle: false,
          placement: DashboardPlacement(row: 3, columnSpan: 12, rowSpan: 30),
        ),
      ],
    ),
    DashboardSection(
      id: 'tail',
      title: 'sectionword',
      collapsed: true,
      widgets: [
        DashboardWidgetSpec(
          id: 'tail-note',
          type: 'text',
          title: 'cardlabel',
          placement: DashboardPlacement(columnSpan: 12),
          settings: {'text': 'tailword and another tailword'},
        ),
      ],
    ),
  ],
);

Finder _field(String id) => find.descendant(
      of: find.byWidgetPredicate(
        (widget) =>
            widget is SurfaceFindTarget &&
            widget.id == dashboardFindWidget(id, 'text'),
      ),
      matching: find.byType(TextField),
    );

void main() {
  surfaceFindTestEnvironment();

  for (final appearance in WorkspaceDesignAppearance.values) {
    for (final readOnly in [false, true]) {
      testWidgets(
          '${appearance.name}: dashboard Ctrl+F reveals collapsed text (readonly=$readOnly)',
          (tester) async {
        final controller = DashboardController(
          viewId: '',
          document: _document,
          mode: readOnly ? DashboardMode.presentation : DashboardMode.edit,
        );
        try {
          await tester.pumpWidget(
            surfaceFindTestApp(
              DashboardPage(
                view: ViewPB(name: 'Titleword'),
                controller: controller,
              ),
              appearance: appearance,
            ),
          );
          await pumpSurfaceFind(tester);
          final topField = tester.widget<TextField>(_field('top-note'));
          final topState = tester.state(_field('top-note'));
          final cardState = tester.state(
            find.byWidgetPredicate(
              (widget) =>
                  widget is DashboardCard && widget.spec.id == 'top-note',
            ),
          );
          final outerScroll = tester.state<ScrollableState>(
            find
                .descendant(
                  of: find.byKey(
                    const PageStorageKey('dashboard-workspace-scroll'),
                  ),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          expect(outerScroll.position.pixels, 0);
          await openSurfaceFind(tester);
          expect(find.byType(FindReplaceBar), findsOneWidget);
          await tester.enterText(
            find.byKey(const ValueKey('findTextField')),
            'tailword',
          );
          await pumpSurfaceFind(tester);
          final session = tester
              .widget<SurfaceFindHost>(find.byType(SurfaceFindHost))
              .controller;
          expect(session.matches, hasLength(2));
          expect(outerScroll.position.pixels, greaterThan(700));
          final paint = surfaceFindPaint(
            tester,
            dashboardFindWidget('tail-note', 'text'),
          );
          expect(paint.matchRects, hasLength(2));
          expect(paint.currentRect, isNotNull);
          _expectCurrentWordVisible(tester, session);
          expect(
            tester.widget<TextField>(_field('tail-note')).readOnly,
            readOnly,
          );
          expect(tester.state(_field('top-note')), same(topState));
          expect(
            tester.widget<TextField>(_field('top-note')).controller,
            same(topField.controller),
          );
          expect(
            tester.state(
              find.byWidgetPredicate(
                (widget) =>
                    widget is DashboardCard && widget.spec.id == 'top-note',
              ),
            ),
            same(cardState),
          );
          expect(controller.document, same(_document));
          expect(controller.document.sections.last.collapsed, isTrue);
          if (readOnly) {
            expect(
              tester
                  .widget<FindReplaceBar>(find.byType(FindReplaceBar))
                  .replaceController,
              isNull,
            );
          }
          await tester.sendKeyEvent(
            LogicalKeyboardKey.f3,
            physicalKey: PhysicalKeyboardKey.f3,
          );
          await pumpSurfaceFind(tester);
          expect(session.currentIndex, 1);
          for (final query in ['cardlabel', 'sectionword', 'Titleword']) {
            await tester.enterText(
              find.byKey(const ValueKey('findTextField')),
              query,
            );
            await pumpSurfaceFind(tester);
            expect(session.matches, hasLength(1));
            expect(session.currentTargetRect, isNotNull);
            _expectCurrentWordVisible(tester, session);
          }
          expect(outerScroll.position.pixels, lessThan(500));
          await tester.sendKeyEvent(
            LogicalKeyboardKey.escape,
            physicalKey: PhysicalKeyboardKey.escape,
          );
          await pumpSurfaceFind(tester);
          expect(find.byType(FindReplaceBar), findsNothing);
          expect(controller.document, same(_document));
          expect(controller.canUndo, isFalse);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
        }
      });
    }
  }

  for (final appearance in WorkspaceDesignAppearance.values) {
    testWidgets(
        '${appearance.name}: section motion and Find retain a hidden native draft',
        (tester) async {
      final type = 'test.dashboard.surface-find.retained.${appearance.name}';
      const fieldKey = ValueKey('section-retained-draft');
      final draft = TextEditingController(text: 'An embedded draft');
      final focus = FocusNode();
      DashboardWidgetRegistry.register(
        DashboardWidgetDefinition(
          type: type,
          extensionId: type,
          label: () => 'Viewer',
          icon: Icons.description_outlined,
          group: DashboardWidgetGroup.content,
          builder: (_) => Semantics(
            label: 'Retained section draft',
            child: TextField(
              key: fieldKey,
              controller: draft,
              focusNode: focus,
            ),
          ),
        ),
      );
      final controller = DashboardController(
        viewId: '',
        document: DashboardDocument(
          settings: const DashboardSettings(showControlBar: false),
          sections: [
            DashboardSection(
              id: 'section',
              title: 'Collapsible',
              widgets: [
                DashboardWidgetSpec(
                  id: 'viewer',
                  type: type,
                  title: 'cardneedle',
                  placement: const DashboardPlacement(columnSpan: 12),
                ),
              ],
            ),
          ],
        ),
      );
      Widget page({required bool reduceMotion}) => surfaceFindTestApp(
            DashboardPage(
              view: ViewPB(name: 'Dashboard'),
              controller: controller,
            ),
            appearance: appearance,
            reduceMotion: reduceMotion,
          );
      void collapse(bool value) => controller.edit(
            (document) => document.withSection(
              document.sections.single.copyWith(collapsed: value),
            ),
          );
      final semantics = tester.ensureSemantics();
      final field = find.byKey(fieldKey);
      final retainedField = find.byKey(fieldKey, skipOffstage: false);
      final label = find.semantics.byLabel(RegExp('Retained section draft'));
      try {
        await tester.pumpWidget(page(reduceMotion: false));
        await pumpSurfaceFind(tester);
        await tester.enterText(field, 'Local unsaved draft');
        draft.selection = const TextSelection(baseOffset: 2, extentOffset: 8);
        final value = draft.value;
        final state = tester.state(retainedField);
        final expandedHeight =
            tester.getSize(find.byType(DashboardSectionView)).height;
        expect(label, findsOneWidget);

        collapse(true);
        await tester.pump();
        await tester.pump(DashboardMetrics.settle ~/ 2);
        final closingHeight =
            tester.getSize(find.byType(DashboardSectionView)).height;
        expect(closingHeight, greaterThan(0));
        expect(closingHeight, lessThan(expandedHeight));
        expect(field.hitTestable(), findsNothing);
        expect(label, findsNothing);
        await tester.pump(DashboardMetrics.settle);
        final collapsedHeight =
            tester.getSize(find.byType(DashboardSectionView)).height;
        expect(collapsedHeight, lessThan(closingHeight));
        expect(field, findsNothing);
        expect(tester.state(retainedField), same(state));
        expect(focus.canRequestFocus, isFalse);
        expect(draft.value, value);

        await tester.pumpWidget(page(reduceMotion: true));
        expect(tester.state(retainedField), same(state));
        final saved = controller.document;
        await openSurfaceFind(tester);
        await tester.enterText(
          find.byKey(const ValueKey('findTextField')),
          'cardneedle',
        );
        await pumpSurfaceFind(tester);
        final session = tester
            .widget<SurfaceFindHost>(find.byType(SurfaceFindHost))
            .controller;
        expect(session.matches, hasLength(1));
        _expectCurrentWordVisible(tester, session);
        expect(field.hitTestable(), findsOneWidget);
        expect(label, findsOneWidget);
        expect(tester.state(field), same(state));
        expect(draft.value, value);
        expect(controller.document, same(saved));

        await tester.sendKeyEvent(
          LogicalKeyboardKey.escape,
          physicalKey: PhysicalKeyboardKey.escape,
        );
        await pumpSurfaceFind(tester);
        expect(field, findsNothing);
        expect(label, findsNothing);
        expect(tester.state(retainedField), same(state));
        expect(draft.value, value);
        expect(controller.document, same(saved));

        await tester.pumpWidget(page(reduceMotion: false));
        collapse(false);
        await tester.pump();
        await tester.pump(DashboardMetrics.settle ~/ 2);
        final openingHeight =
            tester.getSize(find.byType(DashboardSectionView)).height;
        expect(openingHeight, greaterThan(collapsedHeight));
        expect(openingHeight, lessThan(expandedHeight));
        await tester.pump(DashboardMetrics.settle);
        expect(field.hitTestable(), findsOneWidget);
        expect(label, findsOneWidget);
        expect(tester.state(field), same(state));
        expect(draft.value, value);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        semantics.dispose();
        controller.dispose();
        draft.dispose();
        focus.dispose();
        DashboardWidgetRegistry.unregisterAll(type);
      }
    });
  }

  testWidgets(
      'suspended dashboard draft survives find, close and read-only access',
      (tester) async {
    final controller = DashboardController(viewId: '', document: _document);
    try {
      await tester.pumpWidget(
        surfaceFindTestApp(
          DashboardPage(
            view: ViewPB(name: 'Dashboard'),
            controller: controller,
          ),
        ),
      );
      await pumpSurfaceFind(tester);
      await tester.enterText(_field('top-note'), 'Unsaved draftword');
      final native = tester.widget<TextField>(_field('top-note'));
      native.controller!.selection =
          const TextSelection(baseOffset: 1, extentOffset: 5);
      final draft = native.controller!.value;
      final state = tester.state(_field('top-note'));
      controller.setReadOnly(true);
      await tester.pump();
      await openSurfaceFind(tester);
      await tester.enterText(
        find.byKey(const ValueKey('findTextField')),
        'draftword',
      );
      await pumpSurfaceFind(tester);
      final session = tester
          .widget<SurfaceFindHost>(find.byType(SurfaceFindHost))
          .controller;
      expect(session.matches, hasLength(1));
      expect(session.current!.entry.replaceable, isFalse);
      await tester.sendKeyEvent(
        LogicalKeyboardKey.escape,
        physicalKey: PhysicalKeyboardKey.escape,
      );
      await pumpSurfaceFind(tester);
      expect(tester.state(_field('top-note')), same(state));
      expect(native.controller!.value, draft);
      expect(controller.document, same(_document));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    }
  });

  testWidgets('an embedded content region wins without reparenting its draft',
      (tester) async {
    const type = 'test.dashboard.surface-find.viewer';
    var nestedFinds = 0;
    final draft = TextEditingController(text: 'An embedded draft');
    const draftKey = ValueKey('embedded-find-draft');
    DashboardWidgetRegistry.register(
      DashboardWidgetDefinition(
        type: type,
        extensionId: type,
        label: () => 'Viewer',
        icon: Icons.description_outlined,
        group: DashboardWidgetGroup.content,
        builder: (_) => ContextualFindRegion(
          debugLabel: 'Test embedded viewer',
          findInEditable: true,
          onFind: () => nestedFinds++,
          child: TextField(key: draftKey, controller: draft),
        ),
      ),
    );
    final controller = DashboardController(
      viewId: '',
      document: const DashboardDocument(
        settings: DashboardSettings(reduceMotion: true, showControlBar: false),
        sections: [
          DashboardSection(
            id: 's',
            widgets: [
              DashboardWidgetSpec(
                id: 'viewer',
                type: type,
                placement: DashboardPlacement(columnSpan: 12),
              ),
            ],
          ),
        ],
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(-20, -20));
    try {
      await tester.pumpWidget(
        surfaceFindTestApp(
          DashboardPage(
            view: ViewPB(name: 'Dashboard'),
            controller: controller,
          ),
        ),
      );
      await pumpSurfaceFind(tester);
      final before = tester.state(find.byKey(draftKey));
      await openSurfaceFind(tester);
      expect(find.byType(FindReplaceBar), findsOneWidget);
      await mouse.moveTo(tester.getCenter(find.byKey(draftKey)));
      await pumpSurfaceFind(tester);
      await openSurfaceFind(tester);
      expect(nestedFinds, 1);
      expect(find.byType(FindReplaceBar), findsNothing);
      expect(tester.state(find.byKey(draftKey)), same(before));
      expect(draft.text, 'An embedded draft');
    } finally {
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      draft.dispose();
      DashboardWidgetRegistry.unregisterAll(type);
    }
  });
}

void _expectCurrentWordVisible(
  WidgetTester tester,
  SurfaceFindController session,
) {
  final word = session.currentTargetRect;
  expect(word, isNotNull);
  final viewport = tester.getRect(find.byType(SurfaceFindHost));
  expect(word!.width, greaterThan(0));
  expect(word.height, greaterThan(0));
  expect(word.left, greaterThanOrEqualTo(viewport.left));
  expect(word.right, lessThanOrEqualTo(viewport.right));
  expect(word.top, greaterThanOrEqualTo(viewport.top));
  expect(word.bottom, lessThanOrEqualTo(viewport.bottom));
  expect(
    word.overlaps(tester.getRect(find.byType(FindReplaceBar))),
    isFalse,
    reason: 'The Find bar must not cover the selected dashboard word.',
  );
}
