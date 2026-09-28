import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/features/share_tab/data/models/models.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/recent_icons.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/shared/page_icon.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_decoration_actions.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../unit_test/shared/page_icon_test_support.dart';
import 'vivid_icon_test_support.dart';

final _frame = find.byKey(const ValueKey('page-icon-frame'));
final _grip = find.byKey(const ValueKey('page-icon-grip'));
final _resize = find.byKey(const ValueKey('page-icon-resize'));

void main() {
  setUpAll(() async {
    RecentIcons.enable = false;
    await prepareVividIconTestAssets();
  });
  setUp(resetVividIconTestPacks);
  tearDownAll(() => RecentIcons.enable = true);

  for (final appearance in vividIconTestAppearances) {
    testWidgets('$appearance: real repeated drags save, reopen and cancel',
        (tester) async {
      final fixture = _Fixture(appearance: appearance);
      try {
        await fixture.mount(tester);
        final artworkState = tester.state(find.byType(_RetainedArtwork));
        final titleState = tester.state(find.byType(EditableText));
        await tester.enterText(find.byType(TextField), 'Unsubmitted title');
        fixture.title.selection =
            const TextSelection(baseOffset: 2, extentOffset: 8);
        final draft = fixture.title.value;
        final iconBytes = fixture.view.icon.writeToBuffer();

        for (final delta in [61.375, -28.125, 44.25]) {
          final start = tester.getSize(_frame).width;
          final writes = fixture.backend.writes.length;
          final (gesture, origin) = await _startDrag(tester);
          // Each movement is followed by layout. A local-position accumulator
          // drifts here as the bottom-right grip moves along with the artwork.
          for (final part in [0.4, 0.7, 1.0]) {
            await gesture.moveTo(origin + Offset(delta * part, delta * part));
            await tester.pump();
            expect(tester.getSize(_frame).width,
                closeTo(start + delta * part, 0.01));
            expect(fixture.backend.writes, hasLength(writes));
            _expectAspectAndBounds(tester);
          }
          await gesture.up();
          await gesture.removePointer();
          await tester.pumpAndSettle();
          expect(fixture.backend.writes, hasLength(writes + 1));
          expect(IconSize.decode(fixture.view.extra),
              closeTo(start + delta, 0.01));
          expect(
              tester.state(find.byType(_RetainedArtwork)), same(artworkState));
          expect(tester.state(find.byType(EditableText)), same(titleState));
          expect(fixture.title.value, draft);
          expect(fixture.view.icon.writeToBuffer(), iconBytes);
        }

        final saved = IconSize.decode(fixture.view.extra)!;
        final writes = fixture.backend.writes.length;
        fixture.rebuild(() => fixture.showIcon = false);
        await tester.pump();
        fixture.rebuild(() {
          fixture.view = ViewPB.fromBuffer(
            fixture.backend.views[fixture.view.id]!.writeToBuffer(),
          );
          fixture.showIcon = true;
        });
        await tester.pumpAndSettle();
        expect(tester.getSize(_frame).width, closeTo(saved, 0.01));
        expect(tester.state(find.byType(EditableText)), same(titleState));
        expect(fixture.title.value, draft);
        final (gesture, origin) = await _startDrag(tester);
        await gesture.moveTo(origin + const Offset(35, 35));
        await tester.pump();
        expect(tester.getSize(_frame).width, closeTo(saved + 35, 0.01));
        await gesture.cancel();
        await gesture.removePointer();
        await tester.pumpAndSettle();
        expect(tester.getSize(_frame).width, closeTo(saved, 0.01));
        expect(fixture.backend.writes, hasLength(writes));
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    });
  }

  testWidgets(
      'keyboard reveal, continuous steps, reset and Escape cancellation',
      (tester) async {
    final fixture = _Fixture();
    final semantics = tester.ensureSemantics();
    try {
      await fixture.mount(tester);
      await _key(tester, LogicalKeyboardKey.tab, PhysicalKeyboardKey.tab);
      await _key(tester, LogicalKeyboardKey.tab, PhysicalKeyboardKey.tab);
      final data = tester.getSemantics(_resize).getSemanticsData();
      expect(data.label, 'Page icon size');
      expect(data.value, '66.0 pixels');
      expect(data.increasedValue, '67.0 pixels');
      expect(data.decreasedValue, '65.0 pixels');
      expect(data.hasFlag(ui.SemanticsFlag.isFocused), isTrue);
      expect(data.hasFlag(ui.SemanticsFlag.isSlider), isTrue);
      expect(data.hasAction(ui.SemanticsAction.increase), isTrue);
      expect(data.hasAction(ui.SemanticsAction.decrease), isTrue);
      expect(data.customSemanticsActionIds, isNotEmpty);
      expect(_grip.hitTestable(), findsOneWidget);

      await _key(tester, LogicalKeyboardKey.arrowRight,
          PhysicalKeyboardKey.arrowRight);
      expect(IconSize.decode(fixture.view.extra), 67);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft,
          physicalKey: PhysicalKeyboardKey.shiftLeft);
      await _key(
          tester, LogicalKeyboardKey.arrowUp, PhysicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft,
          physicalKey: PhysicalKeyboardKey.shiftLeft);
      expect(IconSize.decode(fixture.view.extra), 77);
      await _key(tester, LogicalKeyboardKey.home, PhysicalKeyboardKey.home);
      expect(IconSize.decode(fixture.view.extra), isNull);
      expect(jsonDecode(fixture.view.extra), isNot(contains(IconSize.key)));
      expect(tester.getSize(_frame), const Size.square(66));

      final writes = fixture.backend.writes.length;
      final (gesture, origin) = await _startDrag(tester);
      await gesture.moveTo(origin + const Offset(40, 40));
      await tester.pump();
      expect(tester.getSize(_frame).width, closeTo(106, 0.01));
      await _key(tester, LogicalKeyboardKey.escape, PhysicalKeyboardKey.escape);
      await gesture.up();
      await gesture.removePointer();
      await tester.pumpAndSettle();
      expect(tester.getSize(_frame), const Size.square(66));
      expect(fixture.backend.writes, hasLength(writes));
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
      semantics.dispose();
    }
  });

  testWidgets('tiny grip movements never open the picker or save metadata',
      (tester) async {
    final fixture = _Fixture();
    try {
      await fixture.mount(tester);
      for (final delta in [Offset.zero, const Offset(0.25, 0.25)]) {
        final (gesture, origin) = await _startDrag(tester);
        await gesture.moveTo(origin + delta);
        await tester.pump();
        await gesture.up();
        await gesture.removePointer();
        await tester.pumpAndSettle();
        expect(find.byType(FlowyIconEmojiPicker), findsNothing);
        expect(tester.getSize(_frame), const Size.square(66));
        expect(fixture.backend.reads, isEmpty);
        expect(fixture.backend.writes, isEmpty);
      }
      await tester.tapAt(tester.getCenter(_frame),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(find.byType(FlowyIconEmojiPicker), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets('bounded fractional reloads retain title and a single listener',
      (tester) async {
    final fixture = _Fixture();
    try {
      await fixture.mount(tester);
      final title = tester.state(find.byType(EditableText));
      const sizes = [16.125, 319.875, 127.375, 66.0625];
      for (var i = 0; i < 24; i++) {
        final target = sizes[i % sizes.length];
        fixture.backend.publish(IconSize.applyTo(fixture.view, target));
        fixture.rebuild(() {
          fixture.view = ViewPB.fromBuffer(
            fixture.backend.views[fixture.view.id]!.writeToBuffer(),
          );
        });
        await tester.pump();
        expect(tester.getSize(_frame), Size.square(target));
        _expectAspectAndBounds(tester);
        expect(fixture.backend.activeListeners, 1);
        fixture.rebuild(() => fixture.showIcon = false);
        await tester.pump();
        expect(fixture.backend.activeListeners, 0);
        fixture.rebuild(() => fixture.showIcon = true);
        await tester.pump();
        expect(tester.getSize(_frame), Size.square(target));
        expect(tester.state(find.byType(EditableText)), same(title));
        expect(fixture.backend.activeListeners, 1);
        expect(tester.takeException(), isNull);
      }
      expect(fixture.backend.reads, isEmpty);
      expect(fixture.backend.writes, isEmpty);
    } finally {
      await fixture.dispose(tester);
    }
    expect(fixture.backend.activeListeners, 0);
  });

  testWidgets(
      'failed keyboard save stays focused and announces an explicit retry',
      (tester) async {
    final fixture = _Fixture();
    final semantics = tester.ensureSemantics();
    try {
      await fixture.mount(tester);
      await _key(tester, LogicalKeyboardKey.tab, PhysicalKeyboardKey.tab);
      await _key(tester, LogicalKeyboardKey.tab, PhysicalKeyboardKey.tab);
      fixture.backend.failWrites = true;
      await _key(tester, LogicalKeyboardKey.arrowRight,
          PhysicalKeyboardKey.arrowRight);
      final data = tester.getSemantics(_resize).getSemanticsData();
      expect(data.value,
          '66.0 pixels, Could not save icon size. Try resizing again.');
      expect(data.hasFlag(ui.SemanticsFlag.isFocused), isTrue);
      expect(data.hasFlag(ui.SemanticsFlag.isLiveRegion), isTrue);
      expect(fixture.saved, isEmpty);
      fixture.backend.failWrites = false;
      await _key(tester, LogicalKeyboardKey.arrowRight,
          PhysicalKeyboardKey.arrowRight);
      expect(fixture.saved, [67]);
      expect(fixture.backend.writes, hasLength(2));
      expect(
          tester.getSemantics(_resize).getSemanticsData().value, '67.0 pixels');
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
      semantics.dispose();
    }
  });

  testWidgets('empty IDs mount without an injected backend or resize actions',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: ResizablePageIcon(
            view: ViewPB(extra: IconSize.merge('', 97.125)),
            editable: true,
            onSizeChanged: (_) => fail('An empty view must not save'),
            builder: (size, _) => SizedBox.square(dimension: size),
          ),
        ),
      ));
      await tester.pump();
      expect(tester.getSize(_frame), const Size.square(97.125));
      expect(find.semantics.byLabel('Page icon size'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      semantics.dispose();
    }
  });

  testWidgets(
      'pane clamps are presentation-only across widths, themes and scale',
      (tester) async {
    final fixture = _Fixture(size: 320);
    try {
      await fixture.mount(tester);
      final artworkState = tester.state(find.byType(_RetainedArtwork));
      final titleState = tester.state(find.byType(EditableText));
      final bytes = fixture.view.writeToBuffer();
      for (final appearance in vividIconTestAppearances) {
        for (final width in [500.0, 240.0, 120.0, 80.0, 500.0]) {
          fixture.rebuild(() {
            fixture.appearance = appearance;
            fixture.width = width;
            fixture.textScale = 2;
            fixture.reduceMotion = true;
          });
          await tester.pumpAndSettle();
          final expected = width < 320 ? width : 320.0;
          expect(tester.getSize(_frame), Size.square(expected));
          _expectAspectAndBounds(tester);
          expect(
              tester.state(find.byType(_RetainedArtwork)), same(artworkState));
          expect(tester.state(find.byType(EditableText)), same(titleState));
          expect(fixture.view.writeToBuffer(), bytes);
          expect(fixture.backend.writes, isEmpty);
          final decoration =
              tester.widget<DecoratedBox>(_grip).decoration as BoxDecoration;
          expect(decoration.color,
              WorkspacePalette.of(tester.element(_frame)).surface);
          if (appearance == 'paper') {
            expect(decoration.color, PaperTheme.editorPreviewBackground);
          }
          expect(tester.takeException(), isNull);
        }
      }
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets('RTL diagonal and upper/lower bounds use real pane geometry',
      (tester) async {
    final fixture = _Fixture()..direction = TextDirection.rtl;
    final semantics = tester.ensureSemantics();
    try {
      await fixture.mount(tester);
      final (first, origin) = await _startDrag(tester);
      await first.moveTo(origin + const Offset(-30, 30));
      await tester.pump();
      expect(tester.getSize(_frame).width, closeTo(96, 0.01));
      await first.moveTo(origin + const Offset(-80, 80));
      await tester.pump();
      expect(tester.getSize(_frame).width, closeTo(146, 0.01));
      await first.up();
      await first.removePointer();
      await tester.pumpAndSettle();
      expect(IconSize.decode(fixture.view.extra), 146);

      final (upper, upperOrigin) = await _startDrag(tester);
      await upper.moveTo(upperOrigin + const Offset(-200, 200));
      await tester.pump();
      expect(tester.getSize(_frame), const Size.square(320));
      await upper.up();
      await upper.removePointer();
      await tester.pumpAndSettle();
      expect(IconSize.decode(fixture.view.extra), 320);
      final maximum = tester.getSemantics(_resize).getSemanticsData();
      expect(maximum.value, '320.0 pixels');
      expect(maximum.increasedValue, '320.0 pixels');
      expect(maximum.hasAction(ui.SemanticsAction.increase), isFalse);

      final (second, secondOrigin) = await _startDrag(tester);
      await second.moveTo(secondOrigin + const Offset(360, -360));
      await tester.pump();
      expect(tester.getSize(_frame), const Size.square(16));
      await second.up();
      await second.removePointer();
      await tester.pumpAndSettle();
      expect(IconSize.decode(fixture.view.extra), 16);
      final minimum = tester.getSemantics(_resize).getSemanticsData();
      expect(minimum.value, '16.0 pixels');
      expect(minimum.decreasedValue, '16.0 pixels');
      expect(minimum.hasAction(ui.SemanticsAction.decrease), isFalse);
      // Even when the grip is revealed at the minimum, the center still opens
      // the existing picker rather than being swallowed by the resize target.
      await tester.tapAt(tester.getCenter(_frame),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(find.byType(FlowyIconEmojiPicker), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
      semantics.dispose();
    }
  });

  testWidgets('a collapsing local allocation cancels even on pointer-up',
      (tester) async {
    final fixture = _Fixture();
    try {
      await fixture.mount(tester);
      final (gesture, origin) = await _startDrag(tester);
      await gesture.moveTo(origin + const Offset(30, 30));
      await tester.pump();
      expect(tester.getSize(_frame), const Size.square(96));
      fixture.rebuild(() => fixture.maxIconSize = 8);
      await tester.pump();
      await gesture.up();
      await gesture.removePointer();
      await tester.pumpAndSettle();
      expect(fixture.backend.writes, isEmpty);
      fixture.rebuild(() => fixture.maxIconSize = IconSize.maximum);
      await tester.pump();
      expect(tester.getSize(_frame), const Size.square(66));
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
    }
  });

  for (final invalidation in ['readonly', 'lock', 'delete', 'rebind']) {
    testWidgets('$invalidation cancels an accepted drag without a save',
        (tester) async {
      final fixture = _Fixture();
      try {
        await fixture.mount(tester);
        final (gesture, origin) = await _startDrag(tester);
        await gesture.moveTo(origin + const Offset(30, 30));
        await tester.pump();
        expect(tester.getSize(_frame).width, closeTo(96, 0.01));
        switch (invalidation) {
          case 'readonly':
            fixture.rebuild(() => fixture.editable = false);
          case 'lock':
            fixture.rebuild(() {
              fixture.view = ViewPB.fromBuffer(fixture.view.writeToBuffer())
                ..isLocked = true;
            });
          case 'delete':
            fixture.backend.delete(fixture.view.id);
          case 'rebind':
            fixture.rebuild(() {
              fixture.binding = Object();
              fixture.view = ViewPB(id: '${fixture.view.id}-replacement');
            });
        }
        await tester.pump();
        await gesture.moveTo(origin + const Offset(60, 60));
        await tester.pump();
        await gesture.up();
        await gesture.removePointer();
        await tester.pumpAndSettle();
        expect(fixture.backend.writes, isEmpty);
        expect(fixture.saved, isEmpty);
        expect(tester.getSize(_frame), const Size.square(66));
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    });
  }

  testWidgets('access loading/readonly gates and revoke/grant invalidate read',
      (tester) async {
    final fixture = _Fixture();
    final access = _Access(PageAccessLevelState.initial(fixture.view));
    fixture.access = access;
    final semantics = tester.ensureSemantics();
    try {
      await fixture.mount(tester);
      expect(find.semantics.byLabel('Page icon size'), findsNothing);
      await tester.tapAt(tester.getCenter(_frame),
          kind: PointerDeviceKind.mouse);
      await tester.pump();
      expect(find.byType(FlowyIconEmojiPicker), findsNothing);
      access.change(access.state.copyWith(isLoadingLockStatus: false));
      await tester.pump();
      expect(find.semantics.byLabel('Page icon size'), findsNothing);
      access.change(
          access.state.copyWith(accessLevel: ShareAccessLevel.fullAccess));
      await tester.pump();
      expect(find.semantics.byLabel('Page icon size'), findsOneWidget);
      final barrier = Completer<void>();
      fixture.backend.readBarrier = barrier;
      final (gesture, origin) = await _startDrag(tester);
      await gesture.moveTo(origin + const Offset(40, 40));
      await tester.pump();
      await gesture.up();
      await gesture.removePointer();
      await tester.pump();
      expect(fixture.backend.reads, hasLength(1));
      // Revoke and grant before another frame; old work must stay cancelled.
      access.change(
          access.state.copyWith(accessLevel: ShareAccessLevel.readOnly));
      access.change(
          access.state.copyWith(accessLevel: ShareAccessLevel.fullAccess));
      barrier.complete();
      await tester.pumpAndSettle();
      expect(fixture.backend.writes, isEmpty);
      expect(fixture.saved, isEmpty);
      expect(tester.getSize(_frame), const Size.square(66));
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
      semantics.dispose();
      await access.close();
    }
  });

  testWidgets('repeated drag releases serialize even before the first ACK',
      (tester) async {
    final fixture = _Fixture();
    try {
      await fixture.mount(tester);
      final barrier = Completer<void>();
      fixture.backend.writeBarrier = barrier;
      final (first, firstOrigin) = await _startDrag(tester);
      await first.moveTo(firstOrigin + const Offset(30, 30));
      await tester.pump();
      await first.up();
      await first.removePointer();
      await tester.pump();
      expect(fixture.backend.writes, hasLength(1));
      final (second, secondOrigin) = await _startDrag(tester);
      await second.moveTo(secondOrigin + const Offset(40, 40));
      await tester.pump();
      await second.up();
      await second.removePointer();
      await tester.pump();
      expect(fixture.backend.writes, hasLength(1));
      expect(tester.getSize(_frame).width, closeTo(136, 0.01));
      barrier.complete();
      await tester.pumpAndSettle();
      expect(fixture.backend.maxActiveWrites, 1);
      expect(
          fixture.backend.writes.map((write) => IconSize.decode(write.extra)),
          [96, 136]);
      expect(IconSize.decode(fixture.view.extra), 136);
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets('resizing retains real artwork, full picker and selected color',
      (tester) async {
    final fixture = _Fixture()..realArtwork = true;
    try {
      await fixture.mount(tester);
      await settleVividIconPictures(tester);
      final artworkState = tester.state(find.byType(RawEmojiIconWidget));
      final pickerState = tester.state(find.byType(ViewIconPicker));
      final oldIcon = fixture.view.icon.writeToBuffer();
      final (gesture, origin) = await _startDrag(tester);
      await gesture.moveTo(origin + const Offset(30, 30));
      await tester.pump();
      await gesture.moveTo(origin + const Offset(63.25, 63.25));
      await tester.pump();
      await gesture.up();
      await gesture.removePointer();
      await tester.pumpAndSettle();
      expect(fixture.view.icon.writeToBuffer(), oldIcon);
      expect(tester.state(find.byType(RawEmojiIconWidget)), same(artworkState));
      expect(tester.state(find.byType(ViewIconPicker)), same(pickerState));
      expect(
          tester.getSize(find.byType(ViewIconPicker)), tester.getSize(_frame));
      await tester.tapAt(tester.getCenter(_frame),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      final picker = tester.widget<FlowyIconEmojiPicker>(
        find.byType(FlowyIconEmojiPicker),
      );
      expect(picker.tabs, kAllIconPickerTabs);
      expect(picker.documentId, fixture.view.id);
      expect(picker.initialType, PickerTabType.icon);
      final chosen =
          IconsData(vividIconTestGroup, 'leaf', '4278255360').toEmojiIconData();
      picker.onSelectedEmoji!(chosen.toSelectedResult());
      await tester.pumpAndSettle();
      expect(fixture.iconWrites.single.toViewIcon(), chosen.toViewIcon());
      expect(fixture.view.icon, chosen.toViewIcon());
      expect(IconSize.decode(fixture.view.extra), 129.25);
      expect(fixture.backend.writes, hasLength(1));
      expect(find.byType(FlowyIconEmojiPicker), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
    }
  });
}

int _viewNumber = 0;

Future<(TestGesture, Offset)> _startDrag(WidgetTester tester) async {
  final gesture = await tester.createGesture(
    kind: PointerDeviceKind.mouse,
  );
  // Mouse gestures share device 1, even with different pointer IDs. A prior
  // tapAt leaves that device present: hover it, do not add it a second time.
  await gesture.moveTo(Offset.zero);
  await gesture.moveTo(tester.getCenter(_frame));
  await tester.pump();
  final origin = tester.getCenter(_grip);
  await gesture.down(origin);
  await tester.pump();
  return (gesture, origin);
}

Future<void> _key(
  WidgetTester tester,
  LogicalKeyboardKey logical,
  PhysicalKeyboardKey physical,
) async {
  await tester.sendKeyEvent(logical, physicalKey: physical);
  await tester.pumpAndSettle();
}

void _expectAspectAndBounds(WidgetTester tester) {
  final box = tester.renderObject<RenderBox>(
    find.byKey(const ValueKey('retained-icon-artwork')),
  );
  final painted = MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );
  expect(painted.width / painted.height, closeTo(2, 0.001));
  final frame = tester.getRect(_frame).inflate(0.01);
  expect(frame.contains(painted.topLeft), isTrue);
  expect(frame.contains(painted.bottomRight), isTrue);
}

class _Fixture {
  _Fixture({this.appearance = 'paper', double? size}) {
    view = ViewPB(
      id: 'page-icon-widget-${_viewNumber++}',
      name: 'A page',
      extra: IconSize.merge('{"unrelated":{"preserved":true}}', size),
      icon: IconsData(vividIconTestGroup, 'rocket', '4278255360')
          .toEmojiIconData()
          .toViewIcon(),
    );
    backend = PageIconMemoryBackend([view]);
  }

  late ViewPB view;
  late PageIconMemoryBackend backend;
  late StateSetter rebuild;
  final title = TextEditingController(text: 'A page');
  final saved = <double?>[];
  final iconWrites = <EmojiIconData>[];
  Object binding = Object();
  String appearance;
  double width = 420;
  double maxIconSize = IconSize.maximum;
  double textScale = 1;
  bool reduceMotion = false;
  bool editable = true;
  bool showIcon = true;
  bool realArtwork = false;
  TextDirection direction = TextDirection.ltr;
  _Access? access;

  Future<void> mount(WidgetTester tester) async {
    final content = StatefulBuilder(
      builder: (context, setState) {
        rebuild = setState;
        return Theme(
          data: vividIconTestTheme(appearance),
          child: Directionality(
            textDirection: direction,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: reduceMotion,
                textScaler: TextScaler.linear(textScale),
              ),
              child: SizedBox(
                width: width,
                height: 500,
                child: SingleChildScrollView(
                  child: WorkspacePageIdentity(
                    icon: showIcon
                        ? ResizablePageIcon(
                            key: const ValueKey('retained-page-icon'),
                            view: view,
                            binding: binding,
                            editable: editable,
                            canResize: () => editable,
                            defaultSize: 66,
                            maxSize: maxIconSize,
                            backend: backend,
                            onSizeChanged: (size) => rebuild(() {
                              saved.add(size);
                              view = IconSize.applyTo(view, size);
                            }),
                            builder: (size, _) => ViewIconPicker(
                              view: view,
                              updateIcon: _writeIcon,
                              onViewChanged: (updated) => rebuild(() {
                                view = ViewPB.fromBuffer(view.writeToBuffer())
                                  ..icon = updated.icon;
                              }),
                              child: PageIconArtwork(
                                size: size,
                                child: SizedBox.square(
                                  dimension: 66,
                                  child: Center(
                                    child: realArtwork
                                        ? RawEmojiIconWidget(
                                            emoji: view.icon.toEmojiIconData(),
                                            emojiSize: 56,
                                            opticalRole: IconOpticalRole.header,
                                          )
                                        : const _RetainedArtwork(),
                                  ),
                                ),
                              ),
                            ),
                          )
                        : null,
                    title: TextField(
                      key: const ValueKey('retained-title-draft'),
                      controller: title,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    await tester.pumpWidget(
      vividIconTestApp(
        appearance,
        access == null
            ? content
            : BlocProvider<PageAccessLevelBloc>.value(
                value: access!,
                child: content,
              ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<FlowyResult<void, FlowyError>> _writeIcon({
    required ViewPB view,
    required EmojiIconData viewIcon,
  }) async {
    iconWrites.add(viewIcon);
    backend.views[view.id] =
        ViewPB.fromBuffer(backend.views[view.id]!.writeToBuffer())
          ..icon = viewIcon.toViewIcon();
    return FlowyResult.success(null);
  }

  Future<void> dispose(WidgetTester tester) async {
    backend.releasePending();
    await disposeVividIconPicker(tester);
    title.dispose();
  }
}

class _RetainedArtwork extends StatefulWidget {
  const _RetainedArtwork();

  @override
  State<_RetainedArtwork> createState() => _RetainedArtworkState();
}

class _RetainedArtworkState extends State<_RetainedArtwork> {
  @override
  Widget build(BuildContext context) => const SizedBox(
        key: ValueKey('retained-icon-artwork'),
        width: 40,
        height: 20,
        child: ColoredBox(color: Color(0xFF278268)),
      );
}

/// A synchronous access source, with no Rust listener or real-zone Bloc work.
class _Access implements PageAccessLevelBloc {
  _Access(this.state);

  @override
  PageAccessLevelState state;
  final _states = StreamController<PageAccessLevelState>.broadcast(sync: true);

  @override
  ViewPB get view => state.view;

  @override
  Stream<PageAccessLevelState> get stream => _states.stream;

  void change(PageAccessLevelState next) {
    state = next;
    _states.add(next);
  }

  @override
  Future<void> close() => _states.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
