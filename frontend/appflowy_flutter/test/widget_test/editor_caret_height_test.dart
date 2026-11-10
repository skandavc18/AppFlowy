import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/plugins/document/application/document_appearance_cubit.dart';
import 'package:appflowy/plugins/document/presentation/editor_configuration.dart';
import 'package:appflowy/plugins/document/presentation/editor_style.dart';
import 'package:appflowy/shared/object_type_typography.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_setting.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

/// The text cursor is as tall as the text it sits in.
///
/// Documents set lines 1.6 times their font size apart, and the caret used to
/// span that whole line box: 26 px against 19 px of text, sunk below the line
/// at the end of a paragraph. It now spans the font's ascent to descent at
/// the caret, so it grows and shrinks with headings and stays on its line.
void main() {
  late AppearanceSettingsCubit appearance;
  late DocumentAppearanceCubit documentAppearance;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    getIt.pushNewScope();
    getIt.registerSingleton<KeyValueStorage>(DartKeyValue());
    appearance = AppearanceSettingsCubit(
      AppearanceSettingsPB(
        locale: LocaleSettingsPB(languageCode: 'en', countryCode: 'US'),
      ),
      DateTimeSettingsPB(),
      AppTheme.fallback,
    );
    documentAppearance = DocumentAppearanceCubit();
    // Documents are set in the bundled Inter on the desktop; measure the real
    // face rather than the test font.
    for (final file in Directory('assets/google_fonts/Inter/static')
        .listSync()
        .whereType<File>()
        .where((file) => !file.path.contains('Italic'))) {
      final bytes = file.readAsBytesSync();
      await (FontLoader('Inter')
            ..addFont(Future.value(ByteData.view(bytes.buffer))))
          .load();
    }
  });

  tearDownAll(() async {
    await appearance.close();
    await documentAppearance.close();
    await getIt.popScope();
  });

  Future<EditorState> pumpEditor(
    WidgetTester tester,
    List<Node> nodes,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(1000, 900);
    addTearDown(tester.view.reset);
    final document = Document.blank();
    for (var i = 0; i < nodes.length; i++) {
      document.insert([i], [nodes[i]]);
    }
    final editorState = EditorState(document: document);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: appearance),
          BlocProvider.value(value: documentAppearance),
        ],
        child: EasyLocalization(
          supportedLocales: const [Locale('en', 'US')],
          path: 'assets/translations',
          fallbackLocale: const Locale('en', 'US'),
          saveLocale: false,
          assetLoader: const TestBundleAssetLoader(),
          child: MaterialApp(
            theme: DesktopAppearance().getThemeData(
              AppTheme.fallback,
              Brightness.dark,
              '',
              builtInCodeFontFamily,
            ),
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  final customizer = EditorStyleCustomizer(
                    context: context,
                    padding: EdgeInsets.zero,
                    width: 720,
                    editorState: editorState,
                  );
                  return AppFlowyEditor(
                    editorState: editorState,
                    editorStyle: customizer.style(),
                    blockComponentBuilders: buildBlockComponentBuilders(
                      context: context,
                      editorState: editorState,
                      styleCustomizer: customizer,
                      editable: true,
                    ),
                    disableAutoScroll: true,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return editorState;
  }

  Rect caretAt(EditorState editorState, int index, int offset) => editorState
      .getNodeAtPath([index])!
      .selectable!
      .getCursorRectInPosition(Position(path: [index], offset: offset))!;

  RenderParagraph paragraphOf(String text) => find
      .byType(RichText)
      .evaluate()
      .map((element) => element.renderObject! as RenderParagraph)
      .lastWhere((paragraph) => paragraph.text.toPlainText() == text);

  double fontSizeOf(RenderParagraph paragraph) {
    double? size;
    paragraph.text.visitChildren((span) {
      size ??= span.style?.fontSize;
      return size == null;
    });
    return size!;
  }

  /// Inter's ascent and descent at [fontSize], with no line spacing.
  ui.LineMetrics glyphMetrics(double fontSize) => (TextPainter(
        text: TextSpan(
          text: 'x',
          style: TextStyle(fontFamily: 'Inter', fontSize: fontSize),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout())
          .computeLineMetrics()
          .single;

  testWidgets('the caret spans the text, not its line spacing', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      const body = 'they can be deleted or archived.';
      const title = 'Heading one';
      final editorState = await pumpEditor(tester, [
        paragraphNode(text: body),
        headingNode(level: 1, text: title),
        paragraphNode(),
      ]);

      final paragraph = paragraphOf(body);
      final fontSize = fontSizeOf(paragraph);
      final glyphs = glyphMetrics(fontSize);
      final glyphHeight = glyphs.ascent + glyphs.descent;
      final baseline =
          paragraph.computeDistanceToActualBaseline(TextBaseline.alphabetic)!;
      final lineHeight = fontSize * ObjectTypeTypography.editorLineHeight;

      for (final offset in [0, 10, body.length]) {
        final caret = caretAt(editorState, 0, offset);
        expect(
          caret.height,
          moreOrLessEquals(glyphHeight, epsilon: 1),
          reason: 'at $offset the caret is as tall as the text',
        );
        expect(caret.height, lessThan(lineHeight * 0.85));
        expect(
          caret.top,
          moreOrLessEquals(baseline - glyphs.ascent, epsilon: 1),
          reason: 'at $offset the caret starts at the text, not below it',
        );
      }

      final heading = paragraphOf(title);
      final headingGlyphs = glyphMetrics(fontSizeOf(heading));
      final headingCaret = caretAt(editorState, 1, title.length);
      expect(
        headingCaret.height,
        moreOrLessEquals(
          headingGlyphs.ascent + headingGlyphs.descent,
          epsilon: 1,
        ),
      );
      expect(
        headingCaret.height / caretAt(editorState, 0, body.length).height,
        moreOrLessEquals(fontSizeOf(heading) / fontSize, epsilon: 0.1),
        reason: 'the caret grows with the text',
      );

      final empty = caretAt(editorState, 2, 0);
      expect(empty.height, moreOrLessEquals(glyphHeight, epsilon: 1));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('after a line break the caret sits on the line below', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      const broken = 'first\nsecond';
      const trailing = 'first\n';
      final editorState = await pumpEditor(tester, [
        paragraphNode(text: broken),
        paragraphNode(text: trailing),
      ]);
      final fontSize = fontSizeOf(paragraphOf(broken));
      final glyphs = glyphMetrics(fontSize);
      final glyphHeight = glyphs.ascent + glyphs.descent;
      final lineHeight = fontSize * ObjectTypeTypography.editorLineHeight;

      for (final caret in [
        caretAt(editorState, 0, 'first\n'.length),
        caretAt(editorState, 1, trailing.length),
      ]) {
        expect(caret.height, moreOrLessEquals(glyphHeight, epsilon: 1));
        expect(caret.center.dy, greaterThan(lineHeight));
        expect(caret.center.dy, lessThan(lineHeight * 2));
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('at the end of a wrapped paragraph the caret ends its last line',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final long = List.filled(12, 'a sentence that wraps').join(' ');
      final editorState = await pumpEditor(tester, [
        paragraphNode(text: long),
      ]);
      final paragraph = paragraphOf(long);
      final fontSize = fontSizeOf(paragraph);
      final glyphs = glyphMetrics(fontSize);
      final glyphHeight = glyphs.ascent + glyphs.descent;
      final lineHeight = fontSize * ObjectTypeTypography.editorLineHeight;
      expect(paragraph.size.height, greaterThan(lineHeight * 2));

      final caret = caretAt(editorState, 0, long.length);
      expect(caret.height, moreOrLessEquals(glyphHeight, epsilon: 1));
      // The last line's half leading is all that lies below its glyphs.
      expect(
        caret.bottom,
        moreOrLessEquals(
          paragraph.size.height - (lineHeight - glyphHeight) / 2,
          epsilon: 1,
        ),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
