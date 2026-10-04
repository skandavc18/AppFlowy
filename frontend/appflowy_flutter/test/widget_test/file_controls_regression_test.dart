import 'dart:async';
import 'dart:ui' as ui;

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/code_test_case_panel.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/local_code_runner.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/sandboxed_code_runner.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_action_buttons.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/document_viewer/standalone_file_scope.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'file_controls_test_support.dart';

const _lineNumbers = ValueKey('code-line-numbers');
const _language = ValueKey('code-language-menu');
const _tests = ValueKey('code-tests');
const _run = ValueKey('code-run');
const _copy = ValueKey('media-copy');

final _source = List.generate(220, (i) => 'print("line $i")').join('\n');

void main() {
  fileControlTestSetup();

  for (final mode in fileControlAppearances) {
    for (final reduced in [false, true]) {
      testWidgets(
          '$mode/reduced=$reduced: metadata toggles retain visible tools and the real editor',
          (tester) async {
        final file = MemoryCodeFile(_source);
        final backend = FileControlBackend(
          fileControlView('code', 'source.py', file.path),
          file,
        );
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        final semantics = tester.ensureSemantics();
        try {
          await mouse.addPointer(location: const Offset(1080, 880));
          await mountFileControls(
            tester,
            backend.viewer(),
            mode: mode,
            reduced: reduced,
          );
          final renderer = tester.state(find.byType(FilePreview));
          final runner = tester.state(find.byType(SandboxedCodeRunner));
          final field = tester.widget<TextField>(_sourceField);
          final editor = tester.state(
            find.descendant(
              of: _sourceField,
              matching: find.byType(EditableText),
            ),
          );
          final actions = tester.state(find.byType(MediaActionButtons));
          final selection =
              const TextSelection(baseOffset: 3, extentOffset: 19);
          field.controller!.value =
              TextEditingValue(text: 'Draft\n$_source', selection: selection);
          field.scrollController!.jumpTo(80);
          await tester.pump();

          expect(find.byKey(_lineNumbers).hitTestable(), findsOneWidget);
          await mouse.moveTo(tester.getCenter(find.byKey(_lineNumbers)));
          await settleFileControls(tester);
          final numberedGlyph = tester
              .widget<WorkspaceGlyph>(
                find.descendant(
                  of: find.byKey(_lineNumbers),
                  matching: find.byType(WorkspaceGlyph),
                ),
              )
              .name;
          await clickFileControl(tester, find.byKey(_lineNumbers));
          expect(_lineButton(tester).selected, isFalse);
          expect(_lineButton(tester).icon, Icons.subject_rounded);
          expect(
            tester
                .widget<WorkspaceGlyph>(
                  find.descendant(
                    of: find.byKey(_lineNumbers),
                    matching: find.byType(WorkspaceGlyph),
                  ),
                )
                .name,
            isNot(numberedGlyph),
          );
          expectFileControlPainted(tester, find.byKey(_lineNumbers));

          await clickFileControl(tester, find.byKey(_language));
          expect(find.widgetWithText(AppMenuRow, 'Java'), findsOneWidget);
          // A menu owns focus/pointer now. Its hold must keep the PUBLISHED
          // host toolbar painted, not just a renderer-local inner reveal.
          await mouse.moveTo(const Offset(1080, 880));
          await settleFileControls(tester);
          expectFileControlPainted(tester, find.byKey(_lineNumbers));
          expectFileControlPainted(tester, find.byKey(_copy));
          await clickFileControl(
            tester,
            find.widgetWithText(AppMenuRow, 'Java'),
          );
          await mouse.moveTo(tester.getCenter(find.byKey(_lineNumbers)));
          await settleFileControls(tester);
          expect(
            tester
                .widget<SandboxedCodeRunner>(find.byType(SandboxedCodeRunner))
                .language,
            'java',
          );
          expect(
            WorkspaceFilePreviewCodec.decode(backend.stored.extra),
            containsPair('show_code_line_numbers', false),
          );

          await clickFileControl(tester, find.byKey(_lineNumbers));
          final saved = WorkspaceFilePreviewCodec.decode(backend.stored.extra);
          expect(
            saved['code_language'],
            'java',
            reason: 'Later toggles cannot spread the loader’s stale metadata',
          );
          expect(saved['show_code_line_numbers'], isTrue);
          expect(_lineButton(tester).icon, Icons.format_list_numbered_rounded);
          expect(
            decodeViewExtra(backend.stored.extra)['unrelated'],
            'preserve me',
          );
          expect(tester.state(find.byType(FilePreview)), same(renderer));
          expect(tester.state(find.byType(SandboxedCodeRunner)), same(runner));
          expect(
            tester.state(
              find.descendant(
                of: _sourceField,
                matching: find.byType(EditableText),
              ),
            ),
            same(editor),
          );
          expect(
            tester.widget<TextField>(_sourceField).controller,
            same(field.controller),
          );
          expect(field.controller!.selection, selection);
          expect(field.controller!.text, 'Draft\n$_source');
          expect(field.scrollController!.offset, 80);
          expect(tester.state(find.byType(MediaActionButtons)), same(actions));
          expect(backend.loads, 1);
          expect(file.reads, 1);
          expect(file.writes, 0);

          // Standalone file options are persistent; decoration hover remains
          // separate. Idle controls retain semantics and native activation.
          FocusManager.instance.primaryFocus?.unfocus();
          await mouse.moveTo(const Offset(1080, 880));
          await settleFileControls(tester);
          expect(find.byKey(_lineNumbers).hitTestable(), findsOneWidget);
          expect(find.semantics.byLabel('Hide line numbers'), findsOneWidget);
          await _tabTo(tester, find.byKey(_lineNumbers));
          expectFileControlPainted(tester, find.byKey(_lineNumbers));
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await settleFileControls(tester);
          expect(_lineButton(tester).selected, isFalse);
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await settleFileControls(tester);
          expect(_lineButton(tester).selected, isTrue);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
          await mouse.removePointer();
          await unmountFileControls(tester);
        }
      });
    }

    testWidgets(
        '$mode: external metadata and saved test cases update without a reload',
        (tester) async {
      final file = MemoryCodeFile(_source);
      final backend = FileControlBackend(
        fileControlView('external', 'source.py', file.path),
        file,
      );
      try {
        await mountFileControls(
          tester,
          backend.viewer(),
          mode: mode,
          accessible: true,
        );
        final runner = tester.state(find.byType(SandboxedCodeRunner));
        final field = tester.widget<TextField>(_sourceField);
        final selection = const TextSelection(baseOffset: 8, extentOffset: 21);
        field.controller!.value =
            TextEditingValue(text: 'Draft\n$_source', selection: selection);
        field.scrollController!.jumpTo(70);
        await clickFileControl(tester, find.byKey(_tests));
        final panelState = tester.state(find.byType(CodeTestCasePanel));
        await tester.enterText(find.byType(TextFormField).first, 'saved input');
        await tester.pump(const Duration(milliseconds: 600));
        await settleFileControls(tester);
        await clickFileControl(tester, find.byKey(_lineNumbers));
        final stored = WorkspaceFilePreviewCodec.decode(backend.stored.extra);
        expect(
          decodeCodeTestCases(stored['code_test_cases']).single.input,
          'saved input',
        );
        expect(tester.state(find.byType(CodeTestCasePanel)), same(panelState));

        backend.publish(
          ViewPB.fromBuffer(backend.stored.writeToBuffer())
            ..extra = WorkspaceFilePreviewCodec.merge(backend.stored.extra, {
              ...stored,
              'code_language': 'java',
              'show_code_line_numbers': true,
            }),
        );
        await settleFileControls(tester);
        final updated = tester
            .widget<SandboxedCodeRunner>(find.byType(SandboxedCodeRunner));
        expect(updated.language, 'java');
        expect(updated.showLineNumbers, isTrue);
        expect(tester.state(find.byType(SandboxedCodeRunner)), same(runner));
        expect(field.controller!.text, 'Draft\n$_source');
        expect(field.controller!.selection, selection);
        expect(field.scrollController!.offset, 70);
        expect(file.reads, 1);
        expect(file.writes, 0);
        expect(backend.loads, 1);
        expect(tester.takeException(), isNull);
      } finally {
        await unmountFileControls(tester);
      }
    });

    for (final width in [240.0, 320.0, 980.0]) {
      testWidgets(
          '$mode/$width: every code/file action survives narrow layout at 2x text',
          (tester) async {
        final file = MemoryCodeFile(_source);
        final backend = FileControlBackend(
          fileControlView(
            'narrow',
            'Very long original source.py',
            file.path,
          ),
          file,
        );
        try {
          await mountFileControls(
            tester,
            backend.viewer(),
            mode: mode,
            width: width,
            textScale: 2,
            accessible: true,
          );
          final before = tester.state(find.byType(SandboxedCodeRunner));
          final renderer = tester.state(find.byType(FilePreview));
          final field = tester.widget<TextField>(_sourceField);
          final scrollView =
              find.byKey(const ValueKey('workspace-file-toolbar-scroll'));
          final scroll =
              tester.widget<SingleChildScrollView>(scrollView).controller!;
          final position = scroll.position;
          for (final key in [
            _language,
            _lineNumbers,
            _tests,
            _run,
            const ValueKey('code-copy'),
            const ValueKey('code-collapse'),
            _copy,
          ]) {
            final finder = find.byKey(key);
            expect(finder, findsOneWidget);
            final element = tester.element(finder);
            // The retained one-row toolbar scrolls at narrow widths. Every
            // action must be reachable, not simultaneously inside the clip.
            await tester.ensureVisible(finder);
            await settleFileControls(tester);
            expect(finder.hitTestable(), findsOneWidget);
            expectFileControlPainted(tester, finder);
            final rect = tester.getRect(finder);
            final bounds =
                tester.getRect(find.byKey(const ValueKey('code-controls')));
            final viewport = tester.getRect(scrollView).intersect(
                  tester.getRect(
                    find.byKey(const ValueKey('workspace-file-identity-row')),
                  ),
                );
            expect(rect.isEmpty, isFalse);
            expect(rect.left, greaterThanOrEqualTo(bounds.left));
            expect(rect.right, lessThanOrEqualTo(bounds.right + 0.01));
            expect(rect.left, greaterThanOrEqualTo(viewport.left - 0.01));
            expect(rect.right, lessThanOrEqualTo(viewport.right + 0.01));
            expect(rect.top, greaterThanOrEqualTo(viewport.top - 0.01));
            expect(rect.bottom, lessThanOrEqualTo(viewport.bottom + 0.01));
            expect(tester.element(finder), same(element));
            expect(
              tester.widget<SingleChildScrollView>(scrollView).controller,
              same(scroll),
            );
            expect(scroll.position, same(position));
            expect(
              tester.state(find.byType(SandboxedCodeRunner)),
              same(before),
            );
            expect(tester.state(find.byType(FilePreview)), same(renderer));
          }
          await tester.ensureVisible(find.byKey(_lineNumbers));
          await settleFileControls(tester);
          await clickFileControl(tester, find.byKey(_lineNumbers));
          await clickFileControl(tester, find.byKey(_lineNumbers));
          expect(tester.state(find.byType(SandboxedCodeRunner)), same(before));
          expect(
            tester.widget<TextField>(_sourceField).controller,
            same(field.controller),
          );
          expect(field.controller!.text, _source);
          expect(backend.loads, 1);
          expect(file.reads, 1);
          expect(file.writes, 0);
          expect(tester.takeException(), isNull);
        } finally {
          await unmountFileControls(tester);
        }
      });
    }
  }

  testWidgets('embedded settings stay cumulative without a host echo',
      (tester) async {
    final file = MemoryCodeFile(_source);
    final changes = <Map<String, dynamic>>[];
    try {
      await mountFileControls(
        tester,
        FilePreview(
          file: file,
          name: 'embedded.py',
          kind: FilePreviewKind.code,
          metadata: const {'unowned': 42},
          onMetadataChanged: changes.add,
        ),
        accessible: true,
      );
      final runner = tester.state(find.byType(SandboxedCodeRunner));
      await clickFileControl(tester, find.byKey(_lineNumbers));
      await clickFileControl(tester, find.byKey(_language));
      await clickFileControl(tester, find.widgetWithText(AppMenuRow, 'Java'));
      expect(changes.last, containsPair('show_code_line_numbers', false));
      expect(changes.last, containsPair('code_language', 'java'));
      expect(changes.last, containsPair('unowned', 42));
      expect(tester.state(find.byType(SandboxedCodeRunner)), same(runner));
      expect(file.reads, 1);
      expect(tester.takeException(), isNull);
    } finally {
      await unmountFileControls(tester);
    }
  });

  for (final mode in fileControlAppearances) {
    testWidgets(
        '$mode: published controls preserve an in-flight run, terminal and editor',
        (tester) async {
      final chrome = StandaloneFileChromeController();
      final engine = _HeldRunner();
      final editor = TextEditingController(text: 'Real editor draft');
      final leaf = TextField(
        key: const ValueKey('held-editor'),
        controller: editor,
        expands: true,
        maxLines: null,
      );
      var language = 'python';
      var numbers = true;
      var factories = 0;
      try {
        await mountFileControls(
          tester,
          StatefulBuilder(
            builder: (context, update) => PreviewToolbarRegion(
              child: StandaloneFileScope(
                canvas: Theme.of(context).scaffoldBackgroundColor,
                rendererName: 'source.py',
                displayName: 'source.py',
                chrome: chrome,
                canEdit: () => true,
                canRead: () => true,
                editable: true,
                available: true,
                child: Column(
                  children: [
                    ValueListenableBuilder<StandaloneFileHeader>(
                      valueListenable: chrome,
                      builder: (context, value, _) => PreviewToolbar(
                        keepVisible: value.keepActionsVisible,
                        child: value.toolbarBuilder
                                ?.call(context, const SizedBox()) ??
                            const SizedBox(),
                      ),
                    ),
                    Expanded(
                      child: SandboxedCodeRunner(
                        displayName: 'source.py',
                        code: 'print("held run")',
                        fileName: fileNameForCodeLanguage(language),
                        language: language,
                        showLineNumbers: numbers,
                        onLanguageChanged: (value) =>
                            update(() => language = value),
                        onToggleLineNumbers: () =>
                            update(() => numbers = !numbers),
                        localRunnerFactory: () {
                          factories++;
                          return engine;
                        },
                        expandEditor: true,
                        framed: false,
                        child: leaf,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          mode: mode,
          accessible: true,
          reduced: true,
        );
        final state = tester.state(find.byType(SandboxedCodeRunner));
        final fieldState = tester.state(
          find.descendant(
            of: find.byKey(const ValueKey('held-editor')),
            matching: find.byType(EditableText),
          ),
        );
        await clickFileControl(tester, find.byKey(_run));
        expect(engine.runs, 1);
        expect(_runButton(tester).tooltip, 'Stop');
        await clickFileControl(tester, find.byKey(_lineNumbers));
        await clickFileControl(tester, find.byKey(_language));
        await clickFileControl(tester, find.widgetWithText(AppMenuRow, 'Java'));
        expect(factories, 1);
        expect(engine.cancelled, isFalse);
        expect(_runButton(tester).tooltip, 'Stop');
        expect(tester.state(find.byType(SandboxedCodeRunner)), same(state));
        expect(
          tester.state(
            find.descendant(
              of: find.byKey(const ValueKey('held-editor')),
              matching: find.byType(EditableText),
            ),
          ),
          same(fieldState),
        );
        expect(editor.text, 'Real editor draft');
        // A language for the NEXT run cannot redirect Stop to another engine,
        // and a preview-only choice cannot hide the active run's stop control.
        for (final label in ['Javascript', 'Typescript']) {
          await clickFileControl(tester, find.byKey(_language));
          await clickFileControl(
            tester,
            find.widgetWithText(AppMenuRow, label),
          );
          expect(_runButton(tester).tooltip, 'Stop');
          expect(_runButton(tester).onPressed, isNotNull);
          expect(engine.cancelled, isFalse);
          expect(tester.state(find.byType(SandboxedCodeRunner)), same(state));
        }
        engine.output!('Still the same run\n');
        await clickFileControl(tester, find.byKey(_run));
        expect(engine.cancelled, isTrue);
        engine.done.complete(
          const LocalCodeResult(stdout: '', stderr: '', exitCode: 0),
        );
        await settleFileControls(tester);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is SelectableText &&
                widget.textSpan?.toPlainText().contains('Still the same run') ==
                    true,
          ),
          findsOneWidget,
        );
        expect(engine.runs, 1);
        expect(tester.takeException(), isNull);
      } finally {
        if (!engine.done.isCompleted) {
          engine.done.complete(
            const LocalCodeResult(stdout: '', stderr: '', exitCode: 0),
          );
        }
        await unmountFileControls(tester);
        editor.dispose();
        chrome.dispose();
      }
    });
  }

  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    testWidgets(
        '$platform: persistent file controls work with touch without a mouse',
        (tester) async {
      final file = MemoryCodeFile(_source);
      final backend = FileControlBackend(
        fileControlView('touch', 'source.py', file.path),
        file,
      );
      try {
        await mountFileControls(
          tester,
          backend.viewer(editable: false),
          mode: 'paper',
          platform: platform,
          reduced: true,
        );
        final renderer = tester.state(find.byType(FilePreview));
        if (platform == TargetPlatform.windows) {
          expect(find.byKey(_lineNumbers).hitTestable(), findsOneWidget);
          await tester.tapAt(tester.getCenter(_sourceField));
          await settleFileControls(tester);
        }
        expect(find.byKey(_lineNumbers).hitTestable(), findsOneWidget);
        expect(find.byKey(_copy).hitTestable(), findsOneWidget);
        await tester.tapAt(tester.getCenter(find.byKey(_lineNumbers)));
        await settleFileControls(tester);
        expect(_lineButton(tester).selected, isFalse);
        expect(tester.state(find.byType(FilePreview)), same(renderer));
        expect(
          backend.extraWrites,
          isEmpty,
          reason: 'A read-only viewer does not save settings',
        );
        expect(file.writes, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await unmountFileControls(tester);
      }
    });
  }

  testWidgets('plain text focus and blur retain persistent standalone actions',
      (tester) async {
    final file = MemoryCodeFile(_source, path: '/fixture/notes.txt');
    final backend = FileControlBackend(
      fileControlView('text-focus', 'notes.txt', file.path),
      file,
    );
    try {
      await mountFileControls(
        tester,
        backend.viewer(),
        mode: 'paper',
        reduced: true,
      );
      expect(find.byType(SandboxedCodeRunner), findsNothing);
      expect(find.byKey(_copy).hitTestable(), findsOneWidget);
      final field = tester.widget<TextField>(_sourceField);
      final renderer = tester.state(find.byType(FilePreview));
      final copy = find.byKey(_copy, skipOffstage: false);
      final copyElement = tester.element(copy);
      final header = find.byKey(
        const ValueKey('workspace-file-identity'),
        skipOffstage: false,
      );
      final headerTop = tester.getTopLeft(header).dy;
      final outer = tester
          .state<NestedScrollViewState>(find.byType(NestedScrollView))
          .outerController;
      field.focusNode!.requestFocus();
      await settleFileControls(tester);
      expect(outer.offset, greaterThan(0));
      expect(
        tester.getTopLeft(header).dy,
        closeTo(headerTop - outer.offset, .01),
      );
      expect(copy.hitTestable(), findsNothing);
      expect(tester.element(copy), same(copyElement));
      expect(tester.renderObject(copy).attached, isTrue);
      final fades = find.ancestor(
        of: copy,
        matching: find.byType(AnimatedOpacity, skipOffstage: false),
      );
      expect(fades, findsWidgets);
      for (final fade in tester.widgetList<AnimatedOpacity>(fades)) {
        expect(fade.opacity, 1);
      }
      field.focusNode!.unfocus();
      await settleFileControls(tester);
      await tester.ensureVisible(copy);
      await settleFileControls(tester);
      expect(find.byKey(_copy).hitTestable(), findsOneWidget);
      expect(tester.element(copy), same(copyElement));
      final viewport = tester.getRect(find.byType(NestedScrollView));
      final bounds = tester.getRect(copy);
      expect(viewport.inflate(.01).intersect(bounds), bounds);
      expect(tester.state(find.byType(FilePreview)), same(renderer));
      expect(file.reads, 1);
      expect(tester.takeException(), isNull);
    } finally {
      await unmountFileControls(tester);
    }
  });

  testWidgets(
      'header publication remains post-frame and old owners cannot clear a replacement',
      (tester) async {
    final chrome = StandaloneFileChromeController();
    final phases = <SchedulerPhase>[];
    chrome.addListener(
      () => phases.add(SchedulerBinding.instance.schedulerPhase),
    );
    var owner = 'first';
    late StateSetter update;
    try {
      await mountFileControls(
        tester,
        StatefulBuilder(
          builder: (_, setState) {
            update = setState;
            return StandaloneFileHeaderSlot(
              key: ValueKey(owner),
              controller: chrome,
              controls: StandaloneFileHeader(toolbar: Text(owner)),
            );
          },
        ),
      );
      update(() => owner = 'replacement');
      await tester.pump();
      expect((chrome.value.toolbar! as Text).data, 'replacement');
      expect(phases, everyElement(SchedulerPhase.postFrameCallbacks));
      await tester.pump();
      expect((chrome.value.toolbar! as Text).data, 'replacement');
      expect(tester.takeException(), isNull);
    } finally {
      await unmountFileControls(tester);
      chrome.dispose();
    }
  });
}

Finder get _sourceField =>
    find.byWidgetPredicate((widget) => widget is TextField && widget.expands);
CodeToolbarButton _lineButton(WidgetTester tester) =>
    tester.widget<CodeToolbarButton>(find.byKey(_lineNumbers));
CodeToolbarButton _runButton(WidgetTester tester) =>
    tester.widget<CodeToolbarButton>(find.byKey(_run));

Future<void> _tabTo(WidgetTester tester, Finder control) async {
  final native =
      find.descendant(of: control, matching: find.byType(TextButton));
  bool focused() {
    final target = tester.element(native);
    var within = false;
    FocusManager.instance.primaryFocus?.context
        ?.visitAncestorElements((element) {
      if (identical(element, target)) within = true;
      return !within;
    });
    return within;
  }

  for (var i = 0; i < 40 && !focused(); i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await settleFileControls(tester);
  }
  expect(
    focused(),
    isTrue,
    reason: 'Hidden chrome stays in the native Tab order',
  );
  expect(
    tester
        .getSemantics(native)
        .getSemanticsData()
        .hasFlag(ui.SemanticsFlag.isButton),
    isTrue,
  );
}

class _HeldRunner extends LocalCodeRunner {
  final done = Completer<LocalCodeResult>();
  void Function(String)? output;
  int runs = 0;
  bool cancelled = false;
  @override
  bool get acceptsInput => !done.isCompleted;
  @override
  Future<LocalCodeResult> run({
    required LocalToolchain toolchain,
    required String code,
    void Function(String chunk)? onStdout,
    void Function(String chunk)? onStderr,
  }) {
    runs++;
    output = onStdout;
    return done.future;
  }

  @override
  void cancel() => cancelled = true;
}
