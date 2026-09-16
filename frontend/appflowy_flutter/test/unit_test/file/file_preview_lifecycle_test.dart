import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'replacing a loaded file never displays its bytes under a new identity',
      (tester) async {
    final first = _DelayedFile('first.txt')
      ..content.complete('First file contents');
    final second = _DelayedFile('second.txt');
    final selected = ValueNotifier<File>(first);
    await tester.pumpWidget(_app(selected));
    await tester.pumpAndSettle();
    expect(_text('First file contents'), findsOneWidget);
    selected.value = second;
    await tester.pump();
    expect(_text('First file contents'), findsNothing);
    expect(find.text('first.txt'), findsNothing);
    second.content.complete('Second file contents');
    await tester.pumpAndSettle();
    expect(_text('Second file contents'), findsOneWidget);
    expect(find.text('second.txt'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    selected.dispose();
  });

  testWidgets(
      'late file IO keeps its own input and cannot overwrite the current preview',
      (tester) async {
    final exists = Completer<bool>();
    final first = _DelayedFile('old.txt', exists: exists.future);
    final second = _DelayedFile('new.txt')..content.complete('Current bytes');
    final selected = ValueNotifier<File>(first);
    await tester.pumpWidget(_app(selected));
    selected.value = second;
    await tester.pumpAndSettle();
    expect(_text('Current bytes'), findsOneWidget);
    exists.complete(true);
    await tester.pump();
    first.content.complete('Obsolete bytes');
    await tester.pumpAndSettle();
    expect(first.reads, 1);
    expect(second.reads, 1);
    expect(_text('Current bytes'), findsOneWidget);
    expect(_text('Obsolete bytes'), findsNothing);
    expect(find.text('new.txt'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    selected.dispose();
  });
}

Finder _text(String value) => find.byWidgetPredicate(
      (widget) =>
          widget is SelectableText && widget.textSpan?.toPlainText() == value,
    );

Widget _app(ValueNotifier<File> selected) => MaterialApp(
      home: AppFlowyTheme(
        data: AppFlowyDefaultTheme().light(),
        child: Scaffold(
          body: ValueListenableBuilder<File>(
            valueListenable: selected,
            builder: (_, file, __) => FilePreview(
              file: file,
              name: file.path.split('/').last,
              kind: FilePreviewKind.text,
              metadata: const {},
              editable: false,
              onMetadataChanged: (_) {},
            ),
          ),
        ),
      ),
    );

class _DelayedFile extends Fake implements File {
  _DelayedFile(String name, {Future<bool>? exists})
      : path = '/fixture/$name',
        _exists = exists ?? Future.value(true);

  @override
  final String path;
  final Future<bool> _exists;
  final content = Completer<String>();
  int reads = 0;

  @override
  Future<bool> exists() => _exists;
  @override
  Future<int> length() async => 64;
  @override
  FileStat statSync() =>
      throw const FileSystemException('No real file in this IO test');
  @override
  Future<String> readAsString({Encoding encoding = utf8}) {
    reads++;
    return content.future;
  }
}
