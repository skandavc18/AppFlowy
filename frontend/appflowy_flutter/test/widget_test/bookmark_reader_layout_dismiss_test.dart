import 'dart:async';
import 'dart:ui' as ui;

import 'package:appflowy/plugins/collection/views/bookmark/bookmark_chrome.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_reader.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_controller.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_link.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_service.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_snapshot.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_controller.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

// Real BookmarkReader, native buttons/fields, showGeneralDialog and AppMenu.
// Only clipboard/snapshot IO, backend writes and the rendering leaves are faked.
// The leaves model retained query/scroll state, not WebView2 or Ctrl+F behavior.
const _appearances = ['light', 'dark', 'paper'];
const _away = Offset(4, 4);
const _urlA = 'https://bookmark-reader.invalid/article-a';
const _urlB = 'https://bookmark-reader.invalid/article-b';
late Map<String, dynamic> _translations;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fontFetching = GoogleFonts.config.allowRuntimeFetching;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    _translations = await const TestBundleAssetLoader().load(
      'assets/translations',
      const Locale('en', 'US'),
    );
    for (final family in _appearances
        .map((mode) => _theme(mode).textTheme.bodyMedium?.fontFamily)
        .whereType<String>()
        .toSet()) {
      await (FontLoader(family)
            ..addFont(
              rootBundle
                  .load('assets/google_fonts/DM_Sans/DMSans-Variable.ttf'),
            ))
          .load();
    }
  });
  tearDownAll(() => GoogleFonts.config.allowRuntimeFetching = fontFetching);

  for (final mode in _appearances) {
    for (final host in [
      (width: 1440.0, scale: 1.0),
      (width: 760.0, scale: 1.0),
      (width: 320.0, scale: 2.0),
    ]) {
      _test('$mode $host: close stays far right with hidden/revealed tools',
          (tester) async {
        final semantics = tester.ensureSemantics();
        final fixture = _Fixture();
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        try {
          await mouse.addPointer(location: _away);
          await fixture.mount(
            tester,
            mode: mode,
            width: host.width,
            scale: host.scale,
          );
          // Opening used a real mouse click; move that device off the new panel
          // before measuring the genuinely hidden toolbar state.
          await mouse.moveTo(_away);
          await _settle(tester);
          final panel = tester.getRect(_key('panel'));
          final close = _button('close');
          final closeBounds = tester.getRect(close);
          final headerBounds = tester.getRect(_key('header'));
          final titleBounds = tester.getRect(_key('title'));
          final tools = find.descendant(
            of: _key('tools'),
            matching: find.byType(TextButton),
          );
          expect(tools, findsNWidgets(7));
          final toolBounds = [
            for (var i = 0; i < 7; i++) tester.getRect(tools.at(i)),
          ];
          final closeState = tester.state(close);
          final leafState = tester.state(_probe('web'));
          final context = tester.element(close);
          expect(PaperTheme.isEnabled(context), mode == 'paper');
          expect(
            Theme.of(context).brightness,
            mode == 'dark' ? Brightness.dark : Brightness.light,
          );
          final panelWidget =
              tester.widget<BookmarkPanel>(find.byType(BookmarkPanel));
          expect(panelWidget.color, bookmarkThemeOf(context).panel);
          expect(
            panel.right - closeBounds.right,
            closeTo(BookmarkMetrics.space3, 0.01),
          );
          expect(
            titleBounds.left,
            closeTo(
              panel.left + BookmarkMetrics.space5 + 22 + BookmarkMetrics.space3,
              0.01,
            ),
          );
          expect(tester.getRect(_key('url')).left, titleBounds.left);
          expect(titleBounds.width, greaterThan(70));
          expect(
            find.descendant(
              of: _key('header'),
              matching: find.byType(Scrollable),
            ),
            findsNothing,
            reason: 'Close and tools must never depend on scrolling a header.',
          );
          _expectHidden(tester, true);
          expect(close.hitTestable(), findsOneWidget);
          final data = tester.getSemantics(close).getSemanticsData();
          expect(data.hasFlag(ui.SemanticsFlag.isButton), isTrue);
          expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
          expect(
            data.label,
            tester.widget<BookmarkAction>(_key('close')).tooltip,
          );

          for (final visible in [true, false, true, false]) {
            await mouse.moveTo(visible ? headerBounds.center : _away);
            await _settle(tester);
            _expectHidden(tester, !visible);
            expect(tester.getRect(close), closeBounds);
            expect(tester.getRect(_key('header')), headerBounds);
            expect(tester.getRect(_key('title')), titleBounds);
            expect(tester.state(close), same(closeState));
            expect(tester.state(_probe('web')), same(leafState));
            for (var i = 0; i < 7; i++) {
              final rect = tester.getRect(tools.at(i));
              expect(rect, toolBounds[i]);
              _expectInside(rect, headerBounds);
              expect(rect.right, lessThanOrEqualTo(closeBounds.left));
              expect(
                tools.at(i).hitTestable(),
                visible ? findsOneWidget : findsNothing,
              );
            }
            expect(
              tester.getRect(_button('aside-toggle')).right,
              closeTo(closeBounds.left - BookmarkMetrics.space1, 0.01),
            );
            expect(close.hitTestable(), findsOneWidget);
          }
          if (host.width == 320) {
            expect(tester.getRect(_key('stage')).width, panel.width);
            expect(tester.getSize(_key('aside')).width, greaterThan(200));
            expect(tester.getSize(_probe('web')).width, greaterThan(64));
            expect(
              tester.getRect(_button('aside-toggle')).top,
              greaterThan(closeBounds.bottom),
            );
          }
          await _click(tester, close);
          await _settle(tester);
          expect(fixture.readerPops, 1);
          expect(fixture.completions, 1);
          expect(fixture.service.writes, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          await mouse.removePointer();
          await fixture.dispose(tester);
          semantics.dispose();
        }
      });
    }

    for (final leaf in ['web', 'offline']) {
      _test(
          '$mode $leaf: resize/reveal/aside retain query, notes, tag and scroll',
          (tester) async {
        final fixture = _Fixture();
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        try {
          await mouse.addPointer(location: _away);
          await fixture.mount(tester, mode: mode);
          await _reveal(tester, mouse);
          if (leaf == 'offline') {
            await _click(tester, _button('offline'));
            await _settle(tester);
          }
          final probe = tester.state<_ReadingLeafState>(_probe(leaf));
          await tester.enterText(_probeField(leaf), 'query stays here');
          probe.query.selection =
              const TextSelection(baseOffset: 1, extentOffset: 5);
          await tester.enterText(
            _key('notes'),
            'Unsaved notes for only this page',
          );
          await tester.enterText(_key('tag-input'), 'unfinished-tag');
          final notes = tester.widget<TextField>(_key('notes')).controller!;
          final tags = tester.widget<TextField>(_key('tag-input')).controller!;
          notes.selection = const TextSelection(baseOffset: 2, extentOffset: 9);
          tags.selection = const TextSelection(baseOffset: 1, extentOffset: 4);
          FocusManager.instance.primaryFocus?.unfocus();
          await _pump(tester);
          final aside = tester
              .widget<SingleChildScrollView>(_key('aside-scroll'))
              .controller!;
          aside.jumpTo(40);
          probe.scroll.jumpTo(160);
          fixture.controller.setQuery('library query');
          await _pump(tester);
          final notesValue = notes.value;
          final tagValue = tags.value;
          final queryValue = probe.query.value;
          final notesElement = tester.element(_key('notes'));
          final tagElement = tester.element(_key('tag-input'));
          final position = probe.scroll.position;
          final asidePosition = aside.position;
          final snapshotReads = fixture.snapshots.reads.length;
          final builds = probe.builds;

          await mouse.moveTo(_away);
          await _pump(tester);
          await mouse.moveTo(tester.getCenter(_key('header')));
          await _pump(tester);
          expect(
            probe.builds,
            builds,
            reason: 'Hover must not rebuild the renderer.',
          );

          for (final host in [
            (width: 320.0, scale: 2.0),
            (width: 1100.0, scale: 1.0),
            (width: 640.0, scale: 2.0),
            (width: 1440.0, scale: 1.0),
          ]) {
            fixture.scale.value = host.scale;
            tester.view.physicalSize = Size(host.width, 900);
            await _pump(tester);
            await mouse.moveTo(tester.getCenter(_key('header')));
            await _pump(tester);
            for (final shown in [false, true]) {
              await _click(tester, _button('aside-toggle'));
              await _pump(tester);
              expect(tester.widget<Offstage>(_key('aside')).offstage, !shown);
              expect(
                tester.element(_key('notes', offstage: true)),
                same(notesElement),
              );
              expect(
                tester.element(_key('tag-input', offstage: true)),
                same(tagElement),
              );
              expect(
                tester
                    .widget<TextField>(_key('notes', offstage: true))
                    .controller,
                same(notes),
              );
              expect(
                tester
                    .widget<TextField>(_key('tag-input', offstage: true))
                    .controller,
                same(tags),
              );
              expect(notes.value, notesValue);
              expect(tags.value, tagValue);
              expect(tester.state(_probe(leaf)), same(probe));
              expect(probe.query.value, queryValue);
              expect(probe.scroll.position, same(position));
              expect(probe.scroll.offset, 160);
              expect(aside.position, same(asidePosition));
              expect(aside.offset, 40);
              expect(tester.getSize(_probe(leaf)).width, greaterThan(64));
              expect(tester.getSize(_probe(leaf)).height, greaterThan(64));
              expect(_button('close').hitTestable(), findsOneWidget);
            }
          }
          expect(fixture.controller.query, 'library query');
          expect(fixture.snapshots.reads.length, snapshotReads);
          expect(probe.disposed, isFalse);
          expect(fixture.controller.refreshes, isEmpty);
          await _click(tester, _button('close'));
          await _settle(tester);
          expect(probe.disposed, isTrue);
          expect(fixture.service.writes.single.metadata.notes, notesValue.text);
          expect(fixture.service.writes.single.view.id, 'a');
          expect(tester.takeException(), isNull);
        } finally {
          await mouse.removePointer();
          await fixture.dispose(tester);
        }
      });
    }
  }

  for (final edge in ['left', 'right', 'top', 'bottom']) {
    _test(
        '$edge margin: real mouse hit closes once and asynchronously flushes own notes',
        (tester) async {
      final fixture = _Fixture();
      final gate = fixture.service.writeGate = Completer<void>();
      try {
        await fixture.mount(tester);
        final original = fixture.controller.entryFor('a')!.metadata.toJson();
        final other = fixture.controller.entryFor('b')!.view.writeToBuffer();
        await tester.enterText(_key('notes'), 'Only A is changed');
        // Another selected library item is not the reader's edit destination.
        fixture.controller.openBookmark('b');
        final state = fixture.controller.state.toJson();
        final close = tester.widget<BookmarkAction>(_key('close')).onPressed!;
        final panel = tester.getRect(_key('panel'));
        final point = switch (edge) {
          'left' => Offset(panel.left - 4, panel.center.dy),
          'right' => Offset(panel.right + 4, panel.center.dy),
          'top' => Offset(panel.center.dx, panel.top - 4),
          _ => Offset(panel.center.dx, panel.bottom + 4),
        };
        final outside = tester.renderObject<RenderBox>(_key('dismiss-area'));
        final hit = tester.hitTestOnBinding(point);
        expect(
          hit.path.any((entry) => identical(entry.target, outside)),
          isTrue,
        );
        final panelBox = tester.renderObject<RenderBox>(_key('panel'));
        expect(
          hit.path.any((entry) => identical(entry.target, panelBox)),
          isFalse,
        );
        await tester.tapAt(point, kind: PointerDeviceKind.mouse);
        await _settle(tester);
        expect(find.byType(BookmarkReader), findsNothing);
        expect(fixture.readerPops, 1);
        expect(fixture.completions, 1);
        expect(fixture.backgroundClicks, 0);
        expect(fixture.service.writes, hasLength(1));
        expect(
          fixture.service.completed,
          0,
          reason: 'Closing must not await backend IO.',
        );
        final write = fixture.service.writes.single;
        expect(write.view.id, 'a');
        expect(
          write.metadata.toJson(),
          {...original, 'notes': 'Only A is changed'},
        );
        expect(fixture.controller.entryFor('b')!.view.writeToBuffer(), other);
        expect(fixture.controller.state.toJson(), state);
        close();
        await tester.pump(const Duration(seconds: 1));
        expect(fixture.readerPops, 1);
        expect(fixture.service.writes, hasLength(1));
        gate.complete();
        await _pump(tester);
        expect(fixture.service.completed, 1);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    });
  }

  for (final button in [kSecondaryButton, kTertiaryButton]) {
    _test('mouse button $button: outside release closes and flushes only once',
        (tester) async {
      final fixture = _Fixture();
      TestGesture? pointer;
      try {
        await fixture.mount(tester);
        await tester.enterText(_key('notes'), 'Mouse release draft');
        pointer = await tester.startGesture(
          _away,
          kind: PointerDeviceKind.mouse,
          buttons: button,
        );
        await _pump(tester);
        expect(fixture.readerPops, 0);
        expect(fixture.service.writes, isEmpty);
        await pointer.up();
        await _settle(tester);
        expect(find.byType(BookmarkReader), findsNothing);
        expect(fixture.readerPops, 1);
        expect(fixture.completions, 1);
        expect(fixture.backgroundClicks, 0);
        expect(
          fixture.service.writes.single.metadata.notes,
          'Mouse release draft',
        );
        await tester.pump(const Duration(seconds: 1));
        expect(fixture.service.writes, hasLength(1));
        expect(tester.takeException(), isNull);
      } finally {
        await pointer?.removePointer();
        await fixture.dispose(tester);
      }
    });
  }

  _test(
      'panel padding, unhandled page pointers, notes and real tools stay inside',
      (tester) async {
    String? clipboardText;
    final clipboardWrites = <String>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    // Exercise the real Copy action without depending on the test runner's
    // native clipboard. Reads return only what a completed write supplied.
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          final text =
              (call.arguments as Map<Object?, Object?>)['text'] as String;
          clipboardText = text;
          clipboardWrites.add(text);
          return null;
        case 'Clipboard.getData':
          return clipboardText == null ? null : {'text': clipboardText};
        case 'Clipboard.hasStrings':
          return {'value': clipboardText?.isNotEmpty ?? false};
        default:
          return null;
      }
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final fixture = _Fixture();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    try {
      await mouse.addPointer(location: _away);
      await fixture.mount(tester);
      final panel = tester.getRect(_key('panel'));
      final page = tester.getRect(_probe('web'));
      final outside = tester.renderObject<RenderBox>(_key('dismiss-area'));
      for (final point in [
        Offset(panel.left + 2, panel.center.dy),
        Offset(panel.right - 2, panel.center.dy),
        Offset(panel.center.dx, panel.top + 2),
        Offset(panel.center.dx, panel.bottom - 2),
        page.center,
        tester.getCenter(_key('notes')),
        tester.getCenter(_key('tag-input')),
      ]) {
        expect(
          tester.hitTestOnBinding(point).path.any(
                (entry) => identical(entry.target, outside),
              ),
          isFalse,
        );
        await tester.tapAt(point, kind: PointerDeviceKind.mouse);
        await _pump(tester);
        expect(fixture.readerPops, 0);
      }
      await _reveal(tester, mouse);
      await _click(tester, _actionWithIcon(Icons.link_rounded));
      await _pump(tester);
      ClipboardData? copiedLink;
      var readCompleted = false;
      final read = Clipboard.getData(Clipboard.kTextPlain).then<void>((data) {
        copiedLink = data;
        readCompleted = true;
      });
      // Start the fake-zone Future before pumping its channel completion;
      // directly awaiting a platform response here can strand the whole test.
      await _pump(tester);
      expect(
        readCompleted,
        isTrue,
        reason: 'The clipboard response must complete before it is awaited.',
      );
      await read;
      expect(copiedLink?.text, _urlA);
      expect(clipboardWrites, [_urlA]);
      await _click(tester, _button('aside-toggle'));
      await _pump(tester);
      await tester.tapAt(
        tester.getCenter(_probe('web')),
        kind: PointerDeviceKind.mouse,
      );
      await _pump(tester);
      expect(fixture.readerPops, 0);
      expect(fixture.service.writes, isEmpty);
      expect(fixture.backgroundClicks, 0);
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await fixture.dispose(tester);
    }
  });

  _test('shared AppMenu submenu owns the first outside click, not the reader',
      (tester) async {
    final fixture = _Fixture();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    try {
      await mouse.addPointer(location: _away);
      await fixture.mount(tester);
      await _click(tester, find.byKey(const ValueKey('probe-web-menu')));
      await _settle(tester);
      await _click(tester, find.text('Nested options'));
      await _settle(tester);
      expect(find.byType(AppMenuSurface), findsNWidgets(2));
      await _click(tester, find.text('Keep menu open'));
      await _pump(tester);
      expect(find.byType(AppMenuSurface), findsNWidgets(2));
      await mouse.moveTo(_away);
      await _pump(tester);
      _expectHidden(tester, false);
      await tester.tapAt(_away, kind: PointerDeviceKind.mouse);
      await _settle(tester);
      expect(find.byType(AppMenuSurface), findsNothing);
      expect(find.byType(BookmarkReader), findsOneWidget);
      expect(fixture.readerPops, 0);
      expect(fixture.service.writes, isEmpty);
      await tester.tapAt(_away, kind: PointerDeviceKind.mouse);
      await _settle(tester);
      expect(fixture.readerPops, 1);
      expect(fixture.completions, 1);
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await fixture.dispose(tester);
    }
  });

  _test(
      'a captured Close cannot pop a newer dialog; its inside click stays inside',
      (tester) async {
    final fixture = _Fixture();
    try {
      await fixture.mount(tester);
      final close = tester.widget<BookmarkAction>(_key('close')).onPressed!;
      final popup = _showNewerDialog(tester);
      await _settle(tester);
      close();
      await _click(tester, find.text('Newer popup'));
      await _pump(tester);
      expect(find.text('Newer popup'), findsOneWidget);
      expect(fixture.observer.popped, isEmpty);
      await tester.tapAt(_away, kind: PointerDeviceKind.mouse);
      await _settle(tester);
      await popup;
      expect(fixture.readerPops, 0);
      expect(find.byType(BookmarkReader), findsOneWidget);
      await tester.tapAt(_away, kind: PointerDeviceKind.mouse);
      await _settle(tester);
      expect(fixture.readerPops, 1);
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
    }
  });

  for (final button in [kPrimaryButton, kSecondaryButton, kTertiaryButton]) {
    _test(
        'outside button $button released after a newer popup opens dismisses neither',
        (tester) async {
      final fixture = _Fixture();
      TestGesture? pointer;
      try {
        await fixture.mount(tester);
        pointer = await tester.startGesture(
          _away,
          kind: PointerDeviceKind.mouse,
          buttons: button,
        );
        await tester.pump(const Duration(milliseconds: 120));
        unawaited(_showNewerDialog(tester));
        await _settle(tester);
        await pointer.up();
        await _settle(tester);
        expect(find.text('Newer popup'), findsOneWidget);
        expect(find.byType(BookmarkReader), findsOneWidget);
        expect(fixture.observer.popped, isEmpty);
        expect(fixture.service.writes, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await pointer?.removePointer();
        await fixture.dispose(tester);
      }
    });
  }

  _test('Escape retains the route behavior and flushes its pending notes once',
      (tester) async {
    final fixture = _Fixture();
    try {
      await fixture.mount(tester);
      await tester.enterText(_key('notes'), 'Escape draft');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(tester);
      expect(find.byType(BookmarkReader), findsNothing);
      expect(fixture.readerPops, 1);
      expect(fixture.service.writes.single.metadata.notes, 'Escape draft');
      await tester.pump(const Duration(seconds: 1));
      expect(fixture.service.writes, hasLength(1));
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
    }
  });

  _test(
      'explicit readOnly keeps reading/copy/close but disables bookmark writes',
      (tester) async {
    final fixture = _Fixture(readOnly: true, unread: true);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    try {
      await mouse.addPointer(location: _away);
      await fixture.mount(tester);
      expect(tester.widget<TextField>(_key('notes')).readOnly, isTrue);
      expect(tester.widget<TextField>(_key('tag-input')).readOnly, isTrue);
      await _reveal(tester, mouse);
      for (final icon in [Icons.star_outline_rounded, Icons.download_rounded]) {
        expect(
          tester.widget<TextButton>(_actionWithIcon(icon)).onPressed,
          isNull,
        );
      }
      await _click(tester, _button('offline'));
      await _pump(tester);
      final probe = tester.state<_ReadingLeafState>(_probe('offline'));
      probe.scroll.jumpTo(160);
      await _pump(tester);
      expect(fixture.controller.progress, isEmpty);
      expect(fixture.controller.refreshes, isEmpty);
      expect(
        fixture.controller.entryFor('a')!.metadata.readState,
        BookmarkReadState.unread,
      );
      await tester.tapAt(_away, kind: PointerDeviceKind.mouse);
      await _settle(tester);
      expect(fixture.service.writes, isEmpty);
      expect(fixture.readerPops, 1);
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await fixture.dispose(tester);
    }
  });

  _test(
      'revoking write access before debounce/dispose never writes a pending draft',
      (tester) async {
    final fixture = _Fixture();
    try {
      await fixture.mount(tester, rebindable: true);
      await tester.enterText(_key('notes'), 'Draft before access changed');
      fixture.binding.value = fixture.reader(readOnly: true);
      await _pump(tester);
      await tester.pump(const Duration(milliseconds: 650));
      expect(fixture.service.writes, isEmpty);
      expect(
        tester.widget<TextField>(_key('notes')).controller!.text,
        'Draft before access changed',
      );
      await tester.tapAt(_away, kind: PointerDeviceKind.mouse);
      await _settle(tester);
      expect(fixture.service.writes, isEmpty);
      expect(fixture.readerPops, 1);
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
    }
  });

  _test('a live guard rejects captured edits and progress without a rebuild',
      (tester) async {
    var editable = true;
    final fixture = _Fixture(canEdit: () => editable);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    try {
      await mouse.addPointer(location: _away);
      await fixture.mount(tester, rebindable: true);
      await _reveal(tester, mouse);
      await _click(tester, _button('offline'));
      await _pump(tester);
      final leaf = tester.state<_ReadingLeafState>(_probe('offline'));
      final notes = tester.widget<TextField>(_key('notes'));
      final tags = tester.widget<TextField>(_key('tag-input'));
      final star = tester
          .widget<TextButton>(_actionWithIcon(Icons.star_outline_rounded))
          .onPressed!;
      final download = tester
          .widget<TextButton>(_actionWithIcon(Icons.download_rounded))
          .onPressed!;
      final chips = tester.widgetList<BookmarkChip>(find.byType(BookmarkChip));
      final removeTag =
          chips.firstWhere((chip) => chip.onRemove != null).onRemove!;
      final read = chips.lastWhere((chip) => chip.onTap != null).onTap!;
      await tester.enterText(_key('notes'), 'Pending guarded draft');
      await tester.enterText(_key('tag-input'), 'pending-tag');
      final original = fixture.controller.entryFor('a')!.view.writeToBuffer();

      editable = false;
      // These handlers were built while writable. Do not rebuild their reader
      // before invoking them; a disabled button alone is not authorization.
      star();
      download();
      removeTag();
      read();
      tags.onSubmitted!('late tag');
      notes.onChanged!('late change');
      leaf.scroll.jumpTo(160);
      expect(tags.controller!.text, 'pending-tag');
      await tester.pump(const Duration(milliseconds: 650));
      expect(fixture.service.writes, isEmpty);
      expect(fixture.controller.progress, isEmpty);
      expect(fixture.controller.refreshes, isEmpty);
      expect(fixture.controller.entryFor('a')!.view.writeToBuffer(), original);
      expect(notes.controller!.text, 'Pending guarded draft');
      await tester.tapAt(_away, kind: PointerDeviceKind.mouse);
      await _settle(tester);
      // Retained callbacks must also be harmless after reader disposal.
      editable = true;
      star();
      download();
      removeTag();
      read();
      tags.onSubmitted!('after close');
      notes.onChanged!('after close');
      await tester.pump(const Duration(seconds: 1));
      expect(fixture.readerPops, 1);
      expect(fixture.service.writes, isEmpty);
      expect(fixture.controller.refreshes, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await fixture.dispose(tester);
    }
  });

  _test('a direct live guard prevents the initial unread-to-reading write',
      (tester) async {
    final fixture = _Fixture(canEdit: () => false, unread: true);
    try {
      await fixture.mount(tester, rebindable: true);
      expect(
        tester.widget<BookmarkReader>(find.byType(BookmarkReader)).readOnly,
        isFalse,
      );
      expect(tester.widget<TextField>(_key('notes')).readOnly, isTrue);
      expect(tester.widget<TextField>(_key('tag-input')).readOnly, isTrue);
      expect(
        fixture.controller.entryFor('a')!.metadata.readState,
        BookmarkReadState.unread,
      );
      await tester.tapAt(_away, kind: PointerDeviceKind.mouse);
      await _settle(tester);
      expect(fixture.service.writes, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
    }
  });

  _test('closing untouched notes never overwrites a newer controller value',
      (tester) async {
    final fixture = _Fixture();
    try {
      await fixture.mount(tester);
      fixture.controller.setViews([
        _view('a', notes: 'Updated elsewhere'),
        _view('b', url: _urlB),
      ]);
      await _pump(tester);
      await tester.tapAt(_away, kind: PointerDeviceKind.mouse);
      await _settle(tester);
      expect(
        fixture.controller.entryFor('a')!.metadata.notes,
        'Updated elsewhere',
      );
      expect(fixture.service.writes, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
    }
  });

  for (final change in ['controller', 'entry']) {
    _test('$change rebind flushes the old draft only to its original owner',
        (tester) async {
      final fixture = _Fixture();
      try {
        await fixture.mount(tester, rebindable: true);
        await tester.enterText(
          _key('notes'),
          'Owned by the old reader binding',
        );
        final next = change == 'controller'
            ? fixture.addController()
            : fixture.controller;
        fixture.binding.value = fixture.reader(
          controller: next,
          entryId: change == 'entry' ? 'b' : 'a',
        );
        await _pump(tester);
        expect(fixture.service.writes.single.view.id, 'a');
        expect(
          fixture.service.writes.single.metadata.notes,
          'Owned by the old reader binding',
        );
        expect(
          tester.widget<TextField>(_key('notes')).controller!.text,
          'Original notes',
        );
        if (change == 'controller') {
          expect(fixture.controller.hasRegisteredListeners, isFalse);
          expect(next.hasRegisteredListeners, isTrue);
          expect(next.service.writes, isEmpty);
        }
        await tester.tapAt(_away, kind: PointerDeviceKind.mouse);
        await _settle(tester);
        expect(fixture.service.writes, hasLength(1));
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    });
  }

  for (final change in ['controller', 'entry']) {
    _test('$change rebind cannot flush a revoked old owner through a new grant',
        (tester) async {
      var oldOwnerEditable = true;
      final fixture = _Fixture(canEdit: () => oldOwnerEditable);
      try {
        await fixture.mount(tester, rebindable: true);
        await tester.enterText(_key('notes'), 'Revoked old owner draft');
        final next = change == 'controller'
            ? fixture.addController()
            : fixture.controller;
        oldOwnerEditable = false;
        fixture.binding.value = fixture.reader(
          controller: next,
          entryId: change == 'entry' ? 'b' : 'a',
          canEdit: () => true,
        );
        await _pump(tester);
        expect(fixture.service.writes, isEmpty);
        expect(next.service.writes, isEmpty);
        expect(
          tester.widget<TextField>(_key('notes')).controller!.text,
          'Original notes',
        );
        expect(tester.widget<TextField>(_key('notes')).readOnly, isFalse);
        await tester.tapAt(_away, kind: PointerDeviceKind.mouse);
        await _settle(tester);
        await tester.pump(const Duration(seconds: 1));
        expect(fixture.service.writes, isEmpty);
        expect(next.service.writes, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    });
  }

  _test(
      'retargeting the same id never flushes its old URL draft into the new source',
      (tester) async {
    final fixture = _Fixture();
    try {
      await fixture.mount(tester);
      await tester.enterText(_key('notes'), 'Old source draft');
      fixture.controller
          .setViews([_view('a', url: _urlB, notes: 'New source notes')]);
      await _pump(tester);
      expect(
        tester.widget<TextField>(_key('notes')).controller!.text,
        'New source notes',
      );
      await tester.pump(const Duration(milliseconds: 650));
      expect(
        fixture.service.writes,
        isEmpty,
        reason: 'The old source debounce must be cancelled, not retargeted.',
      );
      await tester.tapAt(_away, kind: PointerDeviceKind.mouse);
      await _settle(tester);
      expect(fixture.service.writes, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
    }
  });

  for (final change in ['controller', 'path', 'source']) {
    _test('$change change rejects a late snapshot belonging to the old request',
        (tester) async {
      final fixture = _Fixture();
      final oldRead = fixture.snapshots.defer('snapshot-a');
      try {
        await fixture.mount(tester, rebindable: true);
        expect(_probe('web'), findsNothing);
        if (change == 'controller') {
          final next = fixture.addController(snapshotPath: 'snapshot-new');
          fixture.binding.value = fixture.reader(controller: next);
        } else {
          fixture.controller.setViews([
            _view(
              'a',
              url: change == 'source' ? _urlB : _urlA,
              snapshotPath: 'snapshot-new',
            ),
          ]);
        }
        await _pump(tester);
        expect(_probe('web'), findsOneWidget);
        expect(
          tester.widget<BookmarkAction>(_key('offline')).onPressed,
          isNull,
        );
        final leaf = tester.state(_probe('web'));
        oldRead.complete(_snapshot('snapshot-a'));
        await _pump(tester);
        expect(
          tester.widget<BookmarkAction>(_key('offline')).onPressed,
          isNull,
        );
        expect(tester.state(_probe('web')), same(leaf));
        expect(fixture.snapshots.reads, ['snapshot-a', 'snapshot-new']);
        expect(fixture.service.writes, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    });
  }

  for (final change in ['readOnly', 'canEdit', 'controller', 'dismissed']) {
    _test(
        'late download after $change cannot reload or switch the current reader',
        (tester) async {
      var editable = true;
      final fixture = _Fixture(canEdit: () => editable);
      final gate = fixture.controller.refreshGate = Completer<void>();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      try {
        await mouse.addPointer(location: _away);
        await fixture.mount(tester, rebindable: true);
        await _reveal(tester, mouse);
        await _click(tester, _actionWithIcon(Icons.download_rounded));
        await _pump(tester);
        expect(fixture.controller.refreshes, ['a']);
        if (change == 'readOnly') {
          fixture.binding.value = fixture.reader(readOnly: true);
        } else if (change == 'canEdit') {
          editable = false;
        } else if (change == 'controller') {
          fixture.binding.value =
              fixture.reader(controller: fixture.addController());
        } else {
          await tester.tapAt(_away, kind: PointerDeviceKind.mouse);
          await _settle(tester);
        }
        await _pump(tester);
        final reads = fixture.snapshots.reads.length;
        gate.complete();
        await _pump(tester);
        expect(fixture.snapshots.reads.length, reads);
        expect(_probe('offline'), findsNothing);
        expect(
          _probe('web'),
          change == 'dismissed' ? findsNothing : findsOneWidget,
        );
        expect(fixture.service.writes, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await fixture.dispose(tester);
      }
    });
  }

  _test('revocation during a snapshot read prevents the late offline switch',
      (tester) async {
    var editable = true;
    final fixture = _Fixture(canEdit: () => editable);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    try {
      await mouse.addPointer(location: _away);
      await fixture.mount(tester, rebindable: true);
      await _reveal(tester, mouse);
      final leaf = tester.state(_probe('web'));
      final pendingRead = fixture.snapshots.defer('snapshot-a');
      await _click(tester, _actionWithIcon(Icons.download_rounded));
      await _pump(tester);
      expect(fixture.snapshots.reads, ['snapshot-a', 'snapshot-a']);
      editable = false;
      pendingRead.complete(_snapshot('snapshot-a'));
      await _pump(tester);
      expect(_probe('offline'), findsNothing);
      expect(tester.state(_probe('web')), same(leaf));
      expect(fixture.service.writes, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await fixture.dispose(tester);
    }
  });

  _test('standalone retains its non-dismissible, always-visible chrome',
      (tester) async {
    final fixture = _Fixture();
    try {
      await fixture.mount(tester, standalone: true, width: 320, scale: 2);
      expect(_key('dismiss-area'), findsNothing);
      expect(tester.widget<TextButton>(_button('close')).onPressed, isNull);
      _expectHidden(tester, false);
      await tester.tapAt(_away, kind: PointerDeviceKind.mouse);
      await _pump(tester);
      expect(find.byType(BookmarkReader), findsOneWidget);
      expect(fixture.observer.popped, isEmpty);
      expect(fixture.service.writes, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
    }
  });
}

void _test(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(
      name,
      body,
      timeout: const Timeout(Duration(seconds: 30)),
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

Finder _key(String suffix, {bool offstage = false}) => find.byKey(
      ValueKey('bookmark-reader-$suffix'),
      skipOffstage: !offstage,
    );

Finder _button(String suffix) => find.descendant(
      of: _key(suffix),
      matching: find.byType(TextButton),
    );

Finder _actionWithIcon(IconData icon) => find.descendant(
      of: find.byWidgetPredicate(
        (widget) => widget is BookmarkAction && widget.icon == icon,
      ),
      matching: find.byType(TextButton),
    );

Finder _probe(String kind) => find.byKey(ValueKey('probe-$kind'));
Finder _probeField(String kind) => find.byKey(ValueKey('probe-$kind-query'));

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

Future<void> _settle(WidgetTester tester) async {
  await _pump(tester);
  await tester.pump(const Duration(milliseconds: 221));
  await tester.pump();
}

Future<void> _reveal(WidgetTester tester, TestGesture mouse) async {
  await mouse.moveTo(tester.getCenter(_key('header')));
  await _settle(tester);
}

Future<void> _click(WidgetTester tester, Finder finder) async {
  expect(finder.hitTestable(), findsOneWidget);
  // Fresh pointer IDs avoid the double-tap recognizer holding a reused mouse.
  await tester.tapAt(tester.getCenter(finder), kind: PointerDeviceKind.mouse);
}

void _expectHidden(WidgetTester tester, bool hidden) {
  final ignored = find
      .descendant(of: _key('tools'), matching: find.byType(IgnorePointer))
      .first;
  final faded = find
      .descendant(of: _key('tools'), matching: find.byType(AnimatedOpacity))
      .first;
  expect(tester.widget<IgnorePointer>(ignored).ignoring, hidden);
  expect(
    tester.renderObject<RenderAnimatedOpacity>(faded).opacity.value,
    hidden ? 0 : 1,
  );
}

void _expectInside(Rect child, Rect parent) {
  expect(child.width, greaterThan(0));
  expect(child.height, greaterThan(0));
  expect(child.left, greaterThanOrEqualTo(parent.left - 0.01));
  expect(child.top, greaterThanOrEqualTo(parent.top - 0.01));
  expect(child.right, lessThanOrEqualTo(parent.right + 0.01));
  expect(child.bottom, lessThanOrEqualTo(parent.bottom + 0.01));
}

Future<void> _showNewerDialog(WidgetTester tester) => showDialog<void>(
      context: tester.element(_key('close')),
      builder: (_) => const AlertDialog(content: Text('Newer popup')),
    );

ThemeData _theme(String mode) => DesktopAppearance()
    .getThemeData(
      mode == 'paper'
          ? AppTheme.builtins
              .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
          : AppTheme.fallback,
      mode == 'dark' ? Brightness.dark : Brightness.light,
      'DM Sans',
      builtInCodeFontFamily,
    )
    .copyWith(platform: TargetPlatform.windows);

class _Translations extends AssetLoader {
  const _Translations();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) =>
      Future.value(_translations);
}

class _Fixture {
  _Fixture({this.readOnly = false, this.canEdit, bool unread = false}) {
    controller = _ReaderController(service)
      ..setViews([
        _view('a', unread: unread),
        _view('b', url: _urlB),
      ]);
    controllers.add(controller);
    binding = ValueNotifier(reader(readOnly: readOnly));
  }

  final bool readOnly;
  final bool Function()? canEdit;
  final collection = _ReaderCollection();
  final service = _RecordingService();
  final snapshots = _Snapshots();
  final scale = ValueNotifier(1.0);
  final observer = _PopObserver();
  final controllers = <_ReaderController>[];
  late final _ReaderController controller;
  late final ValueNotifier<BookmarkReader> binding;
  Route<dynamic>? route;
  int completions = 0;
  int backgroundClicks = 0;

  int get readerPops =>
      observer.popped.where((item) => identical(item, route)).length;

  _ReaderController addController({String snapshotPath = 'snapshot-a'}) {
    final next = _ReaderController(_RecordingService())
      ..setViews(
        [_view('a', snapshotPath: snapshotPath), _view('b', url: _urlB)],
      );
    controllers.add(next);
    return next;
  }

  BookmarkReader reader({
    BookmarkController? controller,
    String entryId = 'a',
    bool readOnly = false,
    bool standalone = false,
    bool Function()? canEdit,
  }) =>
      BookmarkReader(
        entryId: entryId,
        controller: controller ?? this.controller,
        snapshots: snapshots,
        readOnly: readOnly,
        canEdit: canEdit ?? this.canEdit,
        standalone: standalone,
        webPageBuilder: _webLeaf,
        offlinePreviewBuilder: _offlineLeaf,
      );

  Future<void> mount(
    WidgetTester tester, {
    String mode = 'paper',
    double width = 1440,
    double scale = 1,
    bool rebindable = false,
    bool standalone = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    this.scale.value = scale;
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        startLocale: const Locale('en', 'US'),
        fallbackLocale: const Locale('en', 'US'),
        saveLocale: false,
        path: 'assets/translations',
        assetLoader: const _Translations(),
        child: Builder(
          builder: (context) => MaterialApp(
            theme: _theme(mode),
            themeAnimationDuration: Duration.zero,
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            navigatorObservers: [observer],
            builder: (context, child) => ValueListenableBuilder<double>(
              valueListenable: this.scale,
              child: child,
              builder: (context, value, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(value)),
                child: TooltipVisibility(visible: false, child: child!),
              ),
            ),
            home: Scaffold(
              body: standalone
                  ? reader(readOnly: readOnly, standalone: true)
                  : Builder(
                      builder: (context) => GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => backgroundClicks++,
                        child: Center(
                          child: TextButton(
                            key: const ValueKey('open-reader'),
                            onPressed: () {
                              final Future<void> result;
                              if (rebindable) {
                                result = showGeneralDialog<void>(
                                  context: context,
                                  barrierDismissible: true,
                                  barrierLabel: 'Reader',
                                  transitionDuration: BookmarkMetrics.reveal,
                                  pageBuilder: (_, __, ___) =>
                                      ValueListenableBuilder<BookmarkReader>(
                                    valueListenable: binding,
                                    builder: (_, reader, __) => reader,
                                  ),
                                );
                              } else {
                                // Exercise the production opening function, not
                                // a hand-made dismiss callback or test scaffold.
                                result = openBookmarkReader(
                                  context: context,
                                  entry: controller.entryFor('a')!,
                                  controller: controller,
                                  collection: collection,
                                  readOnly: readOnly,
                                  snapshots: snapshots,
                                  webPageBuilder: _webLeaf,
                                  offlinePreviewBuilder: _offlineLeaf,
                                );
                              }
                              unawaited(
                                result.whenComplete(() => completions++),
                              );
                            },
                            child: const Text('Open reader'),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
    await _settle(tester);
    if (!standalone) {
      await _click(tester, find.byKey(const ValueKey('open-reader')));
      await _settle(tester);
      route = ModalRoute.of(tester.element(find.byType(BookmarkReader)));
    }
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    for (final controller in controllers) {
      final refresh = controller.refreshGate;
      if (refresh != null && !refresh.isCompleted) refresh.complete();
      final write = controller.service.writeGate;
      if (write != null && !write.isCompleted) write.complete();
      controller.dispose();
    }
    for (final pending in snapshots.pending.values) {
      if (!pending.isCompleted) pending.complete();
    }
    await _pump(tester);
    binding.dispose();
    scale.dispose();
    collection.explorer.dispose();
  }
}

class _ReaderCollection extends Fake implements CollectionViewContext {
  @override
  final collectionView = ViewPB(id: 'bookmark-library');

  @override
  late final explorer = WorkspaceExplorerController(
    root: collectionView,
    listenForUpdates: false,
  );
}

class _PopObserver extends NavigatorObserver {
  final popped = <Route<dynamic>>[];

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      popped.add(route);
}

class _RecordingService extends BookmarkService {
  final writes = <({ViewPB view, BookmarkMetadata metadata})>[];
  Completer<void>? writeGate;
  int completed = 0;

  @override
  Future<FlowyResult<ViewPB, FlowyError>> updateMetadata({
    required ViewPB view,
    required BookmarkMetadata metadata,
  }) async {
    final original = ViewPB.fromBuffer(view.writeToBuffer());
    writes.add((view: original, metadata: metadata));
    await writeGate?.future;
    completed++;
    return FlowyResult.success(
      ViewPB.fromBuffer(original.writeToBuffer())
        ..extra = metadata.mergeIntoExtra(original.extra),
    );
  }
}

class _ReaderController extends BookmarkController {
  _ReaderController(this.service) : super(service: service);

  final _RecordingService service;
  final refreshes = <String>[];
  final progress = <(String, double)>[];
  Completer<void>? refreshGate;

  bool get hasRegisteredListeners => hasListeners;

  @override
  Future<void> refresh(
    BookmarkEntry entry, {
    bool snapshot = false,
    bool force = true,
  }) async {
    refreshes.add(entry.id);
    await refreshGate?.future;
  }

  @override
  Future<void> recordProgress(BookmarkEntry entry, double value) async {
    progress.add((entry.id, value));
  }
}

class _Snapshots extends BookmarkSnapshotStore {
  final reads = <String?>[];
  final pending = <String, Completer<BookmarkSnapshot?>>{};

  Completer<BookmarkSnapshot?> defer(String path) =>
      pending[path] = Completer<BookmarkSnapshot?>();

  @override
  Future<BookmarkSnapshot?> read(String? directoryPath) {
    reads.add(directoryPath);
    return pending[directoryPath]?.future ??
        Future.value(
          directoryPath == 'snapshot-a' ? _snapshot(directoryPath!) : null,
        );
  }
}

BookmarkSnapshot _snapshot(String directory) => BookmarkSnapshot(
      directory: directory,
      savedAt: DateTime(2026, 9, 23),
      bytes: 4096,
      articlePath: '$directory/article.md',
    );

ViewPB _view(
  String id, {
  String url = _urlA,
  String notes = 'Original notes',
  String snapshotPath = 'snapshot-a',
  bool unread = false,
}) =>
    ViewPB(
      id: id,
      name: 'A saved article with a deliberately long title for narrow hosts',
      layout: ViewLayoutPB.Document,
      extra: BookmarkMetadata(
        url: url,
        notes: notes,
        tags: const ['saved'],
        snapshotPath: snapshotPath,
        readState:
            unread ? BookmarkReadState.unread : BookmarkReadState.reading,
        // Tall facts keep the actual aside scrollable at every tested host.
        author: List.filled(80, 'A writer').join('\n'),
      ).mergeIntoExtra('{"unrelated":{"keep":true}}'),
    );

Widget _webLeaf(BuildContext context) {
  final reader = context.findAncestorWidgetOfExactType<BookmarkReader>()!;
  return _ReadingLeaf(
    key: const ValueKey('probe-web'),
    kind: 'web',
    source: reader.controller.entryFor(reader.entryId)!.url,
  );
}

Widget _offlineLeaf(BuildContext context) {
  final reader = context.findAncestorWidgetOfExactType<BookmarkReader>()!;
  return _ReadingLeaf(
    key: const ValueKey('probe-offline'),
    kind: 'offline',
    source: reader.controller.entryFor(reader.entryId)!.metadata.snapshotPath!,
  );
}

class _ReadingLeaf extends StatefulWidget {
  const _ReadingLeaf({
    super.key,
    required this.kind,
    required this.source,
  });
  final String kind;
  final String source;

  @override
  State<_ReadingLeaf> createState() => _ReadingLeafState();
}

class _ReadingLeafState extends State<_ReadingLeaf> {
  final query = TextEditingController();
  final scroll = ScrollController();
  int builds = 0;
  bool disposed = false;

  @override
  void dispose() {
    disposed = true;
    query.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    builds++;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                key: ValueKey('probe-${widget.kind}-query'),
                controller: query,
                decoration: const InputDecoration(isDense: true),
              ),
            ),
            Builder(
              builder: (anchor) => TextButton(
                key: ValueKey('probe-${widget.kind}-menu'),
                onPressed: () => unawaited(
                  showAppMenuForWidget<void>(
                    context: anchor,
                    entries: const [
                      AppMenuItem(
                        label: 'Nested options',
                        submenu: [
                          AppMenuItem(
                            label: 'Keep menu open',
                            closeOnSelect: false,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                child: const Text('Menu'),
              ),
            ),
          ],
        ),
        Expanded(
          // No tap handler: an unhandled renderer click still belongs INSIDE
          // the panel. Dismissal must not depend on web content forwarding taps.
          child: ListView.builder(
            controller: scroll,
            primary: false,
            padding: EdgeInsets.zero,
            itemExtent: 32,
            itemCount: 100,
            itemBuilder: (_, index) => Text(
              '${widget.source} · Reading row $index',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }
}
