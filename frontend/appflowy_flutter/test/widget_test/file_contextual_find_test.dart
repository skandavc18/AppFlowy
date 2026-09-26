import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show ClipOp;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/find_replace/find_replace.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

const _contents = 'Alpha alpha a.b acb\nlast alpha';
const _pane = ValueKey('file-find-pane');
const _outside = ValueKey('file-find-outside');
// Flutter's widgets/undo_history.dart uses this throttle for native snapshots.
const _nativeUndoThrottle = Duration(milliseconds: 500);
late Map<String, dynamic> _translations;

void main() {
  late bool previousFontFetching;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    _translations = await const TestBundleAssetLoader()
        .load('assets/translations', const Locale('en', 'US'));
    previousFontFetching = GoogleFonts.config.allowRuntimeFetching;
    GoogleFonts.config.allowRuntimeFetching = false;
  });
  tearDownAll(
    () => GoogleFonts.config.allowRuntimeFetching = previousFontFetching,
  );

  for (final source in [false, true]) {
    _test('hover routes to the real ${source ? 'source' : 'text'} renderer',
        (tester) async {
      await _withFile(
        tester,
        source: source,
        body: (fixture, file) async {
          final input = _contentInput(tester);
          final original = input.controller.value;
          fixture.pageFocus.requestFocus();
          await tester.pump();
          final mouse =
              await tester.createGesture(kind: PointerDeviceKind.mouse);
          try {
            // Deliberately hover actual RenderEditable content, not the gutter.
            // This guards the shared router integration, not a replacement router.
            await mouse.addPointer(
              location: tester.getCenter(_contentEditable()),
            );
            await tester.pump();
            expect(fixture.pageFocus.hasPrimaryFocus, isTrue);
            expect(input.controller.value, original);
            await _chord(tester);
            expect(find.byType(FindReplaceBar), findsOneWidget);
            expect(fixture.pageFinds, 0);
            expect(_bar(tester).findFocusNode.hasPrimaryFocus, isTrue);
            expect(file.reads, 1);
            expect(file.writes, isEmpty);
          } finally {
            await mouse.removePointer();
          }
        },
      );
    });

    _test(
        'real ${source ? 'source' : 'text'} find counts, options and navigation',
        (tester) async {
      await _withFile(
        tester,
        source: source,
        body: (fixture, file) async {
          final input = _contentInput(tester);
          final state = tester.state<EditableTextState>(_contentEditable());
          final selectableState = source
              ? null
              : tester
                  .state<State<SelectableText>>(find.byType(SelectableText));
          input.focusNode.requestFocus();
          await tester.pump();
          await _chord(tester);
          await tester.enterText(
            find.byKey(const ValueKey('findTextField')),
            'alpha',
          );
          await tester.pump();
          expect(_bar(tester).matchCount, 3);
          expect(_bar(tester).currentMatch, 1);
          expect(_bar(tester).options.caseSensitive, isFalse);
          expect(
            find.text(
              LocaleKeys.findAndReplace_matchOfTotal.tr(args: ['1', '3']),
            ),
            findsOneWidget,
          );
          await tester.tap(find.byKey(const ValueKey('findNextMatch')));
          await tester.pump();
          expect(_bar(tester).currentMatch, 2);
          await tester.tap(find.byKey(const ValueKey('findPreviousMatch')));
          await tester.pump();
          await tester.tap(find.byKey(const ValueKey('findPreviousMatch')));
          await tester.pump();
          expect(_bar(tester).currentMatch, 3);

          await tester.tap(find.text('Aa'));
          await tester.pump();
          expect(_bar(tester).matchCount, 2);
          await tester.tap(find.text('.*'));
          await tester.enterText(
            find.byKey(const ValueKey('findTextField')),
            '[',
          );
          await tester.pump();
          expect(_bar(tester).queryInvalid, isTrue);
          expect(_bar(tester).matchCount, 0);
          expect(
            find.text(LocaleKeys.findAndReplace_invalidRegex.tr()),
            findsOneWidget,
          );
          await tester.enterText(
            find.byKey(const ValueKey('findTextField')),
            'a.b',
          );
          await tester.pump();
          expect(_bar(tester).queryInvalid, isFalse);
          expect(_bar(tester).matchCount, 2);
          await tester.tap(find.text('.*'));
          await tester.pump();
          expect(_bar(tester).matchCount, 1);
          await tester.enterText(
            find.byKey(const ValueKey('findTextField')),
            'absent',
          );
          await tester.pump();
          expect(_bar(tester).matchCount, 0);
          expect(_bar(tester).currentMatch, 0);
          expect(
            find.text(LocaleKeys.findAndReplace_noResult.tr()),
            findsOneWidget,
          );
          expect(_contentInput(tester).controller, same(input.controller));
          expect(
            tester.state<EditableTextState>(_contentEditable()),
            same(state),
          );
          if (!source) {
            expect(
              tester.state(find.byType(SelectableText)),
              same(selectableState),
            );
          }
          expect(input.controller.text, _contents);
          expect(file.reads, 1);
          expect(file.writes, isEmpty);
        },
      );
    });

    _test('outside dismissal leaves the clicked field focused (source=$source)',
        (tester) async {
      await _withFile(
        tester,
        source: source,
        body: (fixture, file) async {
          final input = _contentInput(tester);
          input.focusNode.requestFocus();
          await tester.pump();
          await _chord(tester);
          await tester.enterText(
            find.byKey(const ValueKey('findTextField')),
            'alpha',
          );
          await tester.pump();
          final focusHistory = <FocusNode?>[];
          void record() => focusHistory.add(FocusManager.instance.primaryFocus);
          FocusManager.instance.addListener(record);
          try {
            await tester.tap(
              find.byKey(_outside),
              kind: PointerDeviceKind.mouse,
            );
            await tester.pump();
            await tester.pump();
            expect(find.byType(FindReplaceBar), findsNothing);
            expect(fixture.outsideFocus.hasPrimaryFocus, isTrue);
            expect(focusHistory, isNot(contains(input.focusNode)));
            expect(input.controller.text, _contents);
            expect(file.writes, isEmpty);
          } finally {
            FocusManager.instance.removeListener(record);
          }
        },
      );
    });
  }

  _test('text highlights retain native state and restore the reader selection',
      (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        } else if (call.method == 'Clipboard.hasStrings') {
          return {'value': copied != null};
        } else if (call.method == 'Clipboard.getData') {
          return {'text': copied};
        }
        return null;
      },
    );
    try {
      await _withFile(
        tester,
        source: false,
        body: (fixture, file) async {
          final selectable = find.byType(SelectableText);
          final selectableState = tester.state(selectable);
          final editableState =
              tester.state<EditableTextState>(_contentEditable());
          final input = _contentInput(tester);
          input.focusNode.requestFocus();
          await tester.pump();
          await _chord(tester, key: LogicalKeyboardKey.keyA);
          final selection =
              TextSelection(baseOffset: 0, extentOffset: _contents.length);
          expect(input.controller.selection, selection);
          await _chord(tester);

          for (final mode in ['light', 'dark', 'paper']) {
            for (final width in [720.0, 280.0]) {
              fixture.changeLayout(mode, width);
              await tester.pump();
              await tester.enterText(
                find.byKey(const ValueKey('findTextField')),
                'alpha',
              );
              await tester.pump();
              expect(_bar(tester).matchCount, 3);
              _expectTextHighlights(tester, const [
                TextSelection(baseOffset: 0, extentOffset: 5),
                TextSelection(baseOffset: 6, extentOffset: 11),
                TextSelection(baseOffset: 25, extentOffset: 30),
              ]);
              await tester.tap(find.byKey(const ValueKey('findNextMatch')));
              await tester.pump();
              _expectTextHighlights(
                tester,
                const [
                  TextSelection(baseOffset: 0, extentOffset: 5),
                  TextSelection(baseOffset: 6, extentOffset: 11),
                  TextSelection(baseOffset: 25, extentOffset: 30),
                ],
                currentIndex: 1,
              );
              await tester.enterText(
                find.byKey(const ValueKey('findTextField')),
                'absent',
              );
              await tester.pump();
              _expectTextHighlights(tester, const []);
              expect(tester.state(selectable), same(selectableState));
              expect(
                tester.state<EditableTextState>(_contentEditable()),
                same(editableState),
              );
              expect(_contentInput(tester).controller, same(input.controller));
              expect(input.controller.text, _contents);
              // Refocusing an open find must not overwrite the saved selection
              // with SelectableText's native blur-cleared selection.
              await _chord(tester);
            }
          }

          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pump();
          await tester.pump();
          expect(find.byType(FindReplaceBar), findsNothing);
          expect(input.focusNode.hasPrimaryFocus, isTrue);
          expect(input.controller.selection, selection);
          expect(editableState.renderEditable.selection, selection);
          expect(tester.state(selectable), same(selectableState));
          _expectTextHighlights(tester, const []);
          await _chord(tester, key: LogicalKeyboardKey.keyC);
          expect(copied, _contents);
          expect(file.reads, 1);
          expect(file.writes, isEmpty);
        },
      );
    } finally {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    }
  });

  _test('native TextField control groups edits and redoes with Ctrl+Shift+Z',
      (tester) async {
    final controller = TextEditingController(text: _contents);
    final undoController = UndoHistoryController();
    final focusNode = FocusNode(debugLabel: 'native-undo-control');
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextField(
              controller: controller,
              undoController: undoController,
              focusNode: focusNode,
              maxLines: null,
            ),
          ),
        ),
      );
      final field = find.byType(TextField);
      await tester.showKeyboard(field);
      expect(focusNode.hasPrimaryFocus, isTrue);
      expect(controller.selection.isValid, isTrue);
      // Seal the valid, focused baseline before creating a separate edit group.
      await tester.pump(_nativeUndoThrottle);
      expect(undoController.value, UndoHistoryValue.empty);
      await tester.enterText(field, 'draft $_contents');
      const partialGroup = Duration(milliseconds: 300);
      await tester.pump(partialGroup);
      expect(undoController.value.canUndo, isFalse);
      await tester.pump(_nativeUndoThrottle - partialGroup);
      expect(undoController.value.canUndo, isTrue);

      await _chord(tester, key: LogicalKeyboardKey.keyZ);
      expect(controller.text, _contents);
      expect(undoController.value.canRedo, isTrue);
      // The installed SDK's Windows shortcuts do not bind Ctrl+Y. It must
      // leave the native redo entry intact, not be treated as a lost history.
      await _chord(tester, key: LogicalKeyboardKey.keyY);
      expect(controller.text, _contents);
      expect(undoController.value.canRedo, isTrue);
      await _chord(tester, key: LogicalKeyboardKey.keyZ, shift: true);
      expect(controller.text, 'draft $_contents');
      expect(undoController.value.canUndo, isTrue);
      expect(undoController.value.canRedo, isFalse);
      expect(focusNode.hasPrimaryFocus, isTrue);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      focusNode.dispose();
      undoController.dispose();
      controller.dispose();
    }
  });

  _test('bounded narrow bars and themes retain source draft, state and undo',
      (tester) async {
    await _withFile(
      tester,
      source: true,
      body: (fixture, file) async {
        final contentField = find.ancestor(
          of: _contentEditable(),
          matching: find.byType(TextField),
        );
        final state = tester.state<EditableTextState>(_contentEditable());
        final input = _contentInput(tester);
        final scroll = input.scrollController;
        // Native UndoHistory ignores invalid selections and coalesces for 500ms.
        // Focus the original text and seal that baseline BEFORE the first edit.
        await tester.showKeyboard(contentField);
        await tester.pump(_nativeUndoThrottle);
        expect(input.focusNode.hasPrimaryFocus, isTrue);
        expect(input.controller.selection.isValid, isTrue);
        expect(input.controller.text, _contents);
        final historyFinder = find.descendant(
          of: _contentEditable(),
          matching: find.byType(UndoHistory<TextEditingValue>),
        );
        final history =
            tester.state<UndoHistoryState<TextEditingValue>>(historyFinder);
        expect(history.canUndo, isFalse);
        await tester.enterText(contentField, 'draft $_contents');
        await tester.pump(_nativeUndoThrottle);
        expect(file.writes.last, 'draft $_contents');
        expect(history.canUndo, isTrue);
        await _chord(tester);
        await tester.enterText(
          find.byKey(const ValueKey('findTextField')),
          'alpha',
        );
        await tester.pump();
        final query = _bar(tester).findController;
        for (final mode in ['light', 'dark', 'paper']) {
          for (final width in [720.0, 280.0, 320.0]) {
            fixture.changeLayout(mode, width);
            await tester.pump();
            expect(tester.takeException(), isNull);
            expect(
              tester.state<EditableTextState>(_contentEditable()),
              same(state),
            );
            expect(_contentInput(tester).controller, same(input.controller));
            expect(_contentInput(tester).scrollController, same(scroll));
            expect(tester.state(historyFinder), same(history));
            expect(history.canUndo, isTrue);
            expect(input.controller.text, 'draft $_contents');
            expect(_bar(tester).findController, same(query));
            expect(_bar(tester).matchCount, 3);
            final bar = tester.getRect(find.byType(FindReplaceBar));
            final pane = tester.getRect(find.byKey(_pane));
            expect(bar.left, greaterThanOrEqualTo(pane.left));
            expect(bar.right, lessThanOrEqualTo(pane.right));
            expect(
              PaperTheme.isEnabled(tester.element(find.byType(FindReplaceBar))),
              mode == 'paper',
            );
          }
        }
        await tester.tap(find.byKey(const ValueKey('findClose')));
        await tester.pump();
        expect(input.focusNode.hasPrimaryFocus, isTrue);
        await _chord(tester, key: LogicalKeyboardKey.keyZ);
        expect(input.controller.text, _contents);
        expect(history.canUndo, isFalse);
        expect(history.canRedo, isTrue);
        expect(input.focusNode.hasPrimaryFocus, isTrue);
        await _chord(tester, key: LogicalKeyboardKey.keyZ, shift: true);
        expect(input.controller.text, 'draft $_contents');
        expect(history.canUndo, isTrue);
        expect(history.canRedo, isFalse);
        expect(file.reads, 1);
      },
    );
  });

  _test('read-only source finds but never exposes replacement', (tester) async {
    await _withFile(
      tester,
      source: true,
      editable: false,
      body: (fixture, file) async {
        final input = _contentInput(tester);
        expect(input.readOnly, isTrue);
        input.focusNode.requestFocus();
        await tester.pump();
        await _chord(tester);
        await tester.enterText(
          find.byKey(const ValueKey('findTextField')),
          'alpha',
        );
        await tester.pump();
        expect(_bar(tester).matchCount, 3);
        expect(_bar(tester).replaceController, isNull);
        expect(find.byKey(const ValueKey('findReplaceOne')), findsNothing);
        expect(_owner(tester).onReplace, isNull);
        expect(file.writes, isEmpty);
      },
    );
  });

  _test('first frame before file IO and pending focus during removal are safe',
      (tester) async {
    final file = _ControlledFile(pending: true);
    final key = GlobalKey<_FileHarnessState>();
    await tester.pumpWidget(_FileHarness(key: key, file: file, source: true));
    await tester.pump();
    expect(find.byType(FilePreview), findsOneWidget);
    expect(find.byType(FindReplaceBar), findsNothing);
    expect(file.reads, 0);
    expect(tester.takeException(), isNull);
    file.available.complete(true);
    file.content.complete(_contents);
    await tester.pumpAndSettle();
    expect(_contentEditable(), findsOneWidget);
    // Invoke the actual renderer callback then remove it before its focus frame.
    _owner(tester).onFind();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(ContextualFindRegion.debugRegisteredRegionCount, 0);
  });
}

void _test(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(
      name,
      body,
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
      timeout: const Timeout(Duration(seconds: 20)),
    );

Finder _contentEditable() => find.descendant(
      of: find.byType(FilePreview),
      matching: find.byElementPredicate(
        (element) =>
            element.widget is EditableText &&
            element.findAncestorWidgetOfExactType<FindReplaceBar>() == null,
      ),
    );

EditableText _contentInput(WidgetTester tester) =>
    tester.widget<EditableText>(_contentEditable());
FindReplaceBar _bar(WidgetTester tester) =>
    tester.widget<FindReplaceBar>(find.byType(FindReplaceBar));
ContextualFindRegion _owner(WidgetTester tester) =>
    tester.widget<ContextualFindRegion>(
      find
          .descendant(
            of: find.byType(FilePreview),
            matching: find.byType(ContextualFindRegion),
          )
          .first,
    );

Future<void> _chord(
  WidgetTester tester, {
  LogicalKeyboardKey key = LogicalKeyboardKey.keyF,
  bool shift = false,
}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
  await tester.pump();
}

Future<void> _withFile(
  WidgetTester tester, {
  required bool source,
  bool editable = true,
  required Future<void> Function(
    _FileHarnessState fixture,
    _ControlledFile file,
  ) body,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(900, 740);
  final file = _ControlledFile();
  final key = GlobalKey<_FileHarnessState>();
  try {
    await tester.pumpWidget(
      _FileHarness(key: key, file: file, source: source, editable: editable),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await body(key.currentState!, file);
    expect(tester.takeException(), isNull);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.reset();
  }
  expect(ContextualFindRegion.debugRegisteredRegionCount, 0);
}

void _expectTextHighlights(
  WidgetTester tester,
  List<TextSelection> matches, {
  int currentIndex = 0,
}) {
  final painterFinder = find
      .ancestor(
        of: find.byType(SelectableText),
        matching: find.byType(CustomPaint),
      )
      .first;
  final paintWidget = tester.widget<CustomPaint>(painterFinder);
  final paintBox = tester.renderObject<RenderBox>(painterFinder);
  final editable =
      tester.state<EditableTextState>(_contentEditable()).renderEditable;
  final brightness = Theme.of(tester.element(painterFinder)).brightness;
  final expected = <(Rect, Color)>[];
  for (var index = 0; index < matches.length; index++) {
    // Paint round-trips color channels through float32. Normalize only the
    // expected color through that same public API; keep rectangle equality exact.
    final paint = Paint()
      ..color = index == currentIndex
          ? FindHighlightColors.current(brightness)
          : FindHighlightColors.match(brightness);
    for (final box in editable.getBoxesForSelection(matches[index])) {
      expected.add(
        (
          MatrixUtils.transformRect(
            editable.getTransformTo(paintBox),
            box.toRect(),
          ),
          paint.color,
        ),
      );
    }
  }
  final canvas = _HighlightCanvas();
  paintWidget.painter!.paint(canvas, paintBox.size);
  expect(canvas.rects, expected);
  expect(paintWidget.painter!.hitTest(Offset.zero), isFalse);
}

class _HighlightCanvas extends Fake implements Canvas {
  final rects = <(Rect, Color)>[];
  final _transform = Matrix4.identity();

  @override
  void save() {}
  @override
  void restore() {}
  @override
  void clipRect(
    Rect rect, {
    ClipOp clipOp = ClipOp.intersect,
    bool doAntiAlias = true,
  }) {}
  @override
  void transform(Float64List matrix4) =>
      _transform.multiply(Matrix4.fromList(matrix4));
  @override
  void drawRect(Rect rect, Paint paint) =>
      rects.add((MatrixUtils.transformRect(_transform, rect), paint.color));
}

class _FileHarness extends StatefulWidget {
  const _FileHarness({
    super.key,
    required this.file,
    required this.source,
    this.editable = true,
  });
  final File file;
  final bool source;
  final bool editable;
  @override
  State<_FileHarness> createState() => _FileHarnessState();
}

class _FileHarnessState extends State<_FileHarness> {
  final pageFocus = FocusNode(debugLabel: 'surrounding-page-caret');
  final outsideFocus = FocusNode(debugLabel: 'outside-file');
  int pageFinds = 0;
  double width = 720;
  String mode = 'light';

  void changeLayout(String appearance, double size) => setState(() {
        mode = appearance;
        width = size;
      });

  @override
  Widget build(BuildContext context) => EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/translations',
        saveLocale: false,
        assetLoader: const _PreloadedTranslations(),
        child: Builder(
          builder: (context) => MaterialApp(
            locale: const Locale('en', 'US'),
            localizationsDelegates: context.localizationDelegates,
            themeAnimationDuration: Duration.zero,
            theme: ThemeData(
              brightness: mode == 'dark' ? Brightness.dark : Brightness.light,
              platform: TargetPlatform.windows,
              extensions: [PaperThemeExtension(enabled: mode == 'paper')],
            ),
            home: AppFlowyTheme(
              data: mode == 'dark'
                  ? AppFlowyDefaultTheme().dark()
                  : AppFlowyDefaultTheme().light(),
              child: Scaffold(
                body: ContextualFindRegion(
                  debugLabel: 'Surrounding page',
                  onFind: () => pageFinds++,
                  child: Focus(
                    focusNode: pageFocus,
                    onKeyEvent: (_, event) {
                      if (event is KeyDownEvent &&
                          HardwareKeyboard.instance.isControlPressed &&
                          event.logicalKey == LogicalKeyboardKey.keyF) {
                        pageFinds++;
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: Stack(
                      children: [
                        Positioned(
                          left: 24,
                          top: 8,
                          width: 240,
                          height: 48,
                          child: TextField(
                            key: _outside,
                            focusNode: outsideFocus,
                          ),
                        ),
                        Positioned(
                          left: 24,
                          top: 80,
                          width: width,
                          height: 440,
                          child: SizedBox(
                            key: _pane,
                            child: FilePreview(
                              file: widget.file,
                              name:
                                  widget.source ? 'source.html' : 'preview.txt',
                              kind: widget.source
                                  ? FilePreviewKind.html
                                  : FilePreviewKind.text,
                              metadata: {
                                if (widget.source) filePreviewEditModeKey: true,
                              },
                              onMetadataChanged: (_) {},
                              editable: widget.editable,
                              bare: true,
                            ),
                          ),
                        ),
                        const Positioned(
                          left: 24,
                          top: 580,
                          child: Text('Surrounding page'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  @override
  void dispose() {
    pageFocus.dispose();
    outsideFocus.dispose();
    super.dispose();
  }
}

class _PreloadedTranslations extends AssetLoader {
  const _PreloadedTranslations();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) =>
      Future.value(_translations);
}

// IO only is controlled: the actual loader, syntax editor, TextFindSession,
// FindReplaceBar, scrolling and native text/undo handling all remain in use.
class _ControlledFile extends Fake implements File {
  _ControlledFile({bool pending = false}) {
    if (!pending) {
      available.complete(true);
      content.complete(_contents);
    }
  }
  final available = Completer<bool>();
  final content = Completer<String>();
  final writes = <String>[];
  int reads = 0;
  @override
  String get path => '/fixture/source.html';
  @override
  Future<bool> exists() => available.future;
  @override
  Future<int> length() async => 128;
  @override
  Future<String> readAsString({Encoding encoding = utf8}) {
    reads++;
    return content.future;
  }

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) async {
    writes.add(contents);
    return this;
  }

  @override
  void writeAsStringSync(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) =>
      writes.add(contents);
}
