import 'dart:async';
import 'dart:ui' show SemanticsAction, SemanticsFlag;

import 'package:appflowy/extensions/dart/built_in/astrology/astrology_model.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_place_dropdown.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_style.dart';
import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/shared/context_menu/app_menu_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/shared/scrolling/scroll_activation_region.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/link.dart' show LinkDelegate;
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

const _copyright = 'https://www.openstreetmap.org/copyright';
const _longPlace = AstrologyPlace(
  name: 'Springfield, Sangamon County, Illinois, United States of America',
  latitude: 39.7817,
  longitude: -89.6501,
  timeZone: 'America/Chicago',
);

void main() {
  _case('closed means no popup, message, spinner, list or attribution',
      (tester, h, launcher) async {
    h
      ..open = false
      ..busy = true
      ..message = 'Pending search';
    await h.mount(tester);
    expect(_field, findsOneWidget);
    expect(find.text('Birth place label'), findsOneWidget);
    expect(_popup, findsNothing);
    expect(_list, findsNothing);
    expect(_key('astrology-search-message'), findsNothing);
    expect(_key('astrology-place-attribution'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(h.selections, isEmpty);
    expect(launcher.urls, isEmpty);
  });

  _case('controlled open/close preserves the actual editable child and draft',
      (tester, h, launcher) async {
    h.open = false;
    await h.mount(tester);
    await tester.enterText(_field, 'Uncommitted place');
    await _frames(tester);
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    for (var cycle = 0; cycle < 2; cycle++) {
      h.change(() => h.open = true);
      await _frames(tester);
      expect(_popup, findsOneWidget);
      expect(tester.widget(_popup), isA<Material>());
      expect(tester.widget(_row(0)), isA<TextButton>());
      expect(tester.state(find.byType(EditableText)), same(editable));
      expect(h.text.text, 'Uncommitted place');
      expect(h.focus.hasPrimaryFocus, isTrue);
      h.change(() => h.open = false);
      await _frames(tester);
      expect(_popup, findsNothing);
      expect(_list, findsNothing);
    }
    expect(h.selections, isEmpty);
    expect(launcher.urls, isEmpty);
  });

  for (final customGroup in [false, true]) {
    _case(
        'first click selects once without losing field focus '
        '(${customGroup ? 'custom' : 'EditableText'} group)',
        (tester, h, launcher) async {
      h
        ..groupId = customGroup ? Object() : EditableText
        ..closeOnBlur = true
        ..closeOnSelection = true;
      await h.mount(tester);
      await tester.tap(_field, kind: PointerDeviceKind.mouse);
      await _frames(tester);
      expect(h.focus.hasPrimaryFocus, isTrue);

      final press = await tester.startGesture(
        tester.getCenter(_row(0)),
        kind: PointerDeviceKind.mouse,
      );
      try {
        await _frames(tester);
        expect(h.selections, isEmpty, reason: 'Pointer down is not a choice.');
        expect(h.outsideTaps, 0);
        expect(h.focus.hasPrimaryFocus, isTrue);
        expect(_row(0), findsOneWidget);
        await press.up();
      } finally {
        await press.removePointer();
      }
      await _frames(tester);
      expect(h.selections, [0]);
      expect(h.focus.hasPrimaryFocus, isTrue);
      expect(h.outsideTaps, 0);
      expect(_popup, findsNothing);
      expect(h.text.text, 'Draft place');
      expect(launcher.urls, isEmpty);
    });
  }

  _case('dragging results scrolls the list without choosing or blurring',
      (tester, h, launcher) async {
    h.closeOnBlur = true;
    await h.mount(tester);
    await tester.tap(_field);
    await _frames(tester);
    final position = _position(tester);
    expect(position.maxScrollExtent, greaterThan(120));
    await tester.dragFrom(
      tester.getRect(_row(1)).intersect(tester.getRect(_list)).center,
      const Offset(0, -130),
    );
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));
    expect(h.selections, isEmpty);
    expect(h.outsideTaps, 0);
    expect(h.focus.hasPrimaryFocus, isTrue);
    expect(_popup, findsOneWidget);
    expect(_within(_popup, find.byType(RawScrollbar)), findsNothing);
    expect(_within(_popup, find.byType(Scrollbar)), findsNothing);
    expect(launcher.urls, isEmpty);
  });

  _case('captured row callbacks cannot select after replacement or retirement',
      (tester, h, _) async {
    await h.mount(tester);
    final retired = tester.widget<TextButton>(_row(0)).onPressed!;
    final newSelections = <int>[];
    h.change(() {
      h.results = const [_longPlace];
      h.onSelected = newSelections.add;
    });
    await _frames(tester);
    retired();
    expect(h.selections, isEmpty);
    expect(newSelections, isEmpty);
    expect(find.text(_longPlace.name), findsOneWidget);

    // A new search generation can replace only its handler, not the list.
    final oldHandler = tester.widget<TextButton>(_row(0)).onPressed!;
    h.change(() => h.onSelected = (index) => newSelections.add(index + 10));
    await _frames(tester);
    oldHandler();
    expect(newSelections, isEmpty);
    await tester.tap(_row(0));
    await _frames(tester);
    expect(newSelections, [10]);

    final beforeBusy = tester.widget<TextButton>(_row(0)).onPressed!;
    h.change(() => h.busy = true);
    await _frames(tester);
    expect(tester.widget<TextButton>(_row(0)).onPressed, isNull);
    beforeBusy();
    expect(newSelections, [10]);

    h.change(() => h.busy = false);
    await _frames(tester);
    final beforeClose = tester.widget<TextButton>(_row(0)).onPressed!;
    h.change(() {
      h.open = false;
      h.enabled = false;
    });
    await _frames(tester);
    beforeClose();
    expect(_popup, findsNothing);
    expect(newSelections, [10]);

    h.change(() {
      h.open = true;
      h.enabled = true;
    });
    await _frames(tester);
    beforeClose();
    expect(newSelections, [10], reason: 'Reopening cannot revive an old row.');
    final beforeDispose = tester.widget<TextButton>(_row(0)).onPressed!;
    h.change(() => h.hostVisible = false);
    await _frames(tester);
    beforeDispose();
    expect(_popup, findsNothing);
    expect(newSelections, [10]);
  });

  _case('highlight reveal moves its own position, never the form or page',
      (tester, h, _) async {
    h.layout = (field) => SingleChildScrollView(
          controller: h.page,
          child: SizedBox(
            height: 1500,
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 40, top: 100),
                child: SizedBox(
                  width: 340,
                  height: 240,
                  child: SingleChildScrollView(
                    controller: h.form,
                    child: SizedBox(
                      height: 800,
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: _labelled(field),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
    await h.mount(tester);
    final scroll = tester.widget<SingleChildScrollView>(_list).controller!;
    expect(scroll.offset, 0);
    h.change(() => h.highlightedIndex = h.results.length - 1);
    await _frames(tester);
    // Flutter may replace the position when inherited physics refreshes. The
    // owned controller and its current offset are the persistent UI contract.
    expect(
        tester.widget<SingleChildScrollView>(_list).controller, same(scroll));
    expect(scroll.offset, greaterThan(0));
    _expectInside(
      tester.getRect(_row(h.highlightedIndex)),
      tester.getRect(_list),
    );
    expect(h.page.offset, 0);
    expect(h.form.offset, 0);
    expect(h.selections, isEmpty);

    h.change(() => h.highlightedIndex = 0);
    await _frames(tester);
    expect(scroll.offset, 0);
    h.change(() => h.highlightedIndex = 999);
    await _frames(tester);
    h.change(() {
      h.results = const [];
      h.highlightedIndex = -1;
    });
    await _frames(tester);
    expect(_row(0), findsNothing);
    expect(h.page.offset, 0);
    expect(h.form.offset, 0);
    expect(h.selections, isEmpty);
  });

  _case(
      'ancestor scroll repositions, hides outside either viewport, and reopens',
      (tester, h, _) async {
    h.layout = (field) => Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 40, top: 80),
            child: SizedBox(
              width: 340,
              height: 260,
              child: SingleChildScrollView(
                controller: h.page,
                child: SizedBox(
                  height: 1500,
                  child: SingleChildScrollView(
                    controller: h.horizontal,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: 1500,
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 120),
                          child: _labelled(field),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
    await h.mount(tester);
    final initial = tester.getRect(_popup);
    h.page.jumpTo(40);
    await _frames(tester);
    expect(tester.getRect(_popup).top, closeTo(initial.top - 40, 0.1));
    h.page.jumpTo(600);
    await _frames(tester);
    expect(_popup, findsNothing);
    expect(
      h.open,
      isTrue,
      reason: 'Visibility is not a parent state mutation.',
    );
    h.page.jumpTo(0);
    await _frames(tester);
    expect(_popup, findsOneWidget);
    h.horizontal.jumpTo(700);
    await _frames(tester);
    expect(_popup, findsNothing);
    h.horizontal.jumpTo(0);
    await _frames(tester);
    expect(_popup, findsOneWidget);
    expect(h.selections, isEmpty);
  });

  _case('real overlay escapes a clipped small card and anchors only the field',
      (tester, h, _) async {
    h.layout = (field) => Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 50, top: 80),
            child: ClipRRect(
              key: const ValueKey('test-clipped-card'),
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: 380,
                height: 124,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('A label wider than its editable field'),
                      const SizedBox(height: 6),
                      SizedBox(width: 240, child: field),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
    await h.mount(tester);
    final field = tester.getRect(_field);
    final card = tester.getRect(_key('test-clipped-card'));
    final popup = tester.getRect(_popup);
    expect(popup.top, closeTo(field.bottom + AppMenuMetrics.anchorGap, 0.1));
    expect(popup.left, closeTo(field.left, 0.1));
    expect(popup.width, closeTo(field.width, 0.1));
    expect(popup.bottom, greaterThan(card.bottom));
    expect(popup.width, lessThan(380));
    expect(tester.getCenter(_row(2)).dy, greaterThan(card.bottom));
    expect(_row(2).hitTestable(), findsOneWidget);
    await tester.tap(_row(2));
    await _frames(tester);
    expect(h.selections, [2]);
  });

  _case('bottom/right placement respects safe padding and keyboard insets',
      (tester, h, _) async {
    const size = Size(360, 240);
    tester.view.physicalSize = size;
    h
      ..padding = const EdgeInsets.fromLTRB(8, 12, 10, 14)
      ..insets = const EdgeInsets.only(right: 20, bottom: 48)
      ..layout = (field) => Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(left: 250, top: 120, width: 160, child: field),
            ],
          );
    await h.mount(tester);
    final popup = tester.getRect(_popup);
    _expectInside(popup, _usable(size, h));
    expect(
      popup.bottom,
      closeTo(tester.getRect(_field).top - AppMenuMetrics.anchorGap, 0.1),
    );
    expect(popup.right, closeTo(_usable(size, h).right, 0.1));
    expect(popup.height, lessThan(120));
    expect(popup.width, 160);
  });

  _case('a short narrow window at 2x clamps width and height without overflow',
      (tester, h, _) async {
    const size = Size(220, 170);
    tester.view.physicalSize = size;
    h
      ..scale = 2
      ..padding = const EdgeInsets.all(4)
      ..layout = (field) => Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(left: -20, top: 30, width: 300, child: field),
            ],
          );
    await h.mount(tester);
    final popup = tester.getRect(_popup);
    _expectInside(popup, _usable(size, h));
    expect(popup.width, closeTo(_usable(size, h).width, 0.1));
    expect(popup.height, lessThan(90));
    expect(_position(tester).maxScrollExtent, greaterThan(0));
    expect(_key('astrology-place-attribution'), findsOneWidget);
  });

  _case('layout and window changes are observed without changing dropdown data',
      (tester, h, _) async {
    var left = 40.0;
    var top = 60.0;
    final move = ValueNotifier<int>(0);
    try {
      h.layout = (field) => ValueListenableBuilder<int>(
            valueListenable: move,
            child: SizedBox(width: 280, child: field),
            builder: (_, __, child) => Stack(
              children: [Positioned(left: left, top: top, child: child!)],
            ),
          );
      await h.mount(tester);
      final initial = tester.getRect(_popup);
      left += 50;
      top += 30;
      move.value++;
      await _frames(tester);
      final moved = tester.getRect(_popup);
      expect(moved.left, closeTo(initial.left + 50, 0.1));
      expect(moved.top, closeTo(initial.top + 30, 0.1));
      tester.view.physicalSize = const Size(300, 240);
      await _frames(tester);
      _expectInside(tester.getRect(_popup), _usable(const Size(300, 240), h));
      expect(h.selections, isEmpty);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      move.dispose();
    }
  });

  for (final mode in [
    (name: 'native', premium: false, reduced: false),
    (name: 'premium', premium: true, reduced: false),
    (name: 'reduced motion', premium: true, reduced: true),
  ]) {
    _case(
        '${mode.name}: inactive card still permits popup-only wheel scrolling',
        (tester, h, _) async {
      h
        ..premium = mode.premium
        ..reduced = mode.reduced
        ..layout = (field) => SingleChildScrollView(
              controller: h.page,
              child: SizedBox(
                height: 1600,
                child: _defaultLayout(field),
              ),
            );
      await h.mount(tester);
      expect(
        tester
            .widget<ScrollActivationRegion>(
              find.byType(ScrollActivationRegion),
            )
            .active,
        isFalse,
      );
      expect(find.byType(PremiumScrollScope), findsOneWidget);
      final position = _position(tester);
      expect(position.physics.shouldAcceptUserOffset(position), isTrue);
      await _wheel(tester, tester.getCenter(_list));
      expect(position.pixels, closeTo(60, 0.2));
      expect(h.page.offset, 0);
      final retained = position.pixels;
      await _wheel(tester, const Offset(600, 350));
      expect(h.page.offset, closeTo(60, 0.2));
      expect(position.pixels, retained);
      expect(h.selections, isEmpty);
      expect(_within(_popup, find.byType(RawScrollbar)), findsNothing);
    });
  }

  for (final appearance in [
    (name: 'light', brightness: Brightness.light, paper: false),
    (name: 'dark', brightness: Brightness.dark, paper: false),
    (name: 'paper', brightness: Brightness.light, paper: true),
  ]) {
    for (final scale in [1.0, 2.0]) {
      _case(
          '${appearance.name} at ${scale}x inherits field palette and semantics',
          (tester, h, launcher) async {
        h
          ..scale = scale
          ..localTheme = ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF80644F),
              brightness: appearance.brightness,
            ),
            extensions: [PaperThemeExtension(enabled: appearance.paper)],
          )
          ..results = const [_longPlace]
          ..highlightedIndex = 0;
        await h.mount(tester);
        final palette = AstrologyPalette.of(
          tester.element(find.byType(AstrologyPlaceDropdown)),
        );
        final surface = tester.widget<Material>(_popup);
        expect(surface.color, palette.raised);
        expect(surface.surfaceTintColor, palette.raised);
        final shape = surface.shape! as RoundedRectangleBorder;
        expect(shape.side.color, palette.line);
        expect(
          shape.borderRadius,
          BorderRadius.circular(AppMenuMetrics.cornerRadius),
        );
        final button = tester.widget<TextButton>(_row(0));
        expect(button.style!.backgroundColor!.resolve({}), palette.selection);
        final label = tester.widget<Text>(find.text(_longPlace.name));
        expect(label.maxLines, 2);
        expect(label.style!.color, palette.ink);
        expect(
          find.text('39.7817°, -89.6501° · America/Chicago'),
          findsOneWidget,
        );
        final data = tester.getSemantics(_row(0)).getSemanticsData();
        expect(data.hasFlag(SemanticsFlag.isButton), isTrue);
        expect(data.hasFlag(SemanticsFlag.isSelected), isTrue);
        expect(data.hasAction(SemanticsAction.tap), isTrue);
        expect(data.label, contains(_longPlace.name));
        expect(h.selections, isEmpty, reason: 'Highlighting is not selection.');
        _expectInside(tester.getRect(_popup), _usable(const Size(800, 600), h));
        expect(_within(_popup, find.byType(RawScrollbar)), findsNothing);
        if (appearance.paper) {
          expect(surface.color, PaperTheme.popupBackground);
          expect(surface.color!.r, greaterThan(surface.color!.b));
        }
        expect(launcher.urls, isEmpty);
      });
    }
  }

  _case(
      'non-focusable rows remain accessible and keyboard stays with the field',
      (tester, h, _) async {
    h.results = _places(2);
    await h.mount(tester);
    await tester.tap(_field);
    await _frames(tester);
    h.change(() => h.highlightedIndex = 1);
    await _frames(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _frames(tester);
    expect(h.focus.hasPrimaryFocus, isTrue);
    // A bare TextField receives onSubmitted through the platform text-input
    // action, not a synthetic physical key alone. The form's own Enter-to-pick
    // handler is covered separately by its integration tests.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _frames(tester);
    expect(h.submissions, ['Draft place']);
    expect(h.selections, isEmpty);

    h.focus.requestFocus();
    await _frames(tester);
    final row = tester.getSemantics(_row(1));
    expect(row.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    row.owner!.performAction(row.id, SemanticsAction.tap);
    await _frames(tester);
    expect(h.selections, [1]);
    expect(h.focus.hasPrimaryFocus, isTrue);
    final labelContext = tester.element(find.text(h.results[1].name));
    expect(Focus.of(labelContext).canRequestFocus, isFalse);
  });

  _case('loading, empty and error messages stay compact and controlled',
      (tester, h, launcher) async {
    h
      ..results = const []
      ..busy = true;
    await h.mount(tester);
    expect(find.text('Searching places…'), findsOneWidget);
    expect(
      tester.getSize(find.byType(CircularProgressIndicator)),
      const Size(16, 16),
    );
    final loadingHeight = tester.getSize(_popup).height;
    expect(loadingHeight, lessThan(140));
    for (final message in [
      'No matching places.',
      'Unable to search. Try again.',
    ]) {
      h.change(() {
        h.busy = false;
        h.message = message;
      });
      await _frames(tester);
      expect(
        tester.widget<Text>(_key('astrology-search-message')).data,
        message,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.getSize(_popup).height, closeTo(loadingHeight, 25));
      expect(_row(0), findsNothing);
    }
    h.change(() => h.message = null);
    await _frames(tester);
    expect(find.text('No places found.'), findsOneWidget);
    expect(_key('astrology-place-attribution'), findsOneWidget);
    expect(h.selections, isEmpty);
    expect(launcher.urls, isEmpty);
  });

  _case('attribution launches only on click and does not select or take focus',
      (tester, h, launcher) async {
    await h.mount(tester);
    expect(launcher.urls, isEmpty);
    await tester.tap(_field);
    await _frames(tester);
    await tester.tap(_key('astrology-place-attribution'));
    await _frames(tester);
    expect(launcher.urls, [_copyright]);
    expect(
      launcher.options.single.mode,
      PreferredLaunchMode.externalApplication,
    );
    expect(h.selections, isEmpty);
    expect(h.focus.hasPrimaryFocus, isTrue);
    expect(h.outsideTaps, 0);
  });

  for (final throws in [false, true]) {
    _case('attribution handles ${throws ? 'platform errors' : 'false results'}',
        (tester, h, launcher) async {
      launcher
        ..succeeds = false
        ..failure = throws ? PlatformException(code: 'no_browser') : null;
      await h.mount(tester);
      await tester.tap(_key('astrology-place-attribution'));
      await _frames(tester);
      expect(launcher.urls, [_copyright]);
      expect(
        find.textContaining('Could not open the browser.'),
        findsOneWidget,
      );
      expect(find.textContaining('licensed under ODbL:'), findsOneWidget);
      expect(h.selections, isEmpty);
    });
  }

  for (final disposeHost in [false, true]) {
    _case(
        'pending browser completion is safe after '
        '${disposeHost ? 'host disposal' : 'closing'}',
        (tester, h, launcher) async {
      final pending = Completer<bool>();
      launcher.pending = pending;
      await h.mount(tester);
      await tester.tap(_key('astrology-place-attribution'));
      await _frames(tester);
      expect(launcher.urls, [_copyright]);
      h.change(() {
        if (disposeHost) {
          h.hostVisible = false;
        } else {
          h.open = false;
        }
      });
      await _frames(tester);
      pending.completeError(PlatformException(code: 'closed'));
      await _frames(tester);
      expect(_popup, findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });
  }

  _case('disposal between post-frame opening and overlay layout leaves nothing',
      (tester, h, _) async {
    h.open = false;
    await h.mount(tester);
    h.change(() => h.open = true);
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await _frames(tester);
    expect(_popup, findsNothing);
    expect(_list, findsNothing);
  });
}

void _case(
  String name,
  Future<void> Function(WidgetTester, _Harness, _UrlLauncher) body,
) {
  testWidgets(
    name,
    (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(800, 600);
      final semantics = tester.ensureSemantics();
      final previousLauncher = UrlLauncherPlatform.instance;
      final launcher = _UrlLauncher();
      final harness = _Harness();
      UrlLauncherPlatform.instance = launcher;
      try {
        await body(tester, harness, launcher);
        expect(find.byType(ErrorWidget), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        try {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        } finally {
          harness.dispose();
          UrlLauncherPlatform.instance = previousLauncher;
          // Dispose inside the test body, even when an assertion fails.
          semantics.dispose();
          tester.view.reset();
        }
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}

class _Harness extends ChangeNotifier {
  _Harness() {
    focus.addListener(_focusChanged);
  }

  final text = TextEditingController(text: 'Draft place');
  final focus = FocusNode();
  final page = ScrollController();
  final form = ScrollController();
  final horizontal = ScrollController();
  final selections = <int>[];
  final submissions = <String>[];
  List<AstrologyPlace> results = _places(24);
  ValueChanged<int>? onSelected;
  Widget Function(Widget)? layout;
  ThemeData? localTheme;
  Object groupId = EditableText;
  String? message;
  EdgeInsets padding = EdgeInsets.zero;
  EdgeInsets insets = EdgeInsets.zero;
  double scale = 1;
  int highlightedIndex = -1;
  int outsideTaps = 0;
  bool open = true;
  bool busy = false;
  bool enabled = true;
  bool hostVisible = true;
  bool closeOnBlur = false;
  bool closeOnSelection = false;
  bool premium = false;
  bool reduced = false;

  void change(VoidCallback update) {
    update();
    notifyListeners();
  }

  void _focusChanged() {
    if (!focus.hasFocus && closeOnBlur && open) change(() => open = false);
  }

  void _select(int index) {
    selections.add(index);
    if (closeOnSelection) change(() => open = false);
  }

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      ListenableBuilder(
        listenable: this,
        builder: (_, __) => MaterialApp(
          theme: ThemeData(platform: TargetPlatform.windows),
          themeAnimationDuration: Duration.zero,
          builder: (context, navigator) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: padding,
              viewPadding: padding,
              viewInsets: insets,
              textScaler: TextScaler.linear(scale),
              disableAnimations: reduced,
            ),
            child: PremiumScrollScope(enabled: premium, child: navigator!),
          ),
          home: Scaffold(
            resizeToAvoidBottomInset: false,
            body: !hostVisible
                ? const SizedBox.shrink()
                : Theme(
                    // Deliberately field-local: the root overlay stays light.
                    data: localTheme ??
                        ThemeData(platform: TargetPlatform.windows),
                    child: (layout ?? _defaultLayout)(
                      ScrollActivationRegion(
                        active: false,
                        child: AstrologyPlaceDropdown(
                          isOpen: open,
                          results: results,
                          busy: busy,
                          highlightedIndex: highlightedIndex,
                          onSelected: onSelected ?? _select,
                          message: message,
                          groupId: groupId,
                          child: TextEntryShortcuts(
                            child: TextField(
                              key: const ValueKey('test-place-field'),
                              groupId: groupId,
                              controller: text,
                              focusNode: focus,
                              enabled: enabled,
                              style: const TextStyle(fontSize: 14),
                              onSubmitted: submissions.add,
                              onTapOutside: (_) {
                                outsideTaps++;
                                focus.unfocus();
                                change(() => open = false);
                              },
                              decoration: const InputDecoration(
                                isDense: true,
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.all(12),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
    await _frames(tester);
  }

  @override
  void dispose() {
    focus.removeListener(_focusChanged);
    focus.dispose();
    text.dispose();
    page.dispose();
    form.dispose();
    horizontal.dispose();
    super.dispose();
  }
}

/// No native/browser IO: the sole platform boundary is replaced in every test.
class _UrlLauncher extends UrlLauncherPlatform {
  final urls = <String>[];
  final options = <LaunchOptions>[];
  bool succeeds = true;
  Object? failure;
  Completer<bool>? pending;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) {
    urls.add(url);
    this.options.add(options);
    final error = failure;
    if (error != null) return Future<bool>.error(error);
    return pending?.future ?? Future.value(succeeds);
  }
}

List<AstrologyPlace> _places(int count) => List.generate(
      count,
      (index) => AstrologyPlace(
        name: 'Place $index, District $index, Region, Country',
        latitude: 12 + index / 100,
        longitude: 77 + index / 100,
        timeZone: 'Asia/Kolkata',
      ),
    );

Widget _defaultLayout(Widget field) => Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 40, top: 80),
        child: _labelled(field),
      ),
    );

Widget _labelled(Widget field) => SizedBox(
      width: 320,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Birth place label'),
          const SizedBox(height: 6),
          field,
        ],
      ),
    );

Finder _key(String value) => find.byKey(ValueKey(value));
Finder get _field => _key('test-place-field');
Finder get _popup => _key('astrology-place-dropdown');
Finder get _list => _key('astrology-place-suggestions-scroll');
Finder _row(int index) => _key('astrology-result-$index');
Finder _within(Finder parent, Finder child) =>
    find.descendant(of: parent, matching: child);
ScrollPosition _position(WidgetTester tester) =>
    tester.widget<SingleChildScrollView>(_list).controller!.position;

Rect _usable(Size size, _Harness h) {
  final insets = h.padding + h.insets;
  return Rect.fromLTRB(
    insets.left,
    insets.top,
    size.width - insets.right,
    size.height - insets.bottom,
  ).deflate(AppMenuMetrics.screenInset);
}

void _expectInside(Rect actual, Rect bounds) {
  expect(actual.isEmpty, isFalse);
  expect(actual.left, greaterThanOrEqualTo(bounds.left - 0.1));
  expect(actual.top, greaterThanOrEqualTo(bounds.top - 0.1));
  expect(actual.right, lessThanOrEqualTo(bounds.right + 0.1));
  expect(actual.bottom, lessThanOrEqualTo(bounds.bottom + 0.1));
}

// Finite frame draining works for loading spinners too; no pumpAndSettle on a
// deliberately busy popup. The component itself has no search timers.
Future<void> _frames(WidgetTester tester) async {
  for (var frame = 0; frame < 4; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _wheel(WidgetTester tester, Offset position) async {
  await tester.sendEventToBinding(
    PointerScrollEvent(position: position, scrollDelta: const Offset(0, 60)),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 16));
}
