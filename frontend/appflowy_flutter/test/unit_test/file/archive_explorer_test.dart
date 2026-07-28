import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/archive/archive_document.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/archive/archive_explorer.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery.dart';
import 'package:archive/archive.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _zip(Map<String, String> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    final bytes = Uint8List.fromList(entry.value.codeUnits);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

/// Lets the real file reads behind the gallery finish, then rebuilds.
///
/// Each entry is unpacked in its own round trip to disk, and only
/// [WidgetTester.pump] is used while that is in flight: the loading spinner
/// animates forever, so settling before it is gone times out.
Future<void> _settle(WidgetTester tester) async {
  for (var attempt = 0; attempt < 24; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  late Directory directory;
  late File file;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('archive_explorer_test');
    file = File('${directory.path}/bundle.zip');
    await file.writeAsBytes(
      _zip(const {
        'readme.md': '# Hello',
        'src/main.dart': 'void main() {}',
        'src/util/strings.dart': 'const a = 1;',
      }),
    );
  });

  tearDown(() async {
    try {
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    } on FileSystemException {
      // Windows can still hold the staged archive open for a moment; a stray
      // temporary directory must not fail the test.
    }
  });

  Future<void> pumpArchive(
    WidgetTester tester, {
    bool editable = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 800,
            child: ArchiveExplorer(
              file: file,
              name: 'bundle.zip',
              editable: editable,
              embedded: false,
            ),
          ),
        ),
      ),
    );
    await _settle(tester);
  }

  testWidgets('lays the archive out as a wall of folder cards', (tester) async {
    await pumpArchive(tester);

    expect(find.byType(FolderGalleryCard), findsNWidgets(2));
    expect(find.text('src'), findsOneWidget);
    expect(find.text('readme.md'), findsOneWidget);
    // A nested entry belongs to its own folder, not the root.
    expect(find.text('main.dart'), findsNothing);
  });

  testWidgets('opening a folder card shows what is inside it', (tester) async {
    await pumpArchive(tester);

    // The card title listens for a double tap, so a single tap is only
    // recognised once that window has passed.
    await tester.tap(find.text('src'));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
    await _settle(tester);

    expect(find.text('main.dart'), findsOneWidget);
    expect(find.text('util'), findsOneWidget);
    expect(find.text('readme.md'), findsNothing);
    // The trail back to the archive appears once you are inside it.
    expect(find.widgetWithText(TextButton, 'bundle.zip'), findsOneWidget);
  });

  testWidgets('a read only archive offers no editing controls', (tester) async {
    await pumpArchive(tester, editable: false);

    expect(find.byTooltip('Add files to this archive'), findsNothing);
    expect(find.byTooltip('New folder'), findsNothing);
    expect(find.byType(FolderGalleryCard), findsNWidgets(2));
  });

  testWidgets('the search field waits to be asked for', (tester) async {
    await pumpArchive(tester);

    expect(find.byType(TextField), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('adds a folder to the archive on disk', (tester) async {
    await pumpArchive(tester);

    await tester.tap(find.byTooltip('New folder'));
    await _settle(tester);

    final reloaded = ArchiveDocument.fromBytes(file.readAsBytesSync());
    expect(reloaded.isDirectory('New folder'), isTrue);
    expect(find.byType(FolderGalleryCard), findsNWidgets(3));
  });
}
