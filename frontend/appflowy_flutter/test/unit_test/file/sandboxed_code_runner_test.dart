import 'package:appflowy/plugins/document/presentation/editor_plugins/code_block/syntax_highlighter.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/sandboxed_code_runner.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('code block geometry stays compact and editor-like', () {
    expect(codeBlockCornerRadius, 12);
    expect(codeBlockAnimationDuration, AppFlowyMotion.standard);
  });

  test('selects isolated local runtime only for JavaScript', () {
    expect(codeRuntimeForName('script.js'), CodeRuntime.javascript);
    expect(codeRuntimeForName('module.mjs'), CodeRuntime.javascript);
    expect(codeRuntimeForName('program.py'), CodeRuntime.serverRequired);
    expect(codeRuntimeForName('main.cpp'), CodeRuntime.serverRequired);
    expect(codeRuntimeForName('styles.css'), CodeRuntime.unsupported);
  });

  test('maps file extensions to editor languages', () {
    expect(codeLanguageForName('script.JS'), 'javascript');
    expect(codeLanguageForName('main.cpp'), 'cpp');
    expect(codeLanguageForName('notebook.py'), 'python');
    expect(codeLanguageForName('README'), 'text');
  });

  test('maps editor languages to runnable file names', () {
    expect(fileNameForCodeLanguage('javascript'), 'main.js');
    expect(fileNameForCodeLanguage('typescript'), 'main.ts');
    expect(fileNameForCodeLanguage('python'), 'main.py');
    expect(fileNameForCodeLanguage('text'), 'main.txt');
    expect(fileNameForCodeLanguage('auto'), 'main');
  });

  test('normalizes language labels used by code toolbars', () {
    expect(normalizeCodeLanguage('JavaScript'), 'javascript');
    expect(normalizeCodeLanguage('C++'), 'cpp');
    expect(normalizeCodeLanguage('Plain Text'), 'text');
    expect(normalizeCodeLanguage('  '), 'auto');
    expect(normalizeCodeLanguage('BASH'), 'shell');
  });

  test('builds syntax-colored spans for supported languages', () {
    final span = buildSyntaxHighlightedTextSpan(
      code: 'const answer = "AppFlowy";',
      language: 'javascript',
      brightness: Brightness.light,
    );

    expect(_containsColoredSpan(span), isTrue);
  });

  test('uses Dark+ and warm paper syntax colors', () {
    final darkSpan = buildSyntaxHighlightedTextSpan(
      code: 'const answer = "AppFlowy";',
      language: 'javascript',
      brightness: Brightness.dark,
    );
    final paperSpan = buildSyntaxHighlightedTextSpan(
      code: '// A quiet comment\nconst answer = "AppFlowy";',
      language: 'javascript',
      brightness: Brightness.light,
      isPaper: true,
    );

    expect(_colorsIn(darkSpan), contains(const Color(0xFFC586C0)));
    expect(_colorsIn(darkSpan), contains(const Color(0xFFCE9178)));
    expect(_colorsIn(paperSpan), contains(const Color(0xFF8F4A73)));
    expect(_colorsIn(paperSpan), contains(const Color(0xFF5D6D40)));
    expect(_colorsIn(paperSpan), contains(const Color(0xFF70695E)));
    for (final color in _colorsIn(paperSpan)) {
      expect(
        _contrastRatio(color, PaperTheme.codeBlockBackground),
        greaterThanOrEqualTo(4.5),
        reason: '$color should remain readable in paper mode',
      );
    }
  });

  test('falls back to auto detection for unknown language identifiers', () {
    final span = buildSyntaxHighlightedTextSpan(
      code: 'const answer = 42;',
      language: 'legacy-javascript-label',
      brightness: Brightness.dark,
    );

    expect(_containsColoredSpan(span), isTrue);
  });

  testWidgets(
    'premium code header fits mobile and animates copy and collapse',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: AppFlowyTheme(
            data: AppFlowyDefaultTheme().light(
              fontFamily: preferredFontFamily,
            ),
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 260,
                  child: SandboxedCodeRunner(
                    code: 'print("AppFlowy")',
                    fileName: 'main.py',
                    language: 'python',
                    showLineNumbers: true,
                    onLanguageChanged: (_) {},
                    onToggleLineNumbers: () {},
                    child: const SizedBox(
                      key: ValueKey('code-editor-child'),
                      height: 80,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      final expandedHeight =
          tester.getSize(find.byType(SandboxedCodeRunner)).height;

      await tester.tap(find.byIcon(Icons.content_copy_outlined));
      await tester.pump(codeBlockAnimationDuration);
      expect(find.textContaining('Copied'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.unfold_less_rounded));
      await tester.pump();
      await tester.pump(codeBlockAnimationDuration);
      final collapsedHeight =
          tester.getSize(find.byType(SandboxedCodeRunner)).height;

      expect(collapsedHeight, lessThan(expandedHeight));
      expect(find.byKey(const ValueKey('code-editor-child')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('premium dark shell uses neutral layered styling', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: AppFlowyTheme(
          data: AppFlowyDefaultTheme().dark(
            fontFamily: preferredFontFamily,
          ),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 640,
                child: SandboxedCodeRunner(
                  code: 'SELECT * FROM appflowy;',
                  fileName: 'query.sql',
                  language: 'sql',
                  showLineNumbers: true,
                  onLanguageChanged: (_) {},
                  onToggleLineNumbers: () {},
                  child: const SizedBox(height: 80),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final shells = tester
        .widgetList<AnimatedContainer>(
      find.descendant(
        of: find.byType(SandboxedCodeRunner),
        matching: find.byType(AnimatedContainer),
      ),
    )
        .where((container) {
      final decoration = container.decoration;
      return decoration is BoxDecoration &&
          decoration.borderRadius ==
              BorderRadius.circular(codeBlockCornerRadius);
    });
    final shell = shells.single.decoration! as BoxDecoration;

    expect(shell.color, const Color(0xFF18191D));
    expect(shell.border, isA<Border>());
    expect(shell.boxShadow, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('premium runner adapts to a constrained resized height', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppFlowyTheme(
          data: AppFlowyDefaultTheme().light(
            fontFamily: preferredFontFamily,
          ),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 520,
                height: 180,
                child: SandboxedCodeRunner(
                  code: List.generate(30, (index) => 'line $index').join('\n'),
                  fileName: 'main.py',
                  language: 'python',
                  showLineNumbers: true,
                  onLanguageChanged: (_) {},
                  onToggleLineNumbers: () {},
                  child: const SizedBox(height: 640),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.getSize(find.byType(SandboxedCodeRunner)).height, 180);
    expect(tester.takeException(), isNull);
  });

  testWidgets('premium paper shell keeps every visible layer warm', (
    tester,
  ) async {
    final paperAppTheme = AppTheme.builtins.firstWhere(
      (theme) => theme.themeName == BuiltInTheme.paper,
    );
    final palette = PremiumTheme.resolve(
      appTheme: paperAppTheme,
      legacy: paperAppTheme.lightTheme,
      brightness: Brightness.light,
    );
    final baseTheme = AppFlowyDefaultTheme().light(
      fontFamily: preferredFontFamily,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light().copyWith(
          extensions: [
            palette,
            const PaperThemeExtension(enabled: true),
          ],
        ),
        home: AppFlowyTheme(
          data: PremiumTheme.appFlowyTheme(
            base: baseTheme,
            palette: palette,
            brightness: Brightness.light,
          ),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 640,
                child: SandboxedCodeRunner(
                  code: 'Paper mode stays warm.',
                  fileName: 'paper.txt',
                  language: 'text',
                  showLineNumbers: true,
                  onLanguageChanged: (_) {},
                  onToggleLineNumbers: () {},
                  child: const SizedBox(height: 80),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final shell = tester
        .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
        .map((container) => container.decoration)
        .whereType<BoxDecoration>()
        .singleWhere(
          (decoration) =>
              decoration.borderRadius ==
              BorderRadius.circular(codeBlockCornerRadius),
        );
    final warmHeaders = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((box) => box.decoration)
        .whereType<BoxDecoration>()
        .where(
          (decoration) =>
              decoration.color == PaperTheme.codeBlockHeaderBackground,
        );

    expect(shell.color, PaperTheme.codeBlockBackground);
    expect(shell.boxShadow, hasLength(2));
    expect(warmHeaders, isNotEmpty);
    expect(tester.takeException(), isNull);
  });
}

bool _containsColoredSpan(InlineSpan span) {
  if (span is! TextSpan) {
    return false;
  }
  if (span.style?.color != null) {
    return true;
  }
  return span.children?.any(_containsColoredSpan) ?? false;
}

Set<Color> _colorsIn(InlineSpan span) {
  if (span is! TextSpan) {
    return {};
  }

  return {
    if (span.style?.color case final color?) color,
    ...?span.children?.expand(_colorsIn),
  };
}

double _contrastRatio(Color foreground, Color background) {
  final lighter = foreground.computeLuminance() > background.computeLuminance()
      ? foreground
      : background;
  final darker = identical(lighter, foreground) ? background : foreground;
  return (lighter.computeLuminance() + 0.05) /
      (darker.computeLuminance() + 0.05);
}
