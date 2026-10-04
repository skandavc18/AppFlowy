import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:appflowy/shared/page_cover.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/presentation/settings/pages/cover_appearance_setting.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/page_cover_test_support.dart';
import 'workspace_overlay_test_app.dart';

const _art =
    PageStyleCover(type: PageStyleCoverImageType.builtInImage, value: 'n1');
const _frameKey = ValueKey('resize-test-header');

void main() {
  setUpAll(initializeWorkspaceOverlayTests);

  for (final appearance in ['light', 'dark', 'paper']) {
    testWidgets(
        '$appearance live defaults retain title state/focus and explicit height',
        (tester) async {
      final storage = CoverMemoryStorage();
      final store = CoverAppearanceStore(resolveStorage: () => storage);
      await store.ensureLoaded();
      final io = CoverMemoryViews(_view());
      final original = io.view.writeToBuffer();
      final draft = TextEditingController(text: 'Unsaved title');
      final focus = FocusNode();
      await _mount(
        tester,
        store,
        io,
        appearance: appearance,
        title: TextField(controller: draft, focusNode: focus),
      );
      final titleState = tester.state(find.byType(EditableText));
      focus.requestFocus();
      draft.selection = const TextSelection(baseOffset: 1, extentOffset: 5);
      await tester.pump();
      await store.update(
        (v) => v.copyWith(
          corners: CoverCorners.square,
          aspectRatio: 4,
          fit: CoverImageFit.fit,
          position: CoverPosition.bottom,
        ),
      );
      await tester.pump();
      final width = tester.getSize(find.byType(WorkspacePageCover)).width;
      expect(
        tester.getSize(find.byType(WorkspacePageCover)).height,
        closeTo(width / 4, .001),
      );
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.fit, BoxFit.contain);
      expect(image.alignment, Alignment.bottomCenter);
      expect(tester.state(find.byType(EditableText)), same(titleState));
      expect(focus.hasFocus, isTrue);
      expect(draft.text, 'Unsaved title');
      expect(
        draft.selection,
        const TextSelection(baseOffset: 1, extentOffset: 5),
      );
      expect(io.view.writeToBuffer(), original);
      expect(io.writes, isEmpty);

      io.emit(PageCoverHeight.applyTo(io.view, 230.125));
      await tester.pump();
      await store.update(
        (v) => v.copyWith(aspectRatio: 6, fit: CoverImageFit.stretch),
      );
      await tester.pump();
      expect(tester.getSize(find.byType(WorkspacePageCover)).height, 230.125);
      expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.fill);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      draft.dispose();
      focus.dispose();
      store.dispose();
    });

    for (final terminal in ['release', 'cancel', 'escape']) {
      testWidgets('$appearance pumped drag $terminal writes only on release',
          (tester) async {
        final store =
            CoverAppearanceStore(resolveStorage: () => CoverMemoryStorage());
        await store.ensureLoaded();
        final io = CoverMemoryViews(_view());
        await _mount(tester, store, io, appearance: appearance);
        final frame = find.byType(WorkspacePageCover);
        final original = tester.getSize(frame).height;
        final grip = find.byKey(const ValueKey('page-cover-resize'));
        expect(grip.hitTestable(), findsOneWidget);
        final pointer = await tester.startGesture(
          tester.getCenter(grip),
          kind: PointerDeviceKind.mouse,
        );
        await pointer.moveBy(const Offset(0, 4));
        await tester.pump();
        await pointer.moveBy(const Offset(0, 37.25));
        await tester.pump();
        final preview = tester.getSize(frame).height;
        expect(preview, greaterThan(original));
        expect(io.writes, isEmpty);
        if (terminal == 'cancel') {
          await pointer.cancel();
        } else if (terminal == 'escape') {
          await tester.sendKeyEvent(
            LogicalKeyboardKey.escape,
            physicalKey: PhysicalKeyboardKey.escape,
          );
          await pointer.up();
        } else {
          await pointer.up();
        }
        await tester.pump();
        await tester.pump();
        expect(io.writes.length, terminal == 'release' ? 1 : 0);
        expect(
          tester.getSize(frame).height,
          terminal == 'release' ? preview : original,
        );
        if (terminal == 'release') {
          expect(PageCoverHeight.decode(io.view.extra), preview);
          await tester.sendKeyEvent(
            LogicalKeyboardKey.arrowDown,
            physicalKey: PhysicalKeyboardKey.arrowDown,
          );
          await tester.pump();
          expect(PageCoverHeight.decode(io.view.extra), preview + 1);
          await tester.sendKeyEvent(
            LogicalKeyboardKey.home,
            physicalKey: PhysicalKeyboardKey.home,
          );
          await tester.pump();
          expect(PageCoverHeight.decode(io.view.extra), isNull);
          expect(tester.getSize(frame).height, original);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        store.dispose();
      });
    }

    testWidgets('$appearance read-only changes cancel a held drag',
        (tester) async {
      final store =
          CoverAppearanceStore(resolveStorage: () => CoverMemoryStorage());
      await store.ensureLoaded();
      final io = CoverMemoryViews(_view());
      final editable = ValueNotifier(true);
      await _mount(
        tester,
        store,
        io,
        appearance: appearance,
        editable: editable,
      );
      final original = tester.getSize(find.byType(WorkspacePageCover)).height;
      final pointer = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('page-cover-resize'))),
        kind: PointerDeviceKind.mouse,
      );
      await pointer.moveBy(const Offset(0, 5));
      await tester.pump();
      await pointer.moveBy(const Offset(0, 40));
      await tester.pump();
      editable.value = false;
      await tester.pump();
      await pointer.up();
      await tester.pump();
      expect(find.byKey(const ValueKey('page-cover-resize')), findsNothing);
      expect(tester.getSize(find.byType(WorkspacePageCover)).height, original);
      expect(io.writes, isEmpty);
      editable.value = true;
      await tester.pump();
      expect(io.writes, isEmpty);
      await tester.pumpWidget(const SizedBox());
      editable.dispose();
      store.dispose();
    });

    testWidgets(
        '$appearance native settings change actual preview without page writes',
        (tester) async {
      final storage = CoverMemoryStorage();
      final store = CoverAppearanceStore(resolveStorage: () => storage);
      await store.ensureLoaded();
      await tester.pumpWidget(
        workspaceOverlayTestApp(
          appearance: appearance,
          disableAnimations: true,
          textScale: 2,
          child: Center(
            child: SizedBox(
              width: 360,
              child: SingleChildScrollView(
                child: CoverAppearanceSetting(store: store),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      final square =
          find.byKey(const ValueKey('cover-appearance-CoverCorners.square'));
      await tester.ensureVisible(square);
      await tester.pump();
      await tester.tap(square);
      await tester.pump();
      expect(store.value.corners, CoverCorners.square);
      final fit =
          find.byKey(const ValueKey('cover-appearance-CoverImageFit.fit'));
      await tester.ensureVisible(fit);
      await tester.pump();
      await tester.tap(fit);
      await tester.pump();
      expect(store.value.fit, CoverImageFit.fit);
      expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.contain);
      final reset = find.byKey(const ValueKey('cover-appearance-reset'));
      await tester.ensureVisible(reset);
      await tester.pump();
      await tester.tap(reset);
      await tester.pump();
      expect(store.value, CoverAppearance.defaults);
      expect(
        storage.writes
            .every((write) => write.$1 == CoverAppearanceStore.storageKey),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });
  }

  testWidgets(
      'defaults reach multiple mounted default covers but not thumbnail fit',
      (tester) async {
    final store =
        CoverAppearanceStore(resolveStorage: () => CoverMemoryStorage());
    await store.ensureLoaded();
    await tester.pumpWidget(
      workspaceOverlayTestApp(
        disableAnimations: true,
        child: CoverAppearanceScope(
          store: store,
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (var i = 0; i < 2; i++)
                  WorkspacePageHeader(
                    key: ValueKey('default-$i'),
                    cover: const ViewCoverImage(cover: _art),
                    identity: Text('Page $i'),
                  ),
                const ViewCoverThumbnail(cover: _art),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await store
        .update((v) => v.copyWith(fit: CoverImageFit.fit, aspectRatio: 6));
    await tester.pump();
    for (var i = 0; i < 2; i++) {
      final image = find.descendant(
        of: find.byKey(ValueKey('default-$i')),
        matching: find.byType(Image),
      );
      expect(tester.widget<Image>(image).fit, BoxFit.contain);
    }
    final thumbnail = find.descendant(
      of: find.byType(ViewCoverThumbnail),
      matching: find.byType(Image),
    );
    expect(tester.widget<Image>(thumbnail).fit, BoxFit.cover);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('empty cover slot stays empty and has no writable affordance',
      (tester) async {
    final store =
        CoverAppearanceStore(resolveStorage: () => CoverMemoryStorage());
    await store.ensureLoaded();
    await tester.pumpWidget(
      workspaceOverlayTestApp(
        child: CoverAppearanceScope(
          store: store,
          child: const WorkspacePageHeader(identity: Text('No cover')),
        ),
      ),
    );
    await tester.pump();
    await store.update((v) => v.copyWith(aspectRatio: 1));
    await tester.pump();
    expect(find.byType(WorkspacePageCover), findsNothing);
    expect(find.byKey(const ValueKey('page-cover-resize')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets(
      'pending media action invalidates a queued resize even on same-frame completion',
      (tester) async {
    final store =
        CoverAppearanceStore(resolveStorage: () => CoverMemoryStorage());
    await store.ensureLoaded();
    final io = CoverMemoryViews(_view())..readGate = Completer<void>();
    final gate = ValueNotifier(true);
    await tester.pumpWidget(
      workspaceOverlayTestApp(
        child: CoverAppearanceScope(
          store: store,
          child: PageCoverBackendScope(
            backend: PageCoverBackendService(views: io),
            child: PageCoverInteractionGate(
              allowed: gate,
              child: SingleChildScrollView(
                child: WorkspacePageHeader(
                  coverView: io.view,
                  coverEditable: true,
                  cover: const ViewCoverImage(cover: _art),
                  identity: const Text('Title'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final grip = find.byKey(const ValueKey('page-cover-resize'));
    await tester.tap(grip);
    await tester.pump();
    await tester.sendKeyEvent(
      LogicalKeyboardKey.arrowDown,
      physicalKey: PhysicalKeyboardKey.arrowDown,
    );
    await tester.pump();
    expect(io.reads, 1);
    gate.value = false;
    gate.value = true;
    io.readGate!.complete();
    await tester.pump();
    expect(io.writes, isEmpty);
    await tester.pumpWidget(const SizedBox());
    gate.dispose();
    store.dispose();
  });

  testWidgets('grip has semantic adjustment actions and reports failed saves',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final store =
        CoverAppearanceStore(resolveStorage: () => CoverMemoryStorage());
    await store.ensureLoaded();
    final io = CoverMemoryViews(_view())..failWrite = true;
    await _mount(tester, store, io);
    final grip = find.byKey(const ValueKey('page-cover-resize'));
    final node = tester.getSemantics(grip);
    expect(node.attached, isTrue);
    final data = node.getSemanticsData();
    expect(data.hasAction(SemanticsAction.increase), isTrue);
    expect(data.hasAction(SemanticsAction.decrease), isTrue);
    node.owner!.performAction(node.id, SemanticsAction.increase);
    await tester.pump();
    expect(
      tester.getSemantics(grip).getSemanticsData().hint,
      contains('Could not save'),
    );
    expect(PageCoverHeight.decode(io.view.extra), isNull);
    await tester.pumpWidget(const SizedBox());
    semantics.dispose();
    store.dispose();
  });
}

ViewPB _view() => ViewPB(
      id: 'resize-widget',
      layout: ViewLayoutPB.Document,
      extra: '{"cover":{"type":"built_in","value":"n1"}}',
    );

Future<void> _mount(
  WidgetTester tester,
  CoverAppearanceStore store,
  CoverMemoryViews io, {
  String appearance = 'light',
  Widget title = const Text('Title'),
  ValueNotifier<bool>? editable,
}) async {
  Widget header(bool enabled) => WorkspacePageHeader(
        key: _frameKey,
        coverView: io.view,
        coverEditable: enabled,
        coverBinding: io,
        cover: const ViewCoverImage(
          cover: _art,
          width: double.infinity,
          height: double.infinity,
        ),
        identity: title,
      );
  await tester.pumpWidget(
    workspaceOverlayTestApp(
      appearance: appearance,
      disableAnimations: true,
      child: CoverAppearanceScope(
        store: store,
        child: PageCoverBackendScope(
          backend: PageCoverBackendService(views: io),
          child: SingleChildScrollView(
            child: Column(
              children: [
                editable == null
                    ? header(true)
                    : ValueListenableBuilder<bool>(
                        valueListenable: editable,
                        builder: (_, enabled, __) => header(enabled),
                      ),
                const SizedBox(height: 1000),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}
