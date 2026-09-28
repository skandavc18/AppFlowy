import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/collection_page.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_card.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_chrome.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_grid_view.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_host.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_toolbar.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_views.dart';
import 'package:appflowy/plugins/collection/views/collection_page_scroll_scope.dart';
import 'package:appflowy/shared/icon_emoji_picker/recent_icons.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_controller.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_link.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_controller.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'vivid_icon_test_support.dart';

const _pageScroll = ValueKey('collection-page-scroll-view');
const _title = ValueKey('collection-title');
const _icon = ValueKey('collection-header-icon');
const _identity = ValueKey('collection-page-identity');
const _editor = ValueKey('workspace-inline-name-editor');
const _wheelFrame = Duration(milliseconds: 8);
const _wheelConfig = PremiumScrollPhysicsConfig();
const _modes = [
  BookmarkViewIds.grid,
  BookmarkViewIds.feed,
  BookmarkViewIds.shelf,
  BookmarkViewIds.timeline,
];

void main() {
  final previousRecents = RecentIcons.enable;
  setUpAll(() async {
    RecentIcons.enable = false;
    await prepareVividIconTestAssets();
  });
  tearDownAll(() => RecentIcons.enable = previousRecents);

  for (final appearance in vividIconTestAppearances) {
    for (final mode in _modes) {
      testWidgets(
          '$appearance: $mode body drag retreats the real header exactly once',
          (tester) async {
        _largeViewport(tester);
        final fixture = _Library(mode);
        try {
          await fixture.explorer.initialize();
          await tester.pumpWidget(_app(appearance, fixture.page));
          await tester.pumpAndSettle();

          final nested = _nested(tester);
          final body = _body(tester);
          final model = _model(tester);
          final hostState = tester.state(find.byType(BookmarkHost));
          final stateBefore = model.state.toJson();
          final idsBefore = model.entries.map((entry) => entry.id).toList();
          // Viewport's onstage traversal skips a sliver once its paint extent
          // reaches zero, even though its header remains mounted. Include that
          // header for geometry/lifetime checks, not for gesture targeting.
          final identity = find.byKey(_identity, skipOffstage: false);
          final icon = find.byKey(_icon, skipOffstage: false);
          final title = find.byKey(_title, skipOffstage: false);
          final cover = find.byType(ViewCoverImage, skipOffstage: false);
          final identityElement = tester.element(identity);
          final headerTop = tester.getTopLeft(identity).dy;
          final iconTop = tester.getTopLeft(icon).dy;
          final titleTop = tester.getTopLeft(title).dy;
          final coverTop = tester.getTopLeft(cover).dy;
          final extent = nested.outerController.position.maxScrollExtent;
          expect(extent, greaterThan(0));
          expect(find.byKey(_identity), findsOneWidget);
          expect(nested.innerController.positions, hasLength(1));
          expect(
            tester.widget<BookmarkScrollArea>(_mainArea).controller,
            same(nested.innerController),
          );
          expect(body.position, same(nested.innerController.position));
          final toolbarContext = tester.element(find.byType(BookmarkToolbar));
          expect(
            PrimaryScrollController.of(toolbarContext),
            same(nested.innerController),
          );
          expect(
            PrimaryScrollController.shouldInherit(
              toolbarContext,
              Axis.vertical,
            ),
            isFalse,
          );

          // Start ON the real body, not the cover, and pump between moves so
          // a rebuild/remount during an active drag cannot escape the test.
          final drag = await tester.startGesture(_bodyPoint(tester));
          await drag.moveBy(const Offset(0, -24));
          await tester.pump();
          var previous = _distance(nested);
          final frames = ((extent + 240) / 32).ceil();
          for (var frame = 0; frame < frames; frame++) {
            await drag.moveBy(const Offset(0, -32));
            await tester.pump(const Duration(milliseconds: 16));
            expect(_distance(nested) - previous, closeTo(32, 0.01));
            previous = _distance(nested);
            final outer = nested.outerController.offset;
            expect(
              tester.getTopLeft(identity).dy,
              closeTo(headerTop - outer, 0.01),
            );
            expect(
              tester.getTopLeft(icon).dy,
              closeTo(iconTop - outer, 0.01),
            );
            expect(
              tester.getTopLeft(title).dy,
              closeTo(titleTop - outer, 0.01),
            );
            expect(
              tester.getTopLeft(cover).dy,
              closeTo(coverTop - outer, 0.01),
            );
            if (nested.innerController.offset > 0) {
              expect(outer, closeTo(extent, 0.01));
            }
            expect(nested.innerController.positions, hasLength(1));
          }
          await drag.cancel();
          await tester.pumpAndSettle();
          expect(nested.innerController.offset, greaterThan(150));
          expect(
            tester.getBottomLeft(identity).dy,
            lessThanOrEqualTo(tester.getTopLeft(find.byKey(_pageScroll)).dy),
          );
          expect(tester.element(identity), same(identityElement));
          expect(identityElement.mounted, isTrue);
          expect(tester.renderObject(identity).attached, isTrue);
          expect(find.byKey(_identity), findsNothing);
          expect(identity.hitTestable(), findsNothing);
          expect(title.hitTestable(), findsNothing);
          expect(_body(tester), same(body));
          expect(_model(tester), same(model));
          expect(tester.state(find.byType(BookmarkHost)), same(hostState));
          expect(model.entries.map((entry) => entry.id), idsBefore);
          expect(model.state.toJson(), stateBefore);

          // Reverse using the same real scroll path, rather than jumping an
          // independent header controller back into place.
          final reverse = await tester.startGesture(_bodyPoint(tester));
          await reverse.moveBy(const Offset(0, 24));
          await tester.pump();
          for (var frame = 0;
              frame < 100 && _distance(nested) > 0.01;
              frame++) {
            final amount = math.min(32.0, _distance(nested));
            final before = _distance(nested);
            await reverse.moveBy(Offset(0, amount));
            await tester.pump(const Duration(milliseconds: 16));
            expect(_distance(nested), closeTo(before - amount, 0.01));
          }
          await reverse.cancel();
          await tester.pumpAndSettle();
          expect(nested.outerController.offset, closeTo(0, 0.01));
          expect(nested.innerController.offset, closeTo(0, 0.01));
          expect(find.byKey(_identity), findsOneWidget);
          expect(tester.element(identity), same(identityElement));
          expect(
            tester.getTopLeft(find.byKey(_title)).dy,
            closeTo(titleTop, 0.01),
          );
          expect(fixture.repository.reads, 1);
          expect(fixture.opened, isEmpty);
          expect(fixture.persisted, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          fixture.dispose();
        }
      });

      testWidgets(
        '$appearance: $mode wheel coordinates the real header and body',
        (tester) async {
          _largeViewport(tester);
          final fixture = _Library(mode);
          try {
            await fixture.explorer.initialize();
            await tester.pumpWidget(
              _app(appearance, fixture.page, premium: true),
            );
            await tester.pumpAndSettle();
            final nested = _nested(tester);
            final body = _body(tester);
            final outerPosition = nested.outerController.position;
            final innerPosition = nested.innerController.position;
            final model = _model(tester);
            final hostState = tester.state(find.byType(BookmarkHost));
            final stateBefore = model.state.toJson();
            final idsBefore = model.entries.map((entry) => entry.id).toList();
            final header =
                find.byType(WorkspacePageHeader, skipOffstage: false);
            final identity = find.byKey(_identity, skipOffstage: false);
            final title = find.byKey(_title, skipOffstage: false);
            final identityElement = tester.element(identity);
            final headerRect = tester.getRect(header);
            final identityRect = tester.getRect(identity);
            final bodyRect = tester.getRect(_mainArea);
            // Measure the complete rendered header, including its current
            // typography and spacing, rather than assuming its old height.
            final extent = headerRect.height;
            expect(extent, greaterThan(120));
            expect(outerPosition.maxScrollExtent, closeTo(extent, 0.01));
            expect(find.byType(PremiumCoordinatedScrollScope), findsOneWidget);
            expect(_distance(nested), 0);
            var retiredHeader = false;

            void expectRetainedFrame() {
              final outer = nested.outerController.offset;
              expect(_nested(tester), same(nested));
              expect(nested.outerController.position, same(outerPosition));
              expect(nested.innerController.position, same(innerPosition));
              expect(nested.innerController.positions, hasLength(1));
              expect(body.position, same(innerPosition));
              expect(
                tester.widget<BookmarkScrollArea>(_mainArea).controller,
                same(nested.innerController),
              );
              expect(
                tester.getRect(header).top,
                closeTo(headerRect.top - outer, 0.01),
              );
              expect(tester.getRect(header).height, closeTo(extent, 0.01));
              expect(
                tester.getRect(identity).top,
                closeTo(identityRect.top - outer, 0.01),
              );
              expect(
                tester.getRect(_mainArea).top,
                closeTo(bodyRect.top - outer, 0.01),
              );
              expect(tester.element(identity), same(identityElement));
              expect(identityElement.mounted, isTrue);
              expect(tester.renderObject(identity).attached, isTrue);
              expect(_body(tester), same(body));
              expect(_model(tester), same(model));
              expect(tester.state(find.byType(BookmarkHost)), same(hostState));
              if (nested.innerController.offset > 1e-10) {
                retiredHeader = true;
                expect(outer, closeTo(extent, 0.01));
                expect(
                  tester.getRect(header).bottom,
                  lessThanOrEqualTo(
                    tester.getRect(find.byKey(_pageScroll)).top + 0.01,
                  ),
                );
                expect(find.byKey(_identity), findsNothing);
                expect(identity.hitTestable(), findsNothing);
                expect(title.hitTestable(), findsNothing);
              }
            }

            // Preserve the full header/body round trip, but split the old
            // oversized packets so none hits the premium per-notch cap.
            for (final delta in [
              80.0,
              ..._wheelPackets(extent + 120),
              -80.0,
              ..._wheelPackets(-extent),
              -120.0,
              // Exercise the leading boundary even if previous queues left
              // sub-pixel stopping residuals in either direction.
              -80.0,
            ]) {
              await _expectSmoothedWheel(
                tester,
                nested,
                delta,
                expectFrame: expectRetainedFrame,
              );
            }
            expect(retiredHeader, isTrue);
            expect(
              _distance(nested),
              closeTo(0, _wheelConfig.wheelStopDistance),
            );
            expect(find.byKey(_identity), findsOneWidget);
            expect(find.byKey(_title), findsOneWidget);
            expect(tester.getRect(header).top, closeTo(headerRect.top, 0.01));
            expect(model.entries.map((entry) => entry.id), idsBefore);
            expect(model.state.toJson(), stateBefore);
            expect(fixture.repository.reads, 1);
            expect(fixture.opened, isEmpty);
            expect(fixture.persisted, isEmpty);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            fixture.dispose();
          }
        },
      );
    }

    testWidgets(
      '$appearance: rapid wheels share the header/body queue and retain the title draft',
      (tester) async {
        _largeViewport(tester);
        final fixture = _Library(BookmarkViewIds.grid, withCover: false);
        try {
          await fixture.explorer.initialize();
          await tester
              .pumpWidget(_app(appearance, fixture.page, premium: true));
          await tester.pumpAndSettle();
          fixture.explorer.beginRename(fixture.root.id);
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(_editor),
            'An unsaved collection title',
          );
          final field = tester.widget<EditableText>(find.byKey(_editor));
          const selection = TextSelection(baseOffset: 3, extentOffset: 10);
          field.controller.selection = selection;
          await tester.pumpAndSettle();

          final nested = _nested(tester);
          final body = _body(tester);
          final outerPosition = nested.outerController.position;
          final innerPosition = nested.innerController.position;
          final model = _model(tester);
          final hostState = tester.state(find.byType(BookmarkHost));
          final stateBefore = model.state.toJson();
          final idsBefore = model.entries.map((entry) => entry.id).toList();
          final header = find.byType(WorkspacePageHeader, skipOffstage: false);
          final title = find.byKey(_title, skipOffstage: false);
          final editor = find.byKey(_editor, skipOffstage: false);
          final titleElement = tester.element(title);
          final fieldState = tester.state(editor);
          final headerRect = tester.getRect(header);
          final titleRect = tester.getRect(title);
          final extent = headerRect.height;
          expect(extent, greaterThan(80));
          expect(outerPosition.maxScrollExtent, closeTo(extent, 0.01));

          void expectRetainedFrame() {
            expect(_nested(tester), same(nested));
            expect(_body(tester), same(body));
            expect(nested.outerController.position, same(outerPosition));
            expect(nested.innerController.position, same(innerPosition));
            expect(nested.innerController.positions, hasLength(1));
            expect(body.position, same(innerPosition));
            expect(
              tester.widget<BookmarkScrollArea>(_mainArea).controller,
              same(nested.innerController),
            );
            expect(_model(tester), same(model));
            expect(tester.state(find.byType(BookmarkHost)), same(hostState));
            expect(
              tester.getRect(header).top,
              closeTo(headerRect.top - nested.outerController.offset, 0.01),
            );
            expect(tester.getRect(header).height, closeTo(extent, 0.01));
            expect(
              tester.getRect(title).top,
              closeTo(titleRect.top - nested.outerController.offset, 0.01),
            );
            expect(tester.element(title), same(titleElement));
            expect(titleElement.mounted, isTrue);
            expect(tester.renderObject(title).attached, isTrue);
            expect(tester.state(editor), same(fieldState));
            final retained = tester.widget<EditableText>(editor);
            expect(retained.controller, same(field.controller));
            expect(retained.focusNode, same(field.focusNode));
            expect(retained.focusNode.hasFocus, isTrue);
            expect(retained.controller.text, 'An unsaved collection title');
            expect(retained.controller.selection, selection);
          }

          // Approach the actual header edge through wheel input, not a jump
          // on either position. Both rapid notches then share one live queue.
          for (final delta in _wheelPackets(extent - 40)) {
            await _expectSmoothedWheel(
              tester,
              nested,
              delta,
              expectFrame: expectRetainedFrame,
            );
          }
          expect(nested.innerController.offset, closeTo(0, 1e-10));
          final before = _distance(nested);
          await _wheel(tester, 80);
          expect(_distance(nested), before);
          _expectWheelOffsets(nested, before);
          await tester.pump(_wheelFrame);
          final intermediate = _distance(nested);
          expect(intermediate - before, inExclusiveRange(0, 80));
          _expectWheelOffsets(nested, intermediate);
          expectRetainedFrame();

          // Append before the first notch settles; do not replace its tail,
          // replay it on the body, or apply the second notch synchronously.
          await _wheel(tester, 80);
          expect(_distance(nested), intermediate);
          _expectWheelOffsets(nested, intermediate);
          await tester.pump(const Duration(milliseconds: 16));
          expect(
            _distance(nested) - before,
            inExclusiveRange(intermediate - before, 160),
          );
          _expectWheelOffsets(nested, _distance(nested));
          expectRetainedFrame();
          await tester.pumpAndSettle(_wheelFrame);
          _expectWheelOffsets(
            nested,
            before + 160,
            tolerance: _wheelConfig.wheelStopDistance,
          );
          expect(nested.innerController.offset, greaterThan(0));
          expect(
            tester.getRect(header).bottom,
            lessThanOrEqualTo(
              tester.getRect(find.byKey(_pageScroll)).top + 0.01,
            ),
          );
          expect(find.byKey(_title), findsNothing);
          expect(title.hitTestable(), findsNothing);
          expectRetainedFrame();
          final settledOuter = nested.outerController.offset;
          final settledInner = nested.innerController.offset;
          await tester.pump(const Duration(milliseconds: 500));
          expect(nested.outerController.offset, settledOuter);
          expect(nested.innerController.offset, settledInner);
          expectRetainedFrame();
          expect(model.entries.map((entry) => entry.id), idsBefore);
          expect(model.state.toJson(), stateBefore);
          expect(fixture.repository.reads, 1);
          expect(fixture.repository.renames, 0);
          expect(fixture.opened, isEmpty);
          expect(fixture.persisted, isEmpty);
          expect(tester.takeException(), isNull);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          fixture.dispose();
        }
      },
    );

    testWidgets(
        '$appearance: coverless grid retains its title draft during premium pan and reflow',
        (tester) async {
      _largeViewport(tester);
      final fixture = _Library(BookmarkViewIds.grid, withCover: false);
      final width = ValueNotifier(1280.0);
      try {
        await fixture.explorer.initialize();
        await tester.pumpWidget(
          _app(
            appearance,
            ValueListenableBuilder<double>(
              valueListenable: width,
              child: fixture.page,
              builder: (_, value, child) => Align(
                alignment: Alignment.topLeft,
                child: SizedBox(width: value, child: child),
              ),
            ),
            premium: true,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(ViewCoverImage), findsNothing);
        expect(find.byType(BookmarkGridView), findsOneWidget);
        expect(find.byType(BookmarkCard), findsNWidgets(96));
        fixture.explorer.beginRename(fixture.root.id);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(_editor),
          'An unsaved collection title',
        );
        final field = tester.widget<EditableText>(find.byKey(_editor));
        const selection = TextSelection(baseOffset: 3, extentOffset: 10);
        field.controller.selection = selection;
        await tester.pump();
        final fieldState = tester.state(find.byKey(_editor));
        final model = _model(tester);
        final card = find.byKey(ValueKey(model.entries.first.id));
        final cardState = tester.state(card);
        final nested = _nested(tester);
        final body = _body(tester);
        // The draft must survive even after the whole header is offstage.
        final title = find.byKey(_title, skipOffstage: false);
        final editor = find.byKey(_editor, skipOffstage: false);
        final titleElement = tester.element(title);
        final titleTop = tester.getTopLeft(title).dy;
        final point = _bodyPoint(tester);
        final pan =
            await tester.createGesture(kind: PointerDeviceKind.trackpad);
        await pan.panZoomStart(point);
        var previous = _distance(nested);
        for (var frame = 1; frame <= 60; frame++) {
          await pan.panZoomUpdate(
            point,
            pan: Offset(0, -24.0 * frame),
            timeStamp: Duration(milliseconds: frame * 16),
          );
          await tester.pump(const Duration(milliseconds: 16));
          final distance = _distance(nested);
          // The inherited desktop physics may scale the body, but neither
          // position may replay distance already consumed by the other.
          expect(distance - previous, inInclusiveRange(-0.01, 24.01));
          previous = distance;
          expect(nested.innerController.positions, hasLength(1));
          if (nested.innerController.offset > 0) {
            expect(
              nested.outerController.offset,
              closeTo(nested.outerController.position.maxScrollExtent, 0.01),
            );
          }
        }
        await pan.panZoomEnd(timeStamp: const Duration(milliseconds: 1100));
        await tester.pumpAndSettle();
        expect(nested.outerController.offset, greaterThan(0));
        expect(nested.innerController.offset, greaterThan(100));
        expect(
          tester.getTopLeft(title).dy,
          lessThan(titleTop),
        );
        expect(
          tester.getTopLeft(title).dy,
          closeTo(titleTop - nested.outerController.offset, 0.01),
        );
        expect(find.byKey(_title), findsNothing);
        expect(title.hitTestable(), findsNothing);
        final bodyOffset = nested.innerController.offset;
        width.value = 1120;
        fixture.explorer.updateView(
          ViewPB()
            ..mergeFromMessage(fixture.root)
            ..name = 'The stored title changed elsewhere',
        );
        await tester.pumpAndSettle();
        expect(_nested(tester), same(nested));
        expect(_body(tester), same(body));
        expect(_model(tester), same(model));
        expect(tester.state(card), same(cardState));
        expect(tester.element(title), same(titleElement));
        expect(tester.renderObject(title).attached, isTrue);
        expect(tester.state(editor), same(fieldState));
        final retained = tester.widget<EditableText>(editor);
        expect(retained.controller, same(field.controller));
        expect(retained.focusNode, same(field.focusNode));
        expect(retained.focusNode.hasFocus, isTrue);
        expect(retained.controller.text, 'An unsaved collection title');
        expect(retained.controller.selection, selection);
        expect(nested.innerController.offset, closeTo(bodyOffset, 0.01));
        expect(fixture.repository.renames, 0);
        expect(fixture.persisted, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        fixture.dispose();
        width.dispose();
      }
    });

    testWidgets('$appearance: bookmark tools reveal without removing features',
        (tester) async {
      _largeViewport(tester);
      final semantics = tester.ensureSemantics();
      final fixture = _Library(BookmarkViewIds.grid, withCover: false);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      try {
        await fixture.explorer.initialize();
        await tester.pumpWidget(_app(appearance, fixture.page));
        await tester.pumpAndSettle();
        final tools = find.descendant(
          of: find.byType(BookmarkToolbar),
          matching: find.byType(PreviewToolbar),
        );
        final buttons = find.descendant(
          of: tools,
          matching: find.byType(TextButton),
        );
        final body = _body(tester);
        final before = tester.getRect(_mainArea);
        expect(buttons, findsNWidgets(5));
        expect(buttons.hitTestable(), findsNWidgets(5));
        expect(find.text('96 links').hitTestable(), findsOneWidget);
        await mouse.moveTo(tester.getCenter(find.byType(BookmarkToolbar)));
        await tester.pumpAndSettle();
        expect(buttons.hitTestable(), findsNWidgets(5));
        for (final name in [
          'filter',
          'arrows-vertical',
          'sliders',
          'refresh',
          'link-add',
        ]) {
          expect(
            find.descendant(
              of: tools,
              matching: find.byWidgetPredicate(
                (widget) => widget is WorkspaceGlyph && widget.name == name,
              ),
            ),
            findsOneWidget,
          );
        }
        final sortLabel = LocaleKeys.collections_bookmark_sort.tr();
        final sort = find.descendant(
          of: find.descendant(of: tools, matching: find.byTooltip(sortLabel)),
          matching: find.byType(TextButton),
        );
        expect(sort.hitTestable(), findsOneWidget);
        final sortSemantics = tester.getSemantics(sort).getSemanticsData();
        expect(sortSemantics.label, sortLabel);
        expect(sortSemantics.hasFlag(ui.SemanticsFlag.isButton), isTrue);
        expect(sortSemantics.hasFlag(ui.SemanticsFlag.isEnabled), isTrue);
        expect(sortSemantics.hasAction(ui.SemanticsAction.tap), isTrue);
        await tester.tap(sort);
        await tester.pumpAndSettle();
        await mouse.moveTo(Offset.zero);
        await tester.pumpAndSettle();
        final opacity = tester.widget<AnimatedOpacity>(
          find
              .descendant(of: tools, matching: find.byType(AnimatedOpacity))
              .first,
        );
        expect(opacity.opacity, 1, reason: 'The open menu holds its toolbar.');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(_body(tester), same(body));
        expect(tester.getRect(_mainArea), before);
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox.shrink());
        fixture.dispose();
        semantics.dispose();
      }
    });
  }

  for (final mode in _modes) {
    testWidgets('$mode standalone keeps its owned controller', (tester) async {
      _largeViewport(tester);
      final fixture = _Library(mode);
      final unrelatedPrimary = ScrollController();
      try {
        await fixture.explorer.initialize();
        final definition = fixture.original.viewById(mode)!;
        await tester.pumpWidget(
          _app(
            'paper',
            PrimaryScrollController(
              controller: unrelatedPrimary,
              child: Builder(
                builder: (context) => definition.builder(
                  context,
                  fixture.contextFor(definition),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(CollectionPageScrollScope), findsNothing);
        final controller =
            tester.widget<BookmarkScrollArea>(_mainArea).controller;
        expect(controller, isNot(same(unrelatedPrimary)));
        expect(controller.positions, hasLength(1));
        expect(unrelatedPrimary.hasClients, isFalse);
        final body = _body(tester);
        await tester.drag(_mainArea, const Offset(0, -160));
        await tester.pumpAndSettle();
        expect(controller.offset, greaterThan(0));
        expect(_body(tester), same(body));
        expect(unrelatedPrimary.hasClients, isFalse);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        fixture.dispose();
        unrelatedPrimary.dispose();
      }
    });
  }

  testWidgets('a shelf row scrolls sideways without moving the collection page',
      (tester) async {
    _largeViewport(tester);
    final fixture = _Library(BookmarkViewIds.shelf, withCover: false);
    try {
      await fixture.explorer.initialize();
      await tester.pumpWidget(_app('paper', fixture.page));
      await tester.pumpAndSettle();
      final nested = _nested(tester);
      final row = find
          .byWidgetPredicate(
            (widget) =>
                widget is ListView && widget.scrollDirection == Axis.horizontal,
          )
          .first;
      final rowController = tester.widget<ListView>(row).controller!;
      final titleTop = tester.getTopLeft(find.byKey(_title)).dy;
      expect(rowController, isNot(same(nested.innerController)));
      expect(rowController.position.maxScrollExtent, greaterThan(0));
      final rowRect = tester.getRect(row).intersect(
            tester.getRect(find.byKey(_pageScroll)),
          );
      await tester.dragFrom(rowRect.center, const Offset(-220, 0));
      await tester.pumpAndSettle();
      expect(rowController.offset, greaterThan(0));
      expect(nested.innerController.positions, hasLength(1));
      expect(nested.innerController.offset, 0);
      expect(nested.outerController.offset, 0);
      expect(tester.getTopLeft(find.byKey(_title)).dy, titleTop);
      expect(fixture.opened, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    }
  });

  testWidgets(
      'an empty result detaches without disposing the borrowed controller',
      (tester) async {
    _largeViewport(tester);
    final fixture = _Library(BookmarkViewIds.grid);
    try {
      await fixture.explorer.initialize();
      await tester.pumpWidget(_app('paper', fixture.page));
      await tester.pumpAndSettle();
      final nested = _nested(tester);
      final controller = nested.innerController;
      final model = _model(tester);
      final host = tester.state(find.byType(BookmarkHost));
      model.setQuery('there is no bookmark with this title');
      await tester.pumpAndSettle();
      expect(find.byType(BookmarkEmptyState), findsOneWidget);
      expect(controller.positions, hasLength(1));
      model.setQuery('');
      await tester.pumpAndSettle();
      expect(_nested(tester).innerController, same(controller));
      expect(controller.positions, hasLength(1));
      expect(_model(tester), same(model));
      expect(tester.state(find.byType(BookmarkHost)), same(host));
      await tester.dragFrom(_bodyPoint(tester), const Offset(0, -120));
      await tester.pumpAndSettle();
      expect(nested.outerController.offset, greaterThan(0));
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.dispose();
    }
  });
}

Finder get _mainArea => find.byType(BookmarkScrollArea).first;

NestedScrollViewState _nested(WidgetTester tester) =>
    tester.state<NestedScrollViewState>(find.byKey(_pageScroll));

ScrollableState _body(WidgetTester tester) => tester.state<ScrollableState>(
      find.descendant(of: _mainArea, matching: find.byType(Scrollable)).first,
    );

BookmarkController _model(WidgetTester tester) =>
    tester.widget<BookmarkScaffold>(find.byType(BookmarkScaffold)).controller;

double _distance(NestedScrollViewState nested) =>
    nested.outerController.offset + nested.innerController.offset;

Iterable<double> _wheelPackets(double distance) sync* {
  final count = (distance.abs() / _wheelConfig.maxWheelDelta).ceil();
  for (var index = 0; index < count; index++) {
    yield distance / count;
  }
}

Future<void> _wheel(WidgetTester tester, double delta) =>
    tester.sendEventToBinding(
      PointerScrollEvent(
        position: _bodyPoint(tester),
        scrollDelta: Offset(0, delta),
      ),
    );

void _expectWheelOffsets(
  NestedScrollViewState nested,
  double distance, {
  double tolerance = 0.01,
}) {
  final extent = nested.outerController.position.maxScrollExtent;
  expect(_distance(nested), closeTo(distance, tolerance));
  expect(
    nested.outerController.offset,
    closeTo(math.min(extent, distance), tolerance),
  );
  expect(
    nested.innerController.offset,
    closeTo(math.max(0.0, distance - extent), tolerance),
  );
  expect(nested.outerController.position.outOfRange, isFalse);
  expect(nested.innerController.position.outOfRange, isFalse);
}

Future<void> _expectSmoothedWheel(
  WidgetTester tester,
  NestedScrollViewState nested,
  double delta, {
  required VoidCallback expectFrame,
}) async {
  expect(delta.abs(), lessThanOrEqualTo(_wheelConfig.maxWheelDelta));
  final before = _distance(nested);
  final outerBefore = nested.outerController.offset;
  final innerBefore = nested.innerController.offset;
  final expected = math.max(0.0, before + delta);
  await _wheel(tester, delta);
  // The first 80px notch must leave both offsets exactly zero here. Later
  // notches likewise enqueue, without bypassing the shared outer coordinator.
  expect(_distance(nested), before);
  expect(nested.outerController.offset, outerBefore);
  expect(nested.innerController.offset, innerBefore);
  expectFrame();
  var previous = before;
  for (final duration in [_wheelFrame, const Duration(milliseconds: 16)]) {
    await tester.pump(duration);
    final distance = _distance(nested);
    if (expected == before) {
      expect(distance, before);
    } else if (before + delta < 0) {
      // A boundary may consume less than a notch, including on its first frame.
      expect(distance, inInclusiveRange(0, previous));
    } else {
      expect(
        distance,
        inExclusiveRange(
          math.min(before, expected),
          math.max(before, expected),
        ),
      );
      expect((distance - previous) * delta.sign, greaterThan(0));
    }
    _expectWheelOffsets(nested, distance);
    expectFrame();
    previous = distance;
  }
  await tester.pumpAndSettle(_wheelFrame);
  // Each settled queue may discard only wheelStopDistance (0.1px). Measure
  // from its actual start so that residuals from earlier queues cannot accrue
  // into a false failure, while still checking this entire delta exactly once.
  _expectWheelOffsets(
    nested,
    expected,
    tolerance: _wheelConfig.wheelStopDistance,
  );
  expectFrame();
  final settledOuter = nested.outerController.offset;
  final settledInner = nested.innerController.offset;
  await tester.pump(const Duration(milliseconds: 500));
  expect(nested.outerController.offset, settledOuter);
  expect(nested.innerController.offset, settledInner);
  expect(nested.outerController.position.isScrollingNotifier.value, isFalse);
  expect(nested.innerController.position.isScrollingNotifier.value, isFalse);
  expectFrame();
}

Offset _bodyPoint(WidgetTester tester) {
  final visible = tester.getRect(_mainArea).intersect(
        tester.getRect(find.byKey(_pageScroll)),
      );
  expect(visible.height, greaterThan(40));
  return Offset(visible.left + 12, visible.bottom - 24);
}

void _largeViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1600, 1200);
  addTearDown(tester.view.reset);
}

Widget _app(String appearance, Widget child, {bool premium = false}) =>
    vividIconTestApp(
      appearance,
      PremiumScrollScope(
        enabled: premium,
        child: SizedBox(width: 1280, height: 1000, child: child),
      ),
    );

class _Library {
  _Library(String mode, {bool withCover = true}) {
    root = ViewPB(
      id: 'collection-scroll-$mode',
      name: 'Saved reading',
      layout: ViewLayoutPB.Document,
      extra: CollectionMetadata(
        kind: CollectionKind.bookmark,
        activeViewId: mode,
      ).mergeIntoExtra(const WorkspaceItemMetadata.folder().mergeIntoExtra('')),
    );
    if (withCover) {
      root.extra = ViewCoverCodec.mergeCover(
        root.extra,
        const PageStyleCover(
          type: PageStyleCoverImageType.pureColor,
          value: '#D9C7A4',
        ),
      );
    }
    repository = _Repository(root.id);
    explorer = WorkspaceExplorerController(
      root: root,
      repository: repository,
      listenForUpdates: false,
    );
    original = CollectionRegistry.typeFor(CollectionKind.bookmark);
    // Replace ONLY native metadata persistence. Every registered builder still
    // creates its real BookmarkHost, controller, toolbar, cards and scrollables;
    // the actual CollectionPage creates the header and nested coordinator.
    CollectionRegistry.register(
      original.withViews([
        for (final definition in original.views)
          CollectionViewDefinition(
            id: definition.id,
            labelKey: definition.labelKey,
            icon: definition.icon,
            isAvailable: definition.isAvailable,
            builder: (context, collection) => definition.builder(
              context,
              CollectionViewContext(
                collectionView: collection.collectionView,
                metadata: collection.metadata,
                definition: collection.definition,
                explorer: collection.explorer,
                onOpen: collection.onOpen,
                onOpenView: collection.onOpenView,
                onStateChanged: _persist,
              ),
            ),
          ),
      ]),
    );
  }

  late final ViewPB root;
  late final _Repository repository;
  late final WorkspaceExplorerController explorer;
  late final CollectionTypeDefinition original;
  final opened = <ViewPB>[];
  final persisted = <Map<String, dynamic>>[];

  Widget get page => CollectionPage(
        view: root,
        controller: explorer,
        shellOwnsBreadcrumbs: true,
        onOpen: opened.add,
      );

  CollectionViewContext contextFor(CollectionViewDefinition definition) =>
      CollectionViewContext(
        collectionView: root,
        metadata: root.collection!,
        definition: definition,
        explorer: explorer,
        onOpen: opened.add,
        onOpenView: (_) {},
        onStateChanged: _persist,
      );

  void _persist(String key, Map<String, dynamic> state) => persisted.add(state);

  void dispose() {
    CollectionRegistry.register(original);
    explorer.dispose();
  }
}

class _Repository implements WorkspaceItemRepository {
  _Repository(this.rootId);

  final String rootId;
  int reads = 0;
  int renames = 0;

  @override
  Future<FlowyResult<List<ViewPB>, FlowyError>> getChildren(String id) async {
    reads++;
    return FlowyResult.success([
      for (var index = 0; index < 96; index++)
        ViewPB(
          id: 'saved-link-$index',
          parentViewId: rootId,
          name: 'Saved link $index',
          layout: ViewLayoutPB.Document,
          extra: BookmarkMetadata(
            url: 'https://site-${index % 12}.example.test/article-$index',
            title: 'Saved link $index',
            description: 'Already indexed; no metadata or image network reads.',
            addedAt: DateTime(2026, 9).add(Duration(hours: index)),
          ).mergeIntoExtra(
            const WorkspaceItemMetadata.file(
              contentKind: WorkspaceFileContentKind.binary,
              mimeType: bookmarkMimeType,
            ).mergeIntoExtra(''),
          ),
        ),
    ]);
  }

  @override
  Future<FlowyResult<ViewPB, FlowyError>> rename({
    required String viewId,
    required String name,
  }) async {
    renames++;
    return FlowyResult.failure(
      FlowyError(msg: 'A draft must not be submitted.'),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
