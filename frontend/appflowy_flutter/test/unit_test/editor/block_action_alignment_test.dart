import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/block_action_button.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/block_action_list.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  EditorState buildEditorState({
    required bool applyHeightToFirstAscent,
    double lineHeight = 1.6,
    double fontSize = 16.0,
  }) {
    final editorState = EditorState.blank();
    editorState.editorStyle = EditorStyle.desktop(
      textStyleConfiguration: TextStyleConfiguration(
        text: TextStyle(fontSize: fontSize),
        lineHeight: lineHeight,
        applyHeightToFirstAscent: applyHeightToFirstAscent,
        applyHeightToLastDescent: true,
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
      textHeightBehavior: TextHeightBehavior(
        applyHeightToFirstAscent: configuration.applyHeightToFirstAscent,
        applyHeightToLastDescent: configuration.applyHeightToLastDescent,
        leadingDistribution: configuration.leadingDistribution,
      ),
    )..layout();
    final height = painter.height;
    painter.dispose();
    return height;
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
}
