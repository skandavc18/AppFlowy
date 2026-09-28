import 'dart:convert';
import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/csv_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/notebook/notebook_document.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/notebook/notebook_find.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/notebook/notebook_kernel.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/notebook/notebook_markup.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/notebook/notebook_view.dart';
import 'package:appflowy/shared/document_viewer/standalone_file_scope.dart';
import 'package:appflowy/shared/find_replace/find_replace_bar.dart';
import 'package:appflowy/shared/find_replace/surface_find.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'surface_find_test_support.dart';

void main() {
  surfaceFindTestEnvironment();

  for (final appearance in WorkspaceDesignAppearance.values) {
    testWidgets(
        '${appearance.name}: CSV no-click Find reveals a lazy row and column',
        (tester) async {
      final text = List.generate(1002, (row) {
        return List.generate(10, (column) {
          if (row == 0 && column == 0) return 'needle first';
          if (row == 975 && column == 9) return 'needle and needle';
          if (row == 1001) return 'outside-preview needle';
          if (row % 37 == 0 && column == 2) {
            return List.filled(14, 'wrapped text').join(' ');
          }
          return '$row:$column';
        }).join(',');
      }).join('\n');
      await tester.pumpWidget(_app(
        CsvPreview(text: text, separator: ','),
        appearance: appearance,
      ));
      await pumpSurfaceFind(tester);
      final list = _list(tester);
      final controller = list.controller!;
      final rowDelegate = list.childrenDelegate as SliverChildBuilderDelegate;
      expect(rowDelegate.childCount, 1000);
      expect(list.shrinkWrap, isFalse);
      expect(_target((row: 975, column: 9)), findsNothing);
      expect(find.byType(SelectableText).evaluate().length, lessThan(300));
      expect(find.byType(FindReplaceBar), findsNothing);

      // No click, hover, autofocus, or manual scroll to seed the target.
      await openSurfaceFind(tester);
      await _query(tester, 'needle');
      final session = _find(tester);
      expect(session.matches, hasLength(3));
      expect(session.current!.id, (row: 0, column: 0));
      expect(session.supportsReplace, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.f3,
          physicalKey: PhysicalKeyboardKey.f3);
      await _settleLazyFind(tester);
      expect(session.current!.id, (row: 975, column: 9));
      expect(controller.offset, greaterThan(10000));
      expect(_list(tester).controller, same(controller));
      expect(find.byType(SelectableText).evaluate().length, lessThan(300));
      final paint = surfaceFindPaint(tester, (row: 975, column: 9));
      expect(paint.matchRects, hasLength(2));
      expect(paint.currentRect!.width, lessThan(paint.size.width));
      _expectWordVisible(tester, session, find.byType(CsvPreview));
      final firstWord = paint.currentRect;

      await tester.tap(find.byKey(const ValueKey('findNextMatch')));
      await _settleLazyFind(tester);
      expect(session.currentIndex, 2);
      expect(paint.currentRect, isNot(firstWord));
      _expectWordVisible(tester, session, find.byType(CsvPreview));

      await tester.sendKeyEvent(LogicalKeyboardKey.f3,
          physicalKey: PhysicalKeyboardKey.f3);
      await _settleLazyFind(tester);
      expect(session.current!.id, (row: 0, column: 0));
      _expectWordVisible(tester, session, find.byType(CsvPreview));
      for (final field in tester.widgetList<EditableText>(find.descendant(
        of: find.byType(SelectableText),
        matching: find.byType(EditableText),
      ))) {
        expect(field.readOnly, isTrue);
      }
      await _query(tester, 'outside-preview');
      expect(session.matches, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
        '${appearance.name}: notebook Find unfolds and reveals a lazy output word',
        (tester) async {
      final probe = _NotebookProbe();
      final output = List.generate(165, (line) {
        if (line == 7) return 'needle in the preview';
        if (line == 151) return 'needle below the fold';
        return 'printed line $line';
      }).join('\n');
      final document = NotebookDocument(cells: [
        for (var index = 0; index < 160; index++)
          NotebookCell(
            id: 'cell-$index',
            type: NotebookCellType.code,
            source: index == 0
                ? '# needle first'
                : List.filled(index % 5 + 1, 'value_$index = $index')
                    .join('\n'),
            outputs: index == 145
                ? [NotebookOutput.stream(name: 'stdout', text: output)]
                : const [],
          ),
      ]);
      await tester.pumpWidget(_app(
        probe.view(document.encode()),
        appearance: appearance,
      ));
      await pumpSurfaceFind(tester);
      final controller = _list(tester).controller!;
      expect(_source('cell-145'), findsNothing);
      expect(_sourceFields(tester).length, lessThan(25));

      await openSurfaceFind(tester);
      await _query(tester, 'needle');
      final session = _find(tester);
      expect(session.matches, hasLength(3));
      expect(session.current!.id, notebookSourceFindId('cell-0'));
      await tester.sendKeyEvent(LogicalKeyboardKey.f3,
          physicalKey: PhysicalKeyboardKey.f3);
      await _settleLazyFind(tester);
      final outputId = notebookOutputFindId('cell-145', 0, 'text');
      expect(session.current!.id, outputId);
      expect(controller.offset, greaterThan(8000));
      expect(_list(tester).controller, same(controller));
      final targetElement = tester.element(_target(outputId));
      expect(_outputText(tester, outputId), isNot(contains('below the fold')));
      _expectWordVisible(tester, session, find.byType(ListView));

      await tester.tap(find.byKey(const ValueKey('findNextMatch')));
      await _settleLazyFind(tester);
      expect(session.currentIndex, 2);
      expect(_outputText(tester, outputId), contains('below the fold'));
      expect(tester.element(_target(outputId)), same(targetElement));
      expect(surfaceFindPaint(tester, outputId).matchRects, hasLength(2));
      _expectWordVisible(tester, session, find.byType(ListView));
      expect(_sourceFields(tester).length, lessThan(25));
      expect(_sourceFields(tester).every((field) => field.readOnly), isTrue);
      expect(session.supportsReplace, isFalse);
      probe.expectNoActivity();

      // Closing Find restores the user's folded setting, not a model mutation.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape,
          physicalKey: PhysicalKeyboardKey.escape);
      await _settleLazyFind(tester);
      // Find itself must return to the now-shorter cell; no manual scrolling.
      await openSurfaceFind(tester);
      await _query(tester, 'needle in the preview');
      expect(_outputText(tester, outputId), isNot(contains('below the fold')));
      probe.expectNoActivity();
      await tester.pumpWidget(const SizedBox.shrink());
      probe.expectNoActivity();
    });
  }

  testWidgets(
      'CSV keeps native selection/controllers through query, theme and resize',
      (tester) async {
    const preview =
        CsvPreview(text: 'needle, other \n"one,two", tail ', separator: ',');
    await tester.pumpWidget(_app(preview));
    await pumpSurfaceFind(tester);
    final target = _target((row: 0, column: 0));
    final native =
        find.descendant(of: target, matching: find.byType(EditableText));
    final nativeState = tester.state<EditableTextState>(native);
    final field = tester.widget<EditableText>(native);
    field.controller.selection =
        const TextSelection(baseOffset: 1, extentOffset: 4);
    field.focusNode.requestFocus();
    await tester.pump();
    final value = field.controller.value;
    final vertical = _list(tester).controller;
    await openSurfaceFind(tester);
    await _query(tester, 'needle');
    for (final appearance in WorkspaceDesignAppearance.values) {
      await tester.pumpWidget(_app(preview,
          appearance: appearance,
          size: appearance == WorkspaceDesignAppearance.dark
              ? const Size(440, 380)
              : const Size(620, 460)));
      await _settleLazyFind(tester);
      expect(tester.state<EditableTextState>(native), same(nativeState));
      expect(tester.widget<EditableText>(native).controller,
          same(field.controller));
      expect(field.controller.value, value);
      expect(_list(tester).controller, same(vertical));
    }
    await _query(tester, ' other ');
    expect(_find(tester).matches, hasLength(1));
    await _query(tester, 'one,two');
    expect(_find(tester).matches, isEmpty); // Still the original simple parser.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape,
        physicalKey: PhysicalKeyboardKey.escape);
    await pumpSurfaceFind(tester);
    expect(field.controller.value, value);
    expect(field.focusNode.hasFocus, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'CSV empty, invalid query, revoked access and rebound data are safe',
      (tester) async {
    final chrome = StandaloneFileChromeController();
    var readable = true;
    Widget view(String text, {bool available = true}) => _app(_access(
          chrome,
          CsvPreview(text: text, separator: ','),
          canRead: () => readable,
          available: available,
        ));
    try {
      await tester.pumpWidget(view(''));
      await openSurfaceFind(tester);
      await _query(tester, 'This table is empty.');
      final session = _find(tester);
      expect(session.matches, isEmpty);
      expect(find.byType(FindReplaceBar), findsOneWidget);
      session.setOptions(const FindOptions(useRegex: true));
      await _query(tester, '[');
      expect(session.queryInvalid, isTrue);
      expect(session.matches, isEmpty);
      session.setOptions(const FindOptions());
      await tester.pumpWidget(view('private needle'));
      await _query(tester, 'needle');
      expect(session.matches, hasLength(1));
      readable = false;
      session.step(1);
      await pumpSurfaceFind(tester);
      expect(session.matches, isEmpty);
      expect(session.currentTargetRect, isNull);
      await openSurfaceFind(tester);
      expect(find.byType(FindReplaceBar), findsNothing);
      await tester.pumpWidget(view('private needle', available: false));
      expect(find.byType(SelectableText), findsNothing);
      readable = true;
      await tester.pumpWidget(view('rebound value'));
      await openSurfaceFind(tester);
      await _query(tester, 'private');
      expect(session.matches, isEmpty);
      await _query(tester, 'rebound');
      expect(session.current!.entry.text, 'rebound value');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      chrome.dispose();
    }
  });

  testWidgets('notebook Find uses live drafts and retains native editor state',
      (tester) async {
    final probe = _NotebookProbe();
    final document = NotebookDocument(cells: const [
      NotebookCell(
          id: 'draft', type: NotebookCellType.code, source: 'stored_text'),
    ]);
    Widget view(WorkspaceDesignAppearance appearance, Size size) => _app(
          probe.view(document.encode(), editable: true),
          appearance: appearance,
          size: size,
        );
    await tester.pumpWidget(
        view(WorkspaceDesignAppearance.light, const Size(620, 460)));
    await pumpSurfaceFind(tester);
    final field = tester.widget<TextField>(_source('draft'));
    final native = find.descendant(
        of: _source('draft'), matching: find.byType(EditableText));
    final state = tester.state<EditableTextState>(native);
    final controller = field.controller!;
    // A live controller draft is newer than the per-cell saved model.
    // Updating the controller does not call the viewer's onChanged/save path.
    controller.value = const TextEditingValue(
      text: 'live needle draft',
      selection: TextSelection(baseOffset: 5, extentOffset: 11),
    );
    final draft = controller.value;
    field.focusNode!.requestFocus();
    await tester.pump();
    await openSurfaceFind(tester);
    await _query(tester, 'stored_text');
    expect(_find(tester).matches, isEmpty);
    await _query(tester, 'needle');
    final session = _find(tester);
    expect(session.current!.entry.text, draft.text);
    expect(session.matches, hasLength(1));
    for (final appearance in WorkspaceDesignAppearance.values) {
      await tester.pumpWidget(view(
          appearance,
          appearance == WorkspaceDesignAppearance.paper
              ? const Size(440, 380)
              : const Size(620, 460)));
      await _settleLazyFind(tester);
      expect(tester.state<EditableTextState>(native), same(state));
      expect(tester.widget<TextField>(_source('draft')).controller,
          same(controller));
      expect(controller.value, draft);
      expect(probe.kernels, hasLength(1));
    }
    session.replacementController.text = 'must not edit';
    session.replaceCurrent();
    session.replaceAll();
    expect(controller.value, draft);
    expect(session.supportsReplace, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape,
        physicalKey: PhysicalKeyboardKey.escape);
    await pumpSurfaceFind(tester);
    expect(field.focusNode!.hasFocus, isTrue);
    expect(controller.value, draft);
    await tester.pumpWidget(const SizedBox.shrink());
    probe.expectNoActivity();
  });

  testWidgets(
      'notebook Find reveals distant words inside a real lazy source cell',
      (tester) async {
    final probe = _NotebookProbe();
    final source = NotebookDocument(cells: [
      for (var index = 0; index < 120; index++)
        NotebookCell(
          id: 'source-$index',
          type: NotebookCellType.code,
          source: index == 113
              ? List.generate(
                  220,
                  (line) => line == 3 || line == 205
                      ? '# source needle'
                      : 'line_$line = $line').join('\n')
              : 'value = $index',
        ),
    ]).encode();
    await tester.pumpWidget(_app(probe.view(source)));
    await pumpSurfaceFind(tester);
    expect(_source('source-113'), findsNothing);
    await openSurfaceFind(tester);
    await _query(tester, 'source needle');
    final session = _find(tester);
    expect(session.matches, hasLength(2));
    expect(session.current!.id, notebookSourceFindId('source-113'));
    _expectWordVisible(tester, session, find.byType(ListView));
    final field = tester.widget<TextField>(_source('source-113'));
    final native = find.descendant(
      of: _source('source-113'),
      matching: find.byType(EditableText),
    );
    final state = tester.state<EditableTextState>(native);
    final value = field.controller!.value;
    await tester.sendKeyEvent(LogicalKeyboardKey.f3,
        physicalKey: PhysicalKeyboardKey.f3);
    await _settleLazyFind(tester);
    expect(session.currentIndex, 1);
    _expectWordVisible(tester, session, find.byType(ListView));
    expect(tester.state<EditableTextState>(native), same(state));
    expect(field.controller!.value, value);
    expect(_sourceFields(tester).length, lessThan(25));
    await tester.pumpWidget(const SizedBox.shrink());
    probe.expectNoActivity();
  });

  testWidgets('read-only notebook source Find preserves the markdown renderer',
      (tester) async {
    final probe = _NotebookProbe();
    final source = NotebookDocument(cells: const [
      NotebookCell(
        id: 'prose',
        type: NotebookCellType.markdown,
        source: '# Reading\n\n[Visible label](raw_source_token)',
        metadata: {'private': 'metadata-secret'},
        attachments: {
          'image': {'image/png': 'attachment-secret'}
        },
      ),
    ]).encode();
    await tester.pumpWidget(_app(probe.view(source)));
    await pumpSurfaceFind(tester);
    final renderer = find.byType(NotebookMarkup, skipOffstage: false);
    final state = tester.state(renderer);
    final native = find.descendant(
      of: _source('prose', skipOffstage: false),
      matching: find.byType(EditableText, skipOffstage: false),
      skipOffstage: false,
    );
    final editor = tester.state<EditableTextState>(native);
    await openSurfaceFind(tester);
    await _query(tester, 'raw_source_token');
    expect(_find(tester).matches, hasLength(1));
    expect(_source('prose'), findsOneWidget);
    expect(tester.widget<TextField>(_source('prose')).readOnly, isTrue);
    _expectWordVisible(tester, _find(tester), find.byType(ListView));
    expect(tester.state(renderer), same(state));
    expect(tester.state<EditableTextState>(native), same(editor));
    await _query(tester, 'metadata-secret');
    expect(_find(tester).matches, isEmpty);
    expect(find.byType(NotebookMarkup), findsOneWidget);
    expect(tester.state(renderer), same(state));
    await _query(tester, 'attachment-secret');
    expect(_find(tester).matches, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    probe.expectNoActivity();
  });

  testWidgets(
      'notebook rich output Find uses rendered words and live disclosure text',
      (tester) async {
    final probe = _NotebookProbe();
    final source = NotebookDocument(cells: const [
      NotebookCell(
        id: 'rich',
        type: NotebookCellType.code,
        source: 'display(value)',
        outputs: [
          NotebookOutput(
            kind: NotebookOutputKind.display,
            data: {
              'text/html': '<p>first <b>needle</b></p><p>second needle</p>'
                  '<script>script-secret</script>'
                  '<details><summary>More details</summary><p>opened text</p></details>',
              'text/plain': 'fallback-secret',
              'application/json': '{"token":"serialized-secret"}',
            },
          ),
        ],
      ),
    ]).encode();
    await tester.pumpWidget(_app(probe.view(source)));
    await pumpSurfaceFind(tester);
    final renderer = tester.state(find.byType(NotebookMarkup));
    await openSurfaceFind(tester);
    await _query(tester, 'needle');
    final session = _find(tester);
    expect(session.matches, hasLength(2));
    final id = notebookOutputFindId('rich', 0, 'markup');
    final paint = surfaceFindPaint(tester, id);
    final firstWord = paint.currentRect!;
    await tester.sendKeyEvent(LogicalKeyboardKey.f3,
        physicalKey: PhysicalKeyboardKey.f3);
    await _settleLazyFind(tester);
    expect(session.currentIndex, 1);
    expect(paint.currentRect!.top, greaterThan(firstWord.top));
    _expectWordVisible(tester, session, find.byType(ListView));
    for (final secret in [
      'script-secret',
      'fallback-secret',
      'serialized-secret'
    ]) {
      await _query(tester, secret);
      expect(session.matches, isEmpty);
    }
    await _query(tester, 'opened text');
    expect(session.matches, isEmpty);
    await tester.tap(find.text('More details'));
    await _settleLazyFind(tester);
    expect(session.matches, hasLength(1));
    _expectWordVisible(tester, session, find.byType(ListView));
    expect(tester.state(find.byType(NotebookMarkup)), same(renderer));
    await tester.pumpWidget(const SizedBox.shrink());
    probe.expectNoActivity();
  });

  testWidgets(
      'notebook access and rebinding reject stale saves and cell callbacks',
      (tester) async {
    final oldProbe = _NotebookProbe(path: 'C:/fixture/old.ipynb');
    final nextProbe = _NotebookProbe(path: 'C:/fixture/new.ipynb');
    final chrome = StandaloneFileChromeController();
    var readable = true;
    var writable = true;
    String source(String text) => NotebookDocument(cells: [
          NotebookCell(
              id: 'same-id', type: NotebookCellType.code, source: text),
        ]).encode();
    Widget view(_NotebookProbe probe, String text, {bool available = true}) =>
        _app(_access(
          chrome,
          probe.view(source(text), editable: true),
          canRead: () => readable,
          canEdit: () => writable,
          available: available,
        ));
    try {
      await tester.pumpWidget(view(oldProbe, 'old-secret'));
      await pumpSurfaceFind(tester);
      final oldField = tester.widget<TextField>(_source('same-id'));
      await tester.enterText(_source('same-id'), 'pending old-secret');
      // Rebind BEFORE the normal 600ms autosave deadline.
      await tester.pumpWidget(view(nextProbe, 'new needle'));
      oldField.onChanged!('late callback from the old file');
      await pumpSurfaceFind(tester);
      expect(tester.widget<TextField>(_source('same-id')).controller!.text,
          'new needle');
      await openSurfaceFind(tester);
      await _query(tester, 'old-secret');
      final session = _find(tester);
      expect(session.matches, isEmpty);
      await _query(tester, 'needle');
      expect(session.matches, hasLength(1));

      writable = false;
      final retained = tester.widget<TextField>(_source('same-id'));
      retained.onChanged!('must not save');
      await tester.pumpWidget(view(nextProbe, 'new needle'));
      expect(tester.widget<TextField>(_source('same-id')).readOnly, isTrue);
      await _query(tester, 'needle');
      expect(
          session.matches, hasLength(1)); // Read permission still permits Find.

      readable = false; // Also exercise a live lease without a rebuild.
      session.step(1);
      await pumpSurfaceFind(tester);
      expect(session.matches, isEmpty);
      expect(session.currentTargetRect, isNull);
      await openSurfaceFind(tester);
      expect(find.byType(FindReplaceBar), findsNothing);
      await tester.pumpWidget(view(nextProbe, 'new needle', available: false));
      await pumpSurfaceFind(tester);
      expect(_sourceFields(tester), isEmpty);
      expect(chrome.value.toolbar, isNull);
      oldProbe.expectNoActivity();
      nextProbe.expectNoActivity();
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      chrome.dispose();
    }
    oldProbe.expectNoActivity();
    nextProbe.expectNoActivity();
  });

  testWidgets('notebook invalid/empty states open a zero-match read-only Find',
      (tester) async {
    for (final source in [
      'not JSON',
      '{"cells":[]}',
      '{"cells":[{"outputs":[{"name":42}]}]}'
    ]) {
      final probe = _NotebookProbe();
      await tester.pumpWidget(_app(probe.view(source)));
      await openSurfaceFind(tester);
      await _query(tester, 'cells');
      expect(find.byType(FindReplaceBar), findsOneWidget);
      expect(_find(tester).matches, isEmpty);
      expect(_find(tester).supportsReplace, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.f3,
          physicalKey: PhysicalKeyboardKey.f3);
      await pumpSurfaceFind(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      probe.expectNoActivity();
    }
  });

  testWidgets(
      'disposing a pending lazy Find invalidates its scroll and focus work',
      (tester) async {
    final probe = _NotebookProbe();
    final source = NotebookDocument(cells: [
      for (var index = 0; index < 500; index++)
        NotebookCell(
            id: '$index',
            type: NotebookCellType.code,
            source: index == 499 ? 'far needle' : 'value = $index'),
    ]).encode();
    await tester.pumpWidget(_app(probe.view(source)));
    await openSurfaceFind(tester);
    await tester.enterText(
        find.byKey(const ValueKey('findTextField')), 'needle');
    await tester.pump(); // Start the asynchronous index reveal, then detach.
    await tester.pumpWidget(const SizedBox.shrink());
    await _settleLazyFind(tester);
    probe.expectNoActivity();
  });
}

Widget _app(
  Widget child, {
  WorkspaceDesignAppearance appearance = WorkspaceDesignAppearance.light,
  Size size = const Size(620, 460),
}) =>
    surfaceFindTestApp(
      Align(
          alignment: Alignment.topLeft,
          child:
              SizedBox(width: size.width, height: size.height, child: child)),
      appearance: appearance,
    );

Widget _access(
  StandaloneFileChromeController chrome,
  Widget child, {
  required bool Function() canRead,
  bool Function()? canEdit,
  bool available = true,
}) =>
    Builder(
        builder: (context) => StandaloneFileScope(
              canvas: Theme.of(context).scaffoldBackgroundColor,
              rendererName: 'fixture.ipynb',
              displayName: 'fixture.ipynb',
              chrome: chrome,
              canRead: canRead,
              canEdit: canEdit ?? () => false,
              editable: canEdit?.call() ?? false,
              available: available,
              child: child,
            ));

SurfaceFindController _find(WidgetTester tester) =>
    tester.widget<SurfaceFindHost>(find.byType(SurfaceFindHost)).controller;

ListView _list(WidgetTester tester) =>
    tester.widget<ListView>(find.byType(ListView));

Finder _target(Object id) => find.byWidgetPredicate(
    (widget) => widget is SurfaceFindTarget && widget.id == id);

Finder _source(String id, {bool skipOffstage = true}) =>
    find.byKey(ValueKey(('notebook-source', id)), skipOffstage: skipOffstage);

List<TextField> _sourceFields(WidgetTester tester) => tester
    .widgetList<TextField>(find.byType(TextField))
    .where((field) => field.controller is NotebookCodeController)
    .toList();

String _outputText(WidgetTester tester, Object id) => tester
    .widget<Text>(find.descendant(of: _target(id), matching: find.byType(Text)))
    .data!;

Future<void> _query(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const ValueKey('findTextField')), text);
  await _settleLazyFind(tester);
}

Future<void> _settleLazyFind(WidgetTester tester) async {
  // Bounded frame pumping: variable-height index navigation awaits native
  // layout, while the focused query's cursor can keep scheduling animations.
  for (var frame = 0; frame < 120; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(tester.takeException(), isNull);
}

void _expectWordVisible(
    WidgetTester tester, SurfaceFindController session, Finder viewport) {
  final word = session.currentTargetRect;
  expect(word, isNotNull, reason: 'The selected native word must be laid out.');
  final visible = tester.getRect(viewport);
  expect(word!.width, greaterThan(0));
  expect(word.height, greaterThan(0));
  expect(word.left, greaterThanOrEqualTo(visible.left - 1));
  expect(word.right, lessThanOrEqualTo(visible.right + 1));
  expect(word.top, greaterThanOrEqualTo(visible.top - 1));
  expect(word.bottom, lessThanOrEqualTo(visible.bottom + 1));
  expect(word.overlaps(tester.getRect(find.byType(FindReplaceBar))), isFalse,
      reason: 'The shared Find bar must not cover the selected word.');
}

class _NotebookProbe {
  _NotebookProbe({String path = 'C:/fixture/notebook.ipynb'})
      : file = _FileProbe(path);

  final _FileProbe file;
  final kernels = <_KernelProbe>[];

  Widget view(String source, {bool editable = false}) => NotebookView(
        file: file,
        name: 'fixture.ipynb',
        source: source,
        editable: editable,
        createKernel: (language, directory) {
          final kernel = _KernelProbe(language, directory);
          kernels.add(kernel);
          return kernel;
        },
      );

  void expectNoActivity() {
    expect(file.reads, 0);
    expect(file.writes, isEmpty);
    for (final kernel in kernels) {
      expect(kernel.starts, 0);
      expect(kernel.executions, 0);
      expect(kernel.restarts, 0);
      expect(kernel.state, NotebookKernelState.stopped);
    }
  }
}

class _FileProbe extends Fake implements File {
  _FileProbe(this.path);

  @override
  final String path;
  int reads = 0;
  final writes = <String>[];

  @override
  String readAsStringSync({Encoding encoding = utf8}) {
    reads++;
    return '';
  }

  @override
  void writeAsStringSync(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) {
    writes.add(contents);
  }
}

class _KernelProbe extends NotebookKernel {
  _KernelProbe(String language, String directory)
      : super(language: language, workingDirectory: directory);

  int starts = 0;
  int executions = 0;
  int restarts = 0;

  @override
  Future<bool> ensureStarted() async {
    starts++;
    return false;
  }

  @override
  Future<NotebookExecution> execute(
    String code, {
    required void Function(NotebookOutput) onOutput,
  }) async {
    executions++;
    return const NotebookExecution(failed: true);
  }

  @override
  Future<void> restart() async {
    restarts++;
  }
}
