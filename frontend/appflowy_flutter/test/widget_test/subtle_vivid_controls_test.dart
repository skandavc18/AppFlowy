import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/database/tab_bar/desktop/tab_bar_add_button.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/block_action_button.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/icon_emoji_picker/default_icon_artwork.dart';
import 'package:appflowy/shared/icon_emoji_picker/vivid_icon_artwork.dart';
import 'package:appflowy/shared/icon_emoji_picker/vivid_icons.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/shared/workspace_tokens.dart';
import 'package:appflowy/workspace/application/home/home_setting_bloc.dart';
import 'package:appflowy/workspace/application/settings/default_icon_style.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/home/tabs/tabs_manager.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_item_icon.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart'
    show FlowyIconButton, PopoverState;
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:xml/xml.dart';

import 'test_asset_bundle.dart';
import 'vivid_icon_test_support.dart'
    show prepareVividIconTestAssets, vividIconTestAppearances;
import 'workspace_overlay_test_app.dart';

// Source-only handoff: no new golden or catalogue replica. Existing Vivid
// catalogue/chrome goldens own the full visual review. These tests use real
// controls, compiled production SVGs, in-memory host inputs and no app startup.
const _deadline = Duration(seconds: 10);
const _testTimeout = Timeout(Duration(seconds: 60));
const _workspaceId = 'subtle-vivid-workspace';
const _pixelNames = ['plus', 'dots-six-vertical', 'refresh', 'copy'];
const _pixelSizes = [16.0, 18.0, 24.0];
const _controlNames = {
  'tab': 'plus',
  'database-add': 'plus',
  'block-plus': 'plus',
  'block-grip': 'dots-six-vertical',
  'refresh': 'refresh',
  'copy': 'copy',
};
const _refinedActions = [
  'plus',
  'search',
  'settings',
  'bell',
  'refresh',
  'copy',
  'download',
  'upload',
  'pen',
  'pin',
  'history',
  'clock',
  'trash',
  'lock',
  'shield',
  'text',
  'number',
  'checkbox',
  'select',
  'connections',
  'attachment',
  'sigma',
  'keyboard',
  'filter',
  'sort',
  'link',
  'scissors',
  'clipboard',
];
const _warmNames = {
  ..._pixelNames,
  'file-text',
  'folder',
  'table',
  'kanban',
  'calendar-blank',
  'squares-four',
  'graph',
  'article',
  'list-checks',
  'envelope-simple',
  'chart-bar',
  'map-trifold',
  'presentation-chart',
};
final _network = _NoNetwork();
late _Translations _translations;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final previousFetching = GoogleFonts.config.allowRuntimeFetching;
  final previousCacheSize = svg.cache.maximumSize;

  setUpAll(
    () => _offline(() async {
      GoogleFonts.config.allowRuntimeFetching = false;
      await prepareVividIconTestAssets().timeout(_deadline);
      _translations = _Translations(
        await const TestBundleAssetLoader()
            .load('assets/translations', const Locale('en', 'US'))
            .timeout(_deadline),
      );
      // Compile on real time before mounting, including the real add-menu
      // choices. A cold compute future under the fake clock can otherwise
      // leave a blank SVG which pumpAndSettle alone cannot detect.
      final sources = {
        for (final name in _warmNames) ...[
          defaultIconSvg(name)!,
          vividIconSvg(WorkspaceGlyphs.vividNameFor(name)!)!,
        ],
      };
      svg.cache.maximumSize = math.max(
        previousCacheSize,
        svg.cache.count + sources.length * 2 + 16,
      );
      for (final source in sources) {
        for (final theme in const <SvgTheme?>[null, SvgTheme()]) {
          final bytes = await SvgStringLoader(source, theme: theme)
              .loadBytes(null)
              .timeout(_deadline);
          expect(bytes.lengthInBytes, greaterThan(0));
        }
      }
    }).timeout(const Duration(seconds: 60)),
  );
  tearDownAll(() {
    GoogleFonts.config.allowRuntimeFetching = previousFetching;
    svg.cache.maximumSize = previousCacheSize;
  });

  test('plus and representative actions keep exact quiet SVGs and palettes',
      () {
    for (final entry in _thinArtwork.entries) {
      expect(vividIconSvg(entry.key), entry.value.svg, reason: entry.key);
    }
    final plus = XmlDocument.parse(vividIconSvg('plus')!).rootElement;
    expect(
      plus.findElements('path').map((path) => path.getAttribute('d')),
      ['M16 7v18', 'M7 16h18'],
    );
    expect(
      plus.findElements('path').map((path) => path.getAttribute('stroke')),
      ['url(#main)', 'url(#accent)'],
    );
    expect(
      defaultIconSvg('plus'),
      _defaultSvg(
        '<path d="M12 5v14M5 12h14"/>',
      ),
    );
  });

  test('refined actions are distinct unfilled 2.0/2.2px rounded strokes', () {
    final bodies = <String>{};
    for (final name in _refinedActions) {
      final root = XmlDocument.parse(vividIconSvg(name)!).rootElement;
      expect(root.getAttribute('viewBox'), '0 0 32 32', reason: name);
      expect(root.getAttribute('fill'), 'none', reason: name);
      expect(root.getAttribute('stroke-linecap'), 'round', reason: name);
      expect(root.getAttribute('stroke-linejoin'), 'round', reason: name);
      final elements = _artElements(root).toList();
      expect(
        elements.map((element) => element.name.local),
        everyElement(isIn(['path', 'rect', 'circle', 'g'])),
        reason: '$name must not gain a badge, filter or embedded image',
      );
      final shapes = elements.where((element) => element.name.local != 'g');
      expect(shapes.length, greaterThanOrEqualTo(2), reason: name);
      for (final shape in shapes) {
        expect(_inherited(shape, 'fill'), 'none', reason: '$name filled badge');
        expect(
          _inherited(shape, 'stroke'),
          isIn(['url(#main)', 'url(#accent)']),
          reason: name,
        );
        expect(
          double.parse(_inherited(shape, 'stroke-width')!),
          isIn([2.0, 2.2]),
          reason: '$name must not revert to a heavy miniature illustration',
        );
      }
      expect(bodies.add(_body(root)), isTrue, reason: '$name duplicated shape');
    }
  });

  test('six-dot grip has its own geometry and muted utility palette', () {
    final source = defaultIconSvg('dots-six-vertical')!;
    expect(source, _defaultSvg(_gripBody));
    expect(vividIconSvg('utility-dots-six-vertical'), _vividGrip);
    final dots = XmlDocument.parse(source).findAllElements('circle').toList();
    expect(dots, hasLength(6));
    expect(dots.map((dot) => dot.getAttribute('r')), everyElement('1.5'));
    expect(
      dots.map((dot) => (dot.getAttribute('cx'), dot.getAttribute('cy'))),
      [
        for (final y in ['6', '12', '18'])
          for (final x in ['9', '15']) (x, y),
      ],
    );
    expect(
      WorkspaceGlyphs.nameForSvg(FlowySvgs.drag_element_s),
      'dots-six-vertical',
    );
    expect(
      WorkspaceGlyphs.nameForIcon(Icons.drag_indicator_rounded),
      'dots-six-vertical',
    );
    expect(
      WorkspaceGlyphs.vividNameFor('dots-six-vertical'),
      'utility-dots-six-vertical',
    );
    for (final icon in [Icons.more_horiz_rounded, Icons.more_vert_rounded]) {
      expect(WorkspaceGlyphs.nameForIcon(icon), 'dots-three');
    }
    expect(
      XmlDocument.parse(defaultIconSvg('dots-three')!)
          .findAllElements('circle'),
      hasLength(3),
    );
    for (final entry in _utilityPalettes.entries) {
      expect(
        XmlDocument.parse(vividIconSvg('utility-${entry.key}')!)
            .findAllElements('stop')
            .map((stop) => stop.getAttribute('stop-color')),
        entry.value,
        reason: '${entry.key}: only the new grip gets the muted palette',
      );
    }
  });

  test('original Essentials retain page/folder artwork rather than action ink',
      () {
    final essentials = appFlowyVividIconGroups.singleWhere(
      (group) => group.name == 'appflowy_vivid_essentials',
    );
    expect(essentials.icons, hasLength(56));
    expect(
      essentials.icons.map((icon) => icon.name).toSet().intersection(
            _refinedActions.toSet(),
          ),
      isEmpty,
    );
    for (final entry in _originalArtwork.entries) {
      expect(vividIconSvg(entry.key), entry.value.svg);
      expect(
        essentials.icons.singleWhere((icon) => icon.name == entry.key).content,
        entry.value.svg,
      );
    }
    expect(WorkspaceGlyphs.vividNameFor('file-text'), 'page');
    expect(WorkspaceGlyphs.vividNameFor('folder'), 'folder');
  });

  for (final appearance in vividIconTestAppearances) {
    testWidgets(
      '$appearance: live styles keep real controls and host input',
      (tester) => _withControls(tester, appearance, (fixture) async {
        await tester.enterText(_key('draft'), 'Unfinished host draft');
        const selection = TextSelection(baseOffset: 2, extentOffset: 9);
        fixture.input.selection = selection;
        await tester.pump();
        final editable = find.byType(EditableText);
        final inputState = tester.state(editable);
        final hostBuilds = fixture.builds;
        final controls = {
          for (final id in _controlNames.keys)
            id: (tester.element(_native(id)), tester.getRect(_native(id))),
        };
        final states = {
          for (final id in ['database-add', 'block-plus', 'block-grip'])
            id: tester.state(_key(id)),
        };
        final identities = {
          for (final id in ['page-identity', 'folder-identity'])
            id: tester.element(_key(id)),
        };
        final pageBytes = fixture.page.writeToBuffer();
        final folderBytes = fixture.folder.writeToBuffer();

        for (final style in [
          DefaultIconStyle.monochrome,
          DefaultIconStyle.vivid,
          DefaultIconStyle.monochrome,
        ]) {
          fixture.styles.value = style;
          await _settlePictures(tester);
          for (final entry in _controlNames.entries) {
            _expectGlyph(
              tester,
              _key(entry.key),
              entry.value,
              style,
              size: entry.key == 'refresh' ? 16 : 18,
            );
            expect(
              tester.element(_native(entry.key)),
              same(controls[entry.key]!.$1),
            );
            expect(tester.getRect(_native(entry.key)), controls[entry.key]!.$2);
            _expectHitEdges(_native(entry.key));
          }
          expect(tester.getSize(_native('tab')), const Size.square(32));
          expect(tester.getSize(_native('database-add')), const Size(36, 38));
          for (final id in ['block-plus', 'block-grip']) {
            expect(tester.getSize(_native(id)), const Size.square(28));
            final button = tester.widget<FlowyIconButton>(
              find.descendant(
                of: _key(id),
                matching: find.byType(FlowyIconButton),
              ),
            );
            expect(button.width, 28);
            expect(button.hoverColor, Colors.transparent);
          }
          for (final entry in states.entries) {
            expect(tester.state(_key(entry.key)), same(entry.value));
          }
          _expectGlyph(
            tester,
            _key('page-identity'),
            'file-text',
            style,
            size: 24,
          );
          _expectGlyph(
            tester,
            _key('folder-identity'),
            'folder',
            style,
            size: 24,
          );
          for (final entry in identities.entries) {
            expect(tester.element(_key(entry.key)), same(entry.value));
          }
          expect(fixture.page.writeToBuffer(), pageBytes);
          expect(fixture.folder.writeToBuffer(), folderBytes);
          expect(tester.state(editable), same(inputState));
          expect(
            tester.widget<EditableText>(editable).controller,
            same(fixture.input),
          );
          expect(fixture.input.text, 'Unfinished host draft');
          expect(fixture.input.selection, selection);
          expect(fixture.focus.hasFocus, isTrue);
          expect(fixture.builds, hostBuilds);
          expect(fixture.events, isEmpty);
          expect(fixture.choices, isEmpty);
          expect(fixture.tabs.opens, isEmpty);
        }

        _expectButtonSemantics(tester, _native('tab'), enabled: true);
        final tabRect = tester.getRect(_native('tab'));
        // Outside the 18px glyph but inside the unchanged 32px button.
        await tester.tapAt(
          tabRect.centerLeft + const Offset(1, 0),
          kind: PointerDeviceKind.mouse,
        );
        for (final key in [
          LogicalKeyboardKey.enter,
          LogicalKeyboardKey.space,
        ]) {
          await _focusGlyph(tester, _key('tab'));
          await tester.sendKeyEvent(key);
          await _settleFrames(tester);
        }
        expect(
          fixture.tabs.opens,
          List.filled(3, (_workspaceId, false, true, true)),
        );
        await tester.tap(_native('refresh'), kind: PointerDeviceKind.mouse);
        await tester.tap(_native('copy'), kind: PointerDeviceKind.mouse);
        expect(fixture.events, ['refresh', 'copy']);
      }),
      timeout: _testTimeout,
    );

    testWidgets(
      '$appearance: 16/18/24px ink is light, inset and transparent',
      (tester) => _offline(() async {
        _viewport(tester);
        final styles = ValueNotifier(DefaultIconStyle.vivid);
        try {
          await tester.pumpWidget(
            _app(
              appearance,
              styles,
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final name in _pixelNames)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final size in _pixelSizes)
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: RepaintBoundary(
                                key: ValueKey('$name-$size'),
                                child: WorkspaceGlyph.named(name, size: size),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
          await _settlePictures(tester);
          for (final name in _pixelNames) {
            for (final size in _pixelSizes) {
              final sample = _key('$name-$size');
              _expectGlyph(
                tester,
                sample,
                name,
                DefaultIconStyle.vivid,
                size: size,
              );
              expect(tester.getSize(sample), Size.square(size));
              final pixels = await _readRaster(tester, sample);
              _expectLightInk(
                pixels,
                name,
                EditorSurfaceStyle.canvasBackground(tester.element(sample)),
                '$appearance / $name / ${size.toInt()}px',
              );
              if (name == 'plus') _expectPlusSilhouette(pixels);
              if (name == 'dots-six-vertical') {
                expect(
                  _inkComponents(pixels),
                  6,
                  reason:
                      'The grip must remain six separated dots, not an ellipsis',
                );
              }
            }
          }
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await _settleFrames(tester);
          styles.dispose();
        }
      }),
      timeout: _testTimeout,
    );

    testWidgets(
      '$appearance: native add-view activation and disabled guards',
      (tester) => _withControls(tester, appearance, (fixture) async {
        fixture.styles.value = DefaultIconStyle.vivid;
        await _settlePictures(tester);
        final state = tester.state(_key('database-add'));
        final element = tester.element(_native('database-add'));
        final rect = tester.getRect(_native('database-add'));
        _expectButtonSemantics(tester, _native('database-add'), enabled: true);

        await tester.tap(
          _native('database-add'),
          kind: PointerDeviceKind.mouse,
        );
        await _settlePictures(tester);
        expect(find.byType(TabBarAddButtonAction), findsOneWidget);
        expect(_gridChoice().hitTestable(), findsOneWidget);
        _expectGlyph(
          tester,
          _gridChoice(),
          'table',
          DefaultIconStyle.vivid,
          size: 16,
        );
        _expectButtonSemantics(tester, _gridChoice(), enabled: true);
        await _focusGlyph(tester, _gridChoice());
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await _settleFrames(tester);
        expect(fixture.choices, [DatabaseTabKind.grid]);
        expect(find.byType(TabBarAddButtonAction), findsNothing);

        await _focusGlyph(tester, _key('database-add'));
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await _settlePictures(tester);
        await tester.tap(_gridChoice(), kind: PointerDeviceKind.mouse);
        await _settleFrames(tester);
        expect(fixture.choices, [DatabaseTabKind.grid, DatabaseTabKind.grid]);

        final staleOpen =
            tester.widget<IconButton>(_native('database-add')).onPressed!;
        await tester.tap(
          _native('database-add'),
          kind: PointerDeviceKind.mouse,
        );
        await _settlePictures(tester);
        final staleChoice = tester.widget<TextButton>(_gridChoice()).onPressed!;
        fixture.enabled.value = false;
        await _settleFrames(tester);
        expect(find.byType(TabBarAddButtonAction), findsNothing);
        expect(PopoverState.rootEntry, isEmpty);
        expect(
          tester.widget<IconButton>(_native('database-add')).onPressed,
          isNull,
        );
        _expectButtonSemantics(tester, _native('database-add'), enabled: false);
        await tester.tapAt(rect.center, kind: PointerDeviceKind.mouse);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        // Only this race probe invokes captured callbacks: normal activation
        // above and recovery below both go through native button input.
        staleOpen();
        staleChoice();
        await _settleFrames(tester);
        expect(fixture.choices, hasLength(2));
        expect(find.byType(TabBarAddButtonAction), findsNothing);
        expect(tester.state(_key('database-add')), same(state));
        expect(tester.element(_native('database-add')), same(element));
        expect(tester.getRect(_native('database-add')), rect);

        fixture.enabled.value = true;
        await _settleFrames(tester);
        await tester.tap(
          _native('database-add'),
          kind: PointerDeviceKind.mouse,
        );
        await _settlePictures(tester);
        await tester.tap(_gridChoice(), kind: PointerDeviceKind.mouse);
        await _settleFrames(tester);
        expect(fixture.choices, List.filled(3, DatabaseTabKind.grid));
        expect(fixture.tabs.opens, isEmpty);
      }),
      timeout: _testTimeout,
    );

    testWidgets(
      '$appearance: block hover, secondary pointer and drag handoff',
      (tester) => _withControls(tester, appearance, (fixture) async {
        fixture.styles.value = DefaultIconStyle.vivid;
        await _settlePictures(tester);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(-10, -10));
        try {
          for (final id in ['block-plus', 'block-grip']) {
            final bounds = tester.getRect(_native(id));
            final hover = WorkspaceChrome.hoverColor(tester.element(_key(id)));
            final animation =
                tester.widget<AnimatedContainer>(_blockAnimation(id));
            expect(animation.duration, const Duration(milliseconds: 140));
            expect(animation.curve, WorkspaceTokens.curve);
            expect(_paintedBlockColor(tester, id), hover.withValues(alpha: 0));
            await mouse.moveTo(bounds.center);
            await tester.pump();
            expect(
              (tester.widget<AnimatedContainer>(_blockAnimation(id)).decoration!
                      as BoxDecoration)
                  .color,
              hover,
            );
            await tester.pump(const Duration(milliseconds: 70));
            final halfway = Color.lerp(
              hover.withValues(alpha: 0),
              hover,
              WorkspaceTokens.curve.transform(0.5),
            )!;
            final painted = _paintedBlockColor(tester, id);
            expect(painted.a, closeTo(halfway.a, 0.005));
            expect(painted.r, closeTo(halfway.r, 1 / 255));
            expect(painted.g, closeTo(halfway.g, 1 / 255));
            expect(painted.b, closeTo(halfway.b, 1 / 255));
            await tester.pump(const Duration(milliseconds: 71));
            expect(_paintedBlockColor(tester, id), hover);
            expect(tester.getRect(_native(id)), bounds);
            await mouse.moveTo(const Offset(-10, -10));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 141));
            expect(_paintedBlockColor(tester, id), hover.withValues(alpha: 0));
          }

          final plusEdge = tester.getRect(_native('block-plus')).centerLeft +
              const Offset(1, 0);
          expect(
            tester.getRect(_glyph(_key('block-plus'))).contains(plusEdge),
            isFalse,
          );
          await tester.tapAt(plusEdge, kind: PointerDeviceKind.mouse);
          await tester.tap(
            _native('block-grip'),
            kind: PointerDeviceKind.mouse,
            buttons: kSecondaryMouseButton,
          );
          // The add button has no explicit secondary handler: its established
          // fallback must still invoke onTap exactly once, not twice.
          await tester.tap(
            _native('block-plus'),
            kind: PointerDeviceKind.mouse,
            buttons: kSecondaryMouseButton,
          );
          await _settleFrames(tester);
          expect(fixture.events, [
            'plus-down',
            'plus-tap',
            'grip-down',
            'grip-secondary',
            'plus-down',
            'plus-tap',
          ]);

          final gripState = tester.state(_key('block-grip'));
          final gripElement = tester.element(_native('block-grip'));
          final beforeDrag = fixture.events.length;
          final drag = await tester.startGesture(
            tester.getRect(_native('block-grip')).centerLeft +
                const Offset(1, 0),
            kind: PointerDeviceKind.mouse,
          );
          try {
            expect(fixture.events.skip(beforeDrag), ['grip-down']);
            await drag.moveBy(const Offset(12, 0));
            await tester.pump();
            expect(_key('drag-feedback'), findsOneWidget);
            expect(
              fixture.events.skip(beforeDrag),
              ['grip-down', 'drag-start'],
            );
            fixture.styles.value = DefaultIconStyle.monochrome;
            await tester.pump();
            await drag.moveBy(const Offset(28, 14));
            await tester.pump();
            expect(tester.state(_key('block-grip')), same(gripState));
            expect(tester.element(_native('block-grip')), same(gripElement));
          } finally {
            await drag.up();
          }
          await _settlePictures(tester);
          expect(
            fixture.events.skip(beforeDrag),
            ['grip-down', 'drag-start', 'drag-end'],
          );
          expect(_key('drag-feedback'), findsNothing);
          _expectGlyph(
            tester,
            _key('block-grip'),
            'dots-six-vertical',
            DefaultIconStyle.monochrome,
          );
          expect(tester.getSize(_native('block-grip')), const Size.square(28));
        } finally {
          await mouse.removePointer();
        }
      }),
      timeout: _testTimeout,
    );
  }

  for (final accessible in [false, true]) {
    testWidgets(
      'paper: ${accessible ? 'accessibleNavigation' : 'disableAnimations'} keeps controls immediate',
      (tester) => _withControls(
        tester,
        'paper',
        (fixture) async {
          fixture.styles.value = DefaultIconStyle.vivid;
          await _settlePictures(tester);
          for (final id in ['tab', 'database-add']) {
            expect(
              tester.widget<IconButton>(_native(id)).style!.animationDuration,
              Duration.zero,
            );
          }
          for (final id in ['refresh', 'copy']) {
            expect(
              tester.widget<TextButton>(_native(id)).style!.animationDuration,
              Duration.zero,
            );
          }
          for (final id in ['block-plus', 'block-grip']) {
            expect(
              tester.widget<AnimatedContainer>(_blockAnimation(id)).duration,
              Duration.zero,
            );
          }
          final mouse =
              await tester.createGesture(kind: PointerDeviceKind.mouse);
          await mouse.addPointer(location: const Offset(-10, -10));
          try {
            await mouse.moveTo(tester.getCenter(_native('block-plus')));
            await tester.pump();
            await tester.pump();
            expect(
              _paintedBlockColor(tester, 'block-plus'),
              WorkspaceChrome.hoverColor(tester.element(_key('block-plus'))),
            );
            expect(
              tester.getSize(_native('block-plus')),
              const Size.square(28),
            );
            await _focusGlyph(tester, _key('database-add'));
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await _settlePictures(tester);
            await _focusGlyph(tester, _gridChoice());
            await tester.sendKeyEvent(LogicalKeyboardKey.space);
            await _settleFrames(tester);
            expect(fixture.choices, [DatabaseTabKind.grid]);
            fixture.enabled.value = false;
            await tester.pump();
            _expectButtonSemantics(
              tester,
              _native('database-add'),
              enabled: false,
            );
          } finally {
            await mouse.removePointer();
          }
        },
        disableAnimations: !accessible,
        accessibleNavigation: accessible,
      ),
      timeout: _testTimeout,
    );
  }
}

Finder _key(String value) => find.byKey(ValueKey(value));
Finder _glyph(Finder parent) =>
    find.descendant(of: parent, matching: find.byType(WorkspaceGlyph));
Finder _native(String id) => find.descendant(
      of: _key(id),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is IconButton ||
            widget is TextButton ||
            widget is RawMaterialButton,
      ),
    );
Finder _gridChoice() => find.descendant(
      of: find.byWidgetPredicate(
        (widget) =>
            widget is TabBarAddButtonActionCell &&
            widget.action == DatabaseTabKind.grid,
      ),
      matching: find.byType(TextButton),
    );
Finder _blockAnimation(String id) => find
    .descendant(
      of: _key(id),
      matching: find.byType(AnimatedContainer),
    )
    .first;

Color _paintedBlockColor(WidgetTester tester, String id) => (tester
        .widget<DecoratedBox>(
          find
              .descendant(
                of: _blockAnimation(id),
                matching: find.byType(DecoratedBox),
              )
              .first,
        )
        .decoration as BoxDecoration)
    .color!;

void _expectHitEdges(Finder button) {
  for (final at in const [
    Alignment.center,
    Alignment(-0.95, 0),
    Alignment(0.95, 0),
    Alignment(0, -0.95),
    Alignment(0, 0.95),
  ]) {
    expect(button.hitTestable(at: at), findsOneWidget);
  }
}

void _expectButtonSemantics(
  WidgetTester tester,
  Finder button, {
  required bool enabled,
}) {
  final node = tester.getSemantics(button);
  expect(node.attached, isTrue);
  final data = node.getSemanticsData();
  expect(data.hasFlag(ui.SemanticsFlag.isButton), isTrue);
  expect(data.hasFlag(ui.SemanticsFlag.isEnabled), enabled);
  expect(data.hasAction(ui.SemanticsAction.tap), enabled);
}

Future<void> _focusGlyph(WidgetTester tester, Finder parent) async {
  // The glyph is INSIDE the native button's Focus, unlike IconButton's element.
  final focus = Focus.of(tester.element(_glyph(parent)));
  focus.requestFocus();
  await tester.pump();
  expect(focus.hasPrimaryFocus, isTrue);
}

void _expectGlyph(
  WidgetTester tester,
  Finder parent,
  String name,
  DefaultIconStyle style, {
  double size = 18,
}) {
  final finder = _glyph(parent);
  expect(finder, findsOneWidget);
  final glyph = tester.widget<WorkspaceGlyph>(finder);
  expect(glyph.name, name);
  expect(glyph.size, size);
  expect(tester.getSize(finder), Size.square(size));
  final picture = tester.widget<SvgPicture>(
    find.descendant(
      of: finder,
      matching: find.byType(SvgPicture),
    ),
  );
  final vividName = WorkspaceGlyphs.vividNameFor(name)!;
  final source = style == DefaultIconStyle.monochrome
      ? defaultIconSvg(name)!
      : _thinArtwork[vividName]?.svg ??
          _originalArtwork[vividName]?.svg ??
          (name == 'dots-six-vertical' ? _vividGrip : vividIconSvg(vividName)!);
  final loader = picture.bytesLoader as SvgStringLoader;
  expect(loader.colorMapper, isNull);
  // Public loader equality verifies the exact string; no private/protected
  // flutter_svg access and no test-authored artwork is ever rendered.
  expect(loader, SvgStringLoader(source, theme: loader.theme));
  expect(
    picture.colorFilter,
    style == DefaultIconStyle.vivid
        ? null
        : ColorFilter.mode(
            glyph.color ?? workspaceGlyphInk(tester.element(finder)),
            BlendMode.srcIn,
          ),
  );
  expect(
    find.ancestor(of: finder, matching: find.byType(ColorFiltered)),
    findsNothing,
  );
  expect(
    find.ancestor(of: finder, matching: find.byType(ShaderMask)),
    findsNothing,
  );
}

Future<void> _settleFrames(WidgetTester tester) => tester.pumpAndSettle(
      const Duration(milliseconds: 20),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 5),
    );

Future<void> _settlePictures(WidgetTester tester) async {
  await _settleFrames(tester);
  final pictures = find.byType(SvgPicture).evaluate().toList();
  expect(pictures, isNotEmpty);
  for (final element in pictures) {
    final loader =
        (element.widget as SvgPicture).bytesLoader as SvgStringLoader;
    expect(
      svg.cache.putIfAbsent(loader.cacheKey(element), () {
        throw StateError('Fixture SVG was not warmed before mounting');
      }),
      isA<SynchronousFuture<ByteData>>(),
    );
  }
  await tester.runAsync(() async {
    for (final element in pictures) {
      final picture = element.widget as SvgPicture;
      final decoded = await _ownedUntilDeadline(
        vg.loadPicture(picture.bytesLoader, element),
        (value) => value.picture.dispose(),
      );
      decoded.picture.dispose();
    }
  });
  await _settleFrames(tester);
}

Future<T> _ownedUntilDeadline<T>(Future<T> future, void Function(T) dispose) {
  var timedOut = false;
  return future.then((value) {
    if (timedOut) dispose(value);
    return value;
  }).timeout(
    _deadline,
    onTimeout: () {
      timedOut = true;
      throw TimeoutException(
        'Subtle Vivid engine resource deadline',
        _deadline,
      );
    },
  );
}

void _viewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1000, 800);
  addTearDown(tester.view.reset);
}

Widget _app(
  String appearance,
  ValueNotifier<DefaultIconStyle> styles,
  Widget child, {
  bool disableAnimations = false,
  bool accessibleNavigation = false,
}) {
  final app = workspaceOverlayTestApp(
    appearance: appearance,
    disableAnimations: disableAnimations,
    accessibleNavigation: accessibleNavigation,
    child: Center(child: child),
  ) as EasyLocalization;
  return DefaultIconStyleScope(
    styles: styles,
    child: TooltipVisibility(
      visible: false,
      child: EasyLocalization(
        supportedLocales: app.supportedLocales,
        path: app.path,
        fallbackLocale: app.fallbackLocale,
        useFallbackTranslations: app.useFallbackTranslations,
        saveLocale: false,
        assetLoader: _translations,
        child: app.child,
      ),
    ),
  );
}

Future<void> _withControls(
  WidgetTester tester,
  String appearance,
  Future<void> Function(_Controls) body, {
  bool disableAnimations = false,
  bool accessibleNavigation = false,
}) =>
    _offline(() async {
      _viewport(tester);
      final fixture = _Controls();
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          _app(
            appearance,
            fixture.styles,
            fixture.build(),
            disableAnimations: disableAnimations,
            accessibleNavigation: accessibleNavigation,
          ),
        );
        await _settlePictures(tester);
        expect(
          PaperTheme.isEnabled(tester.element(_key('block-plus'))),
          appearance == 'paper',
        );
        await body(fixture);
        expect(tester.takeException(), isNull);
      } finally {
        try {
          await tester.pumpWidget(const SizedBox.shrink());
          await _settleFrames(tester);
          expect(PopoverState.rootEntry, isEmpty);
        } finally {
          // Semantics must be disposed in the body, before Flutter's leak check.
          semantics.dispose();
          fixture.dispose();
        }
      }
    });

class _Controls {
  final styles = ValueNotifier(DefaultIconStyle.monochrome);
  final enabled = ValueNotifier(true);
  final input = TextEditingController();
  final focus = FocusNode();
  final tabs = _Tabs();
  final home = _HomeSettings();
  final events = <String>[];
  final choices = <DatabaseTabKind>[];
  final page =
      ViewPB(id: 'typed-page', name: 'copy.pdf', layout: ViewLayoutPB.Document)
        ..freeze();
  final folder = ViewPB(
    id: 'typed-folder',
    name: 'clipboard',
    layout: ViewLayoutPB.Document,
    extra: const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
  )..freeze();
  int builds = 0;

  Widget build() => MultiBlocProvider(
        providers: [
          BlocProvider<TabsBloc>.value(value: tabs),
          BlocProvider<HomeSettingBloc>.value(value: home),
        ],
        child: Builder(
          builder: (context) {
            builds++;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const TabsNewTabButton(key: ValueKey('tab')),
                    const SizedBox(width: 8),
                    ValueListenableBuilder<bool>(
                      valueListenable: enabled,
                      builder: (_, allowed, __) => AddDatabaseViewButton(
                        key: const ValueKey('database-add'),
                        enabled: allowed,
                        onTap: choices.add,
                      ),
                    ),
                    const SizedBox(width: 8),
                    BlockActionButton(
                      key: const ValueKey('block-plus'),
                      svg: FlowySvgs.add_s,
                      richMessage: const TextSpan(text: 'Add block'),
                      showTooltip: false,
                      onTap: () => events.add('plus-tap'),
                      onPointerDown: () => events.add('plus-down'),
                    ),
                    const SizedBox(width: 8),
                    // A host gesture probe, not a fake block control or a document
                    // reorder implementation. No EditorState/backend is created.
                    Draggable<int>(
                      data: 1,
                      allowedButtonsFilter: (buttons) =>
                          buttons == kPrimaryMouseButton,
                      feedback: const SizedBox.square(
                        key: ValueKey('drag-feedback'),
                        dimension: 28,
                      ),
                      onDragStarted: () => events.add('drag-start'),
                      onDragEnd: (_) => events.add('drag-end'),
                      child: BlockActionButton(
                        key: const ValueKey('block-grip'),
                        svg: FlowySvgs.drag_element_s,
                        richMessage: const TextSpan(text: 'Drag block'),
                        showTooltip: false,
                        onTap: () => events.add('grip-tap'),
                        onSecondaryTap: () => events.add('grip-secondary'),
                        onPointerDown: () => events.add('grip-down'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    WorkspaceControlButton(
                      key: const ValueKey('refresh'),
                      icon: Icons.refresh_rounded,
                      tooltip: 'Refresh',
                      onPressed: () => events.add('refresh'),
                    ),
                    WorkspaceControlButton(
                      key: const ValueKey('copy'),
                      icon: Icons.copy_rounded,
                      tooltip: 'Copy',
                      iconSize: 18,
                      onPressed: () => events.add('copy'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: 320,
                  child: TextField(
                    key: const ValueKey('draft'),
                    controller: input,
                    focusNode: focus,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    WorkspaceItemIcon.fromView(
                      key: const ValueKey('page-identity'),
                      view: page,
                      size: 24,
                      showThumbnail: false,
                    ),
                    const SizedBox(width: 16),
                    WorkspaceItemIcon.fromView(
                      key: const ValueKey('folder-identity'),
                      view: folder,
                      size: 24,
                      showThumbnail: false,
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );

  void dispose() {
    styles.dispose();
    enabled.dispose();
    input.dispose();
    focus.dispose();
  }
}

// Never construct the real TabsBloc, HomeSettingBloc, PageManager or plugins.
// Unexpected backend-facing methods retain Fake's throwing implementation.
class _Tabs extends Fake implements TabsBloc {
  final opens = <(String, bool, bool, bool?)>[];
  @override
  bool get isClosed => false;
  @override
  Stream<TabsState> get stream => const Stream.empty();
  @override
  Future<void> openHome({
    required String workspaceId,
    bool startup = false,
    bool newTab = false,
    bool Function()? isCurrent,
  }) async {
    opens.add((workspaceId, startup, newTab, isCurrent?.call()));
  }
}

class _HomeSettings extends Fake implements HomeSettingBloc {
  @override
  final state = HomeSettingState(
    panelContext: null,
    workspaceSetting: WorkspaceLatestPB(workspaceId: _workspaceId),
    unauthorized: false,
    menuStatus: MenuStatus.expanded,
    isNotificationPanelCollapsed: true,
    isScreenSmall: false,
    hasColappsedMenuManually: false,
    resizeOffset: 0,
    resizeStart: 0,
    resizeType: MenuResizeType.slide,
  );
  @override
  Stream<HomeSettingState> get stream => const Stream.empty();
}

class _Translations extends AssetLoader {
  const _Translations(this.english);
  final Map<String, dynamic> english;
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) =>
      Future.value(english);
}

class _NoNetwork extends HttpOverrides {
  int attempts = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    attempts++;
    throw StateError('Network is forbidden in subtle Vivid control tests');
  }
}

Future<void> _offline(Future<void> Function() body) async {
  final before = _network.attempts;
  try {
    await HttpOverrides.runWithHttpOverrides(body, _network);
  } finally {
    expect(
      _network.attempts,
      before,
      reason: 'No external backend or cloud requests',
    );
  }
}

class _Raster {
  const _Raster(this.width, this.height, this.bytes);
  final int width;
  final int height;
  final ByteData bytes;
  int alpha(int x, int y) => bytes.getUint8(4 * (y * width + x) + 3);
  Color pixel(int x, int y) {
    final i = 4 * (y * width + x);
    return Color.fromARGB(
      bytes.getUint8(i + 3),
      bytes.getUint8(i),
      bytes.getUint8(i + 1),
      bytes.getUint8(i + 2),
    );
  }
}

Future<_Raster> _readRaster(WidgetTester tester, Finder finder) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(finder);
  expect(boundary.debugNeedsPaint, isFalse);
  final result = await tester.runAsync(() async {
    final image = await _ownedUntilDeadline(
      boundary.toImage(),
      (value) => value.dispose(),
    );
    try {
      final bytes = await image
          .toByteData(format: ui.ImageByteFormat.rawStraightRgba)
          .timeout(_deadline);
      if (bytes == null) throw StateError('No raw SVG pixels returned');
      return _Raster(image.width, image.height, bytes);
    } finally {
      image.dispose();
    }
  });
  expect(result, isNotNull);
  expect(
    Size(result!.width.toDouble(), result.height.toDouble()),
    tester.getSize(finder),
  );
  return result;
}

void _expectLightInk(
  _Raster raster,
  String name,
  Color background,
  String reason,
) {
  var alphaSum = 0;
  var legible = 0;
  final cores = <Color>[];
  for (var y = 0; y < raster.height; y++) {
    for (var x = 0; x < raster.width; x++) {
      final pixel = raster.pixel(x, y);
      alphaSum += raster.alpha(x, y);
      if (x == 0 || y == 0 || x == raster.width - 1 || y == raster.height - 1) {
        expect(
          raster.alpha(x, y),
          0,
          reason: '$reason needs a transparent inset',
        );
      }
      if (pixel.a >= 0.25) cores.add(pixel);
      final composite = Color.alphaBlend(pixel, background).computeLuminance();
      final surface = background.computeLuminance();
      if ((math.max(composite, surface) + 0.05) /
              (math.min(composite, surface) + 0.05) >=
          1.2) {
        legible++;
      }
    }
  }
  final (minCoverage, maxCoverage) = switch (name) {
    'plus' => (0.055, 0.12),
    // Six radius-1.5 dots use ~7.4% of a 24px canvas. At 16px their
    // antialiased cores must remain visible without merging the dots.
    'dots-six-vertical' => (0.055, 0.09),
    'refresh' => (0.10, 0.32),
    _ => (0.10, 0.34),
  };
  // Alpha-weighted area tolerates antialiasing while detecting missing strokes,
  // inflated ink and full-square fills. Not an all-shades WCAG assertion.
  expect(
    alphaSum / (255 * raster.width * raster.height),
    inInclusiveRange(minCoverage, maxCoverage),
    reason: reason,
  );
  expect(cores.length, greaterThanOrEqualTo(8), reason: reason);
  expect(
    legible,
    greaterThanOrEqualTo(4),
    reason: '$reason must not paint blank',
  );
  final span = [
    for (final channel in <double Function(Color)>[
      (c) => c.r,
      (c) => c.g,
      (c) => c.b,
    ])
      cores.map(channel).reduce(math.max) - cores.map(channel).reduce(math.min),
  ].reduce(math.max);
  // Straight RGBA excludes alpha variation as a source of fake palette variety.
  expect(
    span,
    greaterThan(5 / 255),
    reason: '$reason must not be a single tint',
  );
}

void _expectPlusSilhouette(_Raster raster) {
  var left = raster.width;
  var top = raster.height;
  var right = 0;
  var bottom = 0;
  final size = raster.width.toDouble();
  final halfStrokeWithFringe = size * 1.1 / 32 + 0.8;
  for (var y = 0; y < raster.height; y++) {
    for (var x = 0; x < raster.width; x++) {
      if (raster.alpha(x, y) >= 16) {
        left = math.min(left, x);
        top = math.min(top, y);
        right = math.max(right, x + 1);
        bottom = math.max(bottom, y + 1);
      }
      if ((x + 0.5 - size / 2).abs() > halfStrokeWithFringe &&
          (y + 0.5 - size / 2).abs() > halfStrokeWithFringe) {
        expect(
          raster.alpha(x, y),
          lessThanOrEqualTo(3),
          reason:
              'The four spaces between the plus arms must remain transparent',
        );
      }
    }
  }
  // The round 2.2px caps extend the [7,25] paths to [5.9,26.1].
  final inset = size * 5.9 / 32;
  expect(left, closeTo(inset, 1));
  expect(top, closeTo(inset, 1));
  expect(right, closeTo(size - inset, 1));
  expect(bottom, closeTo(size - inset, 1));
  expect((left + right) / 2, closeTo(size / 2, 0.6));
  expect((top + bottom) / 2, closeTo(size / 2, 0.6));
}

int _inkComponents(_Raster raster) {
  final seen = <int>{};
  var components = 0;
  for (var seed = 0; seed < raster.width * raster.height; seed++) {
    if (seen.contains(seed) ||
        raster.alpha(seed % raster.width, seed ~/ raster.width) < 32) {
      continue;
    }
    components++;
    final pending = [seed];
    seen.add(seed);
    while (pending.isNotEmpty) {
      final at = pending.removeLast();
      final x = at % raster.width;
      final y = at ~/ raster.width;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx;
          final ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= raster.width || ny >= raster.height) {
            continue;
          }
          final next = ny * raster.width + nx;
          if (raster.alpha(nx, ny) >= 32 && seen.add(next)) pending.add(next);
        }
      }
    }
  }
  return components;
}

Iterable<XmlElement> _artElements(XmlElement root) sync* {
  for (final child in root.childElements) {
    if (child.name.local == 'defs') continue;
    yield child;
    yield* _artElements(child);
  }
}

String? _inherited(XmlElement element, String attribute) {
  XmlNode? node = element;
  while (node is XmlElement) {
    final value = node.getAttribute(attribute);
    if (value != null) return value;
    node = node.parent;
  }
  return null;
}

String _body(XmlElement root) => root.childElements
    .where((element) => element.name.local != 'defs')
    .map((element) => element.toXmlString())
    .join();

// Independent expected strings are assertion oracles only, NEVER render inputs.
class _Artwork {
  const _Artwork(this.palette, this.body);
  final List<String> palette;
  final String body;
  String get svg =>
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" '
      'fill="none" stroke-linecap="round" stroke-linejoin="round">'
      '<defs><linearGradient id="main" x1="6" y1="3" x2="26" y2="29" '
      'gradientUnits="userSpaceOnUse"><stop stop-color="${palette[0]}"/>'
      '<stop offset="1" stop-color="${palette[1]}"/></linearGradient>'
      '<linearGradient id="accent" x1="8" y1="5" x2="24" y2="28" '
      'gradientUnits="userSpaceOnUse"><stop stop-color="${palette[2]}"/>'
      '<stop offset="1" stop-color="${palette[3]}"/></linearGradient>'
      '</defs>$body</svg>';
}

const _thinArtwork = {
  'plus': _Artwork(
    ['#7AA5A1', '#588D91', '#92A3BE', '#738AAF'],
    '<path d="M16 7v18" stroke="url(#main)" stroke-width="2.2"/>'
    '<path d="M7 16h18" stroke="url(#accent)" stroke-width="2.2"/>',
  ),
  'search': _Artwork(
    ['#82A6B7', '#59899F', '#AAA0C3', '#8176A8'],
    '<circle cx="13.5" cy="13.5" r="8" stroke="url(#main)" stroke-width="2.2"/>'
    '<path d="m19.5 19.5 7 7" stroke="url(#accent)" stroke-width="2.2"/>',
  ),
  'copy': _Artwork(
    ['#8FA9C2', '#648CAC', '#AEA0C5', '#8A79AC'],
    '<path d="M20 10V7a2 2 0 0 0-2-2H7a2 2 0 0 0-2 2v11a2 2 0 0 0 2 2h3" '
    'stroke="url(#main)" stroke-width="2"/>'
    '<rect x="11" y="11" width="16" height="16" rx="2.5" stroke="url(#accent)" stroke-width="2"/>',
  ),
  'refresh': _Artwork(
    ['#7EA8A3', '#578F96', '#A79DC1', '#8478AA'],
    '<path d="M6 13a10.5 10.5 0 0 1 18-6l2 3M26 4v6h-6" stroke="url(#main)" stroke-width="2.2"/>'
    '<path d="M26 19a10.5 10.5 0 0 1-18 6l-2-3M6 28v-6h6" stroke="url(#accent)" stroke-width="2.2"/>',
  ),
};

String _defaultSvg(String body) =>
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" '
    'fill="none" stroke="currentColor" stroke-width="1.75" '
    'stroke-linecap="round" stroke-linejoin="round">$body</svg>';

const _gripBody = '<g fill="currentColor" stroke="none">'
    '<circle cx="9" cy="6" r="1.5"/><circle cx="15" cy="6" r="1.5"/>'
    '<circle cx="9" cy="12" r="1.5"/><circle cx="15" cy="12" r="1.5"/>'
    '<circle cx="9" cy="18" r="1.5"/><circle cx="15" cy="18" r="1.5"/></g>';
final _vividGrip =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">'
    '<defs><linearGradient id="utility" x1="4" y1="3" x2="20" y2="21" '
    'gradientUnits="userSpaceOnUse"><stop stop-color="#789DA3"/>'
    '<stop offset="1" stop-color="#7E8FB1"/></linearGradient></defs>'
    '<g transform="scale(1.3333333333)" fill="none" stroke="url(#utility)" '
    'stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">'
    '${_gripBody.replaceAll('currentColor', 'url(#utility)')}</g></svg>';
const _utilityPalettes = {
  'dots-six-vertical': ['#789DA3', '#7E8FB1'],
  'arrow-left': ['#489ECC', '#9365CD'],
  'check': ['#43C7A7', '#3277BD'],
  'x': ['#EA7893', '#BD486D'],
  'bold': ['#AC79E0', '#527DDD'],
  'warning': ['#E5B44F', '#D16D55'],
};

const _originalArtwork = {
  'page': _Artwork(
    ['#E5F5FF', '#99C8EA', '#9FDCD6', '#4CAAA6'],
    '<path d="M8 3h11l8 8v16a3 3 0 0 1-3 3H8a3 3 0 0 1-3-3V6a3 3 0 0 1 3-3Z" fill="url(#main)"/>'
    '<path d="M19 3v6a2 2 0 0 0 2 2h6Z" fill="url(#accent)"/>'
    '<path d="M8 7v17" stroke="#FFFFFF" stroke-opacity=".5" stroke-width="1.2"/>'
    '<path d="M11 14h10M11 18h10M11 22h7" stroke="#507BA7" stroke-width="1.7"/>',
  ),
  'folder': _Artwork(
    ['#FFE790', '#F6AC35', '#87E7F6', '#2A9BCD'],
    '<path d="M3 9a3 3 0 0 1 3-3h6l3 4h11a3 3 0 0 1 3 3v12a3 3 0 0 1-3 3H6a3 3 0 0 1-3-3Z" fill="#E99132"/>'
    '<rect x="7" y="11" width="18" height="13" rx="2" fill="#FFF5DE"/>'
    '<path d="M10 14h12M10 17h9" stroke="#C6CED2" stroke-width="1.2"/>'
    '<path d="M5 15h23a2 2 0 0 1 2 2.3l-1.5 9a3 3 0 0 1-3 2.7H7a3 3 0 0 1-3-2.6L2.5 18a2.5 2.5 0 0 1 2.5-3Z" fill="url(#main)"/>'
    '<path d="M6 17h19" stroke="#FFF0B5" stroke-width="1.5"/>'
    '<rect x="11" y="21" width="10" height="4" rx="2" fill="url(#accent)"/>',
  ),
};
