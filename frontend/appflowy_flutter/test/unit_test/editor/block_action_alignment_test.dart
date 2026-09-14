import 'dart:ui' as ui;

import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/block_action_button.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/block_action_list.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const sansFamily = 'BlockActionTestSans';
  const monoFamily = 'BlockActionTestMono';
  const baseTextStyle = TextStyle(fontFamily: sansFamily, fontSize: 16.0);
  var measurements = 0;

  setUpAll(() async {
    // Use real, bundled fonts rather than relying only on the test fallback.
    for (final (family, asset) in [
      (sansFamily, 'assets/google_fonts/DM_Sans/DMSans-Variable.ttf'),
      (monoFamily, 'assets/google_fonts/Roboto_Mono/RobotoMono-Regular.ttf'),
    ]) {
      final loader = FontLoader(family)..addFont(rootBundle.load(asset));
      await loader.load();
    }
  });

  setUp(() async {
    await binding.handleSystemMessage({'type': 'fontsChange'});
    measurements = 0;
    BlockActionList.onFirstLineMeasuredForTesting = () => measurements++;
  });

  tearDown(() {
    BlockActionList.onFirstLineMeasuredForTesting = null;
  });

  EditorState buildEditorState({
    required bool applyHeightToFirstAscent,
    bool applyHeightToLastDescent = true,
    double lineHeight = 1.6,
    double fontSize = 16.0,
    double textScaleFactor = 1.0,
    TextLeadingDistribution leadingDistribution = TextLeadingDistribution.even,
  }) {
    final editorState = EditorState.blank();
    addTearDown(editorState.dispose);
    editorState.editorStyle = EditorStyle.desktop(
      textScaleFactor: textScaleFactor,
      textStyleConfiguration: TextStyleConfiguration(
        text: TextStyle(fontSize: fontSize),
        lineHeight: lineHeight,
        applyHeightToFirstAscent: applyHeightToFirstAscent,
        applyHeightToLastDescent: applyHeightToLastDescent,
        leadingDistribution: leadingDistribution,
      ),
    );
    return editorState;
  }

  double measureFirstLineHeight(EditorState editorState, TextStyle textStyle) {
    final configuration = editorState.editorStyle.textStyleConfiguration;
    final painter = TextPainter(
      text: TextSpan(
        text: 'A',
        style: textStyle.copyWith(height: configuration.lineHeight),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      textScaler: TextScaler.linear(editorState.editorStyle.textScaleFactor),
      textHeightBehavior: TextHeightBehavior(
        applyHeightToFirstAscent: configuration.applyHeightToFirstAscent,
        applyHeightToLastDescent: configuration.applyHeightToLastDescent,
        leadingDistribution: configuration.leadingDistribution,
      ),
    );
    try {
      painter.layout();
      return painter.height;
    } finally {
      painter.dispose();
    }
  }

  double checkAlignment(EditorState editorState, TextStyle textStyle) {
    final offset = BlockActionList.topOffsetForFirstLine(
      editorState: editorState,
      textStyle: textStyle,
    );
    expect(
      offset,
      (measureFirstLineHeight(editorState, textStyle) -
              BlockActionList.height) /
          2,
    );
    return offset;
  }

  group('block action alignment', () {
    test('buttons are square and 28px tall', () {
      expect(BlockActionButton.size, 28.0);
      expect(BlockActionList.height, BlockActionButton.size);
    });

    test('the buttons are centered on the first line of text', () {
      // `applyHeightToFirstAscent` is disabled on Windows, which shrinks the
      // first line box, so both cases have to stay centered.
      for (final applyHeightToFirstAscent in [true, false]) {
        for (final fontSize in [16.0, 20.0, 24.0, 32.0]) {
          final editorState = buildEditorState(
            applyHeightToFirstAscent: applyHeightToFirstAscent,
          );
          final textStyle = TextStyle(fontSize: fontSize);
          final offset = BlockActionList.topOffsetForFirstLine(
            editorState: editorState,
            textStyle: textStyle,
          );

          expect(
            offset + BlockActionList.height / 2,
            closeTo(measureFirstLineHeight(editorState, textStyle) / 2, 0.01),
            reason: 'fontSize: $fontSize, '
                'applyHeightToFirstAscent: $applyHeightToFirstAscent',
          );
        }
      }
    });

    test('larger text pushes the buttons further down', () {
      final editorState = buildEditorState(applyHeightToFirstAscent: false);
      final small = BlockActionList.topOffsetForFirstLine(
        editorState: editorState,
        textStyle: const TextStyle(fontSize: 16.0),
      );
      final large = BlockActionList.topOffsetForFirstLine(
        editorState: editorState,
        textStyle: const TextStyle(fontSize: 32.0),
      );

      expect(large, greaterThan(small));
    });
  });

  group('first-line measurement cache', () {
    test('shares measurements across editors and equal, nonidentical styles',
        () {
      final first = buildEditorState(applyHeightToFirstAscent: false);
      final second = buildEditorState(
        applyHeightToFirstAscent: false,
        fontSize:
            24.0, // The supplied block style, not this default, is measured.
      );

      TextStyle freshStyle() => baseTextStyle.copyWith(
            fontFamilyFallback: [monoFamily],
            fontFeatures: [const ui.FontFeature.enable('kern')],
            fontVariations: [const ui.FontVariation('wght', 500)],
          );

      final style = freshStyle();
      final equalStyle = freshStyle();
      expect(equalStyle, style);
      expect(identical(equalStyle, style), isFalse);
      final expected = checkAlignment(first, style);
      for (var i = 0; i < 20; i++) {
        expect(
          checkAlignment(i.isEven ? first : second, freshStyle()),
          expected,
        );
      }
      expect(measurements, 1);
      expect(BlockActionList.firstLineHeightCacheSize, 1);
    });

    for (final (name, style) in [
      ('font family', baseTextStyle.copyWith(fontFamily: monoFamily)),
      (
        'font fallback',
        baseTextStyle.copyWith(fontFamilyFallback: [monoFamily]),
      ),
      (
        'font package',
        const TextStyle(
          fontFamily: sansFamily,
          fontSize: 16.0,
          package: 'first_line_test',
        ),
      ),
      ('font size', baseTextStyle.copyWith(fontSize: 32.0)),
      ('font weight', baseTextStyle.copyWith(fontWeight: FontWeight.w700)),
      ('font style', baseTextStyle.copyWith(fontStyle: FontStyle.italic)),
      ('letter spacing', baseTextStyle.copyWith(letterSpacing: 1.0)),
      ('word spacing', baseTextStyle.copyWith(wordSpacing: 2.0)),
      ('locale', baseTextStyle.copyWith(locale: const Locale('ja'))),
      (
        'font features',
        baseTextStyle.copyWith(
          fontFeatures: [const ui.FontFeature.enable('smcp')],
        ),
      ),
      (
        'font variations',
        baseTextStyle.copyWith(
          fontVariations: [const ui.FontVariation('wght', 700)],
        ),
      ),
      (
        'style leading distribution',
        baseTextStyle.copyWith(
          leadingDistribution: TextLeadingDistribution.proportional,
        ),
      ),
      ('color', baseTextStyle.copyWith(color: Colors.blue)),
    ]) {
      test('keeps a distinct entry for changed $name', () {
        final editor = buildEditorState(applyHeightToFirstAscent: false);
        final original = checkAlignment(editor, baseTextStyle);
        final changed = checkAlignment(editor, style);
        expect(measurements, 2);
        expect(checkAlignment(editor, style.copyWith()), changed);
        expect(checkAlignment(editor, baseTextStyle), original);
        expect(measurements, 2);
        expect(BlockActionList.firstLineHeightCacheSize, 2);
      });
    }

    test('keys the effective style after applying configured line height', () {
      final editor = buildEditorState(applyHeightToFirstAscent: false);
      final first = checkAlignment(editor, baseTextStyle.copyWith(height: 1.0));
      final second =
          checkAlignment(editor, baseTextStyle.copyWith(height: 3.0));
      expect(second, first);
      expect(measurements, 1);
    });

    const configuration = TextStyleConfiguration(
      lineHeight: 1.6,
      applyHeightToLastDescent: true,
    );
    const editorStyle = EditorStyle.desktop(
      textStyleConfiguration: configuration,
    );
    for (final (name, style) in [
      ('text scale', editorStyle.copyWith(textScaleFactor: 1.5)),
      (
        'line height',
        editorStyle.copyWith(
          textStyleConfiguration: configuration.copyWith(lineHeight: 2.0),
        ),
      ),
      (
        'first ascent',
        editorStyle.copyWith(
          textStyleConfiguration:
              configuration.copyWith(applyHeightToFirstAscent: true),
        ),
      ),
      (
        'last descent',
        editorStyle.copyWith(
          textStyleConfiguration:
              configuration.copyWith(applyHeightToLastDescent: false),
        ),
      ),
      (
        'leading distribution',
        editorStyle.copyWith(
          textStyleConfiguration: configuration.copyWith(
            leadingDistribution: TextLeadingDistribution.proportional,
          ),
        ),
      ),
    ]) {
      test('respects changed $name on the same editor', () {
        final editor = buildEditorState(applyHeightToFirstAscent: false);
        final originalStyle = editor.editorStyle;
        final original = checkAlignment(editor, baseTextStyle);
        editor.editorStyle = style;
        final changed = checkAlignment(editor, baseTextStyle);
        expect(measurements, 2);
        expect(checkAlignment(editor, baseTextStyle), changed);
        editor.editorStyle = originalStyle;
        expect(checkAlignment(editor, baseTextStyle), original);
        expect(measurements, 2);
      });
    }

    test('matches fresh font metrics for all height behavior combinations', () {
      for (final family in [sansFamily, monoFamily]) {
        for (final scale in [1.0, 1.5]) {
          for (final lineHeight in [1.2, 1.6]) {
            for (final firstAscent in [false, true]) {
              for (final lastDescent in [false, true]) {
                for (final leading in TextLeadingDistribution.values) {
                  final editor = buildEditorState(
                    applyHeightToFirstAscent: firstAscent,
                    applyHeightToLastDescent: lastDescent,
                    lineHeight: lineHeight,
                    textScaleFactor: scale,
                    leadingDistribution: leading,
                  );
                  final style = baseTextStyle.copyWith(fontFamily: family);
                  final expected = checkAlignment(editor, style);
                  expect(checkAlignment(editor, style), expected);
                }
              }
            }
          }
        }
      }
    });

    test('reuses font metrics at zero text scale', () {
      final editor = buildEditorState(
        applyHeightToFirstAscent: false,
        textScaleFactor: 0.0,
      );
      final expected = checkAlignment(editor, baseTextStyle);
      expect(checkAlignment(editor, baseTextStyle), expected);
      expect(measurements, 1);
    });

    test('never retains more than 32 measured heights', () {
      final editor = buildEditorState(applyHeightToFirstAscent: false);
      for (var i = 0; i < 96; i++) {
        checkAlignment(editor, baseTextStyle.copyWith(fontSize: i + 1.0));
        expect(BlockActionList.firstLineHeightCacheSize, lessThanOrEqualTo(32));
      }
      expect(BlockActionList.firstLineHeightCacheSize, 32);
      expect(measurements, 96);
    });

    test('hits refresh recency and only the least recently used entry is lost',
        () {
      final editor = buildEditorState(applyHeightToFirstAscent: false);
      final styles = List.generate(
        33,
        (i) => baseTextStyle.copyWith(fontSize: 16.0 + i),
      );
      for (final style in styles.take(32)) {
        checkAlignment(editor, style);
      }
      expect(measurements, 32);
      checkAlignment(editor, styles.first); // Refresh the oldest entry.
      expect(measurements, 32);
      checkAlignment(editor, styles.last); // Evict the second, not the first.
      expect(measurements, 33);
      checkAlignment(editor, styles.first);
      checkAlignment(editor, styles[2]);
      expect(measurements, 33);
      checkAlignment(editor, styles[1]);
      expect(measurements, 34);
      expect(BlockActionList.firstLineHeightCacheSize, 32);
    });

    test('system font notifications invalidate every cached metric', () async {
      final editor = buildEditorState(applyHeightToFirstAscent: false);
      final otherStyle = baseTextStyle.copyWith(fontFamily: monoFamily);
      checkAlignment(editor, baseTextStyle);
      checkAlignment(editor, otherStyle);
      expect(measurements, 2);

      for (var change = 0; change < 2; change++) {
        await binding.handleSystemMessage({'type': 'fontsChange'});
        expect(BlockActionList.firstLineHeightCacheSize, 0);
        checkAlignment(editor, baseTextStyle);
        checkAlignment(editor, otherStyle);
        checkAlignment(editor, baseTextStyle);
        expect(measurements, 4 + change * 2);
        expect(BlockActionList.firstLineHeightCacheSize, 2);
      }
    });
  });
}
