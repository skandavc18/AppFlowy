import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/code_test_case_panel.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/local_code_runner.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/notebook/notebook_document.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/notebook/notebook_kernel.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/notebook/notebook_view.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/sandboxed_code_runner.dart';
import 'package:appflowy/shared/icon_emoji_picker/default_icon_artwork.dart';
import 'package:appflowy/shared/icon_emoji_picker/vivid_icon_artwork.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/settings/default_icon_style.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_asset_bundle.dart';
import 'vivid_icon_test_support.dart'
    show settleVividIconPictures, vividIconTestAppearances;
import 'workspace_overlay_test_app.dart';

const _styleCycle = [
  DefaultIconStyle.monochrome,
  DefaultIconStyle.vivid,
  DefaultIconStyle.monochrome,
];
const _testCase = CodeTestCase(
  id: 'role-case',
  name: 'Case 1',
  input: 'input',
  expectedOutput: 'answer',
);
late _Translations _translations;

void main() {
  setUpAll(() async {
    await initializeWorkspaceOverlayTests();
    _translations = _Translations(
      await const TestBundleAssetLoader().load(
        'assets/translations',
        const Locale('en', 'US'),
      ),
    );
  });

  for (final appearance in vividIconTestAppearances) {
    testWidgets('$appearance code role overrides do not classify by color',
        (tester) async {
      _viewport(tester);
      final styles = ValueNotifier(DefaultIconStyle.monochrome);
      var activated = 0;
      try {
        await tester.pumpWidget(
          _app(
            appearance,
            styles,
            Builder(
              builder: (context) {
                final palette = CodeBlockPalette.resolve(context);
                return Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CodeToolbarButton(
                        key: const ValueKey('decorative'),
                        palette: palette,
                        tooltip: 'Decorative accent',
                        icon: Icons.add_rounded,
                        selected: true,
                        foregroundColor: palette.accent,
                        iconRole: WorkspaceGlyphRole.standard,
                        onPressed: () => activated++,
                      ),
                      CodeToolbarButton(
                        key: const ValueKey('accent-status'),
                        palette: palette,
                        tooltip: 'Status using the same accent',
                        icon: Icons.play_arrow_rounded,
                        foregroundColor: palette.accent,
                        iconRole: WorkspaceGlyphRole.preserveInk,
                        onPressed: () {},
                      ),
                      CodeToolbarButton(
                        key: const ValueKey('legacy-delete'),
                        palette: palette,
                        tooltip: 'Delete without a role override',
                        icon: Icons.delete_outline_rounded,
                        onPressed: () {},
                      ),
                      CodeToolbarButton(
                        key: const ValueKey('disabled-override'),
                        palette: palette,
                        tooltip: 'Disabled decorative accent',
                        icon: Icons.add_rounded,
                        foregroundColor: palette.accent,
                        iconRole: WorkspaceGlyphRole.standard,
                        onPressed: null,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
        await settleVividIconPictures(tester);
        final context = tester.element(_key('decorative'));
        final palette = CodeBlockPalette.resolve(context);
        final native = _native(_key('decorative'));
        final element = tester.element(native);
        final bounds = tester.getRect(native);
        expect(PaperTheme.isEnabled(context), appearance == 'paper');

        await _cycleStyles(tester, styles, (style) {
          _expectControl(
            tester,
            _key('decorative'),
            style,
            name: 'plus',
            iconRole: WorkspaceGlyphRole.standard,
            foregroundColor: palette.accent,
            ink: palette.accent,
          );
          _expectControl(
            tester,
            _key('accent-status'),
            style,
            name: 'play',
            iconRole: WorkspaceGlyphRole.preserveInk,
            foregroundColor: palette.accent,
            ink: palette.accent,
          );
          _expectControl(
            tester,
            _key('legacy-delete'),
            style,
            name: 'trash',
            iconRole: null,
            foregroundColor: palette.error,
            ink: palette.error,
          );
          _expectControl(
            tester,
            _key('disabled-override'),
            style,
            name: 'plus',
            iconRole: WorkspaceGlyphRole.standard,
            foregroundColor: palette.accent,
            ink: _disabledInk(tester, _key('disabled-override')),
            enabled: false,
          );
          expect(tester.element(native), same(element));
          expect(tester.getRect(native), bounds);
          expect(activated, 0);
        });
        await tester.tap(native);
        await tester.tap(_native(_key('disabled-override')));
        await tester.pump();
        expect(activated, 1);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        styles.dispose();
      }
    });

    testWidgets('$appearance actual Run/Stop and copied states retain ink',
        (tester) async {
      _viewport(tester);
      final styles = ValueNotifier(DefaultIconStyle.monochrome);
      final fileName = ValueNotifier('main.py');
      final engine = _ControlledRunner();
      final editor = TextEditingController(text: 'Kept source draft');
      const selection = TextSelection(baseOffset: 1, extentOffset: 6);
      editor.selection = selection;
      var factories = 0;
      try {
        await tester.pumpWidget(
          _app(
            appearance,
            styles,
            ValueListenableBuilder<String>(
              valueListenable: fileName,
              builder: (_, name, child) => SandboxedCodeRunner(
                code: 'print(1)',
                fileName: name,
                language: 'python',
                showLineNumbers: true,
                onLanguageChanged: (_) {},
                onToggleLineNumbers: () {},
                localRunnerFactory: () {
                  factories++;
                  return engine;
                },
                child: child!,
              ),
              child: TextField(
                key: const ValueKey('source-draft'),
                controller: editor,
                expands: true,
                maxLines: null,
              ),
            ),
          ),
        );
        await settleVividIconPictures(tester);
        final run = _key('code-run');
        final copy = _key('code-copy');
        final palette = CodeBlockPalette.resolve(tester.element(run));
        final state = tester.state(find.byType(SandboxedCodeRunner));
        final buttonElement = tester.element(_native(run));
        final editorFinder = find.descendant(
          of: _key('source-draft'),
          matching: find.byType(EditableText),
        );
        final editorState = tester.state(editorFinder);

        Future<void> expectRunState(bool running) async {
          final bounds = tester.getRect(_native(run));
          await _cycleStyles(tester, styles, (style) {
            _expectControl(
              tester,
              run,
              style,
              name: running ? 'stop' : 'play',
              iconRole: running
                  ? WorkspaceGlyphRole.preserveInk
                  : WorkspaceGlyphRole.standard,
              foregroundColor: running ? palette.error : palette.accent,
              ink: running ? palette.error : palette.accent,
            );
            expect(
              tester.widget<CodeToolbarButton>(run).label,
              running ? 'Stop' : 'Run',
            );
            expect(tester.element(_native(run)), same(buttonElement));
            expect(tester.getRect(_native(run)), bounds);
            expect(tester.state(find.byType(SandboxedCodeRunner)), same(state));
            expect(tester.state(editorFinder), same(editorState));
            expect(
              tester.widget<EditableText>(editorFinder).controller,
              same(editor),
            );
            expect(editor.text, 'Kept source draft');
            expect(editor.selection, selection);
          });
        }

        await expectRunState(false);
        expect(factories, 0);
        await tester.tap(_native(run));
        await tester.pump();
        expect(engine.runs, 1);
        await expectRunState(true);
        expect(engine.cancels, 0);
        await tester.tap(_native(run));
        await tester.pump();
        expect(engine.cancels, 1);
        engine.done.complete(
          const LocalCodeResult(stdout: '', stderr: '', exitCode: 0),
        );
        await settleVividIconPictures(tester);
        await expectRunState(false);
        expect(factories, 1);
        expect(engine.runs, 1);

        await tester.tap(_native(copy));
        await tester.pump();
        await _cycleStyles(tester, styles, (style) {
          _expectControl(
            tester,
            copy,
            style,
            name: 'check',
            iconRole: WorkspaceGlyphRole.preserveInk,
            foregroundColor: palette.success,
            ink: palette.success,
          );
          expect(tester.widget<CodeToolbarButton>(copy).label, 'Copied');
        });
        await tester.pump(const Duration(seconds: 2));
        await _cycleStyles(tester, styles, (style) {
          _expectControl(
            tester,
            copy,
            style,
            name: 'copy',
            iconRole: WorkspaceGlyphRole.standard,
            ink: PremiumThemeExtension.of(tester.element(copy)).textSecondary,
          );
        });

        fileName.value = 'preview.txt';
        await tester.pump();
        await _cycleStyles(tester, styles, (style) {
          _expectControl(
            tester,
            run,
            style,
            name: 'play',
            iconRole: WorkspaceGlyphRole.standard,
            foregroundColor: palette.accent,
            ink: _disabledInk(tester, run),
            enabled: false,
          );
          expect(tester.widget<CodeToolbarButton>(run).tooltip, 'Preview only');
          expect(tester.state(find.byType(SandboxedCodeRunner)), same(state));
        });
        expect(factories, 1);
        expect(tester.takeException(), isNull);
      } finally {
        if (!engine.done.isCompleted) {
          engine.done.complete(
            const LocalCodeResult(stdout: '', stderr: '', exitCode: 0),
          );
        }
        await tester.pumpWidget(const SizedBox());
        editor.dispose();
        fileName.dispose();
        styles.dispose();
      }
    });

    testWidgets('$appearance actual test summaries keep success and error ink',
        (tester) async {
      _viewport(tester);
      final styles = ValueNotifier(DefaultIconStyle.monochrome);
      final engine = _ControlledRunner();
      try {
        await tester.pumpWidget(
          _app(
            appearance,
            styles,
            SandboxedCodeRunner(
              code: 'print("answer")',
              fileName: 'main.py',
              language: 'python',
              showLineNumbers: true,
              onLanguageChanged: (_) {},
              onToggleLineNumbers: () {},
              testCases: const [_testCase],
              onTestCasesChanged: (_) {},
              localRunnerFactory: () => engine,
              child: const SizedBox(),
            ),
          ),
        );
        await settleVividIconPictures(tester);
        final summary = _key('code-tests');
        final palette = CodeBlockPalette.resolve(tester.element(summary));
        await _cycleStyles(tester, styles, (style) {
          _expectControl(
            tester,
            summary,
            style,
            name: 'list-checks',
            iconRole: WorkspaceGlyphRole.standard,
            ink:
                PremiumThemeExtension.of(tester.element(summary)).textSecondary,
          );
        });
        await tester.tap(_native(summary));
        await settleVividIconPictures(tester);
        final panelState = tester.state(find.byType(CodeTestCasePanel));

        for (final (result, label, outcome, color) in [
          (
            const LocalCodeResult(stdout: 'answer\n', stderr: '', exitCode: 0),
            '1/1',
            'Accepted',
            palette.success,
          ),
          (
            const LocalCodeResult(stdout: 'wrong\n', stderr: '', exitCode: 0),
            '0/1',
            'Wrong answer',
            palette.error,
          ),
          (
            const LocalCodeResult(stdout: '', stderr: 'failed', exitCode: 1),
            '0/1',
            'Runtime error',
            palette.error,
          ),
        ]) {
          engine.caseResult = result;
          await tester.tap(_native(_tooltip('Run every test case')));
          await settleVividIconPictures(tester);
          await _cycleStyles(tester, styles, (style) {
            _expectControl(
              tester,
              summary,
              style,
              name: 'list-checks',
              iconRole: WorkspaceGlyphRole.preserveInk,
              foregroundColor: color,
              ink: color,
            );
            expect(tester.widget<CodeToolbarButton>(summary).label, label);
            expect(tester.widget<CodeToolbarButton>(summary).selected, isTrue);
            expect(find.text(outcome), findsOneWidget);
            expect(
              tester.state(find.byType(CodeTestCasePanel)),
              same(panelState),
            );
          });
        }
        expect(engine.caseRuns, 3);
        expect(engine.cancels, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        styles.dispose();
      }
    });

    testWidgets('$appearance test panel Add/Run differs from Stop/Delete',
        (tester) async {
      _viewport(tester);
      final styles = ValueNotifier(DefaultIconStyle.monochrome);
      var cases = <CodeTestCase>[];
      var running = false;
      var canRun = true;
      var runs = 0;
      var stops = 0;
      late StateSetter update;
      try {
        await tester.pumpWidget(
          _app(
            appearance,
            styles,
            StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return CodeTestCasePanel(
                  palette: CodeBlockPalette.resolve(context),
                  testCases: cases,
                  outcomes: const {},
                  running: running,
                  canRun: canRun,
                  editable: true,
                  onChanged: (next) => cases = next,
                  onRun: () => setState(() {
                    runs++;
                    running = true;
                  }),
                  onStop: () => setState(() {
                    stops++;
                    running = false;
                  }),
                  onClose: () {},
                );
              },
            ),
          ),
        );
        await settleVividIconPictures(tester);
        final palette = CodeBlockPalette.resolve(
          tester.element(find.byType(CodeTestCasePanel)),
        );
        final delete = _tooltip('Delete this test case');
        final run = _tooltip('Run every test case');
        await _cycleStyles(tester, styles, (style) {
          _expectControl(
            tester,
            _label('Add a case'),
            style,
            name: 'plus',
            iconRole: WorkspaceGlyphRole.standard,
            foregroundColor: palette.accent,
            ink: palette.accent,
          );
          _expectControl(
            tester,
            run,
            style,
            name: 'play',
            iconRole: WorkspaceGlyphRole.standard,
            foregroundColor: palette.accent,
            ink: _disabledInk(tester, run),
            enabled: false,
          );
          _expectControl(
            tester,
            delete,
            style,
            name: 'trash',
            iconRole: WorkspaceGlyphRole.preserveInk,
            foregroundColor: palette.error,
            ink: _disabledInk(tester, delete),
            enabled: false,
          );
        });

        await tester.tap(_native(_label('Add a case')));
        await settleVividIconPictures(tester);
        expect(cases, hasLength(1));
        final panelState = tester.state(find.byType(CodeTestCasePanel));
        final field = find.descendant(
          of: _key('${cases.single.id}-input'),
          matching: find.byType(TextFormField),
        );
        await tester.enterText(field, 'Retained input');
        await tester.pump(const Duration(milliseconds: 600));
        final editable = find.descendant(
          of: field,
          matching: find.byType(EditableText),
        );
        final controller = tester.widget<EditableText>(editable).controller;
        const selection = TextSelection(baseOffset: 1, extentOffset: 5);
        controller.selection = selection;
        await _cycleStyles(tester, styles, (style) {
          _expectControl(
            tester,
            run,
            style,
            name: 'play',
            iconRole: WorkspaceGlyphRole.standard,
            foregroundColor: palette.accent,
            ink: palette.accent,
          );
          _expectControl(
            tester,
            delete,
            style,
            name: 'trash',
            iconRole: WorkspaceGlyphRole.preserveInk,
            foregroundColor: palette.error,
            ink: palette.error,
          );
          expect(
            tester.state(find.byType(CodeTestCasePanel)),
            same(panelState),
          );
          expect(
            tester.widget<EditableText>(editable).controller,
            same(controller),
          );
          expect(controller.text, 'Retained input');
          expect(controller.selection, selection);
          expect(cases.single.input, 'Retained input');
          expect(runs, 0);
        });

        await tester.tap(_native(run));
        await tester.pump();
        expect(runs, 1);
        await _cycleStyles(tester, styles, (style) {
          _expectControl(
            tester,
            _label('Stop'),
            style,
            name: 'stop',
            iconRole: WorkspaceGlyphRole.preserveInk,
            foregroundColor: palette.error,
            ink: palette.error,
          );
          _expectControl(
            tester,
            delete,
            style,
            name: 'trash',
            iconRole: WorkspaceGlyphRole.preserveInk,
            foregroundColor: palette.error,
            ink: _disabledInk(tester, delete),
            enabled: false,
          );
          _expectControl(
            tester,
            _tooltip('Add a test case'),
            style,
            name: 'plus',
            iconRole: null,
            ink: _disabledInk(tester, _tooltip('Add a test case')),
            enabled: false,
          );
          expect(tester.widget<TextFormField>(field).enabled, isFalse);
          expect(controller.text, 'Retained input');
          expect(stops, 0);
        });
        await tester.tap(_native(_label('Stop')));
        await tester.pump();
        expect(stops, 1);
        update(() => canRun = false);
        await _cycleStyles(tester, styles, (style) {
          _expectControl(
            tester,
            run,
            style,
            name: 'play',
            iconRole: WorkspaceGlyphRole.standard,
            foregroundColor: palette.accent,
            ink: _disabledInk(tester, run),
            enabled: false,
          );
        });
        await tester.tap(_native(delete));
        await tester.pump();
        expect(cases, isEmpty);
        expect(runs, 1);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        styles.dispose();
      }
    });

    for (final language in ['python', 'julia']) {
      testWidgets('$appearance/$language notebook idle and disabled Run roles',
          (tester) async {
        _viewport(tester);
        final styles = ValueNotifier(DefaultIconStyle.monochrome);
        final editable = ValueNotifier(true);
        final file = _NotebookFile();
        final kernels = <_IdleNotebookKernel>[];
        final source = NotebookDocument(
          cells: [
            NotebookCell(
              id: 'notebook-code',
              type: NotebookCellType.code,
              source: '1 + 1',
              metadata: {'language': language},
            ),
          ],
          metadata: {
            'language_info': {'name': language},
          },
        ).encode();
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        try {
          await mouse.addPointer(location: const Offset(-10, -10));
          await tester.pumpWidget(
            _app(
              appearance,
              styles,
              ValueListenableBuilder<bool>(
                valueListenable: editable,
                builder: (_, canEdit, __) => NotebookView(
                  file: file,
                  name: file.path,
                  editable: canEdit,
                  source: source,
                  createKernel: (language, directory) {
                    final kernel = _IdleNotebookKernel(
                      language: language,
                      workingDirectory: directory,
                    );
                    kernels.add(kernel);
                    return kernel;
                  },
                ),
              ),
            ),
          );
          await settleVividIconPictures(tester);
          await mouse.moveTo(tester.getCenter(find.byType(TextField)));
          await settleVividIconPictures(tester);
          final runAll = _label('Run all');
          final runCell = _tooltip('Run this cell  (Ctrl+Enter)');
          final palette = CodeBlockPalette.resolve(tester.element(runAll));
          final state = tester.state(find.byType(NotebookView));
          final editor = tester.widget<TextField>(find.byType(TextField));
          final runAllElement = tester.element(_native(runAll));
          final runCellElement = tester.element(_native(runCell));
          final retainedRunAll =
              tester.widget<CodeToolbarButton>(runAll).onPressed;
          final retainedRunCell =
              tester.widget<CodeToolbarButton>(runCell).onPressed;
          editor.focusNode!.requestFocus();
          await tester.pump();
          editor.controller!.selection =
              const TextSelection(baseOffset: 0, extentOffset: 3);
          final draft = editor.controller!.value;
          // Language support is not edit authority. Keep the enabled-role
          // coverage, then revoke/grant access without replacing the notebook.
          for (final canEdit in [true, false, true]) {
            editable.value = canEdit;
            final enabled = canEdit && language == 'python';
            await _cycleStyles(tester, styles, (style) {
              _expectControl(
                tester,
                runAll,
                style,
                name: 'play',
                iconRole: WorkspaceGlyphRole.standard,
                foregroundColor: enabled ? palette.accent : null,
                ink: enabled ? palette.accent : _disabledInk(tester, runAll),
                enabled: enabled,
              );
              _expectControl(
                tester,
                runCell,
                style,
                name: 'play',
                iconRole: WorkspaceGlyphRole.standard,
                foregroundColor: palette.accent,
                ink: enabled ? palette.accent : _disabledInk(tester, runCell),
                enabled: enabled,
              );
              expect(tester.state(find.byType(NotebookView)), same(state));
              expect(tester.element(_native(runAll)), same(runAllElement));
              expect(tester.element(_native(runCell)), same(runCellElement));
              final field = tester.widget<TextField>(find.byType(TextField));
              expect(field.controller, same(editor.controller));
              expect(field.readOnly, !canEdit);
              expect(editor.controller!.value, draft);
              expect(find.text('Idle'), findsOneWidget);
            });
            if (!enabled) {
              await tester.tap(_native(runAll));
              await tester.tap(_native(runCell));
              editor.focusNode!.requestFocus();
              await tester.pump();
              await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
              await tester.sendKeyEvent(LogicalKeyboardKey.enter);
              await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
              if (!canEdit && language == 'python') {
                // A callback retained while editable must also fail closed.
                expect(retainedRunAll, isNotNull);
                expect(retainedRunCell, isNotNull);
                retainedRunAll!();
                retainedRunCell!();
              }
              await tester.pump();
            }
            expect(kernels, hasLength(1));
            expect(kernels.single.starts, 0);
            expect(kernels.single.executions, isEmpty);
            expect(editor.controller!.value, draft);
            expect(file.writes, isEmpty);
          }
          expect(tester.takeException(), isNull);
        } finally {
          await mouse.removePointer();
          await tester.pumpWidget(const SizedBox());
          expect(file.writes, isEmpty);
          editable.dispose();
          styles.dispose();
        }
      });
    }
  }
}

Finder _key(String value) => find.byKey(ValueKey(value));

Finder _label(String value) => find.byWidgetPredicate(
      (widget) => widget is CodeToolbarButton && widget.label == value,
    );

Finder _tooltip(String value) => find.byWidgetPredicate(
      (widget) => widget is CodeToolbarButton && widget.tooltip == value,
    );

Finder _native(Finder caller) =>
    find.descendant(of: caller, matching: find.byType(TextButton));

Color _disabledInk(WidgetTester tester, Finder caller) =>
    PremiumThemeExtension.of(tester.element(caller)).textMuted;

Future<void> _cycleStyles(
  WidgetTester tester,
  ValueNotifier<DefaultIconStyle> styles,
  void Function(DefaultIconStyle) check,
) async {
  for (final style in _styleCycle) {
    styles.value = style;
    await settleVividIconPictures(tester);
    check(style);
  }
}

void _expectControl(
  WidgetTester tester,
  Finder caller,
  DefaultIconStyle style, {
  required String name,
  required WorkspaceGlyphRole? iconRole,
  required Color ink,
  Color? foregroundColor,
  bool enabled = true,
}) {
  expect(caller, findsOneWidget);
  final code = tester.widget<CodeToolbarButton>(caller);
  final shared = tester.widget<WorkspaceControlButton>(
    find.descendant(of: caller, matching: find.byType(WorkspaceControlButton)),
  );
  final native = tester.widget<TextButton>(_native(caller));
  expect(code.iconRole, iconRole);
  expect(shared.iconRole, iconRole);
  expect(shared.icon, code.icon);
  expect(shared.label, code.label);
  expect(shared.tooltip, code.tooltip);
  expect(shared.selected, code.selected);
  expect(shared.foregroundColor, foregroundColor);
  expect(shared.onPressed, same(code.onPressed));
  expect(native.onPressed, same(code.onPressed));
  expect(native.onPressed != null, enabled);
  expect(
    native.style!.foregroundColor!.resolve({
      if (!enabled) WidgetState.disabled,
    }),
    ink,
  );

  final role = !enabled
      ? WorkspaceGlyphRole.preserveInk
      : iconRole ??
          (foregroundColor == null
              ? WorkspaceGlyphRole.standard
              : WorkspaceGlyphRole.preserveInk);
  final finder = find.descendant(
    of: caller,
    matching: find.byType(WorkspaceGlyph),
  );
  final glyph = tester.widget<WorkspaceGlyph>(finder);
  expect(glyph.icon, code.icon);
  expect(glyph.name, name);
  expect(glyph.role, role);
  expect(glyph.color, ink);
  final vivid =
      style == DefaultIconStyle.vivid && role == WorkspaceGlyphRole.standard;
  final source = vivid
      ? vividIconSvg(WorkspaceGlyphs.vividNameFor(name)!)
      : defaultIconSvg(name);
  expect(source, isNotNull, reason: '$name must have exact matching artwork');
  final picture = tester.widget<SvgPicture>(
    find.descendant(of: finder, matching: find.byType(SvgPicture)),
  );
  final loader = picture.bytesLoader as SvgStringLoader;
  expect(
    loader,
    SvgStringLoader(
      source!,
      theme: loader.theme,
      colorMapper: loader.colorMapper,
    ),
  );
  expect(
    picture.colorFilter,
    vivid ? null : ColorFilter.mode(ink, BlendMode.srcIn),
  );
}

void _viewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 900);
  addTearDown(tester.view.reset);
}

Widget _app(
  String appearance,
  ValueNotifier<DefaultIconStyle> styles,
  Widget child,
) {
  final app = workspaceOverlayTestApp(
    appearance: appearance,
    disableAnimations: true,
    accessibleNavigation: true,
    child: DefaultIconStyleScope(
      styles: styles,
      child: Center(child: SizedBox(width: 940, height: 640, child: child)),
    ),
  ) as EasyLocalization;
  return EasyLocalization(
    supportedLocales: app.supportedLocales,
    path: app.path,
    fallbackLocale: app.fallbackLocale,
    useFallbackTranslations: app.useFallbackTranslations,
    saveLocale: false,
    assetLoader: _translations,
    child: app.child,
  );
}

class _Translations extends AssetLoader {
  const _Translations(this.english);

  final Map<String, dynamic> english;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) =>
      Future.value(english);
}

/// Keep the real kernel's language/idle state, but never start a process even
/// if an access regression accidentally reaches an execution callback.
class _IdleNotebookKernel extends NotebookKernel {
  _IdleNotebookKernel(
      {required super.language, required super.workingDirectory});

  int starts = 0;
  final executions = <String>[];

  @override
  Future<bool> ensureStarted() async {
    starts++;
    return false;
  }

  @override
  Future<NotebookExecution> execute(
    String code, {
    required void Function(NotebookOutput output) onOutput,
  }) async {
    executions.add(code);
    return const NotebookExecution(failed: true);
  }
}

class _NotebookFile extends Fake implements File {
  @override
  String get path => 'vivid-code-controls.ipynb';

  final writes = <String>[];

  @override
  void writeAsStringSync(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) =>
      writes.add(contents);
}

/// Only the execution boundary is held/faked; all controls and states are real.
/// Neither override starts a process, browser, or native toolchain.
class _ControlledRunner extends LocalCodeRunner {
  final done = Completer<LocalCodeResult>();
  int runs = 0;
  int cancels = 0;
  int caseRuns = 0;
  LocalCodeResult caseResult =
      const LocalCodeResult(stdout: 'answer', stderr: '', exitCode: 0);

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
    return done.future;
  }

  @override
  void cancel() => cancels++;

  @override
  Future<List<LocalCodeResult>> runCases({
    required LocalToolchain toolchain,
    required String code,
    required List<String> inputs,
    Duration caseTimeout = const Duration(seconds: 20),
    void Function(int index, LocalCodeResult result)? onCaseFinished,
  }) async {
    caseRuns++;
    for (var i = 0; i < inputs.length; i++) {
      onCaseFinished?.call(i, caseResult);
    }
    return List.filled(inputs.length, caseResult);
  }
}
