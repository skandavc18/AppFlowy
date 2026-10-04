import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/sandboxed_code_runner.dart';
import 'package:appflowy/shared/document_viewer/standalone_file_page.dart';
import 'package:appflowy/shared/document_viewer/standalone_file_scope.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/shared/scrolling/scroll_gesture_gate.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'file_controls_test_support.dart';

// Author-only regressions. Use the actual root dispatcher, not just its
// ScrollBehavior: reduced motion alone cannot expose priority inversion.
void main() {
  fileControlTestSetup();
  for (final reduced in [false, true]) {
    for (final pan in [false, true]) {
      _filePageTest('Premium root reduced=$reduced pan=$pan: actual code page',
          (tester) async {
        final file = MemoryCodeFile(
          List.generate(400, (i) => 'print("line $i")').join('\n'),
        );
        final backend = FileControlBackend(
          fileControlView('live-root', 'source.py', file.path),
          file,
        );
        await mountFileControls(
          tester,
          PremiumScrollScope(enabled: true, child: backend.viewer()),
          reduced: reduced,
          height: 800,
        );
        final finder =
            find.byWidgetPredicate((w) => w is TextField && w.expands);
        final field = tester.widget<TextField>(finder);
        final native = tester.state(
          find.descendant(of: finder, matching: find.byType(EditableText)),
        );
        final runner = tester.state(find.byType(SandboxedCodeRunner));
        final page =
            tester.state<NestedScrollViewState>(find.byType(NestedScrollView));
        final header = find.byKey(
          const ValueKey('workspace-file-identity'),
          skipOffstage: false,
        );
        final headerElement = tester.element(header);
        final start = tester.getRect(header);
        final extent = page.outerController.position.maxScrollExtent;
        final body = field.scrollController!;
        final bounds = tester
            .getRect(finder)
            .intersect(tester.getRect(find.byType(StandaloneFilePage)));
        final point = Offset(bounds.center.dx, bounds.bottom - 24);
        const selection = TextSelection(baseOffset: 1, extentOffset: 7);
        field.controller!.selection = selection;
        final gesture = pan
            ? await tester.createGesture(kind: PointerDeviceKind.trackpad)
            : null;
        if (gesture != null) await gesture.panZoomStart(point);
        var total = 0.0;
        Future<void> move(double delta) async {
          total += delta;
          if (gesture != null) {
            await gesture.panZoomUpdate(point, pan: Offset(0, -total));
          } else {
            await tester.sendEventToBinding(
              PointerScrollEvent(
                position: point,
                scrollDelta: Offset(0, delta),
              ),
            );
          }
          await tester.pump();
        }

        await move(40);
        // Normal wheel has an immediate fraction and a single local ticker.
        // The old root dispatcher instead animates the independent TextField.
        expect(page.outerController.offset, greaterThan(0));
        expect(page.outerController.offset, lessThanOrEqualTo(40));
        expect(body.offset, 0);
        if (!pan && !reduced) {
          for (var i = 0; i < 8; i++) {
            await tester.pump(const Duration(milliseconds: 16));
            expect(
              body.offset,
              closeTo(0, 1e-9),
              reason: 'No frame may bypass a still-visible header',
            );
            expect(page.outerController.offset, lessThan(extent));
          }
          await tester.sendEventToBinding(
            PointerScrollInertiaCancelEvent(position: point),
          );
          await tester.pump();
        }

        // Fresh exact crossing at the actual controller boundary. We do not
        // assume that kinetic travel equals the original OS wheel distance.
        page.outerController.jumpTo(extent - 10);
        body.jumpTo(0);
        await tester.pump();
        await move(100);
        final immediate = !pan && !reduced ? 22.0 : 100.0;
        expect(page.outerController.offset, closeTo(extent, .01));
        expect(body.offset, closeTo(immediate - 10, .01));
        expect(tester.getRect(header).top, closeTo(start.top - extent, .01));
        expect(header.hitTestable(), findsNothing);
        if (!pan) {
          await tester.sendEventToBinding(
            PointerScrollInertiaCancelEvent(position: point),
          );
        }
        body.jumpTo(5);
        await tester.pump();
        await move(-100);
        expect(body.offset, 0);
        expect(
          page.outerController.offset,
          closeTo(extent - (immediate - 5), .01),
        );
        if (gesture != null) await gesture.panZoomEnd();
        expect(tester.element(header), same(headerElement));
        expect(tester.state(find.byType(SandboxedCodeRunner)), same(runner));
        expect(
          tester.state(
            find.descendant(
              of: finder,
              matching: find.byType(EditableText),
            ),
          ),
          same(native),
        );
        expect(
          tester.widget<TextField>(finder).controller,
          same(field.controller),
        );
        expect(field.controller!.selection, selection);
        expect(file.reads, 1);
        expect(file.writes, 0);
        expect(backend.loads, 1);
        expect(backend.extraWrites, isEmpty);
        expect(tester.takeException(), isNull);
      });
    }
  }

  _filePageTest('inactive gate hides both file and Premium markers from root',
      (tester) async {
    final body = ScrollController();
    final parent = ScrollController();
    final blocked = ValueNotifier(true);
    addTearDown(body.dispose);
    addTearDown(parent.dispose);
    addTearDown(blocked.dispose);
    await mountFileControls(
      tester,
      PremiumScrollScope(
        enabled: true,
        child: SingleChildScrollView(
          controller: parent,
          child: Column(
            children: [
              SizedBox(
                height: 400,
                child: ValueListenableBuilder<bool>(
                  valueListenable: blocked,
                  builder: (_, value, __) => ScrollGestureGate(
                    blocked: value,
                    child: StandaloneFilePage(
                      header: const SizedBox(height: 100),
                      body: StandaloneFileScrollRegion(
                        controller: body,
                        child: ListView.builder(
                          controller: body,
                          itemExtent: 40,
                          itemCount: 100,
                          itemBuilder: (_, i) => Text('row $i'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 1000),
            ],
          ),
        ),
      ),
    );
    final list = find.byType(ListView);
    final element = tester.element(list);
    final page =
        tester.state<NestedScrollViewState>(find.byType(NestedScrollView));
    final point = tester.getCenter(list);
    await tester.sendEventToBinding(
      PointerScrollEvent(position: point, scrollDelta: const Offset(0, 40)),
    );
    await tester.pumpAndSettle();
    expect(parent.offset, greaterThan(0));
    expect(page.outerController.offset, 0);
    expect(body.offset, 0);
    parent.jumpTo(0);
    blocked.value = false;
    await tester.pump();
    await tester.sendEventToBinding(
      PointerScrollEvent(position: point, scrollDelta: const Offset(0, 40)),
    );
    await tester.pump();
    expect(page.outerController.offset, greaterThan(0));
    expect(body.offset, 0);
    expect(parent.offset, 0);
    expect(tester.element(list), same(element));
    expect(tester.takeException(), isNull);
  });

  _filePageTest(
      'disengage hook stops owned motion; disabling retains the child',
      (tester) async {
    final body = ScrollController();
    final enabled = ValueNotifier(true);
    addTearDown(body.dispose);
    addTearDown(enabled.dispose);
    await mountFileControls(
      tester,
      PremiumScrollScope(
        enabled: true,
        child: StandaloneFilePage(
          header: const SizedBox(height: 200),
          body: ValueListenableBuilder<bool>(
            valueListenable: enabled,
            builder: (_, value, __) => StandaloneFileScrollRegion(
              enabled: value,
              controller: body,
              child: ListView.builder(
                controller: body,
                itemExtent: 40,
                itemCount: 100,
                itemBuilder: (_, i) => Text('retained row $i'),
              ),
            ),
          ),
        ),
      ),
    );
    final list = find.byType(ListView);
    final element = tester.element(list);
    final page =
        tester.state<NestedScrollViewState>(find.byType(NestedScrollView));
    final point = tester.getCenter(list);
    await tester.sendEventToBinding(
      PointerScrollEvent(position: point, scrollDelta: const Offset(0, 40)),
    );
    await tester.pump();
    final targets =
        tester.hitTestOnBinding(point).path.map((e) => e.target).toList();
    expect(
      targets.where(StandaloneFileScrollRegion.isHitTestTarget),
      hasLength(1),
    );
    expect(targets.where(PremiumScrollExclusion.isHitTestTarget), hasLength(1));
    // Match ScrollActivationRegion._stopScrolling: cancellation walks mounted
    // RenderObjectElements, not just the most recent pointer's hit path.
    final cancelled = <HitTestTarget>[];
    void cancel(Element element) {
      if (element is RenderObjectElement) {
        final target = element.renderObject;
        StandaloneFileScrollRegion.cancelMotion(target);
        if (StandaloneFileScrollRegion.isHitTestTarget(target)) {
          cancelled.add(target);
        }
      }
      element.visitChildElements(cancel);
    }

    tester.element(find.byType(StandaloneFilePage)).visitChildElements(cancel);
    expect(
      cancelled,
      containsAll(targets.where(StandaloneFileScrollRegion.isHitTestTarget)),
    );
    final stopped = page.outerController.offset;
    expect(stopped, greaterThan(0));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(page.outerController.offset, stopped);
      expect(body.offset, 0);
    }
    enabled.value = false;
    await tester.pump();
    final inactive =
        tester.hitTestOnBinding(point).path.map((e) => e.target).toList();
    expect(inactive.where(StandaloneFileScrollRegion.isHitTestTarget), isEmpty);
    expect(inactive.where(PremiumScrollExclusion.isHitTestTarget), isEmpty);
    expect(tester.element(list), same(element));
    await tester.sendEventToBinding(
      PointerScrollEvent(position: point, scrollDelta: const Offset(0, 40)),
    );
    await tester.pumpAndSettle();
    expect(page.outerController.offset, stopped);
    expect(body.offset, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  for (final bare in [false, true]) {
    for (final reduced in [false, true]) {
      for (final editable in [false, true]) {
        _filePageTest(
          'nested source bare=$bare reduced=$reduced editable=$editable '
          'never borrows enclosing file page',
          (tester) async {
            final chrome = StandaloneFileChromeController();
            addTearDown(chrome.dispose);
            final file = MemoryCodeFile(
              List.generate(400, (i) => 'print($i)').join('\n'),
            );
            await mountFileControls(
              tester,
              PremiumScrollScope(
                enabled: true,
                child: StandaloneFileScope(
                  canvas: Colors.transparent,
                  rendererName: bare ? 'child.py' : 'archive.zip',
                  displayName: 'Parent',
                  chrome: chrome,
                  canEdit: () => false,
                  canRead: () => true,
                  editable: false,
                  available: true,
                  child: StandaloneFilePage(
                    header: const SizedBox(height: 120),
                    body: LayoutBuilder(
                      builder: (_, constraints) => FilePreview(
                        file: file,
                        name: 'child.py',
                        kind: FilePreviewKind.code,
                        bare: bare,
                        framed: false,
                        height: constraints.maxHeight,
                        editable: editable,
                        metadata: const {},
                        onMetadataChanged: (_) {},
                      ),
                    ),
                  ),
                ),
              ),
              reduced: reduced,
            );
            final finder =
                find.byWidgetPredicate((w) => w is TextField && w.expands);
            expect(finder, findsOneWidget);
            final fieldElement = tester.element(finder);
            expect(StandaloneFilePageScroll.maybeOf(fieldElement), isNull);
            final field = tester.widget<TextField>(finder);
            final body = field.scrollController!;
            final nativeFinder = find.descendant(
              of: finder,
              matching: find.byType(EditableText),
            );
            final native = tester.state<EditableTextState>(nativeFinder);
            final runner = tester.state(find.byType(SandboxedCodeRunner));
            final page = tester
                .state<NestedScrollViewState>(find.byType(NestedScrollView));
            expect(field.readOnly, !editable);
            expect(field.scrollPhysics, isNull);
            expect(body.positions, hasLength(1));
            expect(page.outerController.positions, hasLength(1));
            expect(page.innerController.positions, isEmpty);
            expect(
              PrimaryScrollController.maybeOf(fieldElement),
              same(page.innerController),
            );
            expect(body, isNot(same(page.innerController)));
            expect(body, isNot(same(page.outerController)));
            final position = body.position;
            expect(position.maxScrollExtent, greaterThan(100));
            expect(
              position.physics.shouldAcceptUserOffset(position),
              isTrue,
              reason:
                  'Read-only source is not the NeverScrollable line gutter: '
                  '${position.physics}',
            );
            final bounds = tester
                .getRect(finder)
                .intersect(tester.getRect(find.byType(StandaloneFilePage)));
            final point = Offset(bounds.center.dx, bounds.bottom - 24);
            final targets = tester
                .hitTestOnBinding(point)
                .path
                .map((entry) => entry.target)
                .toList();
            final diagnostic = 'bare=$bare reduced=$reduced editable=$editable '
                'body=${position.pixels}/${position.maxScrollExtent} '
                'physics=${position.physics} '
                'hit=${targets.map((target) => target.runtimeType).join(',')} '
                'positions=${tester.stateList<ScrollableState>(find.byType(Scrollable)).map((state) => '${state.position.runtimeType}:${state.position.pixels}/${state.position.maxScrollExtent}:${state.position.physics}').join(';')}';
            expect(
              targets,
              contains(native.renderEditable),
              reason: diagnostic,
            );
            expect(
              targets.where(StandaloneFileScrollRegion.isHitTestTarget),
              isEmpty,
              reason: diagnostic,
            );
            expect(
              targets.where(PremiumScrollExclusion.isHitTestTarget),
              isEmpty,
              reason: 'Disabled adapters must not block the root: $diagnostic',
            );

            const selection = TextSelection(baseOffset: 1, extentOffset: 7);
            field.controller!.selection = selection;
            await tester.pump();
            await tester.sendEventToBinding(
              PointerScrollEvent(
                position: point,
                scrollDelta: const Offset(0, 40),
              ),
            );
            await tester.pump();
            for (var i = 0; i < 10; i++) {
              expect(page.outerController.offset, 0, reason: diagnostic);
              await tester.pump(const Duration(milliseconds: 16));
            }
            await tester.pumpAndSettle();
            expect(page.outerController.offset, 0, reason: diagnostic);
            // Premium's exact-distance queue discards at most wheelStopDistance;
            // this is not the file adapter's amplified kinetic impulse.
            final wheelTolerance = reduced
                ? 1e-9
                : const PremiumScrollPhysicsConfig().wheelStopDistance;
            expect(
              body.offset,
              closeTo(40, wheelTolerance),
              reason: diagnostic,
            );
            final beforeReverse = body.offset;
            await tester.sendEventToBinding(
              PointerScrollEvent(
                position: point,
                scrollDelta: const Offset(0, -20),
              ),
            );
            await tester.pumpAndSettle();
            expect(
              body.offset,
              closeTo(beforeReverse - 20, wheelTolerance),
              reason: diagnostic,
            );
            expect(page.outerController.offset, 0, reason: diagnostic);
            expect(tester.element(finder), same(fieldElement));
            expect(tester.state<EditableTextState>(nativeFinder), same(native));
            expect(
              tester.state(find.byType(SandboxedCodeRunner)),
              same(runner),
            );
            expect(
              tester.widget<TextField>(finder).scrollController,
              same(body),
            );
            expect(
              tester.widget<TextField>(finder).controller,
              same(field.controller),
            );
            expect(field.controller!.selection, selection);
            expect(file.reads, 1);
            expect(file.writes, 0);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}

/// Unmount before test-framework teardown even when mounting/assertions fail.
/// In particular, a routing failure must not masquerade as an icon leak.
void _filePageTest(
  String description,
  Future<void> Function(WidgetTester) body,
) {
  testWidgets(description, (tester) async {
    try {
      await body(tester);
    } finally {
      await unmountFileControls(tester);
    }
  });
}
