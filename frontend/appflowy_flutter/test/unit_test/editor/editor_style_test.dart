import 'package:appflowy/plugins/document/application/document_appearance_cubit.dart';
import 'package:appflowy/plugins/document/presentation/editor_chrome_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_style.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/object_type_typography.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDocumentAppearanceCubit extends Mock
    implements DocumentAppearanceCubit {}

class MockBuildContext extends Mock implements BuildContext {}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  group('EditorStyleCustomizer', () {
    late EditorStyleCustomizer editorStyleCustomizer;
    late MockBuildContext mockBuildContext;

    setUp(() {
      mockBuildContext = MockBuildContext();
      editorStyleCustomizer = EditorStyleCustomizer(
        context: mockBuildContext,
        padding: EdgeInsets.zero,
      );
    });

    test('baseTextStyle should return the expected TextStyle', () {
      const fontFamily = 'Roboto';
      final result = editorStyleCustomizer.baseTextStyle(fontFamily);
      expect(result, isA<TextStyle>());
      expect(result.fontFamily, 'Roboto_500');
      expect(result.fontWeight, defaultFontWeight);
    });

    test('baseTextStyle should use DM Sans with Inter fallback', () {
      const garbage = 'Garbage';
      final result = editorStyleCustomizer.baseTextStyle(garbage);
      expect(result, isA<TextStyle>());
      expect(result.fontFamily, preferredFontFamily);
      expect(result.fontFamilyFallback, defaultFontFamilyFallback);
      expect(result.fontWeight, defaultFontWeight);
    });

    test('baseTextStyle should use ObjectType defaults', () {
      final result = editorStyleCustomizer.baseTextStyle(
        defaultFontFamily,
        fontSize: ObjectTypeTypography.editorFontSize,
      );

      expect(
        result.fontFamily,
        ObjectTypeTypography.fontFamilyForPlatform(defaultTargetPlatform),
      );
      expect(
        result.fontFamilyFallback,
        ObjectTypeTypography.fontFamilyFallbackForPlatform(
          defaultTargetPlatform,
        ),
      );
      expect(result.fontSize, 16);
      expect(
        result.fontWeight,
        ObjectTypeTypography.fontWeightForPlatform(defaultTargetPlatform),
      );
      expect(result.fontVariations, isNull);
      expect(result.letterSpacing, closeTo(-0.16, 0.0001));
    });

    test('editor chrome uses darker semibold ObjectType rendering', () {
      final style = EditorChromeStyle.textStyleFor(
        TargetPlatform.windows,
        Brightness.light,
      );

      expect(style.fontFamily, 'Segoe UI');
      expect(style.fontSize, 14);
      expect(style.fontWeight, FontWeight.w600);
      expect(style.color, EditorChromeStyle.lightForeground);
      expect(style.fontFeatures, isNotEmpty);
      expect(style.shadows, isNotEmpty);
      expect(
        EditorChromeStyle.iconColorFor(Brightness.light),
        EditorChromeStyle.lightIcon,
      );
    });

    test('floating toolbar glyphs use polished semantic emphasis', () {
      final bold = EditorChromeStyle.toolbarGlyphTextStyleFor(
        TargetPlatform.windows,
        Brightness.light,
        EditorToolbarGlyph.bold,
      );
      final underline = EditorChromeStyle.toolbarGlyphTextStyleFor(
        TargetPlatform.windows,
        Brightness.light,
        EditorToolbarGlyph.underline,
      );
      final italic = EditorChromeStyle.toolbarGlyphTextStyleFor(
        TargetPlatform.windows,
        Brightness.light,
        EditorToolbarGlyph.italic,
      );

      expect(bold.fontWeight, FontWeight.w700);
      expect(bold.fontFeatures, isNotEmpty);
      expect(bold.shadows, isNotEmpty);
      expect(underline.fontWeight, FontWeight.w600);
      expect(underline.decoration, TextDecoration.underline);
      expect(underline.decorationThickness, 1.8);
      expect(italic.fontWeight, FontWeight.w600);
      expect(italic.fontStyle, FontStyle.italic);
    });

    test('light editor surfaces use warm paper colors', () {
      const darkFallback = Color(0xFF252525);

      expect(
        EditorSurfaceStyle.codeBlockBackgroundFor(
          Brightness.light,
          darkFallback,
        ),
        EditorSurfaceStyle.lightCodeBlockBackground,
      );
      expect(
        EditorSurfaceStyle.calloutBackgroundFor(
          Brightness.light,
          darkFallback,
        ),
        EditorSurfaceStyle.lightCalloutBackground,
      );
      expect(
        EditorSurfaceStyle.codeBlockBackgroundFor(
          Brightness.dark,
          darkFallback,
        ),
        darkFallback,
      );
    });
  });
}
