import 'dart:async';
import 'dart:ui' as ui;

import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/find_replace/find_replace_bar.dart';
import 'package:appflowy/shared/find_replace/surface_find.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'surface_find_test_support.dart';

void main() {
  surfaceFindTestEnvironment();

  for (final appearance in WorkspaceDesignAppearance.values) {
    testWidgets('${appearance.name}: keyboard-only find scrolls to exact words',
        (tester) async {
      final session = SurfaceFindController(
        search: (query, options) => searchSurfaceEntries(
          const [
            SurfaceFindEntry('top', 'A needle here'),
            SurfaceFindEntry(
              'tail',
              'A needle and another needle at the end',
            ),
          ],
          query,
          options,
        ),
      );
      final scroll = ScrollController();
      final draft = TextEditingController(text: 'Unrelated unsaved draft');
      const draftKey = ValueKey('surface-draft');
      try {
        await tester.pumpWidget(
          surfaceFindTestApp(
            SurfaceFindHost(
              controller: session,
              child: Column(
                children: [
                  TextField(key: draftKey, controller: draft),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scroll,
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SurfaceFindTarget(
                            id: 'top',
                            child: Text('A needle here'),
                          ),
                          SizedBox(height: 1800),
                          SurfaceFindTarget(
                            id: 'tail',
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(text: 'A needle and another '),
                                  TextSpan(
                                    text: 'needle',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  TextSpan(text: ' at the end'),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(height: 600),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            appearance: appearance,
          ),
        );
        await pumpSurfaceFind(tester);
        final before = tester.state(find.byKey(draftKey));
        expect(find.byType(FindReplaceBar), findsNothing);
        expect(scroll.offset, 0);
        await openSurfaceFind(tester);
        expect(find.byType(FindReplaceBar), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('findTextField')),
          'needle',
        );
        await pumpSurfaceFind(tester);
        expect(session.matches, hasLength(3));
        await tester.sendKeyEvent(
          LogicalKeyboardKey.f3,
          physicalKey: PhysicalKeyboardKey.f3,
        );
        await pumpSurfaceFind(tester);
        expect(scroll.offset, greaterThan(1000));
        final paint = surfaceFindPaint(tester, 'tail');
        expect(paint.matchRects, hasLength(2));
        final firstWord = paint.currentRect!;
        expect(firstWord.width, lessThan(paint.size.width));
        await tester.sendKeyEvent(
          LogicalKeyboardKey.f3,
          physicalKey: PhysicalKeyboardKey.f3,
        );
        await pumpSurfaceFind(tester);
        expect(paint.currentRect!.left, greaterThan(firstWord.left));
        expect(tester.state(find.byKey(draftKey)), same(before));
        expect(draft.text, 'Unrelated unsaved draft');
        await tester.sendKeyEvent(
          LogicalKeyboardKey.escape,
          physicalKey: PhysicalKeyboardKey.escape,
        );
        await pumpSurfaceFind(tester);
        expect(find.byType(FindReplaceBar), findsNothing);
        expect(paint.matchRects, isEmpty);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        session.dispose();
        scroll.dispose();
        draft.dispose();
      }
    });
  }

  testWidgets('find retains draft selection and restores only its own focus',
      (tester) async {
    final session = SurfaceFindController(
      search: (q, o) => searchSurfaceEntries(
        const [SurfaceFindEntry('text', 'needle')],
        q,
        o,
      ),
    );
    final draft = TextEditingController(text: 'A composer draft');
    final originalFocus = FocusNode();
    final otherFocus = FocusNode();
    const draftKey = ValueKey('retained-draft');
    try {
      await tester.pumpWidget(
        surfaceFindTestApp(
          SurfaceFindHost(
            controller: session,
            findInEditable: true,
            child: Column(
              children: [
                TextField(
                  key: draftKey,
                  controller: draft,
                  focusNode: originalFocus,
                ),
                const SurfaceFindTarget(id: 'text', child: Text('needle')),
                TextField(
                  key: const ValueKey('other-field'),
                  focusNode: otherFocus,
                ),
              ],
            ),
          ),
        ),
      );
      await pumpSurfaceFind(tester);
      await tester.tap(find.byKey(draftKey));
      draft.selection = const TextSelection(baseOffset: 2, extentOffset: 8);
      final before = draft.value;
      final state = tester.state(find.byKey(draftKey));
      await openSurfaceFind(tester);
      await tester.enterText(
        find.byKey(const ValueKey('findTextField')),
        'needle',
      );
      await pumpSurfaceFind(tester);
      expect(draft.value, before);
      await tester.sendKeyEvent(
        LogicalKeyboardKey.escape,
        physicalKey: PhysicalKeyboardKey.escape,
      );
      await pumpSurfaceFind(tester);
      expect(originalFocus.hasFocus, isTrue);
      expect(tester.state(find.byKey(draftKey)), same(state));
      expect(draft.value, before);
      await openSurfaceFind(tester);
      await tester.tap(find.byKey(const ValueKey('other-field')));
      await tester.pump();
      tester.widget<FindReplaceBar>(find.byType(FindReplaceBar)).onClose();
      await pumpSurfaceFind(tester);
      expect(otherFocus.hasFocus, isTrue);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
      draft.dispose();
      originalFocus.dispose();
      otherFocus.dispose();
    }
  });

  testWidgets('paint excludes nested viewers and unrelated editable controls',
      (tester) async {
    final session = SurfaceFindController(
      search: (q, o) => searchSurfaceEntries(
        const [SurfaceFindEntry('text', 'needle')],
        q,
        o,
      ),
    );
    final protected = TextEditingController(text: 'needle');
    try {
      await tester.pumpWidget(
        surfaceFindTestApp(
          SurfaceFindHost(
            controller: session,
            child: SurfaceFindTarget(
              id: 'text',
              child: Column(
                children: [
                  const Text('needle'),
                  const SurfaceFindExclude(child: Text('needle')),
                  ContextualFindRegion(
                    onFind: () {},
                    child: const Text('needle'),
                  ),
                  TextField(controller: protected),
                ],
              ),
            ),
          ),
        ),
      );
      await openSurfaceFind(tester);
      await tester.enterText(
        find.byKey(const ValueKey('findTextField')),
        'needle',
      );
      await pumpSurfaceFind(tester);
      expect(surfaceFindPaint(tester, 'text').matchRects, hasLength(1));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
      protected.dispose();
    }
  });

  testWidgets(
      'read-only single-line text uses native horizontal reveal, not selection',
      (tester) async {
    final text = '${List.filled(40, 'prefix').join(' ')} needle';
    final field = TextEditingController(text: text)
      ..selection = const TextSelection.collapsed(offset: 0);
    final before = field.value;
    final session = SurfaceFindController(
      search: (q, o) =>
          searchSurfaceEntries([SurfaceFindEntry('readonly', text)], q, o),
    );
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        surfaceFindTestApp(
          SurfaceFindHost(
            controller: session,
            child: Center(
              child: SizedBox(
                width: 180,
                child: SurfaceFindTarget(
                  id: 'readonly',
                  includeEditable: true,
                  child: TextField(
                    key: const ValueKey('readonly-body'),
                    controller: field,
                    readOnly: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await openSurfaceFind(tester);
      await tester.enterText(
        find.byKey(const ValueKey('findTextField')),
        'needle',
      );
      await pumpSurfaceFind(tester);
      final native = find.descendant(
        of: find.byKey(const ValueKey('readonly-body')),
        matching: find.byType(EditableText),
      );
      final RenderEditable editable =
          tester.state<EditableTextState>(native).renderEditable;
      expect(editable.offset.pixels, greaterThan(0));
      final rect = surfaceFindPaint(tester, 'readonly').currentRect!;
      expect(rect.left, greaterThanOrEqualTo(-0.01));
      expect(rect.right, lessThanOrEqualTo(180.01));
      expect(field.value, before);
      expect(
        tester
            .getSemantics(native)
            .getSemanticsData()
            .hasFlag(ui.SemanticsFlag.isReadOnly),
        isTrue,
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
      field.dispose();
      semantics.dispose();
    }
  });

  testWidgets('cancel and disposal invalidate asynchronous reveal/focus work',
      (tester) async {
    final baseline = ContextualFindRegion.debugRegisteredRegionCount;
    final pending = Completer<void>();
    var started = false;
    final session = SurfaceFindController(
      search: (q, o) => searchSurfaceEntries(
        const [SurfaceFindEntry('text', 'needle')],
        q,
        o,
      ),
    );
    await tester.pumpWidget(
      surfaceFindTestApp(
        SurfaceFindHost(
          controller: session,
          onReveal: (_) {
            started = true;
            return pending.future;
          },
          child: const SurfaceFindTarget(id: 'text', child: Text('needle')),
        ),
      ),
    );
    await openSurfaceFind(tester);
    await tester.enterText(
      find.byKey(const ValueKey('findTextField')),
      'needle',
    );
    await tester.pump();
    expect(started, isTrue);
    session.close();
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
    pending.complete();
    await pumpSurfaceFind(tester);
    expect(ContextualFindRegion.debugRegisteredRegionCount, baseline);
  });
}
