import 'package:appflowy/extensions/dart/web_embed_registry.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/local_path_paste.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/local_path_paste_menu.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/link_preview/paste_as/paste_as_menu.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/link_preview/paste_as/paste_choice_menu.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _extension = 'paste-prompt-test';

void main() {
  setUpAll(
    () => ExtensionWebEmbedRegistry.register(_extension, _ExampleSite()),
  );
  tearDownAll(() => ExtensionWebEmbedRegistry.unregisterAll(_extension));

  final paper = AppTheme.builtins.firstWhere(
    (theme) => theme.themeName == BuiltInTheme.paper,
  );
  final appearances = [
    (label: 'light', theme: AppTheme.fallback, brightness: Brightness.light),
    (label: 'dark', theme: AppTheme.fallback, brightness: Brightness.dark),
    (label: 'paper', theme: paper, brightness: Brightness.light),
  ];

  group('a pasted link', () {
    for (final look in appearances) {
      testWidgets('a site that draws it asks to embed it (${look.label})',
          (tester) async {
        PasteMenuType? chosen;
        await _pump(
          tester,
          (editor) => PasteAsMenu(
            editorState: editor,
            href: 'https://example.test/post/42',
            onSelect: (type) => chosen = type,
            onDismiss: () {},
          ),
          appTheme: look.theme,
          brightness: look.brightness,
        );

        final menu = tester.widget<PasteChoiceMenu<PasteMenuType>>(
          find.byType(PasteChoiceMenu<PasteMenuType>),
        );
        expect(menu.choices.map((choice) => choice.value), [
          PasteMenuType.embed,
          PasteMenuType.url,
          PasteMenuType.bookmark,
          PasteMenuType.mention,
        ]);
        expect(menu.initialIndex, 0);
        // The question carries the site's own mark.
        expect(find.byIcon(Icons.public), findsOneWidget);
        expect(
          _surface(tester, PasteChoiceMenu<PasteMenuType>).color,
          look.label == 'paper'
              ? PaperTheme.popupBackground
              : isNot(PaperTheme.popupBackground),
        );

        // Enter answers with the embed, the answer already chosen.
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(chosen, PasteMenuType.embed);
      });
    }

    testWidgets('any other link keeps the plain choice of what to paste',
        (tester) async {
      PasteMenuType? chosen;
      await _pump(
        tester,
        (editor) => PasteAsMenu(
          editorState: editor,
          href: 'https://appflowy.io/',
          onSelect: (type) => chosen = type,
          onDismiss: () {},
        ),
      );

      final menu = tester.widget<PasteChoiceMenu<PasteMenuType>>(
        find.byType(PasteChoiceMenu<PasteMenuType>),
      );
      expect(menu.choices.map((choice) => choice.value), PasteMenuType.values);
      expect(menu.leading, isNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(chosen, PasteMenuType.url);
    });

    test('names what an embed would show', () {
      WebEmbedLink link(String kind, {String? site}) => WebEmbedLink(
            provider: _ExampleSite(),
            kind: kind,
            url: 'https://example.test/x',
            siteName: site,
          );
      expect(webEmbedSubject(link('Post')), 'Example post');
      expect(webEmbedSubject(link('Film or show')), 'Example film or show');
      expect(webEmbedSubject(link('PDF')), 'Example PDF');
      expect(
        webEmbedSubject(link('Spreadsheet', site: 'Google Sheets')),
        'Google Sheets spreadsheet',
      );
      expect(
        webEmbedSubject(link('Sheets', site: 'Google Sheets')),
        'Google Sheets',
      );
      expect(
        PasteEmbedTarget.of('https://example.test/post/1')!.subject,
        'Example post',
      );
      expect(
        PasteEmbedTarget.of('https://www.youtube.com/watch?v=dQw4w9WgXcQ')!
            .subject,
        'YouTube video',
      );
      expect(PasteEmbedTarget.of('https://appflowy.io/'), isNull);
    });
  });

  group('a pasted path', () {
    for (final look in appearances) {
      testWidgets('asks to be copied into AppFlowy (${look.label})',
          (tester) async {
        final chosen = <LocalPathPasteChoice>[];
        var dismissed = 0;
        await _pump(
          tester,
          (editor) => LocalPathPasteMenu(
            editorState: editor,
            item: const PastedLocalPath(
              path: r'C:\Users\me\report.pdf',
              isDirectory: false,
              size: 2048,
            ),
            onSelect: chosen.add,
            onDismiss: () => dismissed++,
          ),
          appTheme: look.theme,
          brightness: look.brightness,
        );

        final menu = tester.widget<PasteChoiceMenu<LocalPathPasteChoice>>(
          find.byType(PasteChoiceMenu<LocalPathPasteChoice>),
        );
        expect(menu.choices.map((choice) => choice.value), [
          LocalPathPasteChoice.copy,
          LocalPathPasteChoice.keepLink,
          LocalPathPasteChoice.keepText,
        ]);
        expect(find.text('2.0 KB'), findsOneWidget);
        expect(
          _surface(tester, PasteChoiceMenu<LocalPathPasteChoice>).color,
          look.label == 'paper'
              ? PaperTheme.popupBackground
              : isNot(PaperTheme.popupBackground),
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(chosen, [
          LocalPathPasteChoice.copy,
          LocalPathPasteChoice.keepLink,
        ]);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        expect(dismissed, 1);
      });
    }

    testWidgets('a folder shows as one, with no size to give', (tester) async {
      await _pump(
        tester,
        (editor) => LocalPathPasteMenu(
          editorState: editor,
          item: const PastedLocalPath(
            path: r'C:\Users\me\Photos',
            isDirectory: true,
          ),
          onSelect: (_) {},
          onDismiss: () {},
        ),
      );
      expect(find.byIcon(Icons.folder_rounded), findsOneWidget);
      final menu = tester.widget<PasteChoiceMenu<LocalPathPasteChoice>>(
        find.byType(PasteChoiceMenu<LocalPathPasteChoice>),
      );
      expect(menu.choices.first.trailing, isNull);
    });

    test('a long name is shortened in the middle', () {
      expect(shortenLocalPathName('report.pdf'), 'report.pdf');
      final short = shortenLocalPathName(
        'Quarterly report for the whole department final.pdf',
      );
      expect(short.length, 24);
      expect(short, startsWith('Quarterly re'));
      expect(short, endsWith('final.pdf'));
      expect(short, contains('…'));
    });
  });
}

BoxDecoration _surface(WidgetTester tester, Type menu) {
  final container = tester.widget<Container>(
    find
        .descendant(of: find.byType(menu), matching: find.byType(Container))
        .first,
  );
  return container.decoration! as BoxDecoration;
}

Future<void> _pump(
  WidgetTester tester,
  Widget Function(EditorState editor) menu, {
  AppTheme? appTheme,
  Brightness brightness = Brightness.light,
}) async {
  final editor = EditorState(document: Document.blank())
    ..disableSealTimer = true;
  addTearDown(editor.dispose);
  final defaultTheme = AppFlowyDefaultTheme();
  final materialTheme = DesktopAppearance().getThemeData(
    appTheme ?? AppTheme.fallback,
    brightness,
    defaultFontFamily,
    builtInCodeFontFamily,
  );
  await tester.pumpWidget(
    MaterialApp(
      themeAnimationDuration: Duration.zero,
      theme: materialTheme,
      home: AppFlowyTheme(
        data: PremiumTheme.appFlowyTheme(
          base: brightness == Brightness.dark
              ? defaultTheme.dark()
              : defaultTheme.light(),
          palette: materialTheme.extension<PremiumThemeExtension>()!,
          brightness: brightness,
        ),
        child: Scaffold(body: Center(child: menu(editor))),
      ),
    ),
  );
  // The menu takes the keyboard after its first frame.
  await tester.pump();
}

class _ExampleSite extends WebEmbedProvider {
  @override
  String get id => 'example';

  @override
  String get name => 'Example';

  @override
  IconData iconFor(String kind) => Icons.public;

  @override
  Color colorFor(String kind) => const Color(0xFF3366FF);

  @override
  WebEmbedLink? recognize(Uri uri) => uri.host == 'example.test'
      ? WebEmbedLink(provider: this, kind: 'Post', url: uri.toString())
      : null;

  @override
  Widget buildView(
    BuildContext context,
    WebEmbedLink link,
    WebEmbedViewOptions options,
  ) =>
      const SizedBox.shrink();
}
