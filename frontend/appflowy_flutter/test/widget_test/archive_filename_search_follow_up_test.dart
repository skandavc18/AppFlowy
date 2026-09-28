import 'dart:async';
import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/archive/archive_document.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/archive/archive_explorer.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/archive/archive_gallery.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_action_buttons.dart';
import 'package:appflowy/shared/file_browser/file_browser_items.dart';
import 'package:appflowy/shared/file_browser/file_browser_view.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'file_controls_test_support.dart';

void main() {
  fileControlTestSetup();
  late Directory temporary;
  late File archive;
  late List<int> original;
  setUp(() async {
    temporary =
        await Directory.systemTemp.createTemp('archive-search-follow-up-');
    archive = File('${temporary.path}/fixture.zip');
    final document = ArchiveDocument.empty();
    for (final path in [
      'root.bin',
      'src/current.bin',
      'elsewhere/deep/Unique Report.bin',
      'elsewhere/deep/ordinary.bin',
    ]) {
      document.writeBytes(path, Uint8List.fromList([1, 2, 3]));
    }
    original = document.encode();
    await archive.writeAsBytes(original);
  });
  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  for (final mode in FileBrowserViewMode.values) {
    testWidgets(
        '${mode.name}: actual search filters recursive basenames and clearing restores current path',
        (tester) async {
      var writes = 0;
      var commandeeredKeys = 0;
      try {
        await mountFileControls(
            tester,
            ContextualFindScope(
                child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.backspace): () =>
                    commandeeredKeys++,
              },
              child: ArchiveExplorer(
                file: archive,
                name: 'fixture.zip',
                embedded: false,
                metadata: FileBrowserViewSettings.withMode(const {}, mode),
                onChanged: () => writes++,
              ),
            )),
            mode: 'paper',
            width: 780,
            height: 640,
            accessible: true,
            reduced: true);
        await _loaded(tester);
        // Invoke the real header navigation callback, not a separate test model.
        tester
            .widget<ArchiveGalleryHeader>(find.byType(ArchiveGalleryHeader))
            .onNavigate('src');
        await _loaded(tester);
        expect(_names(tester), contains('current.bin'));
        await _find(tester);
        final field = find.byKey(const ValueKey('archive-search-field'));
        final input = tester.widget<TextField>(field);
        await tester.enterText(field, 'UNIQUE REPORT.bin');
        await tester.pump(const Duration(milliseconds: 181));
        await _loaded(tester);
        expect(_names(tester), ['Unique Report.bin']);
        expect(find.text('Unique Report.bin'), findsOneWidget);
        expect(find.text('current.bin'), findsNothing);
        expect(find.text('1 matches · all folders'), findsOneWidget);
        expect(input.focusNode!.hasFocus, isTrue);
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pump();
        expect(input.focusNode!.hasFocus, isTrue);
        // Editing must stay in the search field, not in a shell/editor ancestor.
        await _command(
            tester, LogicalKeyboardKey.keyA, PhysicalKeyboardKey.keyA);
        await tester.sendKeyEvent(LogicalKeyboardKey.backspace,
            physicalKey: PhysicalKeyboardKey.backspace);
        await tester.pump(const Duration(milliseconds: 181));
        await _loaded(tester);
        expect(input.controller!.text, isEmpty);
        expect(commandeeredKeys, 0);
        expect(_names(tester), contains('current.bin'));
        final header = tester
            .widget<ArchiveGalleryHeader>(find.byType(ArchiveGalleryHeader));
        expect(header.breadcrumbs, ['', 'src']);
        await tester.enterText(field, 'missing-name');
        await tester.pump(const Duration(milliseconds: 181));
        await _loaded(tester);
        expect(_names(tester), isEmpty);
        expect(find.text('0 matches · all folders'), findsOneWidget);
        await tester.tap(find.byTooltip('Close search'));
        await _loaded(tester);
        expect(_names(tester), contains('current.bin'));
        tester
            .widget<ArchiveGalleryHeader>(find.byType(ArchiveGalleryHeader))
            .onNavigate('');
        await _loaded(tester);
        expect(_names(tester), contains('root.bin'));
        expect(writes, 0);
        expect(await tester.runAsync(archive.readAsBytes), original);
        expect(tester.takeException(), isNull);
      } finally {
        await unmountFileControls(tester);
      }
    });
  }

  test(
      'model already matches basenames recursively; quotes are literal and search never changes bytes',
      () {
    final document = ArchiveDocument.fromBytes(Uint8List.fromList(original));
    final before = document.encode();
    expect(document.search('unique report').map((entry) => entry.path),
        ['elsewhere/deep/Unique Report.bin']);
    expect(document.search('deep/ordinary').single.name, 'ordinary.bin');
    expect(document.search('"Unique Report"'), isEmpty);
    expect(document.search('filename:Unique'), isEmpty);
    expect(document.encode(), before);
    expect(document.isDirty, isFalse);
  });

  for (final appearance in fileControlAppearances) {
    testWidgets(
        '$appearance: real fullscreen publishes working search and always exposes one safe Close',
        (tester) async {
      final actions = FileControlMediaActions();
      late BuildContext launcher;
      var completed = 0;
      try {
        await mountFileControls(tester, Builder(builder: (context) {
          launcher = context;
          return const Text('Underlying page');
        }), mode: appearance, width: 320, textScale: 2, reduced: true);
        await tester.binding.setSurfaceSize(const Size(360, 900));
        await tester.pump();
        unawaited(showArchiveFullscreen(launcher,
                file: archive,
                name: 'fixture.zip',
                editable: false,
                mediaActions: actions)
            .then((_) => completed++));
        await tester.pump();
        final close = find.byKey(const ValueKey('archive-fullscreen-close'));
        expect(close.hitTestable(), findsOneWidget,
            reason: 'Close exists before decoding finishes');
        await _loaded(tester);
        expect(find.byType(MediaActionButtons), findsOneWidget);
        expect(
            find.ancestor(
                of: close, matching: find.byType(SingleChildScrollView)),
            findsNothing);
        await _find(tester);
        final field = find.byKey(const ValueKey('archive-search-field'));
        await tester.enterText(field, 'Unique Report');
        await tester.pump(const Duration(milliseconds: 181));
        await _loaded(tester);
        expect(_names(tester), ['Unique Report.bin']);
        expect(close.hitTestable(), findsOneWidget);
        final callback =
            tester.widget<WorkspaceControlButton>(close).onPressed!;
        final routeContext =
            tester.element(find.byKey(const ValueKey('archive-fullscreen')));
        unawaited(showDialog<void>(
            context: routeContext,
            builder: (_) => const AlertDialog(title: Text('Newer dialog'))));
        await settleFileControls(tester);
        callback();
        await tester.pump();
        expect(find.text('Newer dialog'), findsOneWidget);
        expect(completed, 0);
        Navigator.of(routeContext).pop();
        await settleFileControls(tester);
        callback();
        callback();
        await settleFileControls(tester);
        expect(completed, 1);
        expect(find.byKey(const ValueKey('archive-fullscreen')), findsNothing);
        expect(find.text('Underlying page'), findsOneWidget);
        expect(actions.copies, isEmpty);
        expect(actions.shares, isEmpty);
        unawaited(showArchiveFullscreen(
          launcher,
          file: archive,
          name: 'fixture.zip',
          editable: false,
          mediaActions: actions,
        ));
        await _loaded(tester);
        await tester.sendKeyEvent(
          LogicalKeyboardKey.f11,
          physicalKey: PhysicalKeyboardKey.f11,
        );
        await settleFileControls(tester);
        expect(find.byKey(const ValueKey('archive-fullscreen')), findsNothing);
        expect(find.text('Underlying page'), findsOneWidget);
        expect(await tester.runAsync(archive.readAsBytes), original);
        expect(tester.takeException(), isNull);
      } finally {
        await unmountFileControls(tester);
      }
    });
  }
}

List<String> _names(WidgetTester tester) {
  final gallery = find.byType(ArchiveGallery);
  if (gallery.evaluate().isNotEmpty) {
    return tester
        .widget<ArchiveGallery>(gallery)
        .entries
        .map((entry) => entry.entry.name)
        .toList();
  }
  final items = find.byType(FileBrowserItems);
  if (items.evaluate().isEmpty) return [];
  // During normal Columns navigation ancestors intentionally remain mounted.
  return tester
      .widgetList<FileBrowserItems>(items)
      .expand((list) => list.entries.map((entry) => entry.item.name))
      .toList();
}

Future<void> _loaded(WidgetTester tester) async {
  // Bounded real IO turns; only disposable fixture bytes are read/extracted.
  for (var i = 0; i < 24; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  await settleFileControls(tester);
  expect(find.byType(ArchiveGalleryHeader), findsOneWidget);
}

Future<void> _find(WidgetTester tester) async {
  await _command(tester, LogicalKeyboardKey.keyF, PhysicalKeyboardKey.keyF);
  await settleFileControls(tester);
  expect(find.byKey(const ValueKey('archive-search-field')), findsOneWidget);
}

Future<void> _command(WidgetTester tester, LogicalKeyboardKey logical,
    PhysicalKeyboardKey physical) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft,
      physicalKey: PhysicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(logical, physicalKey: physical);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft,
      physicalKey: PhysicalKeyboardKey.controlLeft);
}
